-- Pathfinding.lua
-- Minimal, easy-to-read path sketcher.
-- It builds simple “fan” paths from the front of a car to target lateral offsets
-- normalized to the track width (configured below).
-- Lightweight collider check against other cars:
--   • Each sampled point along a path is checked against cars AHEAD from a sorted list you pass in.
--   • If any sample comes closer than a simple combined radius, the path is marked “blocked”.
-- Visualization reflects this state (green = clear, red = blocked).
--
-- NOTE: Keep this file intentionally simple and incremental as requested.

local Pathfinding = {}

local ac = ac
local ac_getSim = ac.getSim
local ac_getCar = ac.getCar
local ac_worldCoordinateToTrack = ac.worldCoordinateToTrack
local ac_trackCoordinateToWorld = ac.trackCoordinateToWorld
local render = render
local render_debugSphere = render.debugSphere
local render_debugLine = render.debugLine
local render_debugText = render.debugText
local math = math
local math_min = math.min
local math_max = math.max
local math_abs = math.abs
local string = string
local string_format = string.format
local RaceTrackManager = RaceTrackManager
local RaceTrackManager_metersToSplineSpan = RaceTrackManager.metersToSplineSpan
local table = table
local table_concat = table.concat
local table_insert = table.insert
local Logger = Logger
local Logger_log = Logger.log
local VecPool = VecPool
local VecPool_getTempVec3 = VecPool.getTempVec3
local GameTimeManager = GameTimeManager
local GameTimeManager_getPlayingGameTime = GameTimeManager.getPlayingGameTime


-- Toggle logs without changing call sites (leave here so it can be switched off easily).
local LOG_ENABLED = false
local function log(fmt, ...)
  if LOG_ENABLED then Logger_log(string.format(fmt, ...)) end
end

local storage_PathFinding = StorageManager.getStorage_PathFinding()

-- Tunables kept tiny on purpose. All distances are “roughly forward along the spline”.
-- local forwardDistanceMeters   = 60.0     -- how far forward the paths extend
-- local anchorAheadMeters       = 1.5      -- where the “fan” originates: a bit in front of the car
-- local numberOfPathSamples     = 12       -- samples per path for drawing
-- local maxAbsOffsetNormalized  = 1.0      -- clamp to track lateral limits for endpoints

-- Make paths split to the sides much earlier (for tight manoeuvres) without changing length:
-- We reach full lateral target by this forward distance (meters), with an ease-out power curve.
-- local splitReachMeters        = 12.0     -- distance at which lateral offset reaches 100%
-- local lateralSplitExponent    = 2.2      -- >1: earlier split; =1: linear; <1: later split

-- Very small and cheap collider model:
-- treat each car as a disc with this radius (meters), add a bit of margin.
-- local approxCarRadiusMeters   = 1.6
-- local safetyMarginMeters      = 0.5
-- local combinedCollisionRadius = (approxCarRadiusMeters * 2.0) + safetyMarginMeters
-- local combinedCollisionRadius2 = combinedCollisionRadius * combinedCollisionRadius

-- Colors for drawing.
local colLineClear   = rgbm(0.30, 0.95, 0.30, 0.35)   -- light green for clear paths
local colLineBlocked = rgbm(1.00, 0.20, 0.20, 0.55)   -- red for blocked paths
local colPoint       = rgbm(0.35, 1.00, 0.35, 0.95)   -- green spheres on samples
local colPointHit    = rgbm(1.00, 0.40, 0.20, 1.00)   -- orange/red sphere to mark the hit sample
local colLabel       = rgbm(1.00, 1.00, 1.00, 0.95)   -- white text
local colAnchor      = rgbm(0.10, 0.90, 1.00, 0.95)   -- cyan anchor marker

-- Helper: wrap track progress into [0..1].
local function wrap01(z)
  z = z % 1.0
  if z < 0.0 then z = z + 1.0 end
  return z
end

-- Minimal easing to split earlier: ease-out by power.
local function easeOutPow01(t, power)
  if power == 1.0 then return t end
  local inv = 1.0 - t
  return 1.0 - (inv ^ power)
end

-- Helper: meters → approximate progress fraction (fallback length).
-- local nominalTrackLengthMeters = RaceTrackManager.getTrackLengthMeters()
-- local function metersToProgress(meters)
  -- return meters / nominalTrackLengthMeters
-- end

-- =========================
-- Data-oriented containers
-- =========================

local PATHS_EDGE_OFFSET_N = 1.0  -- normalized offset for outermost paths
--local PATHS_EDGE_OFFSET_N = 0.9  -- normalized offset for outermost paths

-- PATHS ARE MODULE-WIDE (not per-car) so you can expand/reduce them without extra memory per car.
-- Modify this list to add/remove paths. All code below adapts automatically.
---@type table<integer,number>
local PATH_LATERAL_OFFSETS = { -PATHS_EDGE_OFFSET_N, -0.75, -0.5, 0.0, 0.5, 0.75, PATHS_EDGE_OFFSET_N }
--local PATH_LATERAL_OFFSETS = { -0.75, -0.5, 0.0, 0.5, 0.75 }
-- local PATH_LATERAL_OFFSETS = {  -0.5, 0.0, 0.5 }
local TOTAL_PATH_LATERAL_OFFSETS = #PATH_LATERAL_OFFSETS

