-- FrenetAvoid.lua - multi-car safe collision avoidance using Frenet frame (normalized offsets [-1..1]).
-- Uses quintic lateral trajectories with predictive TTC-based planning and emergency densification.
-- Provides detailed debug drawing and logging to verify planner decisions and physics outputs.

-- Logger output reference:
-- "FrenetAvoid: ego#<i> z=<progress> x=<offset> dt=<Δt> v=<speed> m/s" – initial state per car (track progress, lateral offset, timestep, speed).
-- "Nearby opponents: <N>" – number of opponent cars within the considered forward/backward windows.
-- "TTC=<t>s -> emergency densify" – triggered when time-to-collision falls below emergency threshold (densifies candidate grid).
-- "SidePref: pref=<LEFT/RIGHT> sign=<±1> penaltyW=<w> active=<yes/no>" – overtaking-side preference used for this frame.
-- "OK car=<i> targetN=<offset> T=<time> samples=<count> minClr=<clearance> cost=<value>" – candidate path accepted: target lateral offset (normalized), duration (s), number of sample points, minimum clearance (m), and total cost.
-- "DROP car=<i> targetN=<offset> T=<time> collided=<bool>" – candidate path rejected: `collided=true` indicates a collision (clearance < 0) during sampling.
-- "Survivors=<count> bestIdx=<index>" – number of viable candidate paths and the index of the best (lowest-cost) path.
-- "OUT car=<i> chosen=<idx> egoN=<currentOffset> nextN=<targetOffset> outN=<outputOffset> minClr=<clearance> targetN=<offset> T=<time>" – output decision: chosen path index, current offset, next sample offset, output after slew limiting, chosen path min clearance (m), path terminal offset, and path duration (s).
-- "CHOSEN car=<i> idx=<idx> cost=<value> minClr=<clearance> m  targetN=<offset>  T=<time>s" – debug label for chosen path showing index, total cost, min clearance (m), terminal offset, and duration.
-- "[AUDIT] car=<i> outN(cmd)=<commandedOffset> actN=<actualOffset> Δ=<difference> ..." – compares commanded vs actual applied offset; warns if difference exceeds threshold.

local FrenetAvoid = {}

local LOG_MESSAGE = false

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
local minAheadMetersAtLowSpeed       = 12.0
local maxAheadMetersAtHighSpeed      = 140.0   -- ↑ important: let planner “see” far enough at 200+ km/h
local nominalTrackLengthMeters       = 20000.0 -- fallback track length for progress fraction → distance conversion

-- Collision model: simple disc footprints (fast). Accounts for car sizes via radii.
local opponentRadiusMeters           = 1.45
local egoRadiusMeters                = 1.45

-- Lateral bounds and slew-rate limiter for output command
local maxAbsOffsetNormalized         = 0.95
local maxOffsetChangePerSecondN      = 2.6

-- Cost function weights
local costWeight_Clearance           = 3.0   -- safety (clearance)
local costWeight_TerminalCenter      = 0.7   -- bias to end near center (keeps AI tidy)
local costWeight_JerkComfort         = 0.22  -- smoothness

-- NEW: overtaking-side preference weight (applied only when a blocker ahead exists)
-- If RIGHT is preferred and TTC is low, any terminal on the LEFT gets this *added* to cost (and vice versa).
local costWeight_SidePreference      = 5.0   -- strong bias so we don’t pick the wrong side under pressure

-- Emergency densification thresholds
local minClrTight_m                  = 1.2   -- if min clearance < this (m), space is considered "tight"
local densifyOffsetsExtra            = { -1.0, -0.8, -0.6, 0.6, 0.8, 1.0 }  -- additional offsets to test in emergencies
local densifyEndTimesExtra           = { 0.6, 1.0 }                         -- additional shorter horizons for quick moves

-- Output normalization (required by physics.setAISplineOffset)
local OUTPUT_IS_NORMALIZED           = true

-- Debug drawing toggles
local debugMaxPathsDrawn             = 24
local drawSamplesAsSpheres           = true
local drawOpponentDiscs              = true
local drawRejectionMarkers           = true
local drawEgoFootprint               = true
local drawAnchorLink                 = true

