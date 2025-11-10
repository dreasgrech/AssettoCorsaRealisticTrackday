-- FrenetAvoid.lua
-- NOTE: Keep existing formatting and comments. Heavy inline comments + Logger calls added for diagnosis.

local FrenetAvoid = {}

-- =========================================================================================
-- Tunables (kept names where possible to avoid touching other code)
-- =========================================================================================

-- longitudinal planning window (in normalized Z of the track, 0..1 wraps around)
local longitudinalWindowAheadZ = 0.035   -- typical 80–120 m depending on track length
local longitudinalWindowBehindZ = 0.004

-- planning horizon (seconds ahead the lateral primitive is defined for)
local planningHorizonSeconds = 1.6

-- allow sampling to use speed-aware forward progress
local useSpeedAwareLookahead = true
-- local minAheadMetersAtLowSpeed  =  60.0
local minAheadMetersAtLowSpeed  =  0.0
-- local maxAheadMetersAtHighSpeed = 140.0
local maxAheadMetersAtHighSpeed = 340.0
-- local startMetersAhead          =  10.0
local startMetersAhead          =  0.0
local nominalTrackLengthMeters  = 20832.0 -- Nordschleife default; only used to convert meters→Δz

-- collision clearance
-- local opponentRadiusMeters = 2.1
local opponentRadiusMeters = 1.7
local egoRadiusMeters      = 1.8

-- normalized offset constraints and rate limits
local maxAbsOffsetNormalized = 1.0
local maxOffsetChangePerSecondN = 2.6  -- how fast we can slide across the width (in -1..1 / s)
local OUTPUT_IS_NORMALIZED = true

-- cost weights
local costWeight_Clearance       = 3.0
local costWeight_TerminalCenter  = 0.7
local costWeight_JerkComfort     = 0.22

-- base grids (time terminals and lateral terminals); keep names stable
local candidateEndTimesSecondsBase     = { 0.7, 1.0, 1.3, 1.6 }
local candidateTerminalOffsetsNBase    = { -1.00, -0.75, -0.50, -0.25, 0.0, 0.25, 0.50, 0.75, 1.00 }

-- densification when space is tight (kept names)
local densifyOffsetsExtra = { -1.0, -0.8, -0.6, 0.6, 0.8, 1.0 }
local densifyEndTimesExtra = { 0.6, 1.0 }

-- simple TTC gating to start earlier if we’ll reach a car soon
local ttcEarlyPlanStart_s = 3.0
local ttcEmergency_s      = 1.3
local extraAheadZ_whenEarly = 0.010

-- debug draw flags
local debugMaxPathsDrawn     = 24
local drawSamplesAsSpheres   = true
local drawOpponentDiscs      = true
local drawRejectionMarkers   = true
local drawEgoFootprint       = true
local drawAnchorLink         = true
local drawReturnedOffsetPole = true
local drawActualOffsetPole   = true
local drawTrackWidthGuides   = true
local auditWarnDeltaN        = 0.15

-- colors
local colAll     = rgbm(0.30, 0.90, 0.30, 0.15)
local colChosen  = rgbm(1.00, 0.20, 0.90, 1.00)
local colPoleCmd = rgbm(0.20, 1.00, 1.00, 0.90)
local colPoleAct = rgbm(1.00, 1.00, 0.20, 0.90)
local colRail    = rgbm(0.70, 0.70, 0.70, 0.35)

-- helpers (no allocations)
local abs, min, max = math.abs, math.min, math.max

local function clampN(n)
  if n < -maxAbsOffsetNormalized then return -maxAbsOffsetNormalized end
  if n >  maxAbsOffsetNormalized then return  maxAbsOffsetNormalized end
  return n
end

local function wrap01(z)
  z = z % 1.0
  if z < 0.0 then z = z + 1.0 end
  return z
end

-- meters→Δz mapping for forward sampling (optionally speed-aware)
local function progressAt(egoZ, egoSpeedMps, t)
  if not useSpeedAwareLookahead then
    local frac = t / planningHorizonSeconds
    return wrap01(egoZ + frac * longitudinalWindowAheadZ)
  end
  local aheadMeters = max(minAheadMetersAtLowSpeed, min(maxAheadMetersAtHighSpeed, egoSpeedMps * planningHorizonSeconds))
  local meters = (t / planningHorizonSeconds) * aheadMeters + startMetersAhead
  return wrap01(egoZ + (meters / nominalTrackLengthMeters))
