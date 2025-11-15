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

-- Make paths split to the sides much earlier (for tight manoeuvres) without changing length:
-- We reach full lateral target by this forward distance (meters), with an ease-out power curve.
local splitReachMeters        = 12.0     -- distance at which lateral offset reaches 100%
local lateralSplitExponent    = 2.2      -- >1: earlier split; =1: linear; <1: later split

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
local nominalTrackLengthMeters = RaceTrackManager.getTrackLengthMeters()
local function metersToProgress(meters)
  return meters / nominalTrackLengthMeters
end

-- =========================
-- Data-oriented containers
-- =========================

-- PATHS ARE MODULE-WIDE (not per-car) so you can expand/reduce them without extra memory per car.
-- Modify this list to add/remove paths. All code below adapts automatically.
---@type table<integer,number>
local PATHS = { -1.0, -0.75, -0.5, 0.0, 0.5, 0.75, 1.0 }

---@type table<integer,string>
local navigation_anchorText = {}

---@type table<integer,vec3>
local navigation_anchorWorld = {}

---@type table<integer,integer|nil>
local navigation_lastChosenPathIndex = {}

---@type table<integer,table<integer,integer>>  -- per-car array of counts per path
local navigation_pathCount = {}

---@type table<integer,table<integer,boolean>>  -- per-car array of blocked flags per path
local navigation_pathBlocked = {}

---@type table<integer,table<integer,integer|nil>> -- per-car array of hit sample indices per path
local navigation_pathHitIndex = {}

---@type table<integer,table<integer,integer|nil>> -- per-car array of hit opponent indices per path
local navigation_pathHitOpponentIndex = {}

---@type table<integer,table<integer,vec3|nil>> -- per-car array of hit world positions per path
local navigation_pathHitWorld = {}

---@type table<integer,table<integer,table>>    -- per-car array of lists of sampled points per path
local navigation_pathPoints = {}

-- Ensure per-car arrays exist and match the number of configured paths.
local function ensureCarArrays(carIndex)
  local needed = #PATHS

  local counts = navigation_pathCount[carIndex]
  if not counts or #counts ~= needed then
    counts = {}
    local blocked, hitIdx, hitOpp, hitPos, points = {}, {}, {}, {}, {}
    for i = 1, needed do
      counts[i] = 0
      blocked[i] = false
      hitIdx[i] = nil
      hitOpp[i] = nil
      hitPos[i] = nil
      points[i] = {}
    end
    navigation_pathCount[carIndex] = counts
    navigation_pathBlocked[carIndex] = blocked
    navigation_pathHitIndex[carIndex] = hitIdx
    navigation_pathHitOpponentIndex[carIndex] = hitOpp
    navigation_pathHitWorld[carIndex] = hitPos
    navigation_pathPoints[carIndex] = points
  end

  navigation_anchorText[carIndex] = navigation_anchorText[carIndex] or ""
  -- keep sticky index if present; if it exceeds path count after a config change, drop it
  local lastIdx = navigation_lastChosenPathIndex[carIndex]
  if lastIdx and (lastIdx < 1 or lastIdx > needed) then
    navigation_lastChosenPathIndex[carIndex] = nil
  end
end

