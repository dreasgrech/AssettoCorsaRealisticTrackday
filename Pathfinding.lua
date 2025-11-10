-- Pathfinding.lua
-- Minimal, easy-to-read path sketcher.
-- It builds five simple “fan” paths from the front of a car to target lateral offsets
-- normalized to the track width: {-1, -0.5, 0, +0.5, +1}.
-- Now with a very lightweight collider check against other cars:
--   • Each sampled point along a path is checked against cached opponent positions.
--   • If any sample comes closer than a simple combined radius, the path is marked “blocked”.
-- Visualization reflects this state (green = clear, red = blocked).
--
-- NOTE: Keep this file intentionally simple and incremental as requested.

local Pathfinding = {}

-- Toggle logs without changing call sites (leave here so it can be switched off easily).
local LOG_ENABLED = true
local function log(fmt, ...)
  if LOG_ENABLED then Logger.log(string.format(fmt, ...)) end
end

-- Tunables kept tiny on purpose. All distances are “roughly forward along the spline”.
local forwardDistanceMeters   = 60.0     -- how far forward the paths extend
local anchorAheadMeters       = 1.5      -- where the “fan” originates: a bit in front of the car
local numberOfPathSamples     = 12       -- samples per path for drawing
local maxAbsOffsetNormalized  = 1.0      -- clamp to track lateral limits for endpoints

-- Very small and cheap collider model:
-- treat each car as a disc with this radius (meters), add a bit of margin.
local approxCarRadiusMeters   = 1.6
local safetyMarginMeters      = 0.5
local combinedCollisionRadius = (approxCarRadiusMeters * 2.0) + safetyMarginMeters
local combinedCollisionRadius2 = combinedCollisionRadius * combinedCollisionRadius

-- Colors for drawing.
local colLineClear   = rgbm(0.30, 0.95, 0.30, 0.35)   -- light green for clear paths
local colLineBlocked = rgbm(1.00, 0.20, 0.20, 0.55)   -- red for blocked paths
local colPoint       = rgbm(0.35, 1.00, 0.35, 0.95)   -- green spheres on samples
local colPointHit    = rgbm(1.00, 0.40, 0.20, 1.00)   -- orange/red sphere to mark the hit sample
local colLabel       = rgbm(1.00, 1.00, 1.00, 0.95)   -- white text
local colAnchor      = rgbm(0.10, 0.90, 1.00, 0.95)   -- cyan anchor marker
local colOpponent    = rgbm(1.00, 0.30, 0.30, 0.55)   -- faint red disc for opponent markers

-- Helper: wrap track progress into [0..1].
local function wrap01(z)
  z = z % 1.0
  if z < 0.0 then z = z + 1.0 end
  return z
end

-- Helper: meters → approximate progress fraction (fallback length).
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
    -- Each entry:
    -- { offsetN = -1..+1, worldPoints = { vec3, ... }, count = N,
    --   blocked = false, hitIndex = nil, hitWorld = nil, hitOpponentIndex = nil }
    paths = {
      { offsetN = -1.0, worldPoints = {}, count = 0, blocked = false, hitIndex = nil, hitWorld = nil, hitOpponentIndex = nil },
      { offsetN = -0.5, worldPoints = {}, count = 0, blocked = false, hitIndex = nil, hitWorld = nil, hitOpponentIndex = nil },
      { offsetN =  0.0, worldPoints = {}, count = 0, blocked = false, hitIndex = nil, hitWorld = nil, hitOpponentIndex = nil },
      { offsetN =  0.5, worldPoints = {}, count = 0, blocked = false, hitIndex = nil, hitWorld = nil, hitOpponentIndex = nil },
      { offsetN =  1.0, worldPoints = {}, count = 0, blocked = false, hitIndex = nil, hitWorld = nil, hitOpponentIndex = nil },
    },
    anchorWorld = nil,  -- vec3 where the “fan” originates (a bit in front of car)
    anchorText  = "",   -- short label with current info
    opponents   = {},   -- small cache of opponent positions (table of {index=int, pos=vec3})
    opponentsCount = 0
  }
  perCar[carIndex] = s
  return s
end

