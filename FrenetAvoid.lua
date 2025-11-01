-- FrenetAvoid.lua — multi-car safe, data-oriented, normalized output [-1..+1]
-- Quintic lateral planning in Frenet space (Werling-style), optimized for running on many cars.
-- Per-car scratch arenas (SoA), zero allocations in hot path, explicit indices, heavy debug options.

local FrenetAvoid = {}

---------------------------------------------------------------------------------------------------
-- Tunables
---------------------------------------------------------------------------------------------------
local planningHorizonSeconds     = 1.60
local sampleTimeStepSeconds      = 0.08
local candidateEndTimesSeconds   = { 0.8, 1.2, 1.6 }
local candidateTerminalOffsetsN  = { -0.9,-0.7,-0.5,-0.3, 0.0, 0.3, 0.5, 0.7, 0.9 }

-- Wrap-aware progress window for opponent collection (0..1 along lap)
local longitudinalWindowAheadZ   = 0.020
local longitudinalWindowBehindZ  = 0.006

-- Begin drawing essentially at the bumper
local firstSampleSeconds         = 0.03
local startMetersAhead           = 0.0

-- Speed-aware forward sampling (keeps spacing sensible across speeds)
local useSpeedAwareLookahead     = true
local minAheadMetersAtLowSpeed   = 6.0
local maxAheadMetersAtHighSpeed  = 45.0
local nominalTrackLengthMeters   = 20000.0 -- fallback conversion meters->Δz if you don’t have real length

-- Footprints
local opponentRadiusMeters       = 1.35
local egoRadiusMeters            = 1.35

-- Lateral bounds / smoothing
local maxAbsOffsetNormalized     = 0.95
local maxOffsetChangePerSecondN  = 2.2

-- Costs
local costWeight_Clearance       = 3.0
-- FrenetAvoid.lua — multi-car safe, TTC-aware, data-oriented, normalized output [-1..+1]
-- Quintic lateral planning in Frenet space with early planning + emergency densification.
-- Based on standard Frenet sampling (Werling et al., ICRA 2010) and common FOT implementations.
-- This version removes all `if Logger` guards (Logger is assumed to exist).

local FrenetAvoid = {}

---------------------------------------------------------------------------------------------------
-- Tunables (you can tweak at runtime if you expose them in your settings UI)
---------------------------------------------------------------------------------------------------

-- Base horizon and candidate grid (expanded dynamically with TTC logic below)
local planningHorizonSeconds       = 1.60
local sampleTimeStepSeconds        = 0.08
local candidateEndTimesSecondsBase = { 0.8, 1.2, 1.6 }
local candidateTerminalOffsetsNBase= { -0.9,-0.7,-0.5,-0.3, 0.0, 0.3, 0.5, 0.7, 0.9 }

-- TTC-aware early planning: if TTC is below this, we expand candidate space & lookahead
local ttcEarlyPlanStart_s          = 3.0     -- begin widening search
local ttcEmergency_s               = 1.6     -- emergency densification threshold

-- Forward window for opponent prefilter (in spline progress 0..1); grows with TTC pressure
local longitudinalWindowAheadZ     = 0.020
local longitudinalWindowBehindZ    = 0.006
local extraAheadZ_whenEarly        = 0.020   -- add when TTC < ttcEarlyPlanStart_s

-- Sampling start/spacing
local firstSampleSeconds           = 0.03    -- start near the bumper
local startMetersAhead             = 0.0
local useSpeedAwareLookahead       = true
local minAheadMetersAtLowSpeed     = 6.0
local maxAheadMetersAtHighSpeed    = 45.0
local nominalTrackLengthMeters     = 20000.0 -- used only for meters→Δz fallback

-- Opponent/ego footprints (simple and fast)
local opponentRadiusMeters         = 1.35
local egoRadiusMeters              = 1.35

-- Lateral bounds & slew-rate
local maxAbsOffsetNormalized       = 0.95
local maxOffsetChangePerSecondN    = 2.4

