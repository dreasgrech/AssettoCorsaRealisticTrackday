-- FrenetAvoid.lua - multi-car safe collision avoidance using Frenet frame (normalized offsets [-1..1]).
-- Uses quintic lateral trajectories with predictive TTC-based planning and emergency densification.
-- Provides detailed debug drawing and logging to verify planner decisions and physics outputs.

-- Logger output reference:
-- "FrenetAvoid: ego#<i> z=<progress> x=<offset> dt=<Δt> v=<speed> m/s" – initial state per car (track progress, lateral offset, timestep, speed).
-- "Nearby opponents: <N>" – number of opponent cars within the considered forward/backward windows.
-- "TTC=<t>s -> emergency densify" – triggered when time-to-collision falls below emergency threshold (densifies candidate grid).
-- "OK car=<i> targetN=<offset> T=<time> samples=<count> minClr=<clearance> cost=<value>" – candidate path accepted: target lateral offset (normalized), duration (s), number of sample points, minimum clearance (m), and total cost.
-- "DROP car=<i> targetN=<offset> T=<time> collided=<bool>" – candidate path rejected: `collided=true` indicates a collision (clearance < 0) during sampling.
-- "Survivors=<count> bestIdx=<index>" – number of viable candidate paths and the index of the best (lowest-cost) path.
-- "OUT car=<i> chosen=<idx> egoN=<currentOffset> nextN=<targetOffset> outN=<outputOffset> minClr=<clearance> targetN=<offset> T=<time>" – output decision: chosen path index, current offset, next path point offset, output offset after slew limiting, chosen path min clearance (m), path terminal offset (normalized), and path duration (s).
-- "CHOSEN car=<i> idx=<idx> cost=<value> minClr=<clearance> m  targetN=<offset>  T=<time>s" – debug label for chosen path showing index, total cost, min clearance (m), terminal offset, and duration.
-- "[AUDIT] car=<i> outN(cmd)=<commandedOffset> actN=<actualOffset> Δ=<difference> ..." – compares commanded vs actual applied offset; warns if difference exceeds threshold (AI override or insufficient slew rate).

local FrenetAvoid = {}

---------------------------------------------------------------------------------------------------
-- Tunables (adjust from your settings UI if desired)
---------------------------------------------------------------------------------------------------

-- Base planning horizon and candidate grid (will auto-expand with TTC conditions)
local planningHorizonSeconds         = 1.60
local sampleTimeStepSeconds          = 0.08
local candidateEndTimesSecondsBase   = { 0.8, 1.2, 1.6 }
local candidateTerminalOffsetsNBase  = { -1.0, -0.9, -0.7, -0.5, -0.3, 0.0, 0.3, 0.5, 0.7, 0.9, 1.0 }

-- TTC-aware early planning (begin avoiding sooner, not only when nose-to-tail)
local ttcEarlyPlanStart_s            = 5.0     -- enlarge search window once TTC falls below this (seconds)
local ttcEmergency_s                 = 1.6     -- trigger emergency densification when very close (seconds)

-- Opponent pre-filter windows (track progress fractions). These grow if TTC pressure rises.
local longitudinalWindowAheadZ       = 0.020
local longitudinalWindowBehindZ      = 0.006
local extraAheadZ_whenEarly          = 0.020

-- Sampling anchor and spacing
local firstSampleSeconds             = 0.03    -- time of first forward sample (just beyond the car’s front bumper)
local startMetersAhead               = 0.0
local useSpeedAwareLookahead         = true
local minAheadMetersAtLowSpeed       = 6.0
local maxAheadMetersAtHighSpeed      = 45.0
local nominalTrackLengthMeters       = 20000.0 -- fallback track length for progress fraction → distance conversion

-- Collision model: simple disc footprints (fast). Accounts for car sizes via radii.
local opponentRadiusMeters           = 1.45
local egoRadiusMeters                = 1.45

-- Lateral bounds and slew-rate limiter for output command
local maxAbsOffsetNormalized         = 0.95
local maxOffsetChangePerSecondN      = 2.6

-- Cost function weights
local costWeight_Clearance           = 3.0   -- weight for safety (clearance)
local costWeight_TerminalCenter      = 0.7   -- weight for ending near track center
local costWeight_JerkComfort         = 0.22  -- weight for smoothness (integral of jerk)

-- Emergency densification thresholds
local minClrTight_m                  = 1.2   -- if min clearance < this (m), space is considered "tight"
local densifyOffsetsExtra            = { -1.0, -0.8, -0.6, 0.6, 0.8, 1.0 }  -- additional offsets to test in emergencies
local densifyEndTimesExtra           = { 0.6, 1.0 }                         -- additional shorter time horizons for quick maneuvers