-- Round-trip audit: show commanded vs applied offsets in world
local drawReturnedOffsetPole         = true
local drawActualOffsetPole           = true
local auditWarnDeltaN                = 0.15

-- Debug draw colors
local colAll     = rgbm(0.3, 0.9, 0.3, 0.15)
local colChosen  = rgbm(1.0, 0.2, 0.9, 1.0)
local colPoleCmd = rgbm(0.2, 1.0, 1.0, 0.9)
local colPoleAct = rgbm(1.0, 1.0, 0.2, 0.9)

---------------------------------------------------------------------------------------------------
-- Small helper functions
---------------------------------------------------------------------------------------------------

local function clampOffsetNormalized(n)
  return math.max(-maxAbsOffsetNormalized, math.min(maxAbsOffsetNormalized, n))
end

local function wrap01(z)
  z = z % 1.0
  if z < 0 then z = z + 1 end
  return z
end

-- Minimum distance from point to set of opponent centers, minus radii sum → clearance in meters (negative means overlap).
local function computeMinimumClearanceToOpponentsMeters(worldPos, opponentList)
  local minClearanceSq = 1e18
  for i = 1, opponentList.count do
    local opp = opponentList[i]
    local dx = opp.position.x - worldPos.x
    local dy = opp.position.y - worldPos.y
    local dz = opp.position.z - worldPos.z
    local d2 = dx*dx + dy*dy + dz*dz
    if d2 < minClearanceSq then minClearanceSq = d2 end
  end
  return math.sqrt(minClearanceSq) - (opponentRadiusMeters + egoRadiusMeters)
end

-- Populate `outList` with cars within [aheadWindow, behindWindow] of ego’s progress (wrap-aware).
local function findNearbyOpponentsInProgressWindow(egoIndex, egoProgress, allCars, outList, aheadWindow, behindWindow)
  local count = 0
  for i = 1, #allCars do
    local c = allCars[i]
    if c and c.index ~= egoIndex then
      local tc = ac.worldCoordinateToTrack(c.position)
      if tc then
        local dzAhead  = wrap01(tc.z - egoProgress)
        local dzBehind = wrap01(egoProgress - tc.z)
        if dzAhead <= aheadWindow or dzBehind <= behindWindow then
          count = count + 1
          outList[count] = c
        end
      end
    end
  end
  outList.count = count
  for j = count + 1, #outList do outList[j] = nil end
  return count
end

-- Quintic lateral x(t) with x(0)=x0, x'(0)=v0, x''(0)=0 and x(T)=x1, x'(T)=0, x''(T)=0.
local function planQuinticLateralTrajectory(x0, v0, x1, T)
  local T2, T3, T4, T5 = T*T, T*T*T, T*T*T*T, T*T*T*T*T
  local a0, a1, a2 = x0, v0, 0
  local a3 = (10*(x1 - x0) - (6*v0)*T) / T3
  local a4 = (-15*(x1 - x0) + (8*v0)*T) / T4
  local a5 = (6*(x1 - x0)  - (3*v0)*T) / T5
  return
    function(t)
      if t < 0 then t = 0 elseif t > T then t = T end
      return a0 + a1*t + a2*t*t + a3*t*t*t + a4*t*t*t*t + a5*t*t*t*t*t
    end,
    function(t)
      local tt = (t < 0 and 0) or (t > T and T) or t
      local j = 6*a3 + 24*a4*tt + 60*a5*tt*tt
      return math.abs(j)
    end
end

-- Speed-aware progress: how far (Δz) we’ll be at time t.
local function computeTrackProgressAtTime(egoProgress, egoSpeedMps, t)
  local horizonMeters = math.max(minAheadMetersAtLowSpeed, math.min(maxAheadMetersAtHighSpeed, egoSpeedMps * planningHorizonSeconds))
  local meters = (t / planningHorizonSeconds) * horizonMeters + startMetersAhead
  return wrap01(egoProgress + (meters / nominalTrackLengthMeters))
end