---@type table<integer,string>
local navigation_anchorText = {}

---@type table<integer,vec3>
local navigation_anchorWorldPosition = {}

---@type table<integer,integer|nil>
local navigation_lastChosenPathIndex = {}

-- per-car array of counts per path
---@type table<integer,table<integer,integer>>
local navigation_pathsTotalSamples = {}

-- per-car array of blocked flags per path
---@type table<integer,table<integer,boolean>>
local navigation_pathsIsBlocked = {}

-- per-car array of hit sample indices per path
---@type table<integer,table<integer,integer>>
local navigation_pathsBlockedSampleIndex = {}

-- per-car array of hit other cars indices per path
---@type table<integer,table<integer,integer>>
local navigation_pathsBlockedOtherCarIndex = {}

-- per-car array of hit world positions per path
---@type table<integer,table<integer,vec3>>
local navigation_pathsBlockedSampleWorldPosition = {}

---@type table<integer,table<integer,integer>>
local navigation_pathsBlockedTimeSeconds = {}

-- per-car array of lists of sampled points per path
---@type table<integer,table<integer,table<integer,vec3>>>
local navigation_pathsSamplesWorldPositions = {}

-- Ensure per-car arrays exist and match the number of configured paths.
local function ensureCarArrays(carIndex)
  local pathsTotalSamples = navigation_pathsTotalSamples[carIndex]
  if not pathsTotalSamples or #pathsTotalSamples ~= TOTAL_PATH_LATERAL_OFFSETS then
    pathsTotalSamples = {}
    local blocked, hitIdx, hitOpp, hitPos, points, times = {}, {}, {}, {}, {}, {}
    for i = 1, TOTAL_PATH_LATERAL_OFFSETS do
      pathsTotalSamples[i] = 0
      blocked[i] = false
      hitIdx[i] = nil
      hitOpp[i] = nil
      hitPos[i] = nil
      points[i] = {}
      times[i] = nil
    end
    navigation_pathsTotalSamples[carIndex] = pathsTotalSamples
    navigation_pathsIsBlocked[carIndex] = blocked
    navigation_pathsBlockedSampleIndex[carIndex] = hitIdx
    navigation_pathsBlockedOtherCarIndex[carIndex] = hitOpp
    navigation_pathsBlockedSampleWorldPosition[carIndex] = hitPos
    navigation_pathsSamplesWorldPositions[carIndex] = points
    navigation_pathsBlockedTimeSeconds[carIndex] = times
  end

  navigation_anchorText[carIndex] = navigation_anchorText[carIndex] or ""

  -- TODO: Andreas: investigate why we need this part:
  -- keep sticky index if present; if it exceeds path count after a config change, drop it
  local lastChosenPathIndex = navigation_lastChosenPathIndex[carIndex]
  if lastChosenPathIndex and (lastChosenPathIndex < 1 or lastChosenPathIndex > TOTAL_PATH_LATERAL_OFFSETS) then
    navigation_lastChosenPathIndex[carIndex] = nil
  end
end

local isIntersectingSphere = function(carPosition, otherCarPosition, combinedCollisionRadius2)
  local dx = otherCarPosition.x - carPosition.x
  local dy = otherCarPosition.y - carPosition.y
  local dz = otherCarPosition.z - carPosition.z
  local d2 = dx*dx + dy*dy + dz*dz
  
  -- check if this sample is colliding with the other car
  local intersecting = d2 <= combinedCollisionRadius2
  return intersecting
end

---@param carPosition vec3
---@param otherCarPosition vec3
---@param otherCarAABBSize vec3
---@param otherCarForward vec3
---@param otherCarLeft vec3
---@param otherCarUp vec3
---@return boolean
local isIntersectingAABB = function(carPosition, otherCarPosition, otherCarAABBSize, otherCarForward, otherCarLeft, otherCarUp)
  -- Treat the other car as an oriented bounding box using its forward/left/up directions.
  -- Center at mid-height (same convention as CarOperations.getSideAnchorPoints).
  local safetyMarginMeters = storage_PathFinding.safetyMarginMeters
  local halfSizeX = (otherCarAABBSize.x * 0.5) + safetyMarginMeters
  local halfSizeY = (otherCarAABBSize.y * 0.5)-- + safetyMarginMeters
  local halfSizeZ = (otherCarAABBSize.z * 0.5) + safetyMarginMeters

  local centerX = otherCarPosition.x + otherCarUp.x * halfSizeY
  local centerY = otherCarPosition.y + otherCarUp.y * halfSizeY
  local centerZ = otherCarPosition.z + otherCarUp.z * halfSizeY

  local dx = carPosition.x - centerX
  local dy = carPosition.y - centerY
  local dz = carPosition.z - centerZ

  -- Project into the other car's local space.
  local localX = dx * otherCarLeft.x     + dy * otherCarLeft.y     + dz * otherCarLeft.z -- left/right
  local localY = dx * otherCarUp.x       + dy * otherCarUp.y       + dz * otherCarUp.z   -- up/down
  local localZ = dx * otherCarForward.x  + dy * otherCarForward.y  + dz * otherCarForward.z -- front/back

  local insideX = math_abs(localX) <= halfSizeX
  local insideY = math_abs(localY) <= halfSizeY
  local insideZ = math_abs(localZ) <= halfSizeZ

  local intersecting = insideX and insideY and insideZ
  -- Logger.log(string_format(
    -- "[PF_AABB] |localX|=%.3f <= %.3f = %s, |localY|=%.3f <= %.3f = %s, |localZ|=%.3f <= %.3f = %s => intersecting=%s. otherCarPosition=%s",
     -- localX, halfSizeX, tostring(insideX),
     -- localY, halfSizeY, tostring(insideY),
     -- localZ, halfSizeZ, tostring(insideZ),
     -- tostring(intersecting),
     -- tostring(otherCarPosition)))
  return intersecting
