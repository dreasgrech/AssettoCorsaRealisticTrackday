-- FrenetAvoid.lua — multi-car safe, data-oriented, normalized output [-1..+1]
-- Quintic lateral planning in Frenet space (Werling-style), optimized for running on many cars.
-- Per-car scratch arenas (SoA), zero allocations in hot path, explicit indices, heavy debug options.

local FrenetAvoid = {}

---------------------------------------------------------------------------------------------------
-- Tunables (same semantics as before; some widened defaults for robustness)
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
local costWeight_TerminalCenter  = 0.8
local costWeight_JerkComfort     = 0.25

-- We return normalized because physics.setAISplineOffset expects [-1..+1]
local OUTPUT_IS_NORMALIZED       = true

-- Debug drawing
local debugMaxPathsDrawn         = 24
local drawSamplesAsSpheres       = true
local drawOpponentDiscs          = true
local drawRejectionMarkers       = true
local drawEgoFootprint           = true
local drawAnchorLink             = true

-- Visual colors
local colAll    = rgbm(0.3, 0.9, 0.3, 0.15)   -- pale for non-chosen
local colChosen = rgbm(1.0, 0.2, 0.9, 1.0)    -- magenta, thick

---------------------------------------------------------------------------------------------------
-- Data-Oriented Per-Car Scratch Arenas
---------------------------------------------------------------------------------------------------
-- Each car gets its own scratch arena to avoid contention and GC:
--   samples: SoA arrays (positions, normalized offsets, progress, clearance)
--   cand:    descriptors (startIdx, endIdx, cost, minClr, dT, T)
--   rejects: list of world positions where a candidate collided
--   nearby:  array of opponent references

---@class CarArena
---@field samplesPos table     -- [1..N] of vec3
---@field samplesN   table     -- [1..N] of number
---@field samplesZ   table     -- [1..N] of number
---@field samplesClr table     -- [1..N] of number
---@field samplesCount integer -- current size
---@field candStart  table     -- [1..C] start sample index (into samples arrays)
---@field candEnd    table     -- [1..C] end sample index
---@field candCost   table     -- [1..C] cost
---@field candMinClr table     -- [1..C] min clearance
---@field candDT     table     -- [1..C] terminal lateral offset (normalized)
---@field candT      table     -- [1..C] duration seconds
---@field candCount  integer
---@field rejectsPos table     -- [1..R] of vec3
---@field rejectsCount integer
---@field nearbyCars table     -- [1..K] list of opponent car states
---@field nearbyCount integer
---@field lastOutN   number    -- last output (normalized)

local __car = {}  -- [carIndex] = CarArena

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

local function arenaReset(a)
  a.samplesCount = 0
  a.candCount    = 0
  a.rejectsCount = 0
  a.nearbyCount  = 0
end

---------------------------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------------------------
local function wrap01(z) z = z % 1.0; return (z < 0) and (z + 1.0) or z end
local function clampN(n) return math.max(-maxAbsOffsetNormalized, math.min(maxAbsOffsetNormalized, n)) end

local function offsetNormToMeters(offsetN, progressZ)
  -- Converts normalized offset to meters with CSP’s API. We still return normalized to physics.
  local sides = ac.getTrackAISplineSides(progressZ) -- vec2 left/right meters
  return (offsetN < 0) and (offsetN * sides.x) or (offsetN * sides.y)
end

-- Quintic lateral profile d(t) from d0 (with dDot0) to dT in time T (end with v=a=0)
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

-- Clearance to opponent disks
local function minClearanceMeters(worldPos, opponents, egoIndex, count)
  local best = 1e9
  for i = 1, count do
    local opp = opponents[i]
    -- skip ego if it ever sneaks in
    if opp and opp.index ~= egoIndex then
      local d = (opp.position - worldPos):length()
      local clr = d - (opponentRadiusMeters + egoRadiusMeters)
      if clr < best then best = clr end
    end
  end
  return best
end

-- Opponents near us (wrap-aware progress window)
local function collectNearbyOpponents(egoZ, allCars, arena, egoIndex)
  local n, out = 0, arena.nearbyCars
  for i = 1, #allCars do
    local c = allCars[i]
    if c and c.index ~= egoIndex then
      local tc = ac.worldCoordinateToTrack(c.position)
      if tc then
        local ahead  = wrap01(tc.z - egoZ)
        local behind = wrap01(egoZ - tc.z)
        if ahead <= longitudinalWindowAheadZ or behind <= longitudinalWindowBehindZ then
          n = n + 1; out[n] = c
        end
      end
    end
  end
  arena.nearbyCount = n
end

-- Map time→progress Z, optionally speed-aware (meters→Δz). World positions are used for collision anyway.
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

local function clrToColor(c)
  if c <= 0.5 then return rgbm(1.0, 0.1, 0.1, 0.9) end  -- red
  if c <= 2.0 then return rgbm(1.0, 0.8, 0.1, 0.9) end  -- yellow
  return rgbm(0.2, 1.0, 0.2, 0.9)                       -- green
end

