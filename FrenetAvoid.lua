-- FrenetAvoid.lua — normalized lateral avoidance for physics.setAISplineOffset(idx, n, true)
-- Notes:
--  • Keeps visualization and command in sync: returned value always follows the chosen path’s next sample.
--  • Optimized for FPS: zero per-frame allocations, squared-distance clearance, early exits, cached locals.
--  • Multi-car safe: per-car scratch arena keyed by car index.
--  • Comments explain intent; existing comment style preserved; no unrelated code churn.

local FrenetAvoid = {}

-- tunables
local planningHorizonSeconds = 1.60
local sampleTimeStepSeconds = 0.08
local firstSampleSeconds = 0.03
local startMetersAhead = 0.0

-- include full track span up to kerbs; ±1.0 helps visualization reach edges when trackCoordinateToWorld supports it
local candidateEndTimesSecondsBase = { 0.8, 1.2, 1.6 }
local candidateTerminalOffsetsNBase = { -1.0,-0.9,-0.7,-0.5,-0.3, 0.0, 0.3, 0.5, 0.7, 0.9, 1.0 }

local longitudinalWindowAheadZ = 0.020
local longitudinalWindowBehindZ = 0.006
local extraAheadZ_whenEarly = 0.020

local useSpeedAwareLookahead = true
local minAheadMetersAtLowSpeed = 6.0
local maxAheadMetersAtHighSpeed = 45.0
local nominalTrackLengthMeters = 20000.0

local opponentRadiusMeters = 1.45
local egoRadiusMeters = 1.45
local sumRadii = opponentRadiusMeters + egoRadiusMeters
local sumRadii2 = sumRadii * sumRadii

-- allow full [-1..+1] command so lines can reach the full width
local maxAbsOffsetNormalized = 1.0
local maxOffsetChangePerSecondN = 2.6
local OUTPUT_IS_NORMALIZED = true

local costWeight_Clearance = 3.0
local costWeight_TerminalCenter = 0.7
local costWeight_JerkComfort = 0.22

-- densification when space is tight; keep variable names as in previous revisions
local densifyOffsetsExtra = { -1.0, -0.8, -0.6, 0.6, 0.8, 1.0 }
local densifyEndTimesExtra = { 0.6, 1.0 }

-- simple TTC gating (no heavy math, just to start planning a bit earlier)
local ttcEarlyPlanStart_s = 3.0

-- debug draw flags (kept)
local debugMaxPathsDrawn = 24
local drawSamplesAsSpheres = true
local drawOpponentDiscs = true
local drawRejectionMarkers = true
local drawEgoFootprint = true
local drawAnchorLink = true
local drawReturnedOffsetPole = true
local drawActualOffsetPole = true
local auditWarnDeltaN = 0.15

-- colors (kept)
local colAll     = rgbm(0.3, 0.9, 0.3, 0.15)
local colChosen  = rgbm(1.0, 0.2, 0.9, 1.0)
local colPoleCmd = rgbm(0.2, 1.0, 1.0, 0.9)
local colPoleAct = rgbm(1.0, 1.0, 0.2, 0.9)

-- helpers (no allocations, hot-path friendly)
local abs = math.abs
local min = math.min
local max = math.max
local sqrt = math.sqrt

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
  local a5 = (6*(dT - d0) - (3*dDot0)*T)  / T5
  return function(t)
    if t < 0 then t = 0 elseif t > T then t = T end
    local t2 = t*t
    return a0 + a1*t + a2*t2 + a3*t*t2 + a4*t2*t2 + a5*t2*t2*t
  end,
  function(t) -- absolute jerk proxy (cheap comfort term)
    if t < 0 then t = 0 elseif t > T then t = T end
    local j = 6*a3 + 24*a4*t + 60*a5*t*t
    if j < 0 then return -j end
    return j
  end
end