-- Output normalization (required by physics.setAISplineOffset)
local OUTPUT_IS_NORMALIZED           = true

-- Debug drawing toggles
local debugMaxPathsDrawn             = 24    -- max number of candidate paths to draw (to avoid clutter)
local drawSamplesAsSpheres           = true  -- draw sampled path points as small spheres (colored by clearance)
local drawOpponentDiscs              = true  -- draw opponent car footprints (red spheres) and clearance zones
local drawRejectionMarkers           = true  -- mark rejection points (red X where collisions occurred)
local drawEgoFootprint               = true  -- draw ego car footprint (green sphere)
local drawAnchorLink                 = true  -- draw line from ego to first path sample (steering target)

-- Round-trip audit: show commanded vs applied offsets in world
local drawReturnedOffsetPole         = true   -- draw magenta/cyan pole at commanded offset
local drawActualOffsetPole           = true   -- draw yellow pole at actual offset (after physics applied)
local auditWarnDeltaN                = 0.15   -- log a warning if |actual - commanded| exceeds this (possible override or slow response)

-- Debug draw colors
local colAll     = rgbm(0.3, 0.9, 0.3, 0.15)  -- thin green for all candidate paths
local colChosen  = rgbm(1.0, 0.2, 0.9, 1.0)   -- bright purple for chosen path (thick)
local colPoleCmd = rgbm(0.2, 1.0, 1.0, 0.9)   -- cyan for commanded offset pole
local colPoleAct = rgbm(1.0, 1.0, 0.2, 0.9)   -- yellow for actual offset pole

---------------------------------------------------------------------------------------------------
-- Small helper functions
---------------------------------------------------------------------------------------------------

-- Clamp a normalized lateral offset to the valid range [-maxAbsOffsetNormalized, +maxAbsOffsetNormalized]
local function clampOffsetNormalized(n) 
  return math.max(-maxAbsOffsetNormalized, math.min(maxAbsOffsetNormalized, n)) 
end

-- Wrap a track progress value to [0,1) (handles track lap wrap-around)
local function wrap01(z) 
  z = z % 1.0 
  if z < 0 then z = z + 1 end 
  return z 
end

-- Compute minimum clearance (in meters) from a world position to a list of opponents.
-- Each opponent is treated as a disc of radius opponentRadiusMeters; ego as disc of radius egoRadiusMeters.
-- Returns the smallest distance between the ego position and any opponent, minus the sum of radii (negative if overlapping).
local function computeMinimumClearanceToOpponentsMeters(worldPos, opponentList)
  local minClearance = 1e9  -- start with a very large clearance
  local combinedRadii = opponentRadiusMeters + egoRadiusMeters  -- sum of radii for clearance calculation
  for i = 1, opponentList.count do
    local oppCar = opponentList[i]
    -- Compute squared distance (avoid sqrt until end for performance)
    local dx = oppCar.position.x - worldPos.x
    local dy = oppCar.position.y - worldPos.y
    local dz = oppCar.position.z - worldPos.z
    local distSquared = dx*dx + dy*dy + dz*dz
    if distSquared < minClearance then 
      minClearance = distSquared 
    end
  end
  -- Convert min distance squared back to distance and subtract combined radii
  minClearance = math.sqrt(minClearance) - combinedRadii
  return minClearance
end

-- Collect nearby opponent cars within a given forward/ahead window and behind window (progress fractions).
-- Skips the ego car itself. Uses track progress difference (wrap-aware) to decide if a car is within range.
-- Populates outList with opponent car objects and returns the count.
local function findNearbyOpponentsInProgressWindow(egoIndex, egoProgress, allCars, outList, aheadWindow, behindWindow)
  local count = 0
  for i = 1, #allCars do
    local car = allCars[i]
    if car and car.index ~= egoIndex then
      local trackCoord = ac.worldCoordinateToTrack(car.position)  -- track coordinate: x = lateral offset, z = progress (0..1)
      if trackCoord then
        local dzAhead  = wrap01(trackCoord.z - egoProgress)
        local dzBehind = wrap01(egoProgress - trackCoord.z)
        if dzAhead <= aheadWindow or dzBehind <= behindWindow then
          count = count + 1
          outList[count] = car
        end
      end
    end
  end
  outList.count = count
  -- Clear any leftover entries in outList (if list was longer in previous frame)
  for j = count + 1, #outList do 
    outList[j] = nil 
  end
  return count
end