---------------------------------------------------------------------------------------------------
-- Public: compute offset for a specific car (normalized) — multi-car safe
---------------------------------------------------------------------------------------------------
function FrenetAvoid.computeOffsetForCar(allCars, carIndex, dt)
  local ego = ac.getCar(carIndex)
  if not ego or not ac.hasTrackSpline() then
    if Logger then Logger.warn("FrenetAvoid: no ego or no AI spline for car "..tostring(carIndex)) end
    return 0.0
  end

  local arena = arenaGet(carIndex)
  arenaReset(arena)

  -- Ego Frenet-ish state
  local tc = ac.worldCoordinateToTrack(ego.position)  -- x: normalized lateral, z: progress
  local egoZ = wrap01(tc.z)
  local egoN = clampN(tc.x)
  local vLat0 = 0.0
  local egoSpeedMps = ego.speedKmh and (ego.speedKmh / 3.6) or 0.0

  if Logger then
    Logger.log(string.format("FrenetAvoid car=%d z=%.4f xN=%.3f dt=%.3f v=%.1f m/s",
      carIndex, egoZ, egoN, dt or -1, egoSpeedMps))
  end

  -- Opponents
  collectNearbyOpponents(egoZ, allCars, arena, carIndex)
  if Logger then Logger.log("Nearby opponents: "..tostring(arena.nearbyCount).." for car "..tostring(carIndex)) end

  local bestCost, bestIdx = 1e9, 0

  -- Candidate generation
  -- Keep a single SoA samples arena; each candidate stores [startIdx,endIdx]
  local samplesPos, samplesN, samplesZ, samplesClr = arena.samplesPos, arena.samplesN, arena.samplesZ, arena.samplesClr
  local candStart, candEnd, candCost, candMinClr, candDT, candT = arena.candStart, arena.candEnd, arena.candCost, arena.candMinClr, arena.candDT, arena.candT

  local baseCount = arena.samplesCount

  for ci = 1, #candidateTerminalOffsetsN do
    local nT = clampN(candidateTerminalOffsetsN[ci])
    for ti = 1, #candidateEndTimesSeconds do
      local T = candidateEndTimesSeconds[ti]
      local dAt, jerkAbs = makeLateralQuintic(egoN, vLat0, nT, T)

      local startIdx = arena.samplesCount + 1

      -- Anchor sample[1] at ego pose
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
        if clr < 0.0 then
          collided = true
          -- rejection marker
          if drawRejectionMarkers then
            local r = arena.rejectsCount + 1
            arena.rejectsPos[r] = world
            arena.rejectsCount = r
          end
          if Logger then Logger.log(string.format("REJECT car=%d dT=%.2f T=%.2f t=%.2f clr=%.2f", carIndex, nT, T, t, clr)) end
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

        t = t + sampleTimeStepSeconds
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

        if Logger then Logger.log(string.format("OK car=%d dT=%.2f T=%.2f samples=%d minClr=%.2f cost=%.3f", carIndex, nT, T, count, minClr, cost)) end
        if cost < bestCost then bestCost, bestIdx = cost, c end
      else
        -- rolled-back samples stay for drawing rejection markers only (harmless)
        if Logger then Logger.log(string.format("DROP car=%d dT=%.2f T=%.2f collided=%s", carIndex, nT, T, tostring(collided))) end
      end
    end
  end

  -- Fallback: move gently to center
  if bestIdx == 0 then
    local desiredN = 0.0
    local stepMax = maxOffsetChangePerSecondN * dt
    local outN = clampN(egoN + math.max(-stepMax, math.min(stepMax, desiredN - egoN)))
    arena.lastOutN = outN
    if Logger then Logger.log(string.format("OUT (fallback) car=%d outN=%.3f egoN=%.3f", carIndex, outN, egoN)) end
    return outN
  end

  -- Choose best and move toward its second sample (close to ego)
  local sIdx = candStart[bestIdx]
  local eIdx = candEnd[bestIdx]
  local nextN = samplesN[ math.min(sIdx + 1, eIdx) ]
  local stepMax = maxOffsetChangePerSecondN * dt
  local outN = clampN(egoN + math.max(-stepMax, math.min(stepMax, nextN - egoN)))
  arena.lastOutN = outN

  if Logger then
    Logger.log(string.format(
      "OUT car=%d chosen=%d egoN=%.3f nextN=%.3f outN=%.3f minClr=%.2f",
      carIndex, bestIdx, egoN, nextN, outN, candMinClr[bestIdx]))
  end

  return outN
end

---------------------------------------------------------------------------------------------------
-- Batch helper: compute offsets for many cars (fills outOffsets[i])
---------------------------------------------------------------------------------------------------
---comment
---@param allCars table<integer,ac.StateCar>
---@param dt number
---@param outOffsets table<integer,number>
---@return any
function FrenetAvoid.computeOffsetsForAll(allCars, dt, outOffsets)
  -- outOffsets: numeric array; on return outOffsets[i] = normalized offset for car i (alive only)
  for i = 1, #allCars do
    local c = allCars[i]
    if c then
      outOffsets[i] = FrenetAvoid.computeOffsetForCar(allCars, c.index, dt)
    end
  end
  return outOffsets
end

---------------------------------------------------------------------------------------------------
-- Debug draw for a specific car (uses that car’s arena)
---------------------------------------------------------------------------------------------------
function FrenetAvoid.debugDraw(carIndex)
  local a = __car[carIndex]
  if not a then return end

  -- Opponent / ego footprints
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

  -- Rejection X markers
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

  -- Nothing to draw?
  if a.candCount == 0 then
    if Logger then Logger.log("debugDraw: no candidates for car "..tostring(carIndex)) end
    return
  end

  -- Draw non-chosen (thin)
  local drawn = 0
  for ci = 1, a.candCount do
    -- we’ll find best separately
    local sIdx = a.candStart[ci]
    local eIdx = a.candEnd[ci]
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

  -- Find best
  local bestIdx, bestCost = 1, a.candCost[1]
  for ci = 2, a.candCount do
    local c = a.candCost[ci]
    if c < bestCost then bestIdx, bestCost = ci, c end
  end

  -- Draw chosen, thick + head marker + label + anchor line to next sample
  local sIdx = a.candStart[bestIdx]
  local eIdx = a.candEnd[bestIdx]
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
end

return FrenetAvoid