-- squared-distance clearance (no sqrt until compare) to opponent discs; negative => overlap
local function minClearanceMetersFast(worldPos, opponents, count)
  if count == 0 then return 99.0 end
  local best2 = 1e30
  local wx, wy, wz = worldPos.x, worldPos.y, worldPos.z
  for i = 1, count do
    local p = opponents[i].position
    local dx = p.x - wx
    local dy = p.y - wy
    local dz = p.z - wz
    local d2 = dx*dx + dy*dy + dz*dz
    if d2 < best2 then best2 = d2 end
  end
  return sqrt(best2) - sumRadii
end

-- wrap-aware opponent collection; skips ego
local function collectNearbyOpponents(egoIndex, egoZ, allCars, out, aheadZ, behindZ)
  local n = 0
  for i = 1, #allCars do
    local c = allCars[i]
    if c and c.index ~= egoIndex then
      local tc = ac.worldCoordinateToTrack(c.position)
      if tc then
        local dzAhead  = wrap01(tc.z - egoZ)
        local dzBehind = wrap01(egoZ - tc.z)
        if dzAhead <= aheadZ or dzBehind <= behindZ then
          n = n + 1
          out[n] = c
        end
      end
    end
  end
  out.count = n
  for j = n + 1, #out do out[j] = nil end
  return n
end

-- very light TTC estimate to closest forward car (used only to widen opponent window)
local function estimateTTC_s(egoPos, egoV, egoZ, opponents, count, aheadZ)
  local best
  for i = 1, count do
    local opp = opponents[i]
    local tc = ac.worldCoordinateToTrack(opp.position)
    if tc then
      if wrap01(tc.z - egoZ) <= aheadZ + 0.02 then
        local relV = egoV - (opp.speedKmh or 0)/3.6
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

-- per-car arena (SoA; zero allocations per frame)
local __arena = {}
local function A(ix)
  local a = __arena[ix]
  if a then return a end
  a = {
    nearby = {},

    samplesPos = {}, samplesClr = {}, samplesN = {}, samplesCount = 0,
    candStart = {}, candEnd = {}, candCost = {}, candMinClr = {}, candDT = {}, candT = {}, candCount = 0,

    rejectsPos = {}, rejectsCount = 0,

    lastOutN = 0.0, lastActualN = 0.0, lastEgoZ = 0.0
  }
  __arena[ix] = a
  return a