-- Generate quintic polynomial trajectory for lateral offset, ensuring smooth start/end conditions.
-- Returns two functions: 
--   1) computeOffsetAtTime(t): returns lateral offset at time t (clamped between 0 and T),
--   2) computeAbsoluteJerkAtTime(t): returns an absolute "jerk" value at time t (proxy for comfort).
local function planQuinticLateralTrajectory(x0, v0, x1, T)
  -- Solve coefficients a0..a5 for a quintic polynomial x(t) with:
  -- x(0)=x0, x'(0)=v0, x''(0)=0;  and  x(T)=x1, x'(T)=0, x''(T)=0.
  local T2, T3, T4, T5 = T*T, T*T*T, T*T*T*T, T*T*T*T*T
  local a0 = x0
  local a1 = v0
  local a2 = 0
  local a3 = (10*(x1 - x0) - (6*v0)*T) / T3
  local a4 = (-15*(x1 - x0) + (8*v0)*T) / T4
  local a5 = (6*(x1 - x0) - (3*v0)*T) / T5

  return 
    -- Lateral offset as a function of time t
    function(t)
      if t < 0 then 
        t = 0 
      elseif t > T then 
        t = T 
      end
      return a0 + a1*t + a2*t*t + a3*t*t*t + a4*t*t*t*t + a5*t*t*t*t*t
    end,

    -- Absolute jerk (rate of change of acceleration) as a function of time t
    function(t)
      local tt = math.max(0, math.min(T, t))
      local jerk = 6*a3 + 24*a4*tt + 60*a5*tt*tt
      return math.abs(jerk)
    end
end

-- Calculate track progress fraction at time t ahead, based on ego speed (for speed-aware lookahead).
-- This returns egoProgress + Δz corresponding to how far the car will travel in time t (capped by min/max distances).
local function computeTrackProgressAtTime(egoProgress, egoSpeedMps, t)
  -- Determine a distance ahead for the full planning horizon based on current speed (clamped between min and max)
  local horizonDistance = math.max(minAheadMetersAtLowSpeed,
                             math.min(maxAheadMetersAtHighSpeed, egoSpeedMps * planningHorizonSeconds))
  -- Linearly interpolate the distance for time t within the horizon, plus any starting offset in meters
  local distanceAtTime = (t / planningHorizonSeconds) * horizonDistance + startMetersAhead
  local dz = distanceAtTime / nominalTrackLengthMeters  -- convert distance to track progress fraction
  return wrap01(egoProgress + dz)
end

---------------------------------------------------------------------------------------------------
-- Per-car scratchpad (arena) for reusing data structures (no allocations per frame)
---------------------------------------------------------------------------------------------------
local __carPlanningDataMap = {}
local function getOrCreateCarPlanningData(carIndex)
  local data = __carPlanningDataMap[carIndex]
  if data then 
    return data 
  end
  -- Initialize a new scratch data table for this car
  data = {
    -- Nearby opponents data
    nearbyOpponentCars   = {}, 
    nearbyOpponentCount  = 0,

    -- Sampled path points (world positions, clearance values, lateral offsets)
    sampleWorldPositions = {}, 
    sampleClearances     = {}, 
    sampleLateralOffsets = {}, 
    sampleCount          = 0,

    -- Candidate path info: start/end sample indices, cost, min clearance, terminal offset, duration
    candidateStartIndices      = {}, 
    candidateEndIndices        = {}, 
    candidateCosts             = {}, 
    candidateMinClearances     = {}, 
    candidateTerminalOffsetsN  = {}, 
    candidateDurationsSeconds  = {}, 
    candidateCount             = 0,

    -- Rejection markers (collision sample points and their clearance)
    rejectionSamplePositions = {}, 
    rejectionCount           = 0,
    rejectionClearances      = {},

    -- Last output command and last actual offset (for audit)
    lastOutputOffsetNormalized = 0.0, 
    lastActualOffsetNormalized = 0.0, 
    lastEgoTrackProgress       = 0.0
  }
  __carPlanningDataMap[carIndex] = data
  return data
end