-- Cost weights
local costWeight_Clearance         = 3.0
local costWeight_TerminalCenter    = 0.7
local costWeight_JerkComfort       = 0.22

-- Output is normalized for physics.setAISplineOffset(idx, n, true)
local OUTPUT_IS_NORMALIZED         = true

-- Emergency densification parameters (when space is tight)
local minClrTight_m                = 1.2     -- if min clearance < this on early samples, densify
local densifyOffsetsExtra          = { -1.0, -0.8, -0.6, 0.6, 0.8, 1.0 }
local densifyEndTimesExtra         = { 0.6, 1.0 }

-- Fallback bias if starved: steer away from the nearest opponent laterally
local fallbackAvoidBiasScaleN      = 0.25    -- add this * sign(dirToNearestOpp)

-- Debug drawing
local debugMaxPathsDrawn           = 24
local drawSamplesAsSpheres         = true
local drawOpponentDiscs            = true
local drawRejectionMarkers         = true
local drawEgoFootprint             = true
local drawAnchorLink               = true
local drawReturnedOffsetPole       = true

-- Colors
local colAll    = rgbm(0.3, 0.9, 0.3, 0.15)
local colChosen = rgbm(1.0, 0.2, 0.9, 1.0)
local colPole   = rgbm(0.2, 1.0, 1.0, 0.9)

---------------------------------------------------------------------------------------------------
-- Per-car scratch (SoA) — zero-GC hot path
---------------------------------------------------------------------------------------------------

---@class CarArena
---@field samplesPos table     -- vec3[]
---@field samplesN   table     -- number[]
---@field samplesZ   table     -- number[]
---@field samplesClr table     -- number[]
---@field samplesCount integer
---@field candStart  table     -- number[]
---@field candEnd    table     -- number[]
---@field candCost   table     -- number[]
---@field candMinClr table     -- number[]
---@field candDT     table     -- number[]
---@field candT      table     -- number[]
---@field candCount  integer
---@field rejectsPos table     -- vec3[]
---@field rejectsCount integer
---@field nearbyCars table     -- ac.StateCar[]
---@field nearbyCount integer
---@field lastOutN   number

local __car = {}  -- [carIndex] = CarArena

---@param i integer
---@return CarArena
local function arenaGet(i)
  local a = __car[i]
  if a then return a end
  a = {
    samplesPos={}, samplesN={}, samplesZ={}, samplesClr={}, samplesCount=0,
    candStart={}, candEnd={}, candCost={}, candMinClr={}, candDT={}, candT={}, candCount=0,
    rejectsPos={}, rejectsCount=0,
    nearbyCars={}, nearbyCount=0,
    lastOutN=0.0
  }
  __car[i] = a
  return a
end

---@param a CarArena
local function arenaReset(a)
  a.samplesCount = 0
  a.candCount    = 0
  a.rejectsCount = 0
  a.nearbyCount  = 0
end

---------------------------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------------------------

---@param z number @wrap progress to [0,1)
---@return number
local function wrap01(z) z = z % 1.0; return (z < 0) and (z + 1.0) or z end

---@param n number
---@return number
local function clampN(n) return math.max(-maxAbsOffsetNormalized, math.min(maxAbsOffsetNormalized, n)) end

---@param offsetN number @normalized [-1..1]
---@param progressZ number @track progress
---@return number @meters lateral from center (debug only)
local function offsetNormToMeters(offsetN, progressZ)
  local sides = ac.getTrackAISplineSides(progressZ) -- vec2 left/right in meters
  return (offsetN < 0) and (offsetN * sides.x) or (offsetN * sides.y)
end