-- Public: build simple paths radiating from the front of the car to lateral targets.
-- Each path starts at the anchor point and smoothly interpolates current offset → target offset.
-- NOTE: We no longer gather opponents ourselves. Pass in the globally prepared sorted list.
--       The list is sorted so that index-1 is the car in front, index+1 is behind.
local calculatePath = function(sortedCarsList, sortedCarsListIndex)
  local car = sortedCarsList[sortedCarsListIndex]
  if not car then return end

  local carIndex = car.index
  ensureCarArrays(carIndex)

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

  navigation_anchorWorld[carIndex] = anchorWorld
  navigation_anchorText[carIndex]  = string.format("z=%.4f  n=%.3f  v=%.1f m/s", currentProgressZ, currentOffsetN, carSpeedMps)

  -- Precompute step sizes.
  local totalForwardProgress = metersToProgress(forwardDistanceMeters)
  local stepCount = math.max(2, numberOfPathSamples)
  local stepZ = totalForwardProgress / (stepCount - 1)

  -- Precompute inverse of progress needed to reach full lateral offset by splitReachMeters.
  local splitReachProgress = metersToProgress(splitReachMeters)
  local invSplitReachProgress = (splitReachProgress > 0.0) and (1.0 / splitReachProgress) or 1e9

  -- Generate paths (count adapts to navigation_pathOffsetN length).
  local offsets = PATHS
  local counts  = navigation_pathCount[carIndex]
  local blocked = navigation_pathBlocked[carIndex]
  local hitIdx  = navigation_pathHitIndex[carIndex]
  local hitOpp  = navigation_pathHitOpponentIndex[carIndex]
  local hitPos  = navigation_pathHitWorld[carIndex]
  local points  = navigation_pathPoints[carIndex]

  -- For minimal work, only consider cars AHEAD of the current one in the sorted list.
  -- (sortedCarsListIndex-1 down to 1). Cars behind can’t block our forward samples.
  local firstAheadIndex = (sortedCarsListIndex or 2) - 1

  for p = 1, #offsets do
    local targetOffsetN = math.max(-maxAbsOffsetNormalized, math.min(maxAbsOffsetNormalized, offsets[p]))

    -- Clear previous samples/meta (reuse tables).
    local pts = points[p]
    for i = 1, #pts do pts[i] = nil end
    counts[p] = 0
    blocked[p] = false
    hitIdx[p] = nil
    hitPos[p] = nil
    hitOpp[p] = nil

    -- Sample along the road: linearly progress forward, but move laterally so that
    -- we hit the target offset by `splitReachMeters` (using an ease-out curve).
    counts[p] = 1
    pts[1] = anchorWorld

    for i = 2, stepCount do
      local progressDelta = (i - 1) * stepZ
      local tLatLinear = math.min(1.0, progressDelta * invSplitReachProgress)
      local tLat = easeOutPow01(tLatLinear, lateralSplitExponent)

      local sampleZ = wrap01(anchorZ + (i - 1) * stepZ)
      local sampleN = currentOffsetN + (targetOffsetN - currentOffsetN) * tLat
      local world   = ac.trackCoordinateToWorld(vec3(sampleN, 0.0, sampleZ))

      counts[p] = counts[p] + 1
      pts[counts[p]] = world

      -- --- Minimal collider detection (only what’s needed) -------------------
      if not blocked[p] and firstAheadIndex >= 1 then
        local wx, wy, wz = world.x, world.y, world.z

        -- Check cars in front only; early-exit on first hit.
        for idx = firstAheadIndex, 1, -1 do
          local opp = sortedCarsList[idx]
          -- Defensive: ensure object exists and is not self.
          if opp and opp.index ~= carIndex then
            local op = opp.position
            -- Quick distance gate to skip far-away cars (using world space).
            -- We don’t need a super-precise gate here; this is just to avoid most checks.
            local dx = op.x - wx
            local dy = op.y - wy
            local dz = op.z - wz
            local d2 = dx*dx + dy*dy + dz*dz
            if d2 <= combinedCollisionRadius2 then
              blocked[p] = true
              hitIdx[p] = i
              hitPos[p] = world
              hitOpp[p] = opp.index
              break
            end
          end
        end
      end
      -- ----------------------------------------------------------------------
    end

    log("[PF] car=%d path[%d] targetN=%.2f samples=%d blocked=%s",
      carIndex, p, targetOffsetN, counts[p], tostring(blocked[p]))
  end
end

-- Public: draw the paths like in the sketch: a fan from the car front with labels.
function Pathfinding.drawPaths(carIndex)
  local anchorWorld = navigation_anchorWorld[carIndex]
  if not anchorWorld then return end

  -- Draw anchor (small pole and label).
  render.debugSphere(anchorWorld, 0.12, colAnchor)
  render.debugText(anchorWorld + vec3(0, 0.35, 0), navigation_anchorText[carIndex])

  -- Draw each path:
  --   • Clear path → thin green polyline.
  --   • Blocked path → red polyline and a highlighted sphere at the first hit sample.
  local offsets = PATHS
  local counts  = navigation_pathCount[carIndex]
  local blocked = navigation_pathBlocked[carIndex]
  local hitIdx  = navigation_pathHitIndex[carIndex]
  local hitOpp  = navigation_pathHitOpponentIndex[carIndex]
  local hitPos  = navigation_pathHitWorld[carIndex]
  local points  = navigation_pathPoints[carIndex]

  for p = 1, #offsets do
    local cnt = counts[p]
    if cnt and cnt >= 2 then
      local colLine = blocked[p] and colLineBlocked or colLineClear
      local pts = points[p]

      -- Polyline
      for i = 1, cnt - 1 do
        render.debugLine(pts[i], pts[i + 1], colLine)
      end

      -- Sample markers
      for i = 1, cnt do
        local r = (i == 2) and 0.16 or 0.10
        render.debugSphere(pts[i], r, colPoint)
      end

      -- End label with the associated normalized offset value (+ blocked flag)
      local endPos = pts[cnt]
      if endPos then
        local label = string.format("%.2f", offsets[p])
        if blocked[p] then label = label .. " (blocked)" end
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
      if blocked[p] and hitPos[p] then
        render.debugSphere(hitPos[p], 0.28, colPointHit)
        if hitOpp[p] ~= nil then
          render.debugText(hitPos[p] + vec3(0, 0.45, 0),
            string.format("car#%d", hitOpp[p]), colLabel)
        end
      end
    end
  end
