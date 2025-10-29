-- FrenetAvoid.lua
-- Purpose:
--   Each frame, generate several smooth lateral "side-step" candidates for the ego car (quintic polynomials),
--   test them for clearance against nearby cars, score them for safety/comfort, pick the best,
--   and return a single spline offset for physics.setAISplineOffset().
--
-- Mental model (no math degree required):
--   Think of the track like a zipper: "z" is how far along the zipper you are (0..1 loop),
--   and "x" is how far left/right you are across the zipper (-1..+1, normalized by track width).
--   We try a few gentle slide-left/slide-right curves ahead of the car, reject ones that would get too close
--   to others, and move a small step toward the best curve. Repeat every frame.

local FrenetAvoid = {}

---------------------------------------------------------------------------------------------------
-- TUNABLE SETTINGS (safe defaults)
---------------------------------------------------------------------------------------------------

-- Planning lookahead in wall-clock seconds (short for responsiveness).
local planningHorizonSeconds     = 1.60

-- Time between evaluation samples along a candidate path (lower = more precise but more CPU).
local sampleTimeStepSeconds      = 0.10

-- How long the lateral maneuver lasts (we try a few options and let the cost choose).
local candidateEndTimesSeconds   = { 0.8, 1.2, 1.6 }

-- Where we *might* want to end laterally (normalized -1..+1). 0 is center, +- is left/right.
local candidateTerminalOffsetsN  = { -0.6, -0.4, -0.2, 0.0, 0.2, 0.4, 0.6 }

-- We only care about opponents close by in "z-progress" to save CPU (wrap-around aware).
local longitudinalWindowAheadZ   = 0.015  -- ~1.5% of the lap ahead
local longitudinalWindowBehindZ  = 0.005  -- small slice behind as well

-- Collision model (simple disks). Tweak to your car's footprint.
local opponentRadiusMeters       = 1.2
local egoRadiusMeters            = 1.2

-- Don't drive right on the painted line: keep some lateral margin from the walls.
local maxAbsOffsetNormalized     = 0.95

-- Output smoothing: don't jump laterally faster than this rate (normalized units per second).
local maxOffsetChangePerSecondN  = 1.8

-- Cost function weights (bigger = more important):
local costWeight_Clearance       = 3.0   -- prefers more free space to others
local costWeight_TerminalCenter  = 1.0   -- prefers finishing near center if all else equal
local costWeight_JerkComfort     = 0.2   -- prefers gentle (low-jerk) motions

-- Output units: normalized (-1..+1) or meters (using AI spline left/right widths).
local OUTPUT_IS_NORMALIZED       = true

-- Debug draw: limit how many candidate polylines we draw (to avoid big frames).
local debugMaxPathsDrawn         = 18

---------------------------------------------------------------------------------------------------
-- INTERNAL REUSABLE SCRATCH (avoid allocations each frame)
---------------------------------------------------------------------------------------------------

-- A candidate path is:
-- {
--   samples = { { pos=vec3, offsetN=number, progressZ=number }, ... },
--   terminalOffsetN, durationT, totalCost, minClearanceMeters
-- }
local scratch_CandidatePaths = {}
local scratch_Samples        = {}
local scratch_NearbyCars     = {}   -- opponents filtered by progress window

-- Helper: wrap normalized progress into [0,1)
local function wrap01(z)
  z = z % 1.0
  return (z < 0) and (z + 1.0) or z
end

---------------------------------------------------------------------------------------------------
-- LATERAL QUINTIC POLYNOMIAL (smooth from "now" to "finish flat")
--
-- We want a function d(t) that:
--   starts at offset d(0) = d0,
--   starts with lateral rate d'(0) = dDot0 (we keep this 0 for simplicity),
--   finishes at offset d(T) = dT,
--   and finishes "flat": d'(T) = 0 and d''(T) = 0 (no sideways velocity or accel at the end).
--
-- That's a classic 5th-order (quintic) polynomial. We return two closures:
--   dAt(t):      lateral offset at time t
--   jerkMag(t):  magnitude of the third derivative d'''(t) (comfort proxy)
---------------------------------------------------------------------------------------------------
local function makeLateralQuintic(d0, dDot0, dT, T)
  -- d(t) = a0 + a1 t + a2 t^2 + a3 t^3 + a4 t^4 + a5 t^5
  local a0 = d0
  local a1 = dDot0
  local a2 = 0.0

  local T2, T3, T4, T5 = T*T, T*T*T, T*T*T*T, T*T*T*T*T
  local C0 = dT - (a0 + a1*T + a2*T2)

  -- Closed-form solution for "finish flat" boundary conditions
  local a3 = (10*C0/T3) - (4*a1/T2)
  local a4 = (-15*C0/T4) + (7*a1/T3)
  local a5 = (  6*C0/T5) - (3*a1/T4)

  local function dAt(t)
    local t2, t3, t4, t5 = t*t, t*t*t, t*t*t*t, t*t*t*t*t
    return a0 + a1*t + a2*t2 + a3*t3 + a4*t4 + a5*t5
  end

  local function jerkMag(t)
    -- d'''(t) = 6 a3 + 24 a4 t + 60 a5 t^2  -> use |...| as a comfort penalty
    return math.abs(6*a3 + 24*a4*t + 60*a5*t*t)
  end

  return dAt, jerkMag