-- Quintic lateral: d(t) from (d0, v0) to dT in T seconds; end with v=a=0
---@param d0 number @start lateral (normalized)
---@param dDot0 number @start lateral velocity (normalized/s)
---@param dT number @terminal lateral (normalized)
---@param T number  @duration
---@return fun(t:number):number
---@return fun(t:number):number
local function makeLateralQuintic(d0, dDot0, dT, T)
  local a0, a1, a2 = d0, dDot0, 0.0
  local T2, T3, T4, T5 = T*T, T*T*T, T*T*T*T, T*T*T*T*T
  local C0 = dT - (a0 + a1*T + a2*T2)
  local a3 = (10*C0/T3) - (4*a1/T2)
  local a4 = (-15*C0/T4) + (7*a1/T3)
  local a5 = (  6*C0/T5) - (3*a1/T4)
  local function dAt(t)
    local t2,t3,t4,t5=t*t,t*t*t,t*t*t*t,t*t*t*t*t
    return a0 + a1*t + a2*t2 + a3*t3 + a4*t4 + a5*t5
  end
  local function jerkMag(t) return math.abs(6*a3 + 24*a4*t + 60*a5*t*t) end
  return dAt, jerkMag
end

-- Minimum disk clearance against opponents
---@param worldPos vec3
---@param opponents table
---@param egoIndex integer
---@param count integer
---@return number
local function minClearanceMeters(worldPos, opponents, egoIndex, count)
  local best = 1e9
  for i = 1, count do
    local opp = opponents[i]
    if opp and opp.index ~= egoIndex then
      local d = (opp.position - worldPos):length()
      local clr = d - (opponentRadiusMeters + egoRadiusMeters)
      if clr < best then best = clr end
    end
  end
  return best
end

-- Collect nearby opponents (wrap-aware), optionally expanded if early/TTC
---@param egoZ number
---@param allCars table
---@param arena CarArena
---@param egoIndex integer
---@param extraAheadZ number
local function collectNearbyOpponents(egoZ, allCars, arena, egoIndex, extraAheadZ)
  local n, out = 0, arena.nearbyCars
  local aheadZ = longitudinalWindowAheadZ + (extraAheadZ or 0.0)
  for i = 1, #allCars do
    local c = allCars[i]
    if c and c.index ~= egoIndex then
      local tc = ac.worldCoordinateToTrack(c.position)
      if tc then
        local ahead  = wrap01(tc.z - egoZ)
        local behind = wrap01(egoZ - tc.z)
        if ahead <= aheadZ or behind <= longitudinalWindowBehindZ then
          n = n + 1; out[n] = c
        end
      end
    end
  end
  arena.nearbyCount = n
end

-- Progress mapping; when speed-aware, meters→Δz
---@param egoZ number
---@param egoSpeedMps number
---@param t number
---@return number
local function progressAtTime(egoZ, egoSpeedMps, t)
  if not useSpeedAwareLookahead then
    local frac = t / planningHorizonSeconds
    return wrap01(egoZ + frac * longitudinalWindowAheadZ)
  end
  local aheadMeters = math.max(minAheadMetersAtLowSpeed,
                        math.min(maxAheadMetersAtHighSpeed, egoSpeedMps * planningHorizonSeconds))
  local meters = (t / planningHorizonSeconds) * aheadMeters + startMetersAhead
  local dz = meters / nominalTrackLengthMeters
  return wrap01(egoZ + dz)
end

---@param c number
---@return rgbm
local function clrToColor(c)
  if c <= 0.5 then return rgbm(1.0, 0.1, 0.1, 0.9) end  -- red
  if c <= 2.0 then return rgbm(1.0, 0.8, 0.1, 0.9) end  -- yellow
  return rgbm(0.2, 1.0, 0.2, 0.9)                       -- green
end

-- Estimate TTC to the closest front opponent on the same Z-line (rough but cheap).
-- Positive relV means ego is faster and closing.
---@param ego ac.StateCar
---@param arena CarArena
---@param egoZ number
---@return number|nil
---@return ac.StateCar|nil
local function estimateTTC_s(ego, arena, egoZ)
  local bestT, bestCar = nil, nil
  local egoV = ego.speedKmh / 3.6
  for i = 1, arena.nearbyCount do
    local opp = arena.nearbyCars[i]
    if opp then
      local tc = ac.worldCoordinateToTrack(opp.position)
      if tc then
        local ahead = wrap01(tc.z - egoZ)
        if ahead <= (longitudinalWindowAheadZ + extraAheadZ_whenEarly + 0.02) then
          local relV = egoV - (opp.speedKmh/3.6)
          if relV > 0.2 then
            local d = (opp.position - ego.position):length()
            local t = d / math.max(0.1, relV)
            if (not bestT) or t < bestT then bestT, bestCar = t, opp end
          end
        end
      end
    end
  end
  return bestT, bestCar