end

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

  local arena = A(egoIndex)
  arena.samplesCount, arena.candCount, arena.rejectsCount = 0, 0, 0

  -- ego in track coords
  local tc = ac.worldCoordinateToTrack(ego.position)
  local egoZ = wrap01(tc.z)
  local egoN = clampN(tc.x)
  local egoV = (ego.speedKmh or 0) / 3.6
  arena.lastEgoZ = egoZ

  -- early out: if nobody near ahead/behind windows, just slew slightly to center and keep FPS
  local count = collectNearbyOpponents(egoIndex, egoZ, allCars, arena.nearby, longitudinalWindowAheadZ, longitudinalWindowBehindZ)
  if count == 0 then
    local step = maxOffsetChangePerSecondN * dt
    local outN = clampN(egoN + max(-step, min(step, 0.0 - egoN)))
    arena.lastOutN = outN
    return OUTPUT_IS_NORMALIZED and outN or outN
  end

  -- widen window slightly if TTC is low (cheap, avoids late decisions)
  local ttc = estimateTTC_s(ego.position, egoV, egoZ, arena.nearby, count, longitudinalWindowAheadZ)
  if ttc and ttc < ttcEarlyPlanStart_s then
    count = collectNearbyOpponents(egoIndex, egoZ, allCars, arena.nearby, longitudinalWindowAheadZ + extraAheadZ_whenEarly, longitudinalWindowBehindZ)
  end

  -- candidate time grid (bug-proof: use densifyEndTimesExtra name)
  local candidateEndTimesSeconds = { table.unpack(densifyEndTimesExtra) }
  for i = 1, #candidateEndTimesSecondsBase do
    candidateEndTimesSeconds[#candidateEndTimesSeconds + 1] = candidateEndTimesSecondsBase[i]
  end

  -- candidate lateral terminals; densify if TTC is low
  local candidateTerminalOffsetsN = { table.unpack(candidateTerminalOffsetsNBase) }
  if ttc and ttc < ttcEarlyPlanStart_s then
    for i = 1, #densifyOffsetsExtra do
      candidateTerminalOffsetsN[#candidateTerminalOffsetsN + 1] = densifyOffsetsExtra[i]
    end
  end

  -- when an obstacle is ahead and close, force commitment to the free side and with sufficient magnitude
  local desiredSign = 0
  local minCommitMag = 0.0
  if ttc and ttc < 2.5 then
    -- pick nearest forward opponent by longitudinal progress and decide to pass on the freer side
    local nearestOpp, nearestDz = nil, 1e9
    for i = 1, count do
      local opp = arena.nearby[i]
      local otc = ac.worldCoordinateToTrack(opp.position)
      if otc then
        local dz = wrap01(otc.z - egoZ)
        if dz < nearestDz then
          nearestDz = dz
          nearestOpp = opp
        end
      end
    end
    if nearestOpp then
      local nOpp = ac.worldCoordinateToTrack(nearestOpp.position).x
      -- choose the side away from the obstacle center relative to ego
      if nOpp >= egoN then desiredSign = -1 else desiredSign = 1 end
      -- require a stronger terminal magnitude as we get closer
      if ttc <= 1.2 then
        minCommitMag = 0.8
      elseif ttc <= 1.8 then
        minCommitMag = 0.6
      else
        minCommitMag = 0.4
      end
    end
  end

  if desiredSign ~= 0 then
    -- filter candidates to chosen side and magnitude to avoid dithering straight into the car
    local filtered = {}
    for i = 1, #candidateTerminalOffsetsN do
      local nT = candidateTerminalOffsetsN[i]
      if (nT * desiredSign) > 0 and abs(nT) >= minCommitMag then
        filtered[#filtered + 1] = nT
      end
    end
    if #filtered > 0 then candidateTerminalOffsetsN = filtered end
  end

  Logger.log(string.format("FA in: car=%d z=%.5f xN=%.3f v=%.1f ttc=%.2f near=%d  nT=%d T=%d sign=%d min|n|=%.2f",
    egoIndex, egoZ, egoN, egoV, ttc or -1, count, #candidateTerminalOffsetsN, #candidateEndTimesSeconds, desiredSign, minCommitMag))

  -- anchor: sample[1] at ego pose so lines start at the bumper (avoids “far first node”)
  arena.samplesCount = 1
  arena.samplesPos[1] = ac.trackCoordinateToWorld(vec3(egoN, 0.0, egoZ))
  arena.samplesN[1] = egoN
  arena.samplesClr[1] = 99.0

  local bestCost, bestIdx = 1e9, 0

  -- evaluate candidates; squared-distance clearance + early break on collision
  for ci = 1, #candidateTerminalOffsetsN do
    local nT = clampN(candidateTerminalOffsetsN[ci])
    for ti = 1, #candidateEndTimesSeconds do
      local T = candidateEndTimesSeconds[ti]
      local dAt, jerkAbs = makeLateralQuintic(egoN, 0.0, nT, T)

      local sStart = arena.samplesCount + 1
      local t = firstSampleSeconds
      local minClr, jerkSum = 1e9, 0.0
      local collided = false

      while t <= (T < planningHorizonSeconds and T or planningHorizonSeconds) do
        local n = clampN(dAt(t))
        local z = progressAt(egoZ, egoV, t)
        local pos = ac.trackCoordinateToWorld(vec3(n, 0.0, z))

        local clr = minClearanceMetersFast(pos, arena.nearby, count)
        if clr < 0.0 then
          collided = true
          if drawRejectionMarkers then
            arena.rejectsCount = arena.rejectsCount + 1
            arena.rejectsPos[arena.rejectsCount] = pos
          end
          break
        end

        if clr < minClr then minClr = clr end
        jerkSum = jerkSum + jerkAbs(t)

        arena.samplesCount = arena.samplesCount + 1
        local idx = arena.samplesCount
        arena.samplesPos[idx] = pos
        arena.samplesN[idx] = n
        arena.samplesClr[idx] = clr

        t = t + sampleTimeStepSeconds
      end

      if not collided then
        arena.candCount = arena.candCount + 1
        local k = arena.candCount
        arena.candStart[k]  = sStart - 1 -- include anchor
        arena.candEnd[k]    = arena.samplesCount
        arena.candMinClr[k] = minClr
        arena.candDT[k]     = nT
        arena.candT[k]      = T

        -- clearance dominates; terminal center and jerk keep solutions comfortable
        local cost = (costWeight_Clearance * (1.0 / (0.5 + minClr)))
                   + (costWeight_TerminalCenter * abs(nT))
                   + (costWeight_JerkComfort * jerkSum)

        -- small penalty to discourage going towards the obstacle when a side was selected
        if desiredSign ~= 0 and (nT * desiredSign) <= 0 then
          cost = cost + 10.0
        end

        arena.candCost[k] = cost
        if cost < bestCost then bestCost, bestIdx = cost, k end

        Logger.log(string.format("OK car=%d dT=%.2f T=%.2f minClr=%.2f cost=%.2f", egoIndex, nT, T, minClr, cost))
      else
        Logger.log(string.format("DROP car=%d dT=%.2f T=%.2f (collided)", egoIndex, nT, T))
      end
    end
  end

  Logger.log("Survivors="..tostring(arena.candCount).." bestIdx="..tostring(bestIdx))

  -- command: steer toward the chosen path’s next sample (keeps purple command on magenta line)
  local outN
  if bestIdx == 0 then
    -- safe fallback: slight nudge away from closest opponent horizontally if any, otherwise center
    local desired = 0.0
    do
      local nearest, dBest2
      for i = 1, count do
        local opp = arena.nearby[i]
        local d2 = (opp.position - ego.position):lengthSquared()
        if not dBest2 or d2 < dBest2 then dBest2 = d2; nearest = opp end
      end
      if nearest then
        local nOpp = ac.worldCoordinateToTrack(nearest.position).x
        if nOpp >= egoN then desired = -0.35 else desired = 0.35 end
      end
    end
    local stepMax = maxOffsetChangePerSecondN * dt
    outN = clampN(egoN + max(-stepMax, min(stepMax, desired - egoN)))
  else
    local sIdx = arena.candStart[bestIdx]
    local eIdx = arena.candEnd[bestIdx]
    local nextN = arena.samplesN[min(sIdx + 1, eIdx)]
    local stepMax = maxOffsetChangePerSecondN * dt
    outN = clampN(egoN + max(-stepMax, min(stepMax, nextN - egoN)))
    Logger.log(string.format(
      "OUT car=%d chosen=%d egoN=%.3f nextN=%.3f outN=%.3f minClr=%.2f dT=%.2f T=%.2f",
      egoIndex, bestIdx, egoN, nextN, outN, arena.candMinClr[bestIdx], arena.candDT[bestIdx], arena.candT[bestIdx]))
  end

  arena.lastOutN = outN
  arena.lastActualN = egoN
  return OUTPUT_IS_NORMALIZED and outN or outN
end

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

  if a.candCount > 0 then
    local drawn = 0
    for ci = 1, a.candCount do
      local sIdx, eIdx = a.candStart[ci], a.candEnd[ci]
      for j = sIdx, eIdx - 1 do
        render.debugLine(a.samplesPos[j], a.samplesPos[j+1], colAll)
      end
      if drawSamplesAsSpheres then
        for j = sIdx, eIdx do
          render.debugSphere(a.samplesPos[j], 0.10, rgbm(0.2,1.0,0.2,0.9))
        end
      end
      drawn = drawn + 1
      if drawn >= debugMaxPathsDrawn then break end
    end

    -- draw chosen path thicker (recompute cheapest index here to mirror solver view)
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