end

---------------------------------------------------------------------------------------------------
-- SMALL HELPERS
---------------------------------------------------------------------------------------------------

-- Convert normalized lateral offset (-1..+1) to meters using asymmetric AI-spline widths at a given z.
local function offsetNormToMeters(offsetN, progressZ)
  local sides = ac.getTrackAISplineSides(progressZ)  -- vec2: x=left meters, y=right meters
  local leftM, rightM = sides.x, sides.y
  return (offsetN < 0) and (offsetN * leftM) or (offsetN * rightM)
end

-- Keep offset within safe normalized bounds (with a margin).
local function clampOffsetToRoad(offsetN)
  return math.max(-maxAbsOffsetNormalized, math.min(maxAbsOffsetNormalized, offsetN))
end

-- Minimum clearance from point to a set of opponent cars (disks).
local function minClearanceToOpponentsMeters(worldPos, opponents)
  local best = 1e9
  for i = 1, #opponents do
    local opp = opponents[i]
    local d = (opp.position - worldPos):length()
    local clearance = d - (opponentRadiusMeters + egoRadiusMeters)
    if clearance < best then best = clearance end
  end
  return best
end

-- Build a small list of nearby opponents by progress span (saves a lot of distance checks).
-- IMPORTANT BUGFIX:
--   Previously we were accidentally including the ego car itself in the opponents list.
--   Then, at t=0, the first sample point is very close to the ego, making clearance negative,
--   flagging a "collision" and rejecting *all* candidates. That's why #scratch_CandidatePaths could be 0.
--   We explicitly skip cars whose index matches egoIndex.
local function collectNearbyOpponents(egoProgressZ, allCars, outList, egoIndex)
  local count = 0
  for i = 1, #allCars do
    local car = allCars[i]
    if car and car.index ~= egoIndex then
      local tc = ac.worldCoordinateToTrack(car.position)  -- (x=offsetN, z=progressZ)
      if tc then
        local dzAhead  = wrap01(tc.z - egoProgressZ)
        local dzBehind = wrap01(egoProgressZ - tc.z)
        if dzAhead <= longitudinalWindowAheadZ or dzBehind <= longitudinalWindowBehindZ then
          count = count + 1
          outList[count] = car
        end
      end
    end
  end
  for j = count + 1, #outList do outList[j] = nil end
  return count
end

