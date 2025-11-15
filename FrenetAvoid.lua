-- FrenetAvoid.lua
-- Extremely small and readable “from-scratch” Frenet avoidance.
-- Goal for this version: prove that the car follows ONE planned path.
-- Keep public API identical:
--   FrenetAvoid.computeOffsetForCar(allCars, egoIndex, dt) -> normalized offset [-1..1]
--   FrenetAvoid.computeOffsetsForAll(allCars, dt, outOffsets) -> fills array
--   FrenetAvoid.debugDraw(carIndex) -> draws debug gizmos
--
-- Very simple planner:
--   • Detect if there is ANY car ahead within a short progress window.
--   • If yes, pick a single target lateral offset on the configured overtaking side (RIGHT by default).
--     If not, pick 0.0 (center).
--   • Build a single smooth quintic lateral trajectory from current offset → target offset (duration ~1.2 s).
--   • Each frame, command a small step toward the very next sample on that single path (slew-limited).
--   • Draw *everything* so we can verify: sampled points, planned polyline, commanded vs actual poles,
--     and detection window + opponents used for detection.
--
-- Notes:
--   • This version intentionally avoids cost functions, multiple candidates, clearance checks, TTC, etc.
--     We only want to validate the round-trip: “planned path” → “purple line” → “physics.setAISplineOffset follows it”.

local FrenetAvoid = {}

-- Toggle logs. Keep it here so we can silence them quickly.
local VERBOSE_LOG = false
local function vlog(fmt, ...)
  if VERBOSE_LOG then Logger.log(string.format(fmt, ...)) end
end

---------------------------------------------------------------------------------------------------
-- Tiny set of tunables (keep it small while we validate the loop)
---------------------------------------------------------------------------------------------------

-- How far ahead (in track progress fraction) we look for “a car ahead”.
-- 0.015 ≈ ~300 m on a 20 km track; adjust if your track length differs a lot.
local AHEAD_PROGRESS_WINDOW  = 0.015
local BEHIND_PROGRESS_WINDOW = 0.000  -- we don’t care for this simple test

-- Path generation
local SINGLE_PATH_DURATION_S   = 1.20   -- time to reach target offset
local FIRST_SAMPLE_TIME_S      = 0.05   -- first sample a bit ahead of the bumper
local SAMPLE_DT_S              = 0.10   -- sampling timestep
local MAX_ABS_OFFSET_N         = 0.95   -- never exceed AC’s safe lateral bounds

-- Output slew limiting (how fast we can slide laterally in normalized units per second)
local MAX_DELTA_PER_SECOND_N   = 2.6

-- Detection and side preference
-- Right side is +1, left side is −1.  If RaceTrackManager reports a side, we use it.
local DEFAULT_OVERTAKE_SIGN    = 1   -- +1 → RIGHT, −1 → LEFT
local TARGET_OFFSET_MAG_N      = 0.75  -- how far toward the side we try to move when avoiding

-- Minimal “speed-aware” lookahead just for drawing samples along the track
local MIN_LOOKAHEAD_M          = 10
local MAX_LOOKAHEAD_M          = 80
local NOMINAL_TRACK_LEN_M      = 20000  -- fallback to convert meters → progress fraction

-- Debug drawing toggles (kept very explicit)
local DRAW_DETECTION_WINDOW    = true
local DRAW_OPPONENT_MARKERS    = true
local DRAW_SAMPLES_AS_SPHERES  = true
local DRAW_PURPLE_PATH_THICK   = true
local DRAW_CMD_ACT_POLES       = true

-- Colors
local COL_SAMPLES  = rgbm(0.35, 1.00, 0.35, 0.95)
local COL_PATH     = rgbm(0.30, 0.90, 0.30, 0.25)
local COL_CHOSEN   = rgbm(1.00, 0.20, 0.90, 1.00)
local COL_DET_WIN  = rgbm(0.90, 0.90, 0.90, 0.35)
local COL_OPP      = rgbm(1.00, 0.20, 0.20, 0.45)
local COL_CMD      = rgbm(0.10, 1.00, 1.00, 0.95)
local COL_ACT      = rgbm(1.00, 1.00, 0.25, 0.95)

---------------------------------------------------------------------------------------------------
-- Small math helpers and conversion helpers
---------------------------------------------------------------------------------------------------

local function clampN(n)
  if n > MAX_ABS_OFFSET_N then return MAX_ABS_OFFSET_N end
  if n < -MAX_ABS_OFFSET_N then return -MAX_ABS_OFFSET_N end
  return n
end

local function wrap01(z) z = z % 1.0; if z < 0 then z = z + 1 end; return z end