end

-- Public: return the lateral offset (normalized) associated with the “best” path for a car.
-- “Best” here = first clear path by preference (center-most first, then bias to right on ties).
-- Sticky behavior: if previously chosen path is still clear, keep it to avoid wobbling.
-- If all paths are blocked, returns the one that gets the furthest before the first hit.
local getBestLateralOffset = function(carIndex)
  local offsets = PATHS
  local counts  = navigation_pathCount[carIndex]
  local blocked = navigation_pathBlocked[carIndex]

  -- Compute dynamic “center” index (closest to 0, prefer positive on tie).
  local centerIdx, minAbs = 1, math.huge
  for i = 1, #offsets do
    local a = math.abs(offsets[i])
    if a < minAbs or (a == minAbs and offsets[i] > offsets[centerIdx]) then
      centerIdx, minAbs = i, a
    end
  end

  -- If all paths are present and NONE are blocked, default to center path.
  do
    local haveAll, allClear = true, true
    for i = 1, #offsets do
      if not (counts[i] and counts[i] > 0) then haveAll = false break end
      if blocked[i] then allClear = false break end
    end
    if haveAll and allClear then
      navigation_lastChosenPathIndex[carIndex] = centerIdx
      log("[PF] bestOffset car=%d all-clear -> center idx=%d n=%.2f", carIndex, centerIdx, offsets[centerIdx])
      return offsets[centerIdx]
    end
  end

  -- Sticky choice: if last chosen path still exists and is not blocked, keep it.
  local lastIdx = navigation_lastChosenPathIndex[carIndex]
  if lastIdx and counts[lastIdx] and counts[lastIdx] > 0 and not blocked[lastIdx] then
    log("[PF] bestOffset car=%d STICK idx=%d -> n=%.2f", carIndex, lastIdx, offsets[lastIdx])
    return offsets[lastIdx]
  end

  -- Build dynamic preference order:
  -- sort indices by |offset| ascending, and for equal |offset| prefer positive over negative.
  local pref = {}
  for i = 1, #offsets do pref[i] = i end
  table.sort(pref, function(a, b)
    local aa, bb = math.abs(offsets[a]), math.abs(offsets[b])
    if aa == bb then return offsets[a] > offsets[b] else return aa < bb end
  end)

  -- First, try to pick the first CLEAR path by preference.
  for _, idx in ipairs(pref) do
    if counts[idx] and counts[idx] > 0 and not blocked[idx] then
      navigation_lastChosenPathIndex[carIndex] = idx
      log("[PF] bestOffset car=%d clear path idx=%d -> n=%.2f", carIndex, idx, offsets[idx])
      return offsets[idx]
    end
  end

  -- If everything is blocked, pick the path that goes furthest before the first hit.
  local hitIdx  = navigation_pathHitIndex[carIndex]
  local bestIdx, bestSafeSamples = nil, -1
  for i = 1, #offsets do
    local cnt = counts[i]
    if cnt and cnt > 0 then
      local safe = blocked[i] and (hitIdx[i] or 2) or cnt
      if safe > bestSafeSamples then
        bestSafeSamples = safe
        bestIdx = i
      end
    end
  end
  if bestIdx then
    navigation_lastChosenPathIndex[carIndex] = bestIdx
    log("[PF] bestOffset car=%d fallback idx=%d (safeSamples=%d) -> n=%.2f",
      carIndex, bestIdx, bestSafeSamples, offsets[bestIdx])
    return offsets[bestIdx]
  end

  -- No data yet (calculatePath likely not called).
  return nil
end

-- Convenience: build paths and immediately choose the best lateral offset in one call.
-- This avoids calling two public functions from the caller each frame and keeps state consistent.
-- Returns normalized lateral offset or nil if data is not ready.
function Pathfinding.calculatePathAndGetBestLateralOffset(sortedCarsList, sortedCarsListIndex)
  local car = sortedCarsList and sortedCarsList[sortedCarsListIndex]
  if not car then return nil end

  calculatePath(sortedCarsList, sortedCarsListIndex)
  return getBestLateralOffset(car.index)
end

return Pathfinding