---------------------------------------------------------------------------------------------------
-- Per-car scratchpad (arena) for reusing data (no per-frame allocs)
---------------------------------------------------------------------------------------------------
local __carPlanningDataMap = {}
local function getOrCreateCarPlanningData(carIndex)
  local d = __carPlanningDataMap[carIndex]
  if d then return d end
  d = {
    nearbyOpponentCars   = {}, nearbyOpponentCount  = 0,
    sampleWorldPositions = {}, sampleClearances     = {}, sampleLateralOffsets = {}, sampleCount = 0,
    candidateStartIndices = {}, candidateEndIndices = {}, candidateCosts = {},
    candidateMinClearances = {}, candidateTerminalOffsetsN = {}, candidateDurationsSeconds = {}, candidateCount = 0,
    rejectionSamplePositions = {}, rejectionClearances = {}, rejectionCount = 0,
    lastOutputOffsetNormalized = 0.0, lastActualOffsetNormalized = 0.0, lastEgoTrackProgress = 0.0
  }
  __carPlanningDataMap[carIndex] = d
  return d
end

---------------------------------------------------------------------------------------------------
-- Public: compute lateral offset command for one car (called each frame per car)
---------------------------------------------------------------------------------------------------
---@param allCars ac.StateCar[]
---@param egoIndex integer
---@param dt number
---@return number  -- normalized lateral offset [-1 .. +1]
function FrenetAvoid.computeOffsetForCar(allCars, egoIndex, dt)
  local ego = ac.getCar(egoIndex)
  if not ego or not ac.hasTrackSpline() then
    Logger.warn("FrenetAvoid: no ego car or missing AI spline")
    return 0.0
  end

  local safeDt = math.max(0.016, dt or 0.016)  -- protect slew limiter at very small dt

  local data = getOrCreateCarPlanningData(egoIndex)

  -- Ego state in Frenet
  local tc = ac.worldCoordinateToTrack(ego.position)
  local egoZ = wrap01(tc.z)
  local egoN = clampOffsetNormalized(tc.x)
  local egoV = (ego.speedKmh or 0) / 3.6
  local vLat0 = 0.0

  if LOG_MESSAGE then Logger.log(string.format("FrenetAvoid: ego#%d z=%.4f x=%.3f dt=%.3f v=%.1f m/s", egoIndex, egoZ, egoN, dt or -1, egoV)) end

  -- Nearest ahead car & TTC
  local progressAhead = longitudinalWindowAheadZ
  local nearestAhead, nearestAheadDist = nil, 1e9
  for i = 1, #allCars do
    local c = allCars[i]
    if c and c.index ~= egoIndex then
      local dzAhead = wrap01(ac.worldCoordinateToTrack(c.position).z - egoZ)
      if dzAhead <= progressAhead + 0.02 then
        local d = (c.position - ego.position):length()
        if d < nearestAheadDist then nearestAheadDist, nearestAhead = d, c end
      end
    end
  end
  if nearestAhead then
    local relV = math.max(0.1, egoV - (nearestAhead.speedKmh or 0)/3.6)
    local ttc = nearestAheadDist / relV
    if ttc < ttcEarlyPlanStart_s then progressAhead = progressAhead + extraAheadZ_whenEarly end
    if ttc < ttcEmergency_s then 
      if LOG_MESSAGE then Logger.warn(string.format("TTC=%.2fs -> emergency densify", ttc)) end
    end
  end

  -- Gather opponents in window
  data.nearbyOpponentCount = findNearbyOpponentsInProgressWindow(egoIndex, egoZ, allCars, data.nearbyOpponentCars, progressAhead, longitudinalWindowBehindZ)
  if LOG_MESSAGE then Logger.log("Nearby opponents: " .. tostring(data.nearbyOpponentCount)) end

  -- Build candidate grids (densify under pressure)
  local candidateDurations = { table.unpack(candidateEndTimesSecondsBase) }
  local candidateOffsets   = { table.unpack(candidateTerminalOffsetsNBase) }
  if nearestAhead then
    for _, t in ipairs(densifyEndTimesExtra) do candidateDurations[#candidateDurations+1] = t end
    for _, n in ipairs(densifyOffsetsExtra)   do candidateOffsets[#candidateOffsets+1]   = n end
  end

  -- Determine preferred overtaking side from your track manager (RIGHT or LEFT).
  -- We translate that to a sign: RIGHT → +1, LEFT → -1. If unavailable, default to RIGHT.
  local preferredSideSign = 1
  local preferredSideName = "RIGHT"
  if RaceTrackManager and RaceTrackManager.TrackSide and RaceTrackManager.getOvertakingSide then
    local side = RaceTrackManager.getOvertakingSide()
    if side == RaceTrackManager.TrackSide.LEFT then
      preferredSideSign = -1
      preferredSideName = "LEFT"
    else
      preferredSideSign = 1
      preferredSideName = "RIGHT"
    end
  end

  local sidePreferenceActive = nearestAhead ~= nil  -- only bias when an actual blocker exists ahead
  if LOG_MESSAGE then Logger.log(string.format("SidePref: pref=%s sign=%+d penaltyW=%.2f active=%s", preferredSideName, preferredSideSign, costWeight_SidePreference, tostring(sidePreferenceActive))) end

  -- Reset per-frame buffers
  data.candidateCount, data.sampleCount, data.rejectionCount = 0, 0, 0

  -- Anchor at ego
  data.sampleCount = 1
  data.sampleWorldPositions[1] = ego.position
  data.sampleLateralOffsets[1] = egoN
  data.sampleClearances[1] = 99.0

  local bestIdx, bestCost = 0, 1e9

  for _, terminalNraw in ipairs(candidateOffsets) do
    local terminalN = clampOffsetNormalized(terminalNraw)
    for _, T in ipairs(candidateDurations) do
      local xOfT, jerkAbs = planQuinticLateralTrajectory(egoN, vLat0, terminalN, T)

      local startIdx = data.sampleCount + 1
      local collided = false
      local minClr, jerkSum = 1e9, 0.0
      local haveForward = false

      local t = firstSampleSeconds
      while t <= math.min(T, planningHorizonSeconds) do
        haveForward = true
        local n = clampOffsetNormalized(xOfT(t))
        local z = useSpeedAwareLookahead and computeTrackProgressAtTime(egoZ, egoV, t)
                                           or wrap01(egoZ + (t / planningHorizonSeconds) * longitudinalWindowAheadZ)
        local p = ac.trackCoordinateToWorld(vec3(n, 0, z))

        local clr = computeMinimumClearanceToOpponentsMeters(p, data.nearbyOpponentCars)
        if clr < 0.0 then
          collided = true
          data.rejectionCount = data.rejectionCount + 1
          data.rejectionSamplePositions[data.rejectionCount] = p
          data.rejectionClearances[data.rejectionCount] = clr
          break
        end
        if clr < minClr then minClr = clr end
        jerkSum = jerkSum + jerkAbs(t)

        data.sampleCount = data.sampleCount + 1
        local si = data.sampleCount
        data.sampleWorldPositions[si] = p
        data.sampleLateralOffsets[si] = n
        data.sampleClearances[si]     = clr

        t = t + sampleTimeStepSeconds
      end

      if (not collided) and haveForward then
        data.candidateCount = data.candidateCount + 1
        local ci = data.candidateCount
        data.candidateStartIndices[ci]      = startIdx - 1
        data.candidateEndIndices[ci]        = data.sampleCount
        data.candidateMinClearances[ci]     = minClr
        data.candidateTerminalOffsetsN[ci]  = terminalN
        data.candidateDurationsSeconds[ci]  = T

        -- Base cost: safety + centering + comfort
        local cost = costWeight_Clearance      * (1.0 / (0.5 + minClr))
                   + costWeight_TerminalCenter * math.abs(terminalN)
                   + costWeight_JerkComfort    * jerkSum

        -- Side preference penalty: if there is a blocker ahead, penalize terminal offsets on the non-preferred side.
        if sidePreferenceActive then
          -- Preferred side sign is +1 for RIGHT, -1 for LEFT.
          -- If terminalN has opposite sign, add penalty.
          if terminalN * preferredSideSign < 0 then
            cost = cost + costWeight_SidePreference
          end
        end

        data.candidateCosts[ci] = cost
        if cost < bestCost then bestCost, bestIdx = cost, ci end

        if LOG_MESSAGE then Logger.log(string.format( "OK car=%d targetN=%.2f T=%.2f samples=%d minClr=%.2f cost=%.3f", egoIndex, terminalN, T, (data.candidateEndIndices[ci] - data.candidateStartIndices[ci] + 1), minClr, cost)) end
      else
        if LOG_MESSAGE then Logger.log(string.format("DROP car=%d targetN=%.2f T=%.2f collided=%s", egoIndex, terminalN, T, tostring(collided))) end
      end
    end
  end

  if LOG_MESSAGE then Logger.log(string.format("Survivors=%d bestIdx=%d", data.candidateCount, bestIdx)) end

  -- Output with slew limiting toward next sample on chosen candidate
  local outN
  if bestIdx == 0 then
    -- Fallback: drift slightly toward preferred side if totally blocked (keeps us from sitting behind)
    local desired = 0.15 * preferredSideSign
    local stepMax = maxOffsetChangePerSecondN * safeDt
    outN = clampOffsetNormalized(egoN + math.max(-stepMax, math.min(stepMax, desired - egoN)))
  else
    local sIdx = data.candidateStartIndices[bestIdx]
    local eIdx = data.candidateEndIndices[bestIdx]
    local nextN = data.sampleLateralOffsets[math.min(sIdx + 1, eIdx)]
    local stepMax = maxOffsetChangePerSecondN * safeDt
    outN = clampOffsetNormalized(egoN + math.max(-stepMax, math.min(stepMax, nextN - egoN)))

    if LOG_MESSAGE then Logger.log(string.format( "OUT car=%d chosen=%d egoN=%.3f nextN=%.3f outN=%.3f minClr=%.2f targetN=%.2f T=%.2f", egoIndex, bestIdx, egoN, nextN, outN, data.candidateMinClearances[bestIdx], data.candidateTerminalOffsetsN[bestIdx], data.candidateDurationsSeconds[bestIdx])) end
  end

  data.lastOutputOffsetNormalized = outN
  data.lastActualOffsetNormalized = egoN
  data.lastEgoTrackProgress       = egoZ

  return outN
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
-- Debug draw: visualize planning data and audit command vs actual
---------------------------------------------------------------------------------------------------
---@param carIndex integer
function FrenetAvoid.debugDraw(carIndex)
  local d = __carPlanningDataMap[carIndex]
  if not d then return end

  if drawOpponentDiscs then
    for i = 1, d.nearbyOpponentCount do
      local opp = d.nearbyOpponentCars[i]
      if opp then
        render.debugSphere(opp.position, opponentRadiusMeters + egoRadiusMeters + minClrTight_m, rgbm(1, 1, 1, 0.10))
        render.debugSphere(opp.position, opponentRadiusMeters, rgbm(1, 0, 0, 0.25))
      end
    end
  end
  if drawEgoFootprint then
    local ego = ac.getCar(carIndex)
    if ego then render.debugSphere(ego.position, egoRadiusMeters, rgbm(0, 1, 0, 0.25)) end
  end

  if drawRejectionMarkers then
    for i = 1, d.rejectionCount do
      local p = d.rejectionSamplePositions[i]
      local s = 0.6
      render.debugLine(p + vec3(-s,0,-s), p + vec3(s,0,s), rgbm(1,0,0,1))
      render.debugLine(p + vec3(-s,0, s), p + vec3(s,0,-s), rgbm(1,0,0,1))
      local clr = d.rejectionClearances[i]
      if clr then
        render.debugText(p + vec3(0,0.3,0), clr < 0 and string.format("Collision (%.2fm overlap)", -clr) or string.format("clearance %.2f m", clr))
      end
    end
  end

  if d.candidateCount > 0 then
    local drawn = 0
    for ci = 1, d.candidateCount do
      local sIdx, eIdx = d.candidateStartIndices[ci], d.candidateEndIndices[ci]
      for j = sIdx, eIdx - 1 do
        render.debugLine(d.sampleWorldPositions[j], d.sampleWorldPositions[j + 1], colAll)
      end
      if drawSamplesAsSpheres then
        for j = sIdx, eIdx do
          local clr = d.sampleClearances[j]
          local c = (clr <= 0.5 and rgbm(1,0.1,0.1,0.9)) or (clr <= 2.0 and rgbm(1,0.8,0.1,0.9)) or rgbm(0.2,1.0,0.2,0.9)
          render.debugSphere(d.sampleWorldPositions[j], 0.12, c)
        end
      end
      drawn = drawn + 1
      if drawn >= debugMaxPathsDrawn then break end
    end

    local bestIdx, bestCost = 1, d.candidateCosts[1]
    for ci = 2, d.candidateCount do
      local c = d.candidateCosts[ci]; if c < bestCost then bestIdx, bestCost = ci, c end
    end

    local sIdx, eIdx = d.candidateStartIndices[bestIdx], d.candidateEndIndices[bestIdx]
    for j = sIdx, eIdx - 1 do
      render.debugLine(d.sampleWorldPositions[j], d.sampleWorldPositions[j+1], colChosen)
      render.debugLine(d.sampleWorldPositions[j]+vec3(0,0.01,0), d.sampleWorldPositions[j+1]+vec3(0,0.01,0), colChosen)
      render.debugLine(d.sampleWorldPositions[j]+vec3(0,0.02,0), d.sampleWorldPositions[j+1]+vec3(0,0.02,0), colChosen)
    end

    local head = d.sampleWorldPositions[math.min(sIdx + 2, eIdx)]
    if head then render.debugSphere(head, 0.20, colChosen) end

    local mid = d.sampleWorldPositions[math.floor((sIdx + eIdx) * 0.5)]
    if mid then
      local label = string.format("CHOSEN car=%d idx=%d  cost=%.2f  minClr=%.2f m  targetN=%.2f  T=%.2fs",
        carIndex, bestIdx, d.candidateCosts[bestIdx], d.candidateMinClearances[bestIdx],
        d.candidateTerminalOffsetsN[bestIdx], d.candidateDurationsSeconds[bestIdx])
      render.debugText(mid + vec3(0,0.4,0), label)
    end

    if drawAnchorLink then
      local ego = ac.getCar(carIndex)
      if ego and (sIdx + 1) <= eIdx then
        render.debugLine(ego.position, d.sampleWorldPositions[sIdx + 1], rgbm(1,1,1,0.9))
      end
    end
  end

  local ego = ac.getCar(carIndex)
  if ego then
    local tc = ac.worldCoordinateToTrack(ego.position)
    d.lastActualOffsetNormalized = tc.x
    d.lastEgoTrackProgress = tc.z

    if drawReturnedOffsetPole then
      local cmdPos = ac.trackCoordinateToWorld(vec3(d.lastOutputOffsetNormalized, 0.0, d.lastEgoTrackProgress))
      render.debugLine(ego.position, cmdPos, colPoleCmd)
    end
    if drawActualOffsetPole then
      local actPos = ac.trackCoordinateToWorld(vec3(d.lastActualOffsetNormalized, 0.0, d.lastEgoTrackProgress))
      render.debugLine(ego.position, actPos, colPoleAct)
      local dN = math.abs(d.lastOutputOffsetNormalized - d.lastActualOffsetNormalized)
      if dN > auditWarnDeltaN then
        if LOG_MESSAGE then Logger.warn(string.format("[AUDIT] car=%d  outN(cmd)=%.3f  actN=%.3f  Δ=%.3f", carIndex, d.lastOutputOffsetNormalized, d.lastActualOffsetNormalized, dN)) end
      else
        if LOG_MESSAGE then Logger.log(string.format("[AUDIT] car=%d  outN≈actN  cmd=%.3f act=%.3f Δ=%.3f", carIndex, d.lastOutputOffsetNormalized, d.lastActualOffsetNormalized, dN)) end
      end
    end
  end
end

return FrenetAvoid
