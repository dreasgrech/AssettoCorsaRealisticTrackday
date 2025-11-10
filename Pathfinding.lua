-- Pathfinding.lua
-- Minimal, easy-to-read path sketcher.
-- It builds five simple “fan” paths from the front of a car to target lateral offsets
-- normalized to the track width: {-1, -0.5, 0, +0.5, +1}. No avoidance logic yet — just
-- geometry and drawing so we can validate that a car would be able to follow a path we draw.

local Pathfinding = {}

-- Toggle logs without changing call sites.
local LOG_ENABLED = true
local function log(fmt, ...)
  if LOG_ENABLED then Logger.log(string.format(fmt, ...)) end
end

-- Tunables kept tiny on purpose. All distances are “roughly forward along the spline”.
local forwardDistanceMeters   = 60.0     -- how far forward the paths extend
local anchorAheadMeters       = 1.5      -- where the “fan” originates: a bit in front of the car
local numberOfPathSamples     = 12       -- samples per path for drawing
local maxAbsOffsetNormalized  = 1.0      -- clamp to track lateral limits for endpoints

-- Colors for drawing.
local colLine   = rgbm(0.30, 0.95, 0.30, 0.35)   -- light green for the whole fan
local colPoint  = rgbm(0.35, 1.00, 0.35, 0.95)   -- green spheres on samples
local colLabel  = rgbm(1.00, 1.00, 1.00, 0.95)   -- white text
local colAnchor = rgbm(0.10, 0.90, 1.00, 0.95)   -- cyan anchor marker

-- Helper: wrap track progress into [0..1].
local function wrap01(z)
  z = z % 1.0
  if z < 0.0 then z = z + 1.0 end
  return z
end

-- Helper: meters → approximate progress fraction (fallback constant length).
-- If you have your real track length handy, you can set it here from outside later.
local nominalTrackLengthMeters = RaceTrackManager.getTrackLengthMeters()
local function metersToProgress(meters)
  return meters / nominalTrackLengthMeters
end

-- We keep per-car storage so we don’t allocate every frame.
-- For each car we store five paths; each path is an array of world positions plus some meta.
local perCar = {}
local function getCarStore(carIndex)
  local s = perCar[carIndex]
  if s then return s end
  s = {
    -- Each entry: { offsetN = -1..+1, worldPoints = { vec3, ... }, count = N }
    paths = {
      { offsetN = -1.0, worldPoints = {}, count = 0 },
      { offsetN = -0.5, worldPoints = {}, count = 0 },
      { offsetN =  0.0, worldPoints = {}, count = 0 },
      { offsetN =  0.5, worldPoints = {}, count = 0 },
      { offsetN =  1.0, worldPoints = {}, count = 0 },
    },
    anchorWorld = nil,  -- vec3 where the “fan” originates (a bit in front of car)
    anchorText  = ""    -- short label with current info
  }
  perCar[carIndex] = s
  return s
end

-- Public: build five simple paths radiating from the front of the car to lateral targets.
-- Each path starts at the anchor point and smoothly interpolates current offset → target offset.
function Pathfinding.calculatePath(carIndex)
  local car = ac.getCar(carIndex)
  if not car or not ac.hasTrackSpline() then return end

  -- Project car to track space once.
  local carTrack = ac.worldCoordinateToTrack(car.position)
  if not carTrack then return end

  local currentProgressZ  = wrap01(carTrack.z)
  local currentOffsetN    = math.max(-maxAbsOffsetNormalized, math.min(maxAbsOffsetNormalized, carTrack.x))
  local carSpeedMps       = (car.speedKmh or 0) / 3.6

  -- Where paths originate: a small step ahead along the spline at the *current* lateral offset.
  -- Using the spline keeps the fan aligned with the road.
  local anchorZ = wrap01(currentProgressZ + metersToProgress(anchorAheadMeters))
  local anchorWorld = ac.trackCoordinateToWorld(vec3(currentOffsetN, 0.0, anchorZ))

  local store = getCarStore(carIndex)
  store.anchorWorld = anchorWorld
  store.anchorText  = string.format("z=%.4f  n=%.3f  v=%.1f m/s", currentProgressZ, currentOffsetN, carSpeedMps)

  -- Precompute step sizes.
  local totalForwardProgress = metersToProgress(forwardDistanceMeters)
  local stepCount = math.max(2, numberOfPathSamples)
  local stepZ = totalForwardProgress / (stepCount - 1)

  -- Generate the five paths.
  for p = 1, #store.paths do
    local path = store.paths[p]
    local targetOffsetN = math.max(-maxAbsOffsetNormalized, math.min(maxAbsOffsetNormalized, path.offsetN))

    -- Clear previous samples (reuse tables).
    for i = 1, path.count do path.worldPoints[i] = nil end
    path.count = 0

    -- Sample along the road: linearly move lateral offset from current → target while progressing forward.
    -- Sample 0 is the anchor itself.
    path.count = 1
    path.worldPoints[1] = anchorWorld

    for i = 2, stepCount do
      local t01 = (i - 1) / (stepCount - 1)         -- goes 0 → 1
      local sampleZ = wrap01(anchorZ + (i - 1) * stepZ)
      local sampleN = currentOffsetN + (targetOffsetN - currentOffsetN) * t01
      local world   = ac.trackCoordinateToWorld(vec3(sampleN, 0.0, sampleZ))

      path.count = path.count + 1
      path.worldPoints[path.count] = world
    end

    log("[PF] car=%d path[%d] targetN=%.2f samples=%d", carIndex, p, targetOffsetN, path.count)
  end
end

-- Public: draw the five paths like in the sketch: a fan from the car front with labels.
function Pathfinding.drawPaths(carIndex)
  local store = perCar[carIndex]
  if not store or not store.anchorWorld then return end

  -- Draw anchor (small pole and label).
  render.debugSphere(store.anchorWorld, 0.12, colAnchor)
  render.debugText(store.anchorWorld + vec3(0, 0.35, 0), store.anchorText)

  -- Draw each path as a thin green polyline with small spheres on samples and a label at the end.
  for p = 1, #store.paths do
    local path = store.paths[p]
    if path.count >= 2 then
      -- Polyline
      for i = 1, path.count - 1 do
        render.debugLine(path.worldPoints[i], path.worldPoints[i + 1], colLine)
      end
      -- Sample markers
      for i = 1, path.count do
        local r = (i == 2) and 0.16 or 0.10
        render.debugSphere(path.worldPoints[i], r, colPoint)
      end
      -- End label with the associated normalized offset value
      local endPos = path.worldPoints[path.count]
      if endPos then
        render.debugText(endPos + vec3(0, 0.30, 0), string.format("%.1f", store.paths[p].offsetN), colLabel)
        -- Small “arrowhead” cross near the end to make direction obvious
        local a = endPos + vec3(0.20, 0, 0.20)
        local b = endPos + vec3(-0.20, 0, -0.20)
        local c = endPos + vec3(0.20, 0, -0.20)
        local d = endPos + vec3(-0.20, 0, 0.20)
        render.debugLine(a, b, colLabel)
        render.debugLine(c, d, colLabel)
      end
    end
  end
end

return Pathfinding