-- Quintic with zero accel at start/end: x(0)=x0, x’(0)=v0, x’’(0)=0; x(T)=x1, x’(T)=0, x’’(T)=0
local function makeQuintic(x0, v0, x1, T)
  local T2, T3, T4, T5 = T*T, T*T*T, T*T*T*T, T*T*T*T*T
  local a0, a1, a2 = x0, v0, 0
  local a3 = (10*(x1 - x0) - (6*v0)*T)/T3
  local a4 = (-15*(x1 - x0) + (8*v0)*T)/T4
  local a5 = ( 6*(x1 - x0) - (3*v0)*T)/T5
  return function(t)
    if t < 0 then t = 0 elseif t > T then t = T end
    return a0 + a1*t + a2*t*t + a3*t*t*t + a4*t*t*t*t + a5*t*t*t*t*t
  end
end

local function metersToProgress(m) return (m / NOMINAL_TRACK_LEN_M) end

local function progressAtTime(egoZ, egoVelMS, t)
  -- very small speed-aware interpolation for drawing samples forward
  local horizonM = math.max(MIN_LOOKAHEAD_M, math.min(MAX_LOOKAHEAD_M, egoVelMS * SINGLE_PATH_DURATION_S))
  local distM    = (t / SINGLE_PATH_DURATION_S) * horizonM
  return wrap01(egoZ + metersToProgress(distM))
end

---------------------------------------------------------------------------------------------------
-- Per-car scratch (we keep only what we need)
---------------------------------------------------------------------------------------------------

local __perCar = {}
local function carData(i)
  local d = __perCar[i]
  if d then return d end
  d = {
    samplesWorld = {},   -- world positions of the single path
    samplesN     = {},   -- normalized lateral offsets of samples
    sampleCount  = 0,
    lastCmdN     = 0.0,  -- last commanded normalized offset
    lastActN     = 0.0,  -- last actual (for audit)
    lastZ        = 0.0,  -- last progress (for drawing poles)
    detOpponents = {},   -- list of opponents inside detection window (for drawing)
    detCount     = 0,
    reasonText   = ""    -- short explanation drawn above car
  }
  __perCar[i] = d
  return d
end

---------------------------------------------------------------------------------------------------
-- Single-path planner (this is the HEART of this simplified version)
---------------------------------------------------------------------------------------------------
---@param allCars ac.StateCar[]
---@param egoIndex integer
---@param dt number
---@return number
function FrenetAvoid.computeOffsetForCar(allCars, egoIndex, dt)
  local ego = ac.getCar(egoIndex)
  if not ego or not ac.hasTrackSpline() then return 0 end

  local d = carData(egoIndex)

  -- Ego in Frenet
  local egoTC = ac.worldCoordinateToTrack(ego.position)
  local egoZ  = wrap01(egoTC.z)
  local egoN  = clampN(egoTC.x)
  local egoV  = (ego.speedKmh or 0) / 3.6

  -- 1) Detection: is there ANY opponent ahead within the small progress window?
  --    We also cache those opponents for drawing.
  local ahead = 0
  d.detCount = 0
  local nearestAheadDz = 1e9
  for i = 1, #allCars do
    local c = allCars[i]
    if c and c.index ~= egoIndex then
      local tc = ac.worldCoordinateToTrack(c.position)
      local dzAhead = wrap01(tc.z - egoZ)
      if dzAhead <= AHEAD_PROGRESS_WINDOW then
        ahead = ahead + 1
        d.detCount = d.detCount + 1
        d.detOpponents[d.detCount] = c
        if dzAhead < nearestAheadDz then nearestAheadDz = dzAhead end
      end
    end
  end
  for i = d.detCount + 1, #d.detOpponents do d.detOpponents[i] = nil end

  -- 2) Decide target offset for the SINGLE path:
  --    if blocked ahead → move toward overtaking side; else → go to center (0).
  local sideSign = DEFAULT_OVERTAKE_SIGN
  if RaceTrackManager and RaceTrackManager.getOvertakingSide and RaceTrackManager.TrackSide then
    local side = RaceTrackManager.getOvertakingSide()
    sideSign = (side == RaceTrackManager.TrackSide.LEFT) and -1 or 1
  end

  local wantN, reason
  if ahead > 0 then
    wantN  = clampN(sideSign * TARGET_OFFSET_MAG_N)
    reason = string.format("BlockerAhead: %d car(s), dzMin=%.4f → targetN=%.2f", ahead, nearestAheadDz, wantN)
  else
    wantN  = 0.0
    reason = "ClearAhead → targetN=0.00"
  end
  d.reasonText = reason
  vlog("[FA mini] car=%d  egoN=%.3f  ahead=%d  targetN=%.3f", egoIndex, egoN, ahead, wantN)

  -- 3) Build a SINGLE quintic lateral path x(t) from egoN → wantN (duration fixed).
  --    We assume zero initial lateral velocity for simplicity.
  local xOfT = makeQuintic(egoN, 0.0, wantN, SINGLE_PATH_DURATION_S)

  -- 4) Sample the path forward (for drawing + “next point” to chase).
  d.sampleCount = 0

  -- Anchor sample: ego position now (index 1)
  d.sampleCount = 1
  d.samplesWorld[1] = ego.position
  d.samplesN[1]     = egoN

  -- Forward samples
  local t = FIRST_SAMPLE_TIME_S
  while t <= SINGLE_PATH_DURATION_S do
    local n = clampN(xOfT(t))
    local z = progressAtTime(egoZ, egoV, t)
    d.sampleCount = d.sampleCount + 1
    d.samplesN[d.sampleCount]     = n
    d.samplesWorld[d.sampleCount] = ac.trackCoordinateToWorld(vec3(n, 0, z))
    t = t + SAMPLE_DT_S
  end

  -- 5) Command a step toward the very next sample (index 2):
  local nextN = d.samplesN[ math.min(2, d.sampleCount) ] or egoN
  local maxStep = (dt or 0.016) * MAX_DELTA_PER_SECOND_N
  local outN = clampN(egoN + math.max(-maxStep, math.min(maxStep, nextN - egoN)))

  d.lastCmdN = outN
  d.lastActN = egoN
  d.lastZ    = egoZ

  vlog("[FA mini] OUT car=%d egoN=%.3f nextN=%.3f outN=%.3f reason=\"%s\"", egoIndex, egoN, nextN, outN, reason)

  return outN
