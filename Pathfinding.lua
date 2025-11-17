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


-- Toggle logs without changing call sites (leave here so it can be switched off easily).
local LOG_ENABLED = true
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

-- PATHS ARE MODULE-WIDE (not per-car) so you can expand/reduce them without extra memory per car.
-- Modify this list to add/remove paths. All code below adapts automatically.
---@type table<integer,number>
local PATH_LATERAL_OFFSETS = { -1.0, -0.75, -0.5, 0.0, 0.5, 0.75, 1.0 }
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
---@type table<integer,table<integer,integer|nil>>
local navigation_pathsBlockedSampleIndex = {}

-- per-car array of hit other cars indices per path
---@type table<integer,table<integer,integer|nil>>
local navigation_pathsBlockedOtherCarsIndex = {}

-- per-car array of hit world positions per path
---@type table<integer,table<integer,vec3|nil>>
local navigation_pathsBlockedSampleWorldPosition = {}

-- per-car array of lists of sampled points per path
---@type table<integer,table<integer,table<integer,vec3>>>
local navigation_pathsSamplesWorldPositions = {}

-- Ensure per-car arrays exist and match the number of configured paths.
local function ensureCarArrays(carIndex)
  local pathsTotalSamples = navigation_pathsTotalSamples[carIndex]
  if not pathsTotalSamples or #pathsTotalSamples ~= TOTAL_PATH_LATERAL_OFFSETS then
    pathsTotalSamples = {}
    local blocked, hitIdx, hitOpp, hitPos, points = {}, {}, {}, {}, {}
    for i = 1, TOTAL_PATH_LATERAL_OFFSETS do
      pathsTotalSamples[i] = 0
      blocked[i] = false
      hitIdx[i] = nil
      hitOpp[i] = nil
      hitPos[i] = nil
      points[i] = {}
    end
    navigation_pathsTotalSamples[carIndex] = pathsTotalSamples
    navigation_pathsIsBlocked[carIndex] = blocked
    navigation_pathsBlockedSampleIndex[carIndex] = hitIdx
    navigation_pathsBlockedOtherCarsIndex[carIndex] = hitOpp
    navigation_pathsBlockedSampleWorldPosition[carIndex] = hitPos
    navigation_pathsSamplesWorldPositions[carIndex] = points
  end

  navigation_anchorText[carIndex] = navigation_anchorText[carIndex] or ""

  -- TODO: Andreas: investigate why we need this part:
  -- keep sticky index if present; if it exceeds path count after a config change, drop it
  local lastChosenPathIndex = navigation_lastChosenPathIndex[carIndex]
  if lastChosenPathIndex and (lastChosenPathIndex < 1 or lastChosenPathIndex > TOTAL_PATH_LATERAL_OFFSETS) then
    navigation_lastChosenPathIndex[carIndex] = nil
  end
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
  local anchorWorldPosition = ac_trackCoordinateToWorld(VecPool_getTempVec3(currentOffsetN, 0.0, anchorZ))

  navigation_anchorWorldPosition[carIndex] = anchorWorldPosition
  navigation_anchorText[carIndex]  = string_format("spline=%.4f  n=%.3f  speed=%.1f km/h", currentProgressZ, currentOffsetN, carSpeedKmh)

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
  local pathsBlockedOtherCarsIndex  = navigation_pathsBlockedOtherCarsIndex[carIndex]
  local pathsBlockedSampleWorldPosition  = navigation_pathsBlockedSampleWorldPosition[carIndex]
  local pathsSamplesWorldPositions  = navigation_pathsSamplesWorldPositions[carIndex]

  -- For minimal work, only consider cars AHEAD of the current one in the sorted list.
  -- (sortedCarsListIndex-1 down to 1). Cars behind can’t block our forward samples.
  local firstAheadSortedCarListIndex = (sortedCarsListIndex or 2) - 1

  local approxCarRadiusMeters   = storage_PathFinding.approxCarRadiusMeters
  local safetyMarginMeters      = storage_PathFinding.safetyMarginMeters
  local combinedCollisionRadius = (approxCarRadiusMeters * 2.0) + safetyMarginMeters
  local combinedCollisionRadius2 = combinedCollisionRadius * combinedCollisionRadius

  local lateralSplitExponent = storage_PathFinding.lateralSplitExponent

  -- For each path lateral target offset, build each path's samples and check for collisions after creating the samples
  for pathIndex = 1, TOTAL_PATH_LATERAL_OFFSETS do
    local targetOffsetN = math_max(-maxAbsOffsetNormalized, math_min(maxAbsOffsetNormalized, PATH_LATERAL_OFFSETS[pathIndex]))

    -- Clear previous samples/meta (reuse tables).
    local pathSamplesWorldPositions = pathsSamplesWorldPositions[pathIndex]
    for i = 1, #pathSamplesWorldPositions do
      pathSamplesWorldPositions[i] = nil
    end
    pathsTotalSamples[pathIndex] = 0
    pathsIsBlocked[pathIndex] = false
    pathsBlockedSampleIndex[pathIndex] = nil
    pathsBlockedSampleWorldPosition[pathIndex] = nil
    pathsBlockedOtherCarsIndex[pathIndex] = nil

    -- Sample along the road: linearly progress forward, but move laterally so that we hit the target offset by `splitReachMeters` (using an ease-out curve).

    -- Initialize the sample count (first sample is the anchor).
    pathsTotalSamples[pathIndex] = 1

    -- First sample is always the anchor.
    pathSamplesWorldPositions[1] = anchorWorldPosition

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
        local worldPositionX, worldPositionY, worldPositionZ = sampleWorldPosition.x, sampleWorldPosition.y, sampleWorldPosition.z

        -- Check cars in front only; early-exit on first hit.
        for otherCarSortedCarsListIndex = firstAheadSortedCarListIndex, 1, -1 do
          local otherCar = sortedCarsList[otherCarSortedCarsListIndex]
          
          -- TODO: Andreas: theoratically this index check is not needed since we only check cars ahead
          if otherCar and otherCar.index ~= carIndex then
            -- Keep original quick gate (sphere) for speed; early exit on first overlap:
            local otherCarPosition = otherCar.position
            local dx = otherCarPosition.x - worldPositionX
            local dy = otherCarPosition.y - worldPositionY
            local dz = otherCarPosition.z - worldPositionZ
            local d2 = dx*dx + dy*dy + dz*dz
            
            -- check if this sample is colliding with the other car
            if d2 <= combinedCollisionRadius2 then
              -- mark the path as blocked
              pathsIsBlocked[pathIndex] = true
              pathsBlockedSampleIndex[pathIndex] = currentSampleIndex
              pathsBlockedSampleWorldPosition[pathIndex] = sampleWorldPosition
              pathsBlockedOtherCarsIndex[pathIndex] = otherCar.index
              break -- break out of the for loop over other cars since we found a blocked hit for this path so we don't need to check for other cars
            end
          end
        end -- end of other cars loop
      end
      -- ----------------------------------------------------------------------
    end -- end of samples loop

    log("[PF] car=%d path[%d] targetN=%.2f samples=%d blocked=%s", carIndex, pathIndex, targetOffsetN, pathsTotalSamples[pathIndex], tostring(pathsIsBlocked[pathIndex]))
  end -- end of paths loop