end

---@param otherCar ac.StateCar
---@param color rgbm|nil
function Pathfinding.renderCarAABB(otherCar, color)
  if not otherCar or not otherCar.aabbSize then return end

  -- Use the same parameters and logic as isIntersectingAABB
  local otherCarPosition = otherCar.position
  local otherCarAABBSize = otherCar.aabbSize
  local otherCarForward  = otherCar.look
  local otherCarLeft     = otherCar.side
  local otherCarUp       = otherCar.up

  local safetyMarginMeters = storage_PathFinding.safetyMarginMeters
  local halfSizeX = (otherCarAABBSize.x * 0.5) + safetyMarginMeters
  local halfSizeY = (otherCarAABBSize.y * 0.5)-- + safetyMarginMeters
  local halfSizeZ = (otherCarAABBSize.z * 0.5) + safetyMarginMeters

  -- Center at mid-height, same as isIntersectingAABB
  local center = otherCarPosition + otherCarUp * halfSizeY

  -- Local box axes scaled by half-extents (left/right, up/down, front/back)
  local axisX = otherCarLeft    * halfSizeX
  local axisY = otherCarUp      * halfSizeY
  local axisZ = otherCarForward * halfSizeZ

  -- Oriented box corners in world space
  local c = center
  local p000 = c - axisX - axisY - axisZ
  local p001 = c - axisX - axisY + axisZ
  local p010 = c - axisX + axisY - axisZ
  local p011 = c - axisX + axisY + axisZ
  local p100 = c + axisX - axisY - axisZ
  local p101 = c + axisX - axisY + axisZ
  local p110 = c + axisX + axisY - axisZ
  local p111 = c + axisX + axisY + axisZ

  local col = color or colLineBlocked

  -- Bottom rectangle
  render_debugLine(p000, p001, col)
  render_debugLine(p001, p101, col)
  render_debugLine(p101, p100, col)
  render_debugLine(p100, p000, col)

  -- Top rectangle
  render_debugLine(p010, p011, col)
  render_debugLine(p011, p111, col)
  render_debugLine(p111, p110, col)
  render_debugLine(p110, p010, col)

  -- Vertical edges
  render_debugLine(p000, p010, col)
  render_debugLine(p001, p011, col)
  render_debugLine(p100, p110, col)
  render_debugLine(p101, p111, col)
end