end

-- quintic lateral profile d(t) from d0 (with v0) to dT in time T (end v=a=0)
local function makeLateralQuintic(d0, dDot0, dT, T)
  local T2, T3, T4, T5 = T*T, T*T*T, T*T*T*T, T*T*T*T*T
  local a0, a1, a2 = d0, dDot0, 0.0
  local a3 = (10*(dT - d0) - (6*dDot0)*T) / T3
  local a4 = (-15*(dT - d0) + (8*dDot0)*T) / T4
  local a5 = (6*(dT - d0)  - (3*dDot0)*T) / T5
  return
    function(t) -- d(t)
      if t < 0 then t = 0 elseif t > T then t = T end
      return a0 + a1*t + a2*t*t + a3*t*t*t + a4*t*t*t*t + a5*t*t*t*t*t
    end,
    function(t) -- |jerk|(t) proxy for comfort
      local tt = (t < 0 and 0) or (t > T and T) or t
      local j = 6*a3 + 24*a4*tt + 60*a5*tt*tt
      return abs(j)
    end
end

-- =========================================================================================
-- Nearby collection and TTC probe (uses lib-friendly access)
-- =========================================================================================

---@param egoIndex integer
---@param egoZ number
---@param allCars ac.StateCar[]
---@param out table
---@param aheadZ number
---@param behindZ number
---@return integer
local function collectNearbyOpponents(egoIndex, egoZ, allCars, out, aheadZ, behindZ)
  local count = 0
  for _, c in ac.iterateCars() do
    local idx = c.index
    if idx ~= egoIndex then
      local cz = wrap01(ac.worldCoordinateToTrack(c.position).z - egoZ)
      if cz <= aheadZ or cz >= 1.0 - behindZ then
        count = count + 1
        out[count] = c
      end
    end
  end
  out.count = count
  return count
end

---@param egoPos vec3
---@param egoV number
---@param egoZ number
---@param nearby table
---@param count integer
---@param aheadZ number
---@return number|nil
local function estimateTTC_s(egoPos, egoV, egoZ, nearby, count, aheadZ)
  if count == 0 or egoV < 0.1 then return nil end
  local best
  for i = 1, count do
    local opp = nearby[i]
    if opp then
      local dz = wrap01(ac.worldCoordinateToTrack(opp.position).z - egoZ)
      if dz <= aheadZ then
        local relV = max(0.1, egoV - (opp.speedKmh or 0)/3.6)
        if relV > 0.2 then
          local d = (opp.position - egoPos):length()
          local t = d / relV
          if not best or t < best then best = t end
        end
      end
    end
  end
  return best
end

-- =========================================================================================
-- Per-car scratch arena (SoA; zero allocs per frame)
-- =========================================================================================
local __arena = {}
local function A(ix)
  local a = __arena[ix]
  if a then return a end
  a = {
    nearby = {},

    samplesPos = {}, samplesClr = {}, samplesN = {}, samplesCount = 0,
    candStart = {}, candEnd = {}, candCost = {}, candMinClr = {}, candDT = {}, candT = {}, candCount = 0,

    rejectsPos = {}, rejectsCount = 0,

    lastOutN = 0.0, lastActualN = 0.0, lastEgoZ = 0.0,

    -- debug helpers
    dbg_leftFree = 0.0,
    dbg_rightFree = 0.0,
    dbg_reason = "none"
  }
  __arena[ix] = a
  return a
end

-- =========================================================================================
-- Public: compute lateral offset for one car
-- =========================================================================================