---------------------------------------------------------------------------------------------------
-- Public: compute lateral offset command for one car (called each frame per car)
---------------------------------------------------------------------------------------------------
---@param allCars ac.StateCar[]
---@param egoIndex integer
---@param dt number
---@return number  -- normalized lateral offset [-1 .. +1]
function FrenetAvoid.computeOffsetForCar(allCars, egoIndex, dt)
  local egoCarState = ac.getCar(egoIndex)
  if not egoCarState or not ac.hasTrackSpline() then
    Logger.warn("FrenetAvoid: no ego car or missing AI spline data")
    return 0.0
  end

  -- Retrieve or initialize this car's planning data scratchpad
  local carPlanningData = getOrCreateCarPlanningData(egoIndex)

  -- Ego state in Frenet (track) coordinates:
  -- x = normalized lateral offset (-1..+1), z = track progress (0..1, wraps around)
  local egoTrackCoord = ac.worldCoordinateToTrack(egoCarState.position)
  local egoTrackProgress = wrap01(egoTrackCoord.z)
  local egoLateralOffsetNormalized = clampOffsetNormalized(egoTrackCoord.x)
  local initialLateralVelocity = 0.0  -- assume starting lateral velocity is zero (smooth transition)
  local egoSpeedMetersPerSecond = (egoCarState.speedKmh or 0) / 3.6

  Logger.log(string.format(
    "FrenetAvoid: ego#%d z=%.4f x=%.3f dt=%.3f v=%.1f m/s",
    egoIndex, egoTrackProgress, egoLateralOffsetNormalized, dt or -1, egoSpeedMetersPerSecond
  ))

  -----------------------------------------------------------------------------------------------
  -- Identify opponents near the ego (expand search window early if time-to-collision is short)
  -----------------------------------------------------------------------------------------------
  -- Start with base forward/behind progress windows
  local progressWindowAhead = longitudinalWindowAheadZ
  local progressWindowBehind = longitudinalWindowBehindZ

  -- Quick time-to-collision estimation: find nearest car directly ahead (within a small margin ahead)
  local nearestAheadCar = nil
  local nearestAheadDistance = 1e9
  for i = 1, #allCars do
    local otherCar = allCars[i]
    if otherCar and otherCar.index ~= egoIndex then
      local dzAhead = wrap01(ac.worldCoordinateToTrack(otherCar.position).z - egoTrackProgress)
      if dzAhead <= progressWindowAhead + 0.02 then  -- consider cars slightly beyond the normal ahead window for TTC
        local distance = (otherCar.position - egoCarState.position):length()
        if distance < nearestAheadDistance then
          nearestAheadDistance = distance
          nearestAheadCar = otherCar
        end
      end
    end
  end
  if nearestAheadCar then
    -- Relative speed (ego minus opponent). If opponent is faster or equal speed, use a small positive value to avoid division by zero.
    local relativeClosingSpeed = math.max(0.1, egoSpeedMetersPerSecond - (nearestAheadCar.speedKmh or 0) / 3.6)
    local timeToCollision = nearestAheadDistance / relativeClosingSpeed
    if timeToCollision < ttcEarlyPlanStart_s then
      -- If a potential collision is a few seconds away, widen the forward search window to include more distant opponents
      progressWindowAhead = progressWindowAhead + extraAheadZ_whenEarly
    end
    if timeToCollision < ttcEmergency_s then
      -- Very close to collision: we will add extra candidate offsets and shorter end times (emergency paths)
      Logger.warn(string.format("TTC=%.2fs -> emergency densify", timeToCollision))
    end
  end

  -- Collect all opponent cars within the adjusted forward (ahead) and behind windows
  carPlanningData.nearbyOpponentCount = findNearbyOpponentsInProgressWindow(
    egoIndex, egoTrackProgress, allCars, carPlanningData.nearbyOpponentCars, progressWindowAhead, progressWindowBehind)
  Logger.log("Nearby opponents: " .. tostring(carPlanningData.nearbyOpponentCount))

  -----------------------------------------------------------------------------------------------
  -- Build candidate path grid (time horizons and terminal offsets), densifying if needed
  -----------------------------------------------------------------------------------------------
  -- Start with base candidate durations and lateral offsets
  local candidateDurations = { table.unpack(candidateEndTimesSecondsBase) }
  local candidateTerminalOffsets = { table.unpack(candidateTerminalOffsetsNBase) }
  if nearestAheadCar then
    -- If an opponent is relatively close ahead, add extra shorter durations and more extreme offsets for finer avoidance
    for _, extraT in ipairs(densifyEndTimesExtra) do 
      candidateDurations[#candidateDurations + 1] = extraT 
    end
    for _, extraOffset in ipairs(densifyOffsetsExtra) do 
      candidateTerminalOffsets[#candidateTerminalOffsets + 1] = extraOffset 
    end
  end

  -----------------------------------------------------------------------------------------------
  -- Evaluate each candidate path (anchor at ego position and sample forward points to check clearance)
  -----------------------------------------------------------------------------------------------
  -- Reset counts for candidates, samples, and rejections this frame
  carPlanningData.candidateCount = 0
  carPlanningData.sampleCount = 0
  carPlanningData.rejectionCount = 0

  -- Anchor the first sample at the ego's current position (ensures path continuity from current state)
  carPlanningData.sampleCount = 1
  carPlanningData.sampleWorldPositions[1] = egoCarState.position  -- world position of ego (anchor point)
  carPlanningData.sampleLateralOffsets[1] = egoLateralOffsetNormalized
  carPlanningData.sampleClearances[1] = 99.0  -- use a special high clearance marker for the anchor (not used in cost)

  local bestCost = 1e9
  local bestIndex = 0

  -- Iterate over each terminal offset and each time horizon to create candidate trajectories
  for _, terminalOffsetRaw in ipairs(candidateTerminalOffsets) do
    local terminalOffsetN = clampOffsetNormalized(terminalOffsetRaw)
    for _, duration in ipairs(candidateDurations) do
      -- Plan a smooth quintic trajectory from current lateral offset to the terminal offset in given time
      local computeOffsetAtTime, computeAbsoluteJerkAtTime = planQuinticLateralTrajectory(
        egoLateralOffsetNormalized, initialLateralVelocity, terminalOffsetN, duration)

      -- Record the starting index of samples for this candidate (the anchor sample index)
      local startIndex = carPlanningData.sampleCount + 1

      local collided = false
      local minClearance = 1e9
      local cumulativeJerkCost = 0.0
      local sampleCountForPath = 1  -- include anchor as count 1

      -- Take the first forward sample almost immediately after the car's front (small time step)
      local t = firstSampleSeconds

      -- Sample points along the trajectory until the lesser of the candidate duration or the planning horizon
      while t <= math.min(duration, planningHorizonSeconds) do
        sampleCountForPath = sampleCountForPath + 1
        -- Compute lateral offset at time t along this trajectory, clamp within bounds
        local offsetN = clampOffsetNormalized(computeOffsetAtTime(t))
        -- Compute corresponding track progress at time t (either speed-aware or evenly along the base ahead window fraction)
        local progress = useSpeedAwareLookahead 
                         and computeTrackProgressAtTime(egoTrackProgress, egoSpeedMetersPerSecond, t) 
                         or wrap01(egoTrackProgress + (t / planningHorizonSeconds) * longitudinalWindowAheadZ)
        local worldPos = ac.trackCoordinateToWorld(vec3(offsetN, 0.0, progress))  -- convert Frenet (offset,progress) back to world position

        -- Calculate clearance to all nearby opponents at this sample point
        local clearance = computeMinimumClearanceToOpponentsMeters(worldPos, carPlanningData.nearbyOpponentCars)
        if clearance < 0.0 then
          -- This sample point is in collision with an opponent (negative clearance means overlap)
          collided = true
          carPlanningData.rejectionCount = carPlanningData.rejectionCount + 1
          carPlanningData.rejectionSamplePositions[carPlanningData.rejectionCount] = worldPos
          carPlanningData.rejectionClearances[carPlanningData.rejectionCount] = clearance
          -- Mark the rejection and stop sampling further points for this candidate (path is invalid)
          break
        end
        -- Track the minimum clearance along this path
        if clearance < minClearance then 
          minClearance = clearance 
        end
        -- Accumulate jerk (comfort) cost
        cumulativeJerkCost = cumulativeJerkCost + computeAbsoluteJerkAtTime(t)

        -- Add this sample to the lists
        carPlanningData.sampleCount = carPlanningData.sampleCount + 1
        local sampleIndex = carPlanningData.sampleCount
        carPlanningData.sampleWorldPositions[sampleIndex] = worldPos
        carPlanningData.sampleLateralOffsets[sampleIndex] = offsetN
        carPlanningData.sampleClearances[sampleIndex] = clearance

        t = t + sampleTimeStepSeconds  -- advance time by fixed step and sample again
      end

      if (not collided) and (sampleCountForPath > 1) then
        -- The candidate path survived (no collision) and has at least one forward sample beyond the anchor
        carPlanningData.candidateCount = carPlanningData.candidateCount + 1
        local candIndex = carPlanningData.candidateCount
        -- Record start and end sample indices for this path (including the anchor at startIndex-1)
        carPlanningData.candidateStartIndices[candIndex] = startIndex - 1
        carPlanningData.candidateEndIndices[candIndex]   = carPlanningData.sampleCount
        carPlanningData.candidateMinClearances[candIndex] = minClearance
        carPlanningData.candidateTerminalOffsetsN[candIndex] = terminalOffsetN
        carPlanningData.candidateDurationsSeconds[candIndex] = duration

        -- Compute path cost: lower is better
        -- Safety term: higher cost for lower minimum clearance (uses 1/(0.5 + clearance) to avoid singularity at 0)
        -- Centering term: slight cost for ending far from track center (offset magnitude)
        -- Comfort term: cost for total lateral jerk (higher jerk = less comfortable)
        local cost = costWeight_Clearance * (1.0 / (0.5 + minClearance))
                   + costWeight_TerminalCenter * math.abs(terminalOffsetN)
                   + costWeight_JerkComfort * cumulativeJerkCost
        carPlanningData.candidateCosts[candIndex] = cost
        if cost < bestCost then 
          bestCost = cost 
          bestIndex = candIndex 
        end

        Logger.log(string.format(
          "OK car=%d targetN=%.2f T=%.2f samples=%d minClr=%.2f cost=%.3f",
          egoIndex, terminalOffsetN, duration, (carPlanningData.candidateEndIndices[candIndex] - carPlanningData.candidateStartIndices[candIndex] + 1), 
          minClearance, cost
        ))
      else
        -- Candidate was dropped due to a collision or having no forward movement
        Logger.log(string.format(
          "DROP car=%d targetN=%.2f T=%.2f collided=%s",
          egoIndex, terminalOffsetN, duration, tostring(collided)
        ))
      end
    end
  end

  Logger.log(string.format("Survivors=%d bestIdx=%d", carPlanningData.candidateCount, bestIndex))

  -----------------------------------------------------------------------------------------------
  -- Choose the best path and produce the lateral offset output (with slew rate limiting)
  -----------------------------------------------------------------------------------------------
  local outputOffsetN
  if bestIndex == 0 then
    -- No viable path found: fall back safely by drifting towards track center or away from nearest car
    Logger.warn("FrenetAvoid: no surviving candidates; using safe fallback")
    local desiredOffsetN = 0.0  -- start with a bias towards track center
    local nearestCar, nearestDistance = nil, 1e9
    -- Find the closest nearby opponent (actual distance)
    for i = 1, carPlanningData.nearbyOpponentCount do
      local opp = carPlanningData.nearbyOpponentCars[i]
      local dist = (opp.position - egoCarState.position):length()
      if dist < nearestDistance then 
        nearestDistance = dist 
        nearestCar = opp 
      end
    end
    if nearestCar then
      -- If an opponent is very close, nudge away from it laterally by 0.25 (to left or right)
      local nearestOpponentOffsetN = ac.worldCoordinateToTrack(nearestCar.position).x
      if nearestOpponentOffsetN >= 0 then 
        -- opponent is on the right side -> move left
        desiredOffsetN = clampOffsetNormalized(desiredOffsetN - 0.25) 
      else 
        -- opponent on the left side -> move right
        desiredOffsetN = clampOffsetNormalized(desiredOffsetN + 0.25) 
      end
    end
    -- Apply a slew-rate limit to avoid instant large changes
    local maxChange = maxOffsetChangePerSecondN * dt
    outputOffsetN = clampOffsetNormalized(
                      egoLateralOffsetNormalized + math.max(-maxChange, math.min(maxChange, (desiredOffsetN - egoLateralOffsetNormalized))))
  else
    -- Follow the chosen best path: set steering target to the second sample of that path (just ahead of ego)
    local startIdx = carPlanningData.candidateStartIndices[bestIndex]
    local endIdx = carPlanningData.candidateEndIndices[bestIndex]
    local nextOffsetN = carPlanningData.sampleLateralOffsets[ math.min(startIdx + 1, endIdx) ]
    -- Slew-limit the change from current offset to the target offset for this frame
    local maxChange = maxOffsetChangePerSecondN * dt
    outputOffsetN = clampOffsetNormalized(
                      egoLateralOffsetNormalized + math.max(-maxChange, math.min(maxChange, (nextOffsetN - egoLateralOffsetNormalized))))
    Logger.log(string.format(
      "OUT car=%d chosen=%d egoN=%.3f nextN=%.3f outN=%.3f minClr=%.2f targetN=%.2f T=%.2f",
      egoIndex, bestIndex, egoLateralOffsetNormalized, nextOffsetN, outputOffsetN, 
      carPlanningData.candidateMinClearances[bestIndex], carPlanningData.candidateTerminalOffsetsN[bestIndex], carPlanningData.candidateDurationsSeconds[bestIndex]
    ))
  end

  -- Store output and current actual values for later audit (actual applied offset updated in debugDraw after physics applies it)
  carPlanningData.lastOutputOffsetNormalized = outputOffsetN
  carPlanningData.lastActualOffsetNormalized = egoLateralOffsetNormalized
  carPlanningData.lastEgoTrackProgress = egoTrackProgress

  -- Return the final lateral offset command (normalized, as required by physics.setAISplineOffset)
  return outputOffsetN
end

---------------------------------------------------------------------------------------------------
-- Public: compute offsets for all cars in one batch (fills an output array)
---------------------------------------------------------------------------------------------------
---@param allCars ac.StateCar[]
---@param dt number
---@param outOffsets number[]
---@return number[]  -- array of normalized offsets (by car index+1)
function FrenetAvoid.computeOffsetsForAll(allCars, dt, outOffsets)
  for i = 1, #allCars do
    local car = allCars[i]
    if car then 
      outOffsets[car.index + 1] = FrenetAvoid.computeOffsetForCar(allCars, car.index, dt) 
    end
  end
  return outOffsets
end

---------------------------------------------------------------------------------------------------
-- Debug draw: visualize planning data and perform round-trip audit for a given car index
---------------------------------------------------------------------------------------------------
---@param carIndex integer
function FrenetAvoid.debugDraw(carIndex)
  local data = __carPlanningDataMap[carIndex]
  if not data then 
    return  -- nothing to draw if this car has no planning data (likely not processed yet)
  end

  -- Draw opponent footprints and clearance zones, and ego footprint
  if drawOpponentDiscs then
    for i = 1, data.nearbyOpponentCount do
      local oppCar = data.nearbyOpponentCars[i]
      if oppCar then 
        -- Draw opponent footprint (red sphere) and clearance zone (white translucent sphere of radius opponent+ego radii + safety margin)
        render.debugSphere(oppCar.position, opponentRadiusMeters + egoRadiusMeters + minClrTight_m, rgbm(1, 1, 1, 0.10))
        render.debugSphere(oppCar.position, opponentRadiusMeters, rgbm(1, 0, 0, 0.25))
      end
    end
  end
  if drawEgoFootprint then
    local egoCar = ac.getCar(carIndex)
    if egoCar then 
      render.debugSphere(egoCar.position, egoRadiusMeters, rgbm(0, 1, 0, 0.25)) 
    end
  end

  -- Mark rejection points (red X at each sample where a collision occurred)
  if drawRejectionMarkers then
    for i = 1, data.rejectionCount do
      local p = data.rejectionSamplePositions[i]
      local d = 0.6
      -- Draw an 'X' at the sample position
      render.debugLine(p + vec3(-d, 0, -d), p + vec3(d, 0, d), rgbm(1, 0, 0, 1))
      render.debugLine(p + vec3(-d, 0, d),  p + vec3(d, 0, -d), rgbm(1, 0, 0, 1))
      -- Annotate the rejection with clearance info (negative clearance indicates overlap depth)
      local clr = data.rejectionClearances[i]
      if clr then
        local txt = (clr < 0) 
                    and string.format("Collision (%.2fm overlap)", -clr) 
                    or string.format("clearance %.2f m", clr)
        render.debugText(p + vec3(0, 0.3, 0), txt)
      end
    end
  end

  -- Draw all candidate paths (thin green lines and sample points)
  if data.candidateCount > 0 then
    local drawnCount = 0
    for ci = 1, data.candidateCount do
      local sIdx = data.candidateStartIndices[ci]
      local eIdx = data.candidateEndIndices[ci]
      -- Draw line segments connecting successive sample points along this candidate path
      for j = sIdx, eIdx - 1 do
        render.debugLine(data.sampleWorldPositions[j], data.sampleWorldPositions[j + 1], colAll)
      end
      if drawSamplesAsSpheres then
        -- Draw each sample point as a small sphere colored by clearance (red = very close, orange = moderately close, green = safe)
        for j = sIdx, eIdx do
          local clr = data.sampleClearances[j]
          local color = (clr <= 0.5) and rgbm(1, 0.1, 0.1, 0.9)        -- clearance <= 0.5m: red (high danger)
                       or (clr <= 2.0) and rgbm(1, 0.8, 0.1, 0.9)     -- clearance <= 2m: orange (moderate)
                       or rgbm(0.2, 1.0, 0.2, 0.9)                    -- clearance > 2m: green (safe)
          render.debugSphere(data.sampleWorldPositions[j], 0.12, color)
        end
      end
      drawnCount = drawnCount + 1
      if drawnCount >= debugMaxPathsDrawn then 
        break  -- stop drawing if too many paths
      end
    end

    -- Determine which candidate was chosen as best (same logic as in the solver)
    local bestIdx = 1
    local bestCost = data.candidateCosts[1]
    for ci = 2, data.candidateCount do
      local cost = data.candidateCosts[ci]
      if cost < bestCost then 
        bestIdx = ci 
        bestCost = cost 
      end
    end

    -- Draw the chosen path in a thicker highlighted style (triple purple lines)
    local bestStart = data.candidateStartIndices[bestIdx]
    local bestEnd = data.candidateEndIndices[bestIdx]
    for j = bestStart, bestEnd - 1 do
      render.debugLine(data.sampleWorldPositions[j],     data.sampleWorldPositions[j + 1],     colChosen)
      render.debugLine(data.sampleWorldPositions[j] + vec3(0, 0.01, 0), data.sampleWorldPositions[j + 1] + vec3(0, 0.01, 0), colChosen)
      render.debugLine(data.sampleWorldPositions[j] + vec3(0, 0.02, 0), data.sampleWorldPositions[j + 1] + vec3(0, 0.02, 0), colChosen)
    end

    -- Highlight the second sample of the chosen path (the immediate steering target) with a larger sphere
    local headIndex = data.sampleWorldPositions[ math.min(bestStart + 2, bestEnd) ]
    if headIndex then 
      render.debugSphere(headIndex, 0.20, colChosen) 
    end

    -- Label the chosen path with its index, cost, minimum clearance, terminal offset, and duration
    local midIndex = data.sampleWorldPositions[ math.floor((bestStart + bestEnd) * 0.5) ]
    if midIndex then
      local label = string.format(
        "CHOSEN car=%d idx=%d  cost=%.2f  minClr=%.2f m  targetN=%.2f  T=%.2fs",
        carIndex, bestIdx, data.candidateCosts[bestIdx], data.candidateMinClearances[bestIdx],
        data.candidateTerminalOffsetsN[bestIdx], data.candidateDurationsSeconds[bestIdx]
      )
      render.debugText(midIndex + vec3(0, 0.4, 0), label)
    end

    -- Draw a line from the ego car to the first forward sample of the chosen path (visualize steering direction)
    if drawAnchorLink then
      local egoCar = ac.getCar(carIndex)
      if egoCar and (bestStart + 1) <= bestEnd then
        render.debugLine(egoCar.position, data.sampleWorldPositions[bestStart + 1], rgbm(1, 1, 1, 0.9))
      end
    end
  end

  -- Draw vertical poles indicating the last commanded offset vs the car's actual offset (after physics applied)
  local egoCar = ac.getCar(carIndex)
  if egoCar then
    local trackCoord = ac.worldCoordinateToTrack(egoCar.position)
    data.lastActualOffsetNormalized = trackCoord.x
    data.lastEgoTrackProgress = trackCoord.z

    if drawReturnedOffsetPole then
      -- Magenta/cyan pole for commanded offset (the output we gave to the physics engine)
      local commandedPos = ac.trackCoordinateToWorld(vec3(data.lastOutputOffsetNormalized, 0.0, data.lastEgoTrackProgress))
      render.debugLine(commandedPos + vec3(0, 0.00, 0), commandedPos + vec3(0, 1.2, 0), colPoleCmd)
      render.debugSphere(commandedPos + vec3(0, 1.2, 0), 0.10, colPoleCmd)
      render.debugText(commandedPos + vec3(0, 1.35, 0), string.format("cmd outN=%.3f", data.lastOutputOffsetNormalized))
    end

    if drawActualOffsetPole then
      -- Yellow pole for actual offset (what the physics actually applied, may differ due to AI control limits)
      local actualPos = ac.trackCoordinateToWorld(vec3(data.lastActualOffsetNormalized, 0.0, data.lastEgoTrackProgress))
      render.debugLine(actualPos + vec3(0, 0.00, 0), actualPos + vec3(0, 1.2, 0), colPoleAct)
      render.debugSphere(actualPos + vec3(0, 1.2, 0), 0.10, colPoleAct)
      render.debugText(actualPos + vec3(0, 1.35, 0), string.format("act xN=%.3f", data.lastActualOffsetNormalized))

      -- Log a warning if there's a significant discrepancy between commanded and actual (e.g., controller override or too low slew rate)
      local dN = math.abs(data.lastOutputOffsetNormalized - data.lastActualOffsetNormalized)
      if dN > auditWarnDeltaN then
        Logger.warn(string.format(
          "[AUDIT] car=%d  outN(cmd)=%.3f  actN=%.3f  Δ=%.3f  (controller overriding? slew too low?)",
          carIndex, data.lastOutputOffsetNormalized, data.lastActualOffsetNormalized, dN
        ))
      else
        Logger.log(string.format(
          "[AUDIT] car=%d  outN≈actN  cmd=%.3f act=%.3f Δ=%.3f",
          carIndex, data.lastOutputOffsetNormalized, data.lastActualOffsetNormalized, dN
        ))
      end
    end
  end
end

return FrenetAvoid