-- Small utility: build a tiny list of opponent positions for cheap checks this frame.
-- We only cache the world position and index; nothing else is needed for this step.
local function collectOpponents(carIndex, outList)
  local count = 0
  for i, c in ac.iterateCars() do
    if c and c.index ~= carIndex then
      count = count + 1
      local e = outList[count]
      if e then
        e.index = c.index
        e.pos = c.position
      else
        outList[count] = { index = c.index, pos = c.position }
      end
    end
  end
  for j = count + 1, #outList do outList[j] = nil end
  return count
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

  -- Cache opponents for this frame once (positions only).
  store.opponentsCount = collectOpponents(carIndex, store.opponents)

  -- Precompute step sizes.
  local totalForwardProgress = metersToProgress(forwardDistanceMeters)
  local stepCount = math.max(2, numberOfPathSamples)
  local stepZ = totalForwardProgress / (stepCount - 1)

  -- Generate the five paths.
  for p = 1, #store.paths do
    local path = store.paths[p]
    local targetOffsetN = math.max(-maxAbsOffsetNormalized, math.min(maxAbsOffsetNormalized, path.offsetN))

    -- Clear previous samples/meta (reuse tables).
    for i = 1, path.count do path.worldPoints[i] = nil end
    path.count = 0
    path.blocked = false
    path.hitIndex = nil
    path.hitWorld = nil
    path.hitOpponentIndex = nil

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

      -- --- Minimal collider detection (only what’s needed) -------------------
      -- Check this sample against cached opponents; if any is within the
      -- combinedCollisionRadius, mark the path as blocked and store where it happened.
      if (not path.blocked) and store.opponentsCount > 0 then
        local wx, wy, wz = world.x, world.y, world.z
        for oi = 1, store.opponentsCount do
          local opp = store.opponents[oi]
          local dx = opp.pos.x - wx
          local dy = opp.pos.y - wy
          local dz = opp.pos.z - wz
          local d2 = dx*dx + dy*dy + dz*dz
          if d2 <= combinedCollisionRadius2 then
            path.blocked = true
            path.hitIndex = i
            path.hitWorld = world
            path.hitOpponentIndex = opp.index
            break
          end
        end
      end
      -- ----------------------------------------------------------------------
    end

    log("[PF] car=%d path[%d] targetN=%.2f samples=%d blocked=%s",
      carIndex, p, targetOffsetN, path.count, tostring(path.blocked))
  end
end

-- Public: draw the five paths like in the sketch: a fan from the car front with labels.
function Pathfinding.drawPaths(carIndex)
  local store = perCar[carIndex]
  if not store or not store.anchorWorld then return end

  -- Draw anchor (small pole and label).
  render.debugSphere(store.anchorWorld, 0.12, colAnchor)
  render.debugText(store.anchorWorld + vec3(0, 0.35, 0), store.anchorText)

  -- Optionally show opponent discs we cached (very faint; helps to reason about hits).
  if store.opponentsCount and store.opponentsCount > 0 then
    for i = 1, store.opponentsCount do
      local p = store.opponents[i].pos
      render.debugSphere(p, approxCarRadiusMeters, colOpponent)
    end
  end

  -- Draw each path:
  --   • Clear path → thin green polyline.
  --   • Blocked path → red polyline and a highlighted sphere at the first hit sample.
  for p = 1, #store.paths do
    local path = store.paths[p]
    if path.count >= 2 then
      local colLine = path.blocked and colLineBlocked or colLineClear

      -- Polyline
      for i = 1, path.count - 1 do
        render.debugLine(path.worldPoints[i], path.worldPoints[i + 1], colLine)
      end

      -- Sample markers
      for i = 1, path.count do
        local r = (i == 2) and 0.16 or 0.10
        render.debugSphere(path.worldPoints[i], r, colPoint)
      end

      -- End label with the associated normalized offset value (+ blocked flag)
      local endPos = path.worldPoints[path.count]
      if endPos then
        local label = string.format("%.1f", store.paths[p].offsetN)
        if path.blocked then label = label .. " (blocked)" end
        render.debugText(endPos + vec3(0, 0.30, 0), label, colLabel)

        -- Small “arrowhead” cross near the end to make direction obvious
        local a = endPos + vec3(0.20, 0, 0.20)
        local b = endPos + vec3(-0.20, 0, -0.20)
        local c = endPos + vec3(0.20, 0, -0.20)
        local d = endPos + vec3(-0.20, 0, 0.20)
        render.debugLine(a, b, colLabel)
        render.debugLine(c, d, colLabel)
      end

      -- If blocked, mark the first colliding sample with a bigger orange sphere,
      -- and show which opponent index caused it (helps with auditing).
      if path.blocked and path.hitWorld then
        render.debugSphere(path.hitWorld, 0.28, colPointHit)
        if path.hitOpponentIndex ~= nil then
          render.debugText(path.hitWorld + vec3(0, 0.45, 0),
            string.format("car#%d", path.hitOpponentIndex), colLabel)
        end
      end
    end
  end
end

return Pathfinding