-- Build simple paths radiating from the front of the car to lateral targets.
-- Each path starts at the anchor point and smoothly interpolates current offset → target offset.
---@param sortedCarsList SortedCarsList @The list of cars sorted by track position (furthest ahead first)
---@param sortedCarsListIndex integer @The SortedCarsList index of the car to calculate the path for
local calculatePath = function(sortedCarsList, sortedCarsListIndex)
  local car = sortedCarsList[sortedCarsListIndex]
  if not car then return end

  local carIndex = car.index
  ensureCarArrays(carIndex)

  local carTrackCoordinates = ac_worldCoordinateToTrack(car.position)
  local currentProgressZ  = wrap01(carTrackCoordinates.z)
  local maxAbsOffsetNormalized = storage_PathFinding.maxAbsOffsetNormalized
  local currentOffsetN    = math_max(-maxAbsOffsetNormalized, math_min(maxAbsOffsetNormalized, carTrackCoordinates.x))
  local carSpeedKmh       = car.speedKmh

  -- Where paths originate: a small step ahead along the spline at the *current* lateral offset.
  -- Using the spline keeps the fan aligned with the road.
  local anchorAheadMeters = storage_PathFinding.anchorAheadMeters
  local anchorZ = wrap01(currentProgressZ + RaceTrackManager_metersToSplineSpan(anchorAheadMeters))
  -- local anchorWorldPosition = ac_trackCoordinateToWorld(VecPool_getTempVec3(currentOffsetN, 0.0, anchorZ))
  local anchorWorldPosition = car.position + (car.look * anchorAheadMeters)

  navigation_anchorWorldPosition[carIndex] = anchorWorldPosition
  -- navigation_anchorText[carIndex]  = string_format("spline=%.4f  n=%.3f  speed=%.1f km/h", currentProgressZ, currentOffsetN, carSpeedKmh)
  local lastChosenPathIndex = navigation_lastChosenPathIndex[carIndex] or -1
  navigation_anchorText[carIndex]  = string_format("Path Index: %d (%.2f)", lastChosenPathIndex, PATH_LATERAL_OFFSETS[lastChosenPathIndex] or -1)

  -- Precompute step sizes.
  local forwardDistanceMeters = storage_PathFinding.forwardDistanceMeters
  local totalForwardProgress = RaceTrackManager_metersToSplineSpan(forwardDistanceMeters)
  local numberOfPathSamples = math_max(2, storage_PathFinding.numberOfPathSamples)
  local stepZ = totalForwardProgress / (numberOfPathSamples - 1) -- the increment per step along Z

  -- Precompute inverse of progress needed to reach full lateral offset by splitReachMeters.
  local splitReachMeters = storage_PathFinding.splitReachMeters
  local splitReachProgress = RaceTrackManager_metersToSplineSpan(splitReachMeters)
  local invSplitReachProgress = (splitReachProgress > 0.0) and (1.0 / splitReachProgress) or 1e9

  -- Generate paths (count adapts to navigation_pathOffsetN length).
  local pathsTotalSamples  = navigation_pathsTotalSamples[carIndex]
  local pathsIsBlocked = navigation_pathsIsBlocked[carIndex]
  local pathsBlockedSampleIndex  = navigation_pathsBlockedSampleIndex[carIndex]
  local pathsBlockedOtherCarIndex  = navigation_pathsBlockedOtherCarIndex[carIndex]
  local pathsBlockedSampleWorldPosition  = navigation_pathsBlockedSampleWorldPosition[carIndex]
  local pathsBlockedTimeSeconds  = navigation_pathsBlockedTimeSeconds[carIndex]
  local pathsSamplesWorldPositions  = navigation_pathsSamplesWorldPositions[carIndex]

  -- For minimal work, only consider cars AHEAD of the current one in the sorted list.
  -- (sortedCarsListIndex-1 down to 1). Cars behind can’t block our forward samples.
  local firstAheadSortedCarListIndex = (sortedCarsListIndex or 2) - 1

  --[===[
  local approxCarRadiusMeters   = storage_PathFinding.approxCarRadiusMeters
  local safetyMarginMeters      = storage_PathFinding.safetyMarginMeters
  local combinedCollisionRadius = (approxCarRadiusMeters * 2.0) + safetyMarginMeters
  local combinedCollisionRadius2 = combinedCollisionRadius * combinedCollisionRadius
  --]===]

  local lateralSplitExponent = storage_PathFinding.lateralSplitExponent

  local timeToLeavePathBlockedAfterSampleHitSeconds = storage_PathFinding.timeToLeavePathBlockedAfterSampleHitSeconds 

  local sim = ac_getSim()
  local playingGameTimeSeconds = GameTimeManager_getPlayingGameTime()

  -- For each path lateral target offset, build each path's samples and check for collisions after creating the samples
  for pathIndex = 1, TOTAL_PATH_LATERAL_OFFSETS do
    local targetOffsetN = math_max(-maxAbsOffsetNormalized, math_min(maxAbsOffsetNormalized, PATH_LATERAL_OFFSETS[pathIndex]))

    local leavePathBlocked = false
    local isPathCurrentlyBlocked = pathsIsBlocked[pathIndex]
    -- Determine if we should keep the path marked as blocked based on time since last hit
    if isPathCurrentlyBlocked then
      local pathBlockedTimeSeconds = pathsBlockedTimeSeconds[pathIndex] or 0.0
      local timeSinceBlockedSeconds = playingGameTimeSeconds - pathBlockedTimeSeconds
      -- if timeSinceBlockedSeconds < timeToLeavePathBlockedAfterSampleHitSeconds or sim.isPaused then
      if timeSinceBlockedSeconds < timeToLeavePathBlockedAfterSampleHitSeconds then
        leavePathBlocked = true

        -- Logger.log(string_format("[PF] car=%d path[%d] remains BLOCKED (game time: %.2f, path blocked time: %.2f,time since hit: %.2f s < %.2f s)", carIndex, pathIndex, playingGameTimeSeconds, pathBlockedTimeSeconds, timeSinceBlockedSeconds, timeToLeavePathBlockedAfterSampleHitSeconds))
      end
    end

    -- Clear previous samples/meta (reuse tables).
    local pathSamplesWorldPositions = pathsSamplesWorldPositions[pathIndex]
    for i = 1, #pathSamplesWorldPositions do
      pathSamplesWorldPositions[i] = nil
    end
    pathsTotalSamples[pathIndex] = 0

    -- Only clear the blocked state if we are not leaving it blocked
    if not leavePathBlocked then
      pathsIsBlocked[pathIndex] = false
      pathsBlockedSampleIndex[pathIndex] = nil
      pathsBlockedSampleWorldPosition[pathIndex] = nil
      pathsBlockedOtherCarIndex[pathIndex] = nil
      pathsBlockedTimeSeconds[pathIndex] = nil
    end

    -- Sample along the road: linearly progress forward, but move laterally so that we hit the target offset by `splitReachMeters` (using an ease-out curve).

    -- Initialize the sample count (first sample is the anchor).
    pathsTotalSamples[pathIndex] = 1

    -- First sample is always the anchor.
    pathSamplesWorldPositions[1] = anchorWorldPosition

    -- NEW: keep track of previous sample position for segment midpoint checks.
    -- local lastSampleWorldPosition = anchorWorldPosition

    -- for each step along the path, create a sample point and check for collisions.
    for currentSampleIndex = 2, numberOfPathSamples do
      local progressDelta = (currentSampleIndex - 1) * stepZ
      local tLatLinear = math_min(1.0, progressDelta * invSplitReachProgress)
      local tLat = easeOutPow01(tLatLinear, lateralSplitExponent)

      local sampleZ = wrap01(anchorZ + (currentSampleIndex - 1) * stepZ)
      local sampleN = currentOffsetN + (targetOffsetN - currentOffsetN) * tLat
      local sampleWorldPosition   = ac_trackCoordinateToWorld(VecPool_getTempVec3(sampleN, 0.0, sampleZ))

      -- increase the sample count since we have a new sample
      pathsTotalSamples[pathIndex] = pathsTotalSamples[pathIndex] + 1
      
      -- save the sample world position
      pathSamplesWorldPositions[pathsTotalSamples[pathIndex]] = sampleWorldPosition

      -- --- Minimal collider detection (only what’s needed) -------------------
      if not pathsIsBlocked[pathIndex] and firstAheadSortedCarListIndex >= 1 then
        -- Check cars in front only; early-exit on first hit.
        for otherCarSortedCarsListIndex = firstAheadSortedCarListIndex, 1, -1 do
          local otherCar = sortedCarsList[otherCarSortedCarsListIndex]
          
          -- TODO: Andreas: theoratically this index check is not needed since we only check cars ahead
          if otherCar and otherCar.index ~= carIndex then
            -- check if this sample is colliding with the other car
            -- local intersecting = isIntersectingSphere(sampleWorldPosition, otherCar.position, combinedCollisionRadius2)
            local intersecting = isIntersectingAABB(sampleWorldPosition, otherCar.position, otherCar.aabbSize, otherCar.look, otherCar.side, otherCar.up)

            --[====[
            -- EXTRA “BETWEEN SAMPLES” CHECK:
            -- If endpoint is not inside, also test midpoint of the segment between last and current samples.
            if not intersecting then
              local midX = (lastSampleWorldPosition.x + sampleWorldPosition.x) * 0.5
              local midY = (lastSampleWorldPosition.y + sampleWorldPosition.y) * 0.5
              local midZ = (lastSampleWorldPosition.z + sampleWorldPosition.z) * 0.5
              local midPoint = VecPool_getTempVec3(midX, midY, midZ)
              intersecting = isIntersectingAABB(midPoint, otherCar.position, otherCar.aabbSize, otherCar.look, otherCar.side, otherCar.up)
            end
            --]====]

            if intersecting then
              -- mark the path as blocked
              pathsIsBlocked[pathIndex] = true
              pathsBlockedSampleIndex[pathIndex] = currentSampleIndex
              pathsBlockedSampleWorldPosition[pathIndex] = sampleWorldPosition
              pathsBlockedOtherCarIndex[pathIndex] = otherCar.index
              pathsBlockedTimeSeconds[pathIndex] = playingGameTimeSeconds
              break -- break out of the for loop over other cars since we found a blocked hit for this path so we don't need to check for other cars
            end
          end
        end -- end of other cars loop
      end
      -- ----------------------------------------------------------------------

      -- update previous sample position for the next segment
      -- lastSampleWorldPosition = sampleWorldPosition
    end -- end of samples loop

    log("[PF] car=%d path[%d] targetN=%.2f samples=%d blocked=%s", carIndex, pathIndex, targetOffsetN, pathsTotalSamples[pathIndex], tostring(pathsIsBlocked[pathIndex]))
  end -- end of paths loop