end

---------------------------------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------------------------------

---Compute normalized lateral offset for a single car this frame.
---@param allCars table<integer, ac.StateCar>
---@param carIndex integer
---@param dt number
---@return number @normalized [-1..+1]
function FrenetAvoid.computeOffsetForCar(allCars, carIndex, dt)
  local ego = ac.getCar(carIndex)
  if not ego or not ac.hasTrackSpline() then
    Logger.warn("FrenetAvoid: no ego or no AI spline for car "..tostring(carIndex))
    return 0.0
  end

  local arena = arenaGet(carIndex)
  arenaReset(arena)

  -- Ego in track coords: x=normalized lateral, z=progress [0..1)
  local tc = ac.worldCoordinateToTrack(ego.position)
  local egoZ = wrap01(tc.z)
  local egoN = clampN(tc.x)
  local vLat0 = 0.0
  local egoSpeedMps = ego.speedKmh / 3.6

  -- TTC-aware opponent collection (expand ahead window if needed)
  collectNearbyOpponents(egoZ, allCars, arena, carIndex, 0.0)
  local ttc, ttcCar = estimateTTC_s(ego, arena, egoZ)
  local extraAheadZ = (ttc and ttc < ttcEarlyPlanStart_s) and extraAheadZ_whenEarly or 0.0
  if extraAheadZ > 0.0 then
    collectNearbyOpponents(egoZ, allCars, arena, carIndex, extraAheadZ)
  end

  Logger.log(string.format("FrenetAvoid car=%d z=%.4f xN=%.3f v=%.1f m/s TTC=%.2f",
    carIndex, egoZ, egoN, egoSpeedMps, ttc or -1))

  -- Build candidate sets (base + TTC-driven extras)
  local candidateEndTimesSeconds = candidateEndTimesSecondsBase
  local candidateTerminalOffsetsN = candidateTerminalOffsetsNBase
  local stepSeconds = sampleTimeStepSeconds

  if ttc and ttc < ttcEarlyPlanStart_s then
    -- widen horizon granularity a bit (denser sampling & more offsets)
    stepSeconds = math.max(0.05, sampleTimeStepSeconds * 0.75)
    candidateEndTimesSeconds = { 0.6, 0.9, 1.2, 1.6 }
    candidateTerminalOffsetsN = { -1.0,-0.9,-0.7,-0.5,-0.3, 0.0, 0.3, 0.5, 0.7, 0.9, 1.0 }
  end

  -- SoA aliases
  local samplesPos, samplesN, samplesZ, samplesClr =
    arena.samplesPos, arena.samplesN, arena.samplesZ, arena.samplesClr
  local candStart, candEnd, candCost, candMinClr, candDT, candT =
    arena.candStart, arena.candEnd, arena.candCost, arena.candMinClr, arena.candDT, arena.candT

  local bestCost, bestIdx = 1e9, 0
  local earlyMinClr = 1e9       -- track tightness across first candidates

  -- Generate base grid
  for ci = 1, #candidateTerminalOffsetsN do
    local nT = clampN(candidateTerminalOffsetsN[ci])
    for ti = 1, #candidateEndTimesSeconds do
      local T = candidateEndTimesSeconds[ti]
      local dAt, jerkAbs = makeLateralQuintic(egoN, vLat0, nT, T)

      local startIdx = arena.samplesCount + 1

      -- Anchor the first sample at ego pose
      arena.samplesCount = arena.samplesCount + 1
      local k = arena.samplesCount
      samplesZ[k] = egoZ
      samplesN[k] = egoN
      samplesPos[k] = ac.trackCoordinateToWorld(vec3(egoN, 0.0, egoZ))
      samplesClr[k] = minClearanceMeters(samplesPos[k], arena.nearbyCars, carIndex, arena.nearbyCount)
      if samplesClr[k] < earlyMinClr then earlyMinClr = samplesClr[k] end

      local t = firstSampleSeconds
      local minClr = 1e9
      local jerkSum = 0.0
      local collided = false

      while t <= math.min(T, planningHorizonSeconds) do
        local n = clampN(dAt(t))
        local z = progressAtTime(egoZ, egoSpeedMps, t)
        local world = ac.trackCoordinateToWorld(vec3(n, 0.0, z))

        local clr = minClearanceMeters(world, arena.nearbyCars, carIndex, arena.nearbyCount)
        if clr < 0.0 then
          collided = true
          if drawRejectionMarkers then
            local r = arena.rejectsCount + 1
            arena.rejectsPos[r] = world
            arena.rejectsCount = r
          end
          Logger.log(string.format("REJECT car=%d dT=%.2f T=%.2f t=%.2f clr=%.2f", carIndex, nT, T, t, clr))
          break
        end
        if clr < minClr then minClr = clr end
        jerkSum = jerkSum + jerkAbs(t)

        arena.samplesCount = arena.samplesCount + 1
        local idx = arena.samplesCount
        samplesZ[idx] = z
        samplesN[idx] = n
        samplesPos[idx] = world
        samplesClr[idx] = clr

        t = t + stepSeconds
      end

      if not collided and (arena.samplesCount - startIdx + 1) >= 2 then
        local count = arena.samplesCount - startIdx + 1
        local cost = (costWeight_Clearance * (1.0 / (0.5 + minClr)))
                   + (costWeight_TerminalCenter * math.abs(nT))
                   + (costWeight_JerkComfort * jerkSum)

        local c = arena.candCount + 1
        candStart[c]  = startIdx
        candEnd[c]    = startIdx + count - 1
        candCost[c]   = cost
        candMinClr[c] = minClr
        candDT[c]     = nT
        candT[c]      = T
        arena.candCount = c

        Logger.log(string.format("OK car=%d dT=%.2f T=%.2f samples=%d minClr=%.2f cost=%.3f", carIndex, nT, T, count, minClr, cost))
        if cost < bestCost then bestCost, bestIdx = cost, c end
      else
        Logger.log(string.format("DROP car=%d dT=%.2f T=%.2f collided=%s", carIndex, nT, T, tostring(collided)))
      end
    end
  end

  -- Emergency densification if very tight early space or TTC is critical
  if (arena.candCount == 0) or (earlyMinClr < minClrTight_m) or (ttc and ttc < ttcEmergency_s) then
    Logger.log(string.format("DENSIFY car=%d reason=%s earlyMinClr=%.2f TTC=%.2f",
      carIndex,
      (arena.candCount==0) and "noCandidates" or (earlyMinClr<minClrTight_m) and "tightClr" or "lowTTC",
      earlyMinClr, ttc or -1))

    for ci = 1, #densifyOffsetsExtra do
      local nT = clampN(densifyOffsetsExtra[ci])
      for ti = 1, #densifyEndTimesExtra do
        local T = densifyEndTimesExtra[ti]
        local dAt, jerkAbs = makeLateralQuintic(egoN, 0.0, nT, T)
        local startIdx = arena.samplesCount + 1

        arena.samplesCount = arena.samplesCount + 1
        local k = arena.samplesCount
        samplesZ[k] = egoZ
        samplesN[k] = egoN
        samplesPos[k] = ac.trackCoordinateToWorld(vec3(egoN, 0.0, egoZ))
        samplesClr[k] = minClearanceMeters(samplesPos[k], arena.nearbyCars, carIndex, arena.nearbyCount)

        local t = firstSampleSeconds
        local minClr = 1e9
        local jerkSum = 0.0
        local collided = false
        while t <= math.min(T, planningHorizonSeconds) do
          local n = clampN(dAt(t))
          local z = progressAtTime(egoZ, egoSpeedMps, t)
          local world = ac.trackCoordinateToWorld(vec3(n, 0.0, z))
          local clr = minClearanceMeters(world, arena.nearbyCars, carIndex, arena.nearbyCount)
          if clr < 0.0 then collided = true break end
          if clr < minClr then minClr = clr end
          jerkSum = jerkSum + jerkAbs(t)

          arena.samplesCount = arena.samplesCount + 1
          local idx = arena.samplesCount
          samplesZ[idx] = z; samplesN[idx] = n; samplesPos[idx] = world; samplesClr[idx] = clr
          t = t + math.max(0.04, stepSeconds * 0.7)
        end

        if not collided and (arena.samplesCount - startIdx + 1) >= 2 then
          local count = arena.samplesCount - startIdx + 1
          local cost = (costWeight_Clearance * (1.0 / (0.5 + minClr)))
                     + (costWeight_TerminalCenter * math.abs(nT))
                     + (costWeight_JerkComfort * jerkSum)
          local c = arena.candCount + 1
          candStart[c], candEnd[c], candCost[c], candMinClr[c], candDT[c], candT[c] =
            startIdx, startIdx + count - 1, cost, minClr, nT, T
          arena.candCount = c
          if cost < bestCost then bestCost, bestIdx = cost, c end
        end
      end
    end
  end

  -- No survivors? Favor center but add bias away from nearest opponent
  if bestIdx == 0 then
    Logger.warn("FrenetAvoid: no survivors; applying safe fallback")
    local desiredN = 0.0

    -- bias away from nearest opponent laterally
    local nearest, nearestD, nearestSign = nil, 1e9, 0.0
    for i = 1, arena.nearbyCount do
      local opp = arena.nearbyCars[i]
      if opp then
        local d = (opp.position - ego.position):length()
        if d < nearestD then
          nearestD = d; nearest = opp
        end
      end
    end
    if nearest then
      -- If opponent’s track x is positive (right), push left (negative), and vice-versa
      local nOpp = ac.worldCoordinateToTrack(nearest.position).x
      nearestSign = (nOpp >= 0.0) and -1.0 or 1.0
      desiredN = clampN(desiredN + fallbackAvoidBiasScaleN * nearestSign)
    end

    local stepMax = maxOffsetChangePerSecondN * dt
    local outN = clampN(egoN + math.max(-stepMax, math.min(stepMax, desiredN - egoN)))
    arena.lastOutN = outN
    Logger.log(string.format("OUT (fallback) car=%d outN=%.3f egoN=%.3f desiredN=%.3f", carIndex, outN, egoN, desiredN))
    return outN
  end

  -- Follow best path: head toward its second sample
  local sIdx = candStart[bestIdx]
  local eIdx = candEnd[bestIdx]
  local nextN = arena.samplesN[ math.min(sIdx + 1, eIdx) ]
  local stepMax = maxOffsetChangePerSecondN * dt
  local outN = clampN(egoN + math.max(-stepMax, math.min(stepMax, nextN - egoN)))
  arena.lastOutN = outN

  Logger.log(string.format(
    "OUT car=%d chosen=%d egoN=%.3f nextN=%.3f outN=%.3f minClr=%.2f dT=%.2f T=%.2f",
    carIndex, bestIdx, egoN, nextN, outN, candMinClr[bestIdx], candDT[bestIdx], candT[bestIdx]))

  return outN