end

-- Public: draw the paths like in the sketch: a fan from the car front with labels.
function Pathfinding.drawPaths(carIndex)
  local anchorWorldPosition = navigation_anchorWorldPosition[carIndex]
  if not anchorWorldPosition then return end

  -- Draw anchor (small pole and label).
  render_debugSphere(anchorWorldPosition, 0.12, colAnchor)
  render_debugText(anchorWorldPosition + VecPool_getTempVec3(0, 0.35, 0), navigation_anchorText[carIndex])

  -- Draw each path:
  --   • Clear path → thin green polyline.
  --   • Blocked path → red polyline and a highlighted sphere at the first hit sample.
  local pathsTotalSamples  = navigation_pathsTotalSamples[carIndex]
  local pathsIsBlocked = navigation_pathsIsBlocked[carIndex]
  local pathsHitsOtherCarsIndex  = navigation_pathsBlockedOtherCarsIndex[carIndex]
  local pathsHitSampleWorldPosition  = navigation_pathsBlockedSampleWorldPosition[carIndex]
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
      if pathsIsBlocked[pathIndex] and pathsHitSampleWorldPosition[pathIndex] then
        render_debugSphere(pathsHitSampleWorldPosition[pathIndex], 0.28, colPointHit)
        if pathsHitsOtherCarsIndex[pathIndex] ~= nil then
          render_debugText(pathsHitSampleWorldPosition[pathIndex] + VecPool_getTempVec3(0, 0.45, 0), string_format("car#%d", pathsHitsOtherCarsIndex[pathIndex]), colLabel)
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
      local hitO = navigation_pathsBlockedOtherCarsIndex[carIndex] and navigation_pathsBlockedOtherCarsIndex[carIndex][i]
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
    for i = 1, TOTAL_PATH_LATERAL_OFFSETS do if PATH_LATERAL_OFFSETS[i] == val then table_insert(order, i) return end end
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