end

-- Draw the paths generated for the car
--- @param carIndex integer @The index of the car to draw the paths for
function Pathfinding.drawPaths(carIndex)
  local anchorWorldPosition = navigation_anchorWorldPosition[carIndex]
  if not anchorWorldPosition then return end

  -- Draw anchor (small pole and label).
  render_debugSphere(anchorWorldPosition, 0.12, colAnchor)
  -- render_debugText(anchorWorldPosition + VecPool_getTempVec3(0, 1.5, 1), navigation_anchorText[carIndex])
  local car = ac_getCar(carIndex)
  if car then
    render_debugText(car.position + VecPool_getTempVec3(0, 1.5, 0), navigation_anchorText[carIndex])
  end

  -- Draw each path:
  --   • Clear path → thin green polyline.
  --   • Blocked path → red polyline and a highlighted sphere at the first hit sample.
  local pathsTotalSamples  = navigation_pathsTotalSamples[carIndex]
  local pathsIsBlocked = navigation_pathsIsBlocked[carIndex]
  local pathsBlockedOtherCarIndex  = navigation_pathsBlockedOtherCarIndex[carIndex]
  local pathsBlockedSampleWorldPosition  = navigation_pathsBlockedSampleWorldPosition[carIndex]
  local pathsBlockedSampleIndex  = navigation_pathsBlockedSampleIndex[carIndex]
  local pathsSamplesWorldPositions  = navigation_pathsSamplesWorldPositions[carIndex]

  for pathIndex = 1, TOTAL_PATH_LATERAL_OFFSETS do
    local pathTotalSamples = pathsTotalSamples[pathIndex]
    if pathTotalSamples and pathTotalSamples >= 2 then
      local colLine = pathsIsBlocked[pathIndex] and colLineBlocked or colLineClear
      local pathSamplesWorldPositions = pathsSamplesWorldPositions[pathIndex]

      -- Polyline
      for sampleIndex = 1, pathTotalSamples - 1 do
        render_debugLine(pathSamplesWorldPositions[sampleIndex], pathSamplesWorldPositions[sampleIndex + 1], colLine)
      end

      -- Sample markers
      for sampleIndex = 1, pathTotalSamples do
        local r = (sampleIndex == 2) and 0.16 or 0.10
        render_debugSphere(pathSamplesWorldPositions[sampleIndex], r, colPoint)
        
        -- write the sample blocked index on the first sample after the anchor
        if sampleIndex == 2 then
          render_debugText(pathSamplesWorldPositions[sampleIndex] + VecPool_getTempVec3(0, 0.40, 0), string_format("%d", pathsBlockedSampleIndex[pathIndex] or -1), colLabel)
        end
      end

      -- End label with the associated normalized offset value (+ blocked flag)
      local lastPathSampleWorldPosition = pathSamplesWorldPositions[pathTotalSamples]
      if lastPathSampleWorldPosition then
        local label = string_format("%.2f", PATH_LATERAL_OFFSETS[pathIndex])
        if pathsIsBlocked[pathIndex] then
          label = label .. " (blocked)"
        end

        render_debugText(lastPathSampleWorldPosition + VecPool_getTempVec3(0, 0.30, 0), label, colLabel)

        -- Small “arrowhead” cross near the end to make direction obvious
        local a = lastPathSampleWorldPosition + VecPool_getTempVec3(0.20, 0, 0.20)
        local b = lastPathSampleWorldPosition + VecPool_getTempVec3(-0.20, 0, -0.20)
        local c = lastPathSampleWorldPosition + VecPool_getTempVec3(0.20, 0, -0.20)
        local d = lastPathSampleWorldPosition + VecPool_getTempVec3(-0.20, 0, 0.20)
        render_debugLine(a, b, colLabel)
        render_debugLine(c, d, colLabel)
      end

      -- If blocked, mark the first colliding sample with a bigger orange sphere,
      -- and show which opponent index caused it (helps with auditing).
      if pathsIsBlocked[pathIndex] and pathsBlockedSampleWorldPosition[pathIndex] then
        render_debugSphere(pathsBlockedSampleWorldPosition[pathIndex], 1.28, colPointHit)
        if pathsBlockedOtherCarIndex[pathIndex] ~= nil then
          render_debugText(pathsBlockedSampleWorldPosition[pathIndex] + VecPool_getTempVec3(0, 0.45, 0), string_format("car#%d", pathsBlockedOtherCarIndex[pathIndex]), colLabel)
        end
      end
    end
  end