---------------------------------------------------------------------------------------------------
-- CORE: Compute a good lateral offset for this frame
--
-- Inputs:
--   allCars : array of ac.StateCar (including ego)
--   ego     : ac.StateCar for the car we are steering
--   dt      : frame delta time in seconds
--
-- Output:
--   single number: normalized lateral offset (-1..+1) unless OUTPUT_IS_NORMALIZED=false (then meters)
---------------------------------------------------------------------------------------------------
function FrenetAvoid.computeOffset(allCars, ego, dt)
  if not ego or not ac.hasTrackSpline() then
    if Logger then Logger.warn("FrenetAvoid.computeOffset: no ego or no AI spline; returning 0") end
    return 0.0
  end

  -- Ego Frenet-ish state (from CSP):
  --   tc.x = current lateral offset (normalized), tc.z = current progress around lap (0..1)
  local egoTrack = ac.worldCoordinateToTrack(ego.position)
  local egoProgressZ = wrap01(egoTrack.z)
  local egoOffsetN   = clampOffsetToRoad(egoTrack.x)

  if Logger then
    Logger.log(string.format("FrenetAvoid.computeOffset: ego idx=%d z=%.4f x=%.3f dt=%.3f",
      ego.index, egoProgressZ, egoOffsetN, dt or -1))
  end

  -- Lateral rate at start: keep it 0 for stability. The quintic still allows smooth motion.
  local egoLateralRateStart = 0.0

  -- Build a tiny working set of opponents near us in progress (skip ego)
  local nearbyCount = collectNearbyOpponents(egoProgressZ, allCars, scratch_NearbyCars, ego.index)
  if Logger then Logger.log(string.format("Nearby opponents collected: %d", nearbyCount)) end

  -- Clear previous candidate list
  for i = 1, #scratch_CandidatePaths do scratch_CandidatePaths[i] = nil end

  local bestCost, bestIndex = 1e9, 0
  local totalCandidates = 0

  -- Try several "where to end laterally" targets and maneuver durations
  for _, terminalOffsetN_raw in ipairs(candidateTerminalOffsetsN) do
    local terminalOffsetN = clampOffsetToRoad(terminalOffsetN_raw)

    for __, durationT in ipairs(candidateEndTimesSeconds) do
      local lateralAt, jerkAbs = makeLateralQuintic(egoOffsetN, egoLateralRateStart, terminalOffsetN, durationT)

      -- Reset sample buffer
      for k = 1, #scratch_Samples do scratch_Samples[k] = nil end

      local time = 0.0
      local sampleCount = 0
      local minClearanceMeters = 1e9
      local jerkAccum = 0.0
      local collided = false

      -- We advance slightly forward in progress as time goes (simple and cheap):
      --   over planningHorizonSeconds we sweep longitudinalWindowAheadZ of progress
      while time <= math.min(durationT, planningHorizonSeconds) do
        sampleCount = sampleCount + 1

        -- Where should we be laterally at this time t?
        local offsetN = clampOffsetToRoad(lateralAt(time))

        -- Where are we along the lap by now? (tiny forward sweep; wrap around 1.0)
        local frac = time / planningHorizonSeconds
        local progressZ = wrap01(egoProgressZ + frac * longitudinalWindowAheadZ)

        -- Convert back to a world-space point to check distances
        local worldPos = ac.trackCoordinateToWorld(vec3(offsetN, 0.0, progressZ))

        -- Clearance against nearby cars (simple disk check)
        local clearance = minClearanceToOpponentsMeters(worldPos, scratch_NearbyCars)
        if clearance < 0.0 then
          collided = true
          if Logger then
            Logger.log(string.format("Candidate REJECT: termN=%.2f T=%.2f t=%.2f clearance=%.2f (collision)",
              terminalOffsetN, durationT, time, clearance))
          end
          break
        end
        if clearance < minClearanceMeters then
          minClearanceMeters = clearance
        end

        jerkAccum = jerkAccum + jerkAbs(time)

        local s = scratch_Samples[sampleCount] or {}
        s.pos = worldPos
        s.offsetN = offsetN
        s.progressZ = progressZ
        scratch_Samples[sampleCount] = s

        time = time + sampleTimeStepSeconds
      end

      -- Keep only survivors (not colliding and with at least 2 points to draw)
      if not collided and sampleCount >= 2 then
        -- Simple interpretable cost:
        --   - prefers bigger minClearance (1/(0.5+clr) keeps it bounded and monotonic)
        --   - prefers finishing near center (|terminalOffsetN|)
        --   - prefers low integrated jerk (comfort)
        local cost =
          (costWeight_Clearance      * (1.0 / (0.5 + minClearanceMeters))) +
          (costWeight_TerminalCenter * math.abs(terminalOffsetN)) +
          (costWeight_JerkComfort    * jerkAccum)

        totalCandidates = totalCandidates + 1
        local cand = scratch_CandidatePaths[totalCandidates] or {}
        cand.samples            = {}
        cand.terminalOffsetN    = terminalOffsetN
        cand.durationT          = durationT
        cand.totalCost          = cost
        cand.minClearanceMeters = minClearanceMeters
        for i = 1, sampleCount do cand.samples[i] = scratch_Samples[i] end
        scratch_CandidatePaths[totalCandidates] = cand

        if Logger then
          Logger.log(string.format("Candidate OK: termN=%.2f T=%.2f samples=%d minClr=%.2f cost=%.3f",
            terminalOffsetN, durationT, sampleCount, minClearanceMeters, cost))
        end

        if cost < bestCost then
          bestCost, bestIndex = cost, totalCandidates
        end
      else
        if Logger then
          Logger.log(string.format("Candidate DROPPED: termN=%.2f T=%.2f collided=%s samples=%d",
            terminalOffsetN, durationT, tostring(collided), sampleCount))
        end
      end
    end
  end

  if Logger then Logger.log(string.format("Total survivors: %d (bestIndex=%d)", #scratch_CandidatePaths, bestIndex)) end

  -- If nothing safe, gently drift back to center line
  if bestIndex == 0 then
    if Logger then Logger.warn("FrenetAvoid: no survivors; easing back to center") end
    local desiredN = 0.0
    local stepMax  = maxOffsetChangePerSecondN * dt
    local deltaN   = math.max(-stepMax, math.min(stepMax, desiredN - egoOffsetN))
    local outN     = clampOffsetToRoad(egoOffsetN + deltaN)
    return OUTPUT_IS_NORMALIZED and outN or offsetNormToMeters(outN, egoProgressZ)
  end

  -- Smoothly head toward the *next* point on the best path (prevents twitching)
  local best = scratch_CandidatePaths[bestIndex]
  local nextOffsetN = best.samples[ math.min(2, #best.samples) ].offsetN
  local stepMax     = maxOffsetChangePerSecondN * dt
  local deltaN      = math.max(-stepMax, math.min(stepMax, nextOffsetN - egoOffsetN))
  local outN        = clampOffsetToRoad(egoOffsetN + deltaN)

  if Logger then
    Logger.log(string.format("Output: nextN=%.3f stepMax=%.3f outN=%.3f",
      nextOffsetN, stepMax, outN))
  end

  return OUTPUT_IS_NORMALIZED and outN or offsetNormToMeters(outN, egoProgressZ)
end

---------------------------------------------------------------------------------------------------
-- DEBUG DRAWING (3D)
-- Renders:
--   • All survivor candidates as thin polylines (semi-transparent)
--   • The chosen best candidate as a thicker polyline, plus a label with cost/clearance
---------------------------------------------------------------------------------------------------

local color_AllCandidates = rgbm(0.3, 0.7, 1.0, 0.5)
local color_BestCandidate = rgbm(1.0, 0.9, 0.2, 1.0)

---@param carIndex integer
function FrenetAvoid.debugDraw(carIndex)
  if #scratch_CandidatePaths == 0 then
    -- if Logger then Logger.log("FrenetAvoid.debugDraw: no candidate paths to draw") end
    return
  end

  -- Draw survivors (thin). Cap the number for performance.
  local drawn = 0
  for i = 1, #scratch_CandidatePaths do
    local p = scratch_CandidatePaths[i]
    for j = 1, #p.samples - 1 do
      render.debugLine(p.samples[j].pos, p.samples[j+1].pos, color_AllCandidates)
    end
    drawn = drawn + 1
    if drawn >= debugMaxPathsDrawn then break end
  end

  -- Find best (lowest cost) and highlight it
  local bestIdx, bestCost = 1, scratch_CandidatePaths[1].totalCost
  for i = 2, #scratch_CandidatePaths do
    if scratch_CandidatePaths[i].totalCost < bestCost then
      bestIdx, bestCost = i, scratch_CandidatePaths[i].totalCost
    end
  end
  local bp = scratch_CandidatePaths[bestIdx]
  for j = 1, #bp.samples - 1 do
    render.debugLine(bp.samples[j].pos, bp.samples[j+1].pos, color_BestCandidate)
  end

  -- Label the best at its midpoint
  local mid = bp.samples[math.floor(#bp.samples / 2)]
  if mid then
    local text = string.format("best  cost=%.2f  minClr=%.2fm  dT=%.2f  T=%.2fs",
      bp.totalCost, bp.minClearanceMeters, bp.terminalOffsetN, bp.durationT)
    render.debugText(mid.pos, text)
  end

  -- Optional: small forward tick showing ego's local spline axis
  local ego = ac.getCar(carIndex)
  if ego then
    local tc = ac.worldCoordinateToTrack(ego.position)
    local p1 = ac.trackCoordinateToWorld(vec3(tc.x, 0.0, tc.z))
    local p2 = ac.trackCoordinateToWorld(vec3(tc.x, 0.0, wrap01(tc.z + 0.01)))
    render.debugLine(p1, p2, rgbm(1,1,1,1))
  end
end

return FrenetAvoid