end

---------------------------------------------------------------------------------------------------
-- Batch version (kept identical for compatibility)
---------------------------------------------------------------------------------------------------
---@param allCars ac.StateCar[]
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
-- Debug draw: show exactly what the simple planner is doing
---------------------------------------------------------------------------------------------------
---@param carIndex integer
function FrenetAvoid.debugDraw(carIndex)
  local d = __perCar[carIndex]
  if not d then return end

  -- Draw detection window (progress “slice” ahead of the car)
  if DRAW_DETECTION_WINDOW then
    local ego = ac.getCar(carIndex)
    if ego then
      local tc = ac.worldCoordinateToTrack(ego.position)
      local z0 = tc.z
      local z1 = wrap01(z0 + AHEAD_PROGRESS_WINDOW)
      local p0 = ac.trackCoordinateToWorld(vec3(0, 0, z0))
      local p1L = ac.trackCoordinateToWorld(vec3(-MAX_ABS_OFFSET_N, 0, z1))
      local p1R = ac.trackCoordinateToWorld(vec3(MAX_ABS_OFFSET_N, 0, z1))
      render.debugLine(p0, p1L, COL_DET_WIN) -- left boundary
      render.debugLine(p0, p1R, COL_DET_WIN) -- right boundary
      render.debugText(p0 + vec3(0, 0.4, 0), "AheadWindow")
    end
  end

  -- Draw opponents that triggered the detection
  if DRAW_OPPONENT_MARKERS and d.detCount > 0 then
    for i = 1, d.detCount do
      local opp = d.detOpponents[i]
      if opp then render.debugSphere(opp.position, 1.2, COL_OPP) end
    end
  end

  -- Draw the single planned path (green polyline + spheres)
  if d.sampleCount >= 2 then
    for i = 1, d.sampleCount - 1 do
      render.debugLine(d.samplesWorld[i], d.samplesWorld[i + 1], COL_PATH)
    end
    if DRAW_SAMPLES_AS_SPHERES then
      for i = 1, d.sampleCount do
        render.debugSphere(d.samplesWorld[i], i == 2 and 0.18 or 0.11, COL_SAMPLES)
      end
    end
  end

  -- Emphasize the “chosen path” (it’s the only one): draw thicker purple overlay on the same polyline
  if DRAW_PURPLE_PATH_THICK and d.sampleCount >= 2 then
    for i = 1, d.sampleCount - 1 do
      render.debugLine(d.samplesWorld[i] + vec3(0, 0.01, 0), d.samplesWorld[i + 1] + vec3(0, 0.01, 0), COL_CHOSEN)
      render.debugLine(d.samplesWorld[i] + vec3(0, 0.02, 0), d.samplesWorld[i + 1] + vec3(0, 0.02, 0), COL_CHOSEN)
    end
  end

  -- Show commanded vs actual (poles at the same progress `lastZ`)
  if DRAW_CMD_ACT_POLES then
    local ego = ac.getCar(carIndex)
    if ego then
      local cmdPos = ac.trackCoordinateToWorld(vec3(d.lastCmdN, 0, d.lastZ))
      local actPos = ac.trackCoordinateToWorld(vec3(d.lastActN, 0, d.lastZ))
      render.debugLine(ego.position, cmdPos, COL_CMD)
      render.debugLine(ego.position, actPos, COL_ACT)
      render.debugText(cmdPos + vec3(0, 0.35, 0), string.format("cmdN=%.3f", d.lastCmdN))
      render.debugText(actPos + vec3(0, 0.55, 0), string.format("actN=%.3f", d.lastActN))
    end
  end

  -- Reason label above the second sample (or ego if we don’t have it yet)
  local labelPos = d.samplesWorld[2] or d.samplesWorld[1]
  if labelPos then render.debugText(labelPos + vec3(0, 0.45, 0), d.reasonText or "") end
end

return FrenetAvoid