end

-- --- Decision trace (ADDED, minimal) ----------------------------------------
local DECISION_TRACE_ENABLED = true
local function traceDecision(lines)
  if LOG_ENABLED and DECISION_TRACE_ENABLED and lines and #lines > 0 then
    Logger_log(table_concat(lines, "\n"))
  end
end
-- ----------------------------------------------------------------------------

-- Public: return the lateral offset (normalized) associated with the “best” path for a car.
-- “Best” here = first clear path by preference (center-most first, then bias to right on ties).
-- Sticky behavior: if previously chosen path is still clear, keep it to avoid wobbling.
-- If all paths are blocked, returns the one that gets the furthest before the first hit.
local function getBestLateralOffset(carIndex)
  -- If the last chosen path is still clear, reuse it (sticky behavior).
  local lastChosenPathIndex = navigation_lastChosenPathIndex[carIndex]
  local pathsIsBlocked = navigation_pathsIsBlocked[carIndex]
  if lastChosenPathIndex ~= nil then
    local lastChosenPathStillAvailable = not pathsIsBlocked[lastChosenPathIndex]
    if lastChosenPathStillAvailable then
      log("[PF] car=%d reusing last chosen path index=%d n=%.2f (still clear)", carIndex, lastChosenPathIndex, PATH_LATERAL_OFFSETS[lastChosenPathIndex])
      return PATH_LATERAL_OFFSETS[lastChosenPathIndex]
    end
  end

  local pathsBlockedSampleIndex = navigation_pathsBlockedSampleIndex[carIndex]
  local pathsBlockedSampleWorldPosition = navigation_pathsBlockedSampleWorldPosition[carIndex]
  local pathsSamplesWorldPositions = navigation_pathsSamplesWorldPositions[carIndex]

  local blockedPathIndexes = {}
  for i = 1, TOTAL_PATH_LATERAL_OFFSETS do
    if pathsIsBlocked[i] then
      table_insert(blockedPathIndexes, i)
    end
  end

  local bestPathIndex = 0
  local bestPathBlockedSampleIndex = 0
  local bestPathDistanceToBlockedSamples = 0

  --[====[
  for i = 1, TOTAL_PATH_LATERAL_OFFSETS do
    local pathSamplesWorldPositions = pathsSamplesWorldPositions[i]
    local totalDistancesToBlockedSamples = 0.0
    for j = 1, #blockedPathIndexes do
      local blockedPathIndex = blockedPathIndexes[j]
      local pathBlockedSampleWorldPosition = pathsBlockedSampleWorldPosition[blockedPathIndex]
      local pathBlockedSampleIndex = pathsBlockedSampleIndex[blockedPathIndex]
      
      local distanceBetweenSamples = MathHelpers.distanceBetweenVec3s(
        pathSamplesWorldPositions[pathBlockedSampleIndex],
        pathBlockedSampleWorldPosition
      )

      totalDistancesToBlockedSamples = totalDistancesToBlockedSamples + distanceBetweenSamples
    end
    -- log("[PF] car=%d path[%d] n=%.2f totalDistanceToBlockedSamples=%.3f", carIndex, i, PATH_LATERAL_OFFSETS[i], totalDistancesToBlockedSamples)
    if totalDistancesToBlockedSamples > bestPathDistanceToBlockedSamples then
      bestPathDistanceToBlockedSamples = totalDistancesToBlockedSamples
      bestPathIndex = i
    end
  end
  --]====]

  -- this one picks the best path depending on which blocked path goes the furthest based on the highest blocked sample index
  for i = 1, TOTAL_PATH_LATERAL_OFFSETS do
    local pathBlockedSampleIndex = math.huge
    if pathsIsBlocked[i] then
      pathBlockedSampleIndex = pathsBlockedSampleIndex[i]
    end

    -- if this path's blocked sample index is greater than the best found so far, update best
    if pathBlockedSampleIndex > bestPathBlockedSampleIndex then
      bestPathBlockedSampleIndex = pathBlockedSampleIndex
      bestPathIndex = i
    end
  end

  navigation_lastChosenPathIndex[carIndex] = bestPathIndex
  log("[PF] car=%d choosing new path index=%d n=%.2f (best of blocked)", carIndex, bestPathIndex, PATH_LATERAL_OFFSETS[bestPathIndex])
  return PATH_LATERAL_OFFSETS[bestPathIndex]







  -- for i = 1, TOTAL_PATH_LATERAL_OFFSETS do
    -- if not pathsIsBlocked[i] then
      -- navigation_lastChosenPathIndex[carIndex] = i
      -- log("[PF] car=%d choosing new path index=%d n=%.2f (first clear)", carIndex, i, PATH_LATERAL_OFFSETS[i])
      -- return PATH_LATERAL_OFFSETS[i]
    -- end
  -- end


  --[====[
  local counts  = navigation_pathsTotalSamples[carIndex]
  if not counts then return nil end

  local pathIsBlocked = navigation_pathsIsBlocked[carIndex]

  -- Build a compact decision sheet we’ll log at the end.
  local lines = {}
  lines[#lines+1] = string_format("[PF_DECISION] car=%d", carIndex)

  -- Helper: append per-path status for diagnostics
  local function appendPathStatus()
    for i = 1, TOTAL_PATH_LATERAL_OFFSETS do
      local cnt  = counts[i] or 0
      local stat = (pathIsBlocked[i] and "BLOCKED") or "CLEAR"
      local hitI = navigation_pathsBlockedSampleIndex[carIndex] and navigation_pathsBlockedSampleIndex[carIndex][i]
      local hitO = navigation_pathsBlockedOtherCarIndex[carIndex] and navigation_pathsBlockedOtherCarIndex[carIndex][i]
      if pathIsBlocked[i] and hitI and hitO then
        lines[#lines+1] = string_format("  path[%d] n=% .2f samples=%d -> %s @sample=%d by car#%d", i, PATH_LATERAL_OFFSETS[i], cnt, stat, hitI, hitO)
      else
        lines[#lines+1] = string_format("  path[%d] n=% .2f samples=%d -> %s", i, PATH_LATERAL_OFFSETS[i], cnt, stat)
      end
    end
  end

  -- Compute dynamic “center” index (closest to 0, prefer positive on tie).
  local centerIdx, minAbs = 1, math.huge
  for i = 1, TOTAL_PATH_LATERAL_OFFSETS do
    local a = math_abs(PATH_LATERAL_OFFSETS[i])
    if a < minAbs or (a == minAbs and PATH_LATERAL_OFFSETS[i] > PATH_LATERAL_OFFSETS[centerIdx]) then
      centerIdx, minAbs = i, a
    end
  end

  -- If all paths are present and NONE are blocked, default to center path.
  do
    local haveAll, allClear = true, true
    for i = 1, TOTAL_PATH_LATERAL_OFFSETS do
      if not (counts[i] and counts[i] > 0) then haveAll = false break end
      if pathIsBlocked[i] then allClear = false break end
    end
    if haveAll and allClear then
      navigation_lastChosenPathIndex[carIndex] = centerIdx
      appendPathStatus()
      lines[#lines+1] = string_format("  order: center-only (all clear)")
      lines[#lines+1] = string_format("  chosen: idx=%d n=% .2f (reason: all-clear center)", centerIdx, PATH_LATERAL_OFFSETS[centerIdx])
      traceDecision(lines)
      return PATH_LATERAL_OFFSETS[centerIdx]
    end
  end

  -- Sticky choice: keep last if still clear.
  local lastIdx = navigation_lastChosenPathIndex[carIndex]
  if lastIdx and counts[lastIdx] and counts[lastIdx] > 0 and not pathIsBlocked[lastIdx] then
    appendPathStatus()
    lines[#lines+1] = string_format("  order: (sticky short-circuit)")
    lines[#lines+1] = string_format("  chosen: idx=%d n=% .2f (reason: sticky last still clear)", lastIdx, PATH_LATERAL_OFFSETS[lastIdx])
    traceDecision(lines)
    return PATH_LATERAL_OFFSETS[lastIdx]
  end

  -- Preference order: center, then ±0.5, ±0.75, ±1.0 (right on ties).
  local order = {}
  local function pushIfExists(val)
    for i = 1, TOTAL_PATH_LATERAL_OFFSETS do
      if PATH_LATERAL_OFFSETS[i] == val then
        table_insert(order, i) return
      end
    end
  end
  pushIfExists(0.0)
  pushIfExists(0.5)
  pushIfExists(-0.5)
  pushIfExists(0.75)
  pushIfExists(-0.75)
  pushIfExists(1.0)
  pushIfExists(-1.0)

  appendPathStatus()
  do
    local buf = {}
    for k = 1, #order do buf[k] = string_format("%d(n=% .2f)", order[k], PATH_LATERAL_OFFSETS[order[k]]) end
    lines[#lines+1] = "  order: " .. table_concat(buf, " → ")
  end

  -- First, try to pick the first CLEAR path by preference.
  for _, idx in ipairs(order) do
    if counts[idx] and counts[idx] > 0 and not pathIsBlocked[idx] then
      navigation_lastChosenPathIndex[carIndex] = idx
      lines[#lines+1] = string_format("  chosen: idx=%d n=% .2f (reason: first clear by preference)", idx, PATH_LATERAL_OFFSETS[idx])
      traceDecision(lines)
      return PATH_LATERAL_OFFSETS[idx]
    end
  end

  -- If everything is blocked, pick the path that goes furthest before the first hit.
  local hitIdx  = navigation_pathsBlockedSampleIndex[carIndex]
  local bestIdx, bestSafeSamples = nil, -1
  for i = 1, TOTAL_PATH_LATERAL_OFFSETS do
    local cnt = counts[i]
    if cnt and cnt > 0 then
      local safe = pathIsBlocked[i] and (hitIdx[i] or 2) or cnt
      if safe > bestSafeSamples then
        bestSafeSamples = safe
        bestIdx = i
      end
    end
  end
  if bestIdx then
    navigation_lastChosenPathIndex[carIndex] = bestIdx
    lines[#lines+1] = string_format("  chosen: idx=%d n=% .2f (reason: fallback, furthest safe samples = %d)", bestIdx, PATH_LATERAL_OFFSETS[bestIdx], bestSafeSamples)
    traceDecision(lines)
    return PATH_LATERAL_OFFSETS[bestIdx]
  end

  -- No data yet (calculatePath likely not called).
  lines[#lines+1] = "  chosen: none (reason: no counts yet)"
  traceDecision(lines)
  return nil
  --]====]
end

-- Convenience: build paths and immediately choose the best lateral offset in one call.
-- This avoids calling two public functions from the caller each frame and keeps state consistent.
-- Returns normalized lateral offset or nil if data is not ready.
function Pathfinding.calculatePathAndGetBestLateralOffset(sortedCarsList, sortedCarsListIndex)
  local car = sortedCarsList[sortedCarsListIndex]
  if not car then return nil end

  calculatePath(sortedCarsList, sortedCarsListIndex)
  return getBestLateralOffset(car.index)
end

return Pathfinding