end

---Batch: compute offsets for many cars. Writes outOffsets[carIndex+1] = normalized.
---@param allCars table<integer, ac.StateCar>
---@param dt number
---@param outOffsets number[]
---@return number[]
function FrenetAvoid.computeOffsetsForAll(allCars, dt, outOffsets)
  for i = 1, #allCars do
    local c = allCars[i]
    if c then
      outOffsets[c.index + 1] = FrenetAvoid.computeOffsetForCar(allCars, c.index, dt)
    end
  end
  return outOffsets
end

---------------------------------------------------------------------------------------------------
-- Debug draw for one car (uses that car’s arena)
---------------------------------------------------------------------------------------------------
---@param carIndex integer
function FrenetAvoid.debugDraw(carIndex)
  local a = __car[carIndex]
  if not a then return end

  if drawOpponentDiscs then
    for i = 1, a.nearbyCount do
      local c = a.nearbyCars[i]
      if c then render.debugSphere(c.position, opponentRadiusMeters, rgbm(1,0,0,0.25)) end
    end
  end
  if drawEgoFootprint then
    local ego = ac.getCar(carIndex)
    if ego then render.debugSphere(ego.position, egoRadiusMeters, rgbm(0,1,0,0.25)) end
  end

  if drawRejectionMarkers then
    for i = 1, a.rejectsCount do
      local p = a.rejectsPos[i]
      if p then
        local d = 0.6
        render.debugLine(p + vec3(-d,0,-d), p + vec3(d,0,d), rgbm(1,0,0,1))
        render.debugLine(p + vec3(-d,0, d), p + vec3(d,0,-d), rgbm(1,0,0,1))
      end
    end
  end

  if a.candCount == 0 then
    Logger.log("debugDraw: no candidates for car "..tostring(carIndex))
    return
  end

  local drawn = 0
  for ci = 1, a.candCount do
    local sIdx, eIdx = a.candStart[ci], a.candEnd[ci]
    for j = sIdx, eIdx - 1 do
      render.debugLine(a.samplesPos[j], a.samplesPos[j+1], colAll)
    end
    if drawSamplesAsSpheres then
      for j = sIdx, eIdx do
        render.debugSphere(a.samplesPos[j], 0.12, clrToColor(a.samplesClr[j]))
      end
    end
    drawn = drawn + 1; if drawn >= debugMaxPathsDrawn then break end
  end

  -- Chosen
  local bestIdx, bestCost = 1, a.candCost[1]
  for ci = 2, a.candCount do
    local c = a.candCost[ci]; if c < bestCost then bestIdx, bestCost = ci, c end
  end
  local sIdx, eIdx = a.candStart[bestIdx], a.candEnd[bestIdx]
  for j = sIdx, eIdx - 1 do
    render.debugLine(a.samplesPos[j], a.samplesPos[j+1], colChosen)
    render.debugLine(a.samplesPos[j] + vec3(0,0.01,0), a.samplesPos[j+1] + vec3(0,0.01,0), colChosen)
    render.debugLine(a.samplesPos[j] + vec3(0,0.02,0), a.samplesPos[j+1] + vec3(0,0.02,0), colChosen)
  end
  local head = a.samplesPos[math.min(sIdx + 2, eIdx)]
  if head then render.debugSphere(head, 0.20, colChosen) end
  local mid = a.samplesPos[ math.floor((sIdx + eIdx) * 0.5) ]
  if mid then
    local txt = string.format("CHOSEN car=%d idx=%d  cost=%.2f  minClr=%.2f m  dT=%.2f  T=%.2fs",
      carIndex, bestIdx, a.candCost[bestIdx], a.candMinClr[bestIdx], a.candDT[bestIdx], a.candT[bestIdx])
    render.debugText(mid + vec3(0,0.4,0), txt)
  end

  if drawAnchorLink then
    local ego = ac.getCar(carIndex)
    if ego and sIdx + 1 <= eIdx then
      render.debugLine(ego.position, a.samplesPos[sIdx + 1], rgbm(1,1,1,0.9))
    end
  end

  if drawReturnedOffsetPole then
    local ego = ac.getCar(carIndex)
    if ego then
      local tc = ac.worldCoordinateToTrack(ego.position)
      local poleWorld = ac.trackCoordinateToWorld(vec3(a.lastOutN, 0.0, tc.z))
      render.debugLine(poleWorld + vec3(0,0.00,0), poleWorld + vec3(0,1.2,0), colPole)
      render.debugSphere(poleWorld + vec3(0,1.2,0), 0.10, colPole)
      render.debugText(poleWorld + vec3(0,1.35,0), string.format("outN=%.3f  egoN=%.3f", a.lastOutN, tc.x))
    end
  end
end

return FrenetAvoid