---@param allCars ac.StateCar[]
---@param egoIndex integer
---@param dt number
---@return number  -- normalized [-1..+1]
function FrenetAvoid.computeOffsetForCar(allCars, egoIndex, dt)
  local ego = ac.getCar(egoIndex)
  if not ego or not ac.hasTrackSpline() then
    Logger.warn("FrenetAvoid: missing ego or AI spline")
    return 0.0
  end

  -- IMPORTANT: protect against dt≈0 which would clamp the slew to 0 and break avoidance
  local safeDt = max(0.016, dt or 0.016)  -- never smaller than ~1/60 s

  local arena = A(egoIndex)
  arena.samplesCount, arena.candCount, arena.rejectsCount = 0, 0, 0
  arena.dbg_leftFree, arena.dbg_rightFree, arena.dbg_reason = 0.0, 0.0, "none"

  -- ego in track coords
  local tc = ac.worldCoordinateToTrack(ego.position)
  local egoZ = wrap01(tc.z)
  local egoN = clampN(tc.x)
  local egoV = (ego.speedKmh or 0) / 3.6
  arena.lastEgoZ = egoZ

  -- quick check: if nobody nearby, gently slew to center and return (cheap fast path)
  local count = collectNearbyOpponents(egoIndex, egoZ, allCars, arena.nearby,
    longitudinalWindowAheadZ, longitudinalWindowBehindZ)

  if count == 0 then
    local step = maxOffsetChangePerSecondN * safeDt
    local outN = clampN(egoN + max(-step, min(step, 0.0 - egoN)))
    arena.lastOutN = outN
    Logger.log(string.format("FA: car=%d z=%.4f x=%.3f v=%.1f ttc=none near=0", egoIndex, egoZ, egoN, egoV))
    return outN
  end

  -- widen window if TTC is low (start earlier)
  local ttc = estimateTTC_s(ego.position, egoV, egoZ, arena.nearby, count, longitudinalWindowAheadZ)
  if ttc and ttc < ttcEarlyPlanStart_s then
    count = collectNearbyOpponents(egoIndex, egoZ, allCars, arena.nearby,
      longitudinalWindowAheadZ + extraAheadZ_whenEarly, longitudinalWindowBehindZ)
  end

  -- -----------------------------------------------------------------------------------------
  -- Build candidate grid (time terminals × lateral terminals). Densify if TTC is critical.
  -- -----------------------------------------------------------------------------------------
  local candidateEndTimesSeconds = { table.unpack(densifyEndTimesExtra) }
  for i = 1, #candidateEndTimesSecondsBase do
    candidateEndTimesSeconds[#candidateEndTimesSeconds + 1] = candidateEndTimesSecondsBase[i]
  end

  local candidateTerminalOffsetsN = { table.unpack(candidateTerminalOffsetsNBase) }
  if ttc and ttc < ttcEarlyPlanStart_s then
    for i = 1, #densifyOffsetsExtra do
      candidateTerminalOffsetsN[#candidateTerminalOffsetsN + 1] = densifyOffsetsExtra[i]
    end
  end

  -- ensure terminals cover the full width (defensive)
  candidateTerminalOffsetsN[#candidateTerminalOffsetsN + 1] = -1.0
  candidateTerminalOffsetsN[#candidateTerminalOffsetsN + 1] =  1.0

  -- -----------------------------------------------------------------------------------------
  -- Sample & collide candidates
  -- -----------------------------------------------------------------------------------------
  local bestIdx, bestCost = 0, 1e9

  for tIdx = 1, #candidateEndTimesSeconds do
    local T = candidateEndTimesSeconds[tIdx]
    for oIdx = 1, #candidateTerminalOffsetsN do
      local dT = clampN(candidateTerminalOffsetsN[oIdx])
      local d0, v0 = egoN, 0.0
      local d, jerkAbs = makeLateralQuintic(d0, v0, dT, T)

      -- discretize trajectory; sample count proportional to time
      local steps = max(6, math.floor(10 * T))
      local minClr = 99.0
      local collided = false
      local start = arena.samplesCount + 1

      for s = 0, steps do
        local t = (s / steps) * T
        local n = clampN(d(t))
        local z = progressAt(egoZ, egoV, t)
        local p = ac.trackCoordinateToWorld(vec3(n, 0.0, z))

        arena.samplesCount = arena.samplesCount + 1
        arena.samplesPos[arena.samplesCount] = p
        arena.samplesN[arena.samplesCount] = n

        -- clearance check vs nearby cars (simple spheres, cheap)
        local clr = 99.0
        for i = 1, count do
          local opp = arena.nearby[i]
          local c = (opp.position - p):length() - (opponentRadiusMeters + egoRadiusMeters)
          if c < clr then clr = c end
          if c < 0.0 then
            collided = true
            arena.rejectsCount = arena.rejectsCount + 1
            arena.rejectsPos[arena.rejectsCount] = p
            break
          end
        end
        arena.samplesClr[arena.samplesCount] = clr
        if clr < minClr then minClr = clr end

        if collided then break end
      end

      local stop = arena.samplesCount + 1
      if not collided then
        local comfort = 0.0
        -- integrate jerk proxy sparsely (every other step)
        for s = 0, steps, 2 do
          comfort = comfort + jerkAbs((s / steps) * T)
        end
        local centerBias = abs(dT) -- prefer ending closer to center
        local cost = costWeight_Clearance * (1.0 / (0.05 + minClr)) +
                     costWeight_TerminalCenter * centerBias +
                     costWeight_JerkComfort * comfort

        local k = arena.candCount + 1
        arena.candCount = k
        arena.candStart[k], arena.candEnd[k] = start, stop
        arena.candMinClr[k], arena.candDT[k], arena.candT[k] = minClr, dT, T
        arena.candCost[k] = cost

        if cost < bestCost then bestCost, bestIdx = cost, k end

        Logger.log(string.format("OK car=%d dT=%.2f T=%.2f minClr=%.2f cost=%.2f", egoIndex, dT, T, minClr, cost))
      else
        Logger.log(string.format("DROP car=%d dT=%.2f T=%.2f (collided)", egoIndex, dT, T))
      end
    end
  end

  Logger.log("Survivors="..tostring(arena.candCount).." bestIdx="..tostring(bestIdx))

  -- -----------------------------------------------------------------------------------------
  -- Command: steer toward next sample on the best candidate
  -- -----------------------------------------------------------------------------------------
  local outN
  if bestIdx == 0 then
    -- No survivor: pick a gentle evasive nudge away from nearest car horizontally, else center
    local desired = 0.0
    local nearest, dBest2
    for i = 1, count do
      local opp = arena.nearby[i]
      local d2 = (opp.position - ego.position):lengthSquared()
      if not dBest2 or d2 < dBest2 then dBest2 = d2; nearest = opp end
    end
    if nearest then
      local nOpp = ac.worldCoordinateToTrack(nearest.position).x
      desired = (nOpp >= egoN) and -0.35 or 0.35
    end
    local stepMax = maxOffsetChangePerSecondN * safeDt
    outN = clampN(egoN + max(-stepMax, min(stepMax, desired - egoN)))
    arena.dbg_reason = "fallback"
  else
    local sIdx = arena.candStart[bestIdx]
    local eIdx = arena.candEnd[bestIdx]
    local nextN = arena.samplesN[min(sIdx + 1, eIdx)]

    -- IMPORTANT: never let stepMax go to 0; otherwise purple path sticks straight
    local stepMax = maxOffsetChangePerSecondN * safeDt
    outN = clampN(egoN + max(-stepMax, min(stepMax, nextN - egoN)))

    -- diagnosis: if we *want* to move but step is the limiter, log it distinctly
    if abs(nextN - egoN) > 0.10 and abs(outN - egoN) < 1e-3 then
      Logger.warn(string.format("[SLEW-CAPPED] car=%d egoN=%.3f want=%.3f stepMax=%.3f dt=%.3f",
        egoIndex, egoN, nextN, stepMax, safeDt))
    end

    Logger.log(string.format(
      "OUT car=%d chosen=%d egoN=%.3f nextN=%.3f outN=%.3f minClr=%.2f dT=%.2f T=%.2f reason=%s",
      egoIndex, bestIdx, egoN, nextN, outN, arena.candMinClr[bestIdx], arena.candDT[bestIdx], arena.candT[bestIdx], arena.dbg_reason))
  end

  arena.lastOutN   = outN
  arena.lastActualN = egoN  -- updated again in debugDraw after physics applies
  arena.lastEgoZ   = egoZ
  return outN
end

-- =========================================================================================
-- Batch version (no allocations; keeps caller’s table)
-- =========================================================================================

---@param allCars ac.StateCar[]
---@param dt number
---@param outOffsets number[]  -- 0-based car index stored at [index+1]
---@return number[]
function FrenetAvoid.computeOffsetsForAll(allCars, dt, outOffsets)
  for _, car in ac.iterateCars() do
    local idx = car.index
    outOffsets[idx + 1] = FrenetAvoid.computeOffsetForCar(allCars, idx, dt)
  end
  return outOffsets
end

-- =========================================================================================
-- Debug draw + audit: which path is chosen vs actual applied offset
-- =========================================================================================
---@param carIndex integer
function FrenetAvoid.debugDraw(carIndex)
  local a = __arena[carIndex]
  if not a then return end

  if drawOpponentDiscs then
    local n = a.nearby.count or 0
    for i = 1, n do
      render.debugSphere(a.nearby[i].position, opponentRadiusMeters, rgbm(1,0,0,0.25))
    end
  end

  if drawEgoFootprint then
    local ego = ac.getCar(carIndex)
    if ego then render.debugSphere(ego.position, egoRadiusMeters, rgbm(0,1,0,0.15)) end
  end

  if drawRejectionMarkers then
    for i = 1, a.rejectsCount do
      local p = a.rejectsPos[i]
      local d = 0.6
      render.debugLine(p + vec3(-d,0,-d), p + vec3(d,0,d), rgbm(1,0,0,1))
      render.debugLine(p + vec3(-d,0, d), p + vec3(d,0,-d), rgbm(1,0,0,1))
    end
  end

  if drawAnchorLink and a.samplesCount >= 1 then
    local ego = ac.getCar(carIndex)
    if ego then render.debugLine(ego.position, a.samplesPos[1], rgbm(0.3,0.3,1.0,0.7)) end
  end

  -- track width guides to confirm full usable span (left/right rails)
  if drawTrackWidthGuides then
    local ego = ac.getCar(carIndex)
    if ego then
      local tc = ac.worldCoordinateToTrack(ego.position)
      local baseZ = wrap01(tc.z)
      local steps = 10
      local prevL, prevR
      for i = 0, steps do
        local z = wrap01(baseZ + (i/steps) * longitudinalWindowAheadZ * 2.0)
        local pL = ac.trackCoordinateToWorld(vec3(-1.0, 0.0, z))
        local pR = ac.trackCoordinateToWorld(vec3( 1.0, 0.0, z))
        if prevL then render.debugLine(prevL, pL, colRail) end
        if prevR then render.debugLine(prevR, pR, colRail) end
        prevL, prevR = pL, pR
      end
    end
  end

  if a.candCount > 0 then
    -- draw all candidates thin, then chosen thick
    local drawn = 0
    for ci = 1, a.candCount do
      local sIdx, eIdx = a.candStart[ci], a.candEnd[ci]
      for j = sIdx, eIdx - 1 do
        render.debugLine(a.samplesPos[j], a.samplesPos[j+1], colAll)
      end
      if drawSamplesAsSpheres then
        for j = sIdx, eIdx do
          -- color by clearance: red <0.5, amber <2.0, green otherwise
          local clr = a.samplesClr[j] or 9.9
          local c = (clr <= 0.5 and rgbm(1,0.1,0.1,0.9)) or (clr <= 2.0 and rgbm(1,0.8,0.1,0.9)) or rgbm(0.2,1.0,0.2,0.9)
          render.debugSphere(a.samplesPos[j], 0.10, c)
        end
      end
      drawn = drawn + 1
      if drawn >= debugMaxPathsDrawn then break end
    end

    -- chosen path highlighted in magenta (three passes thick)
    local bestIdx, bestCost = 1, a.candCost[1]
    for ci = 2, a.candCount do
      local c = a.candCost[ci]; if c < bestCost then bestIdx, bestCost = ci, c end
    end
    local sIdx, eIdx = a.candStart[bestIdx], a.candEnd[bestIdx]
    for j = sIdx, eIdx - 1 do
      render.debugLine(a.samplesPos[j], a.samplesPos[j+1], colChosen)
      render.debugLine(a.samplesPos[j]+vec3(0,0.01,0), a.samplesPos[j+1]+vec3(0,0.01,0), colChosen)
      render.debugLine(a.samplesPos[j]+vec3(0,0.02,0), a.samplesPos[j+1]+vec3(0,0.02,0), colChosen)
    end
  end

  -- audit: commanded vs applied (helps confirm spline offset is fed correctly)
  local ego = ac.getCar(carIndex)
  if ego then
    local tc = ac.worldCoordinateToTrack(ego.position)
    a.lastActualN = tc.x

    if drawReturnedOffsetPole then
      local poleCmd = ac.trackCoordinateToWorld(vec3(a.lastOutN, 0.0, a.lastEgoZ))
      render.debugLine(ego.position, poleCmd, colPoleCmd)
    end
    if drawActualOffsetPole then
      local poleAct = ac.trackCoordinateToWorld(vec3(a.lastActualN, 0.0, a.lastEgoZ))
      render.debugLine(ego.position, poleAct, colPoleAct)
      local dN = abs(a.lastOutN - a.lastActualN)
      if dN > auditWarnDeltaN then
        Logger.warn(string.format("[AUDIT] car=%d cmd=%.3f act=%.3f Δ=%.3f", carIndex, a.lastOutN, a.lastActualN, dN))
      end
    end
  end
end

return FrenetAvoid
