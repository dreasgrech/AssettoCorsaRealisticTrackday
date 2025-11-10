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
local colOpponent    = rgbm(1.00, 0.30, 0.30, 0.55)   -- faint red disc for opponent markers

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

---@type table<integer,string>
local navigation_anchorText = {}

---@type table<integer,vec3>
local navigation_anchorWorld = {}

---@type table<integer,integer|nil>
local navigation_lastChosenPathIndex = {}

---@type table<integer,integer>
local navigation_opponentsCount = {}

---@type table<integer,table<integer,integer>>  -- per-car array of opponent indices
local navigation_opponentsIndex = {}

---@type table<integer,table<integer,vec3>>     -- per-car array of opponent positions
local navigation_opponentsPos = {}

---@type table<integer,table<integer,number>>   -- per-car array of 5 offsets
local navigation_pathOffsetN = {}

---@type table<integer,table<integer,integer>>  -- per-car array of 5 counts
local navigation_pathCount = {}

---@type table<integer,table<integer,boolean>>  -- per-car array of 5 blocked flags
local navigation_pathBlocked = {}

---@type table<integer,table<integer,integer|nil>> -- per-car array of 5 hit sample indices
local navigation_pathHitIndex = {}

---@type table<integer,table<integer,integer|nil>> -- per-car array of 5 hit opponent indices
local navigation_pathHitOpponentIndex = {}

---@type table<integer,table<integer,vec3|nil>> -- per-car array of 5 hit world positions
local navigation_pathHitWorld = {}

---@type table<integer,table<integer,table>>    -- per-car array of 5 lists of sampled points
local navigation_pathPoints = {}

-- Ensure per-car arrays exist (no allocations in hot loops besides point lists reuse).
local function ensureCarArrays(carIndex)
  if navigation_pathOffsetN[carIndex] then return end
  navigation_pathOffsetN[carIndex] = { -1.0, -0.5, 0.0, 0.5, 1.0 }
  navigation_pathCount[carIndex] = { 0, 0, 0, 0, 0 }
  navigation_pathBlocked[carIndex] = { false, false, false, false, false }
  navigation_pathHitIndex[carIndex] = { nil, nil, nil, nil, nil }
  navigation_pathHitOpponentIndex[carIndex] = { nil, nil, nil, nil, nil }
  navigation_pathHitWorld[carIndex] = { nil, nil, nil, nil, nil }
  navigation_pathPoints[carIndex] = { {}, {}, {}, {}, {} }

  navigation_anchorText[carIndex] = navigation_anchorText[carIndex] or ""
  navigation_opponentsIndex[carIndex] = navigation_opponentsIndex[carIndex] or {}
  navigation_opponentsPos[carIndex] = navigation_opponentsPos[carIndex] or {}
  navigation_opponentsCount[carIndex] = 0
  navigation_lastChosenPathIndex[carIndex] = navigation_lastChosenPathIndex[carIndex] or nil
end

-- Small utility: build a tiny list of opponent positions for cheap checks this frame.
-- We only cache the world position and index; nothing else is needed for this step.
local function collectOpponents(carIndex)
  local idxList = navigation_opponentsIndex[carIndex]
  local posList = navigation_opponentsPos[carIndex]
  local count = 0
  for _, c in ac.iterateCars() do
    if c and c.index ~= carIndex then
      count = count + 1
      idxList[count] = c.index
      posList[count] = c.position
    end
  end
  -- trim leftovers
  for i = count + 1, #idxList do idxList[i] = nil end
  for i = count + 1, #posList do posList[i] = nil end
  navigation_opponentsCount[carIndex] = count
  return count
end

-- Public: build five simple paths radiating from the front of the car to lateral targets.
-- Each path starts at the anchor point and smoothly interpolates current offset → target offset.
function Pathfinding.calculatePath(carIndex)
  local car = ac.getCar(carIndex)
  if not car or not ac.hasTrackSpline() then return end

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

  -- Cache opponents for this frame once (positions only).
  collectOpponents(carIndex)

  -- Precompute step sizes.
  local totalForwardProgress = metersToProgress(forwardDistanceMeters)
  local stepCount = math.max(2, numberOfPathSamples)
  local stepZ = totalForwardProgress / (stepCount - 1)

  -- Precompute inverse of progress needed to reach full lateral offset by splitReachMeters.
  local splitReachProgress = metersToProgress(splitReachMeters)
  local invSplitReachProgress = (splitReachProgress > 0.0) and (1.0 / splitReachProgress) or 1e9

  -- Generate the five paths.
  local offsets = navigation_pathOffsetN[carIndex]
  local counts  = navigation_pathCount[carIndex]
  local blocked = navigation_pathBlocked[carIndex]
  local hitIdx  = navigation_pathHitIndex[carIndex]
  local hitOpp  = navigation_pathHitOpponentIndex[carIndex]
  local hitPos  = navigation_pathHitWorld[carIndex]
  local points  = navigation_pathPoints[carIndex]

  local oppCount = navigation_opponentsCount[carIndex]
  local oppPos   = navigation_opponentsPos[carIndex]
  local oppIdx   = navigation_opponentsIndex[carIndex]

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
      if (not blocked[p]) and oppCount > 0 then
        local wx, wy, wz = world.x, world.y, world.z
        for oi = 1, oppCount do
          local op = oppPos[oi]
          local dx = op.x - wx
          local dy = op.y - wy
          local dz = op.z - wz
          local d2 = dx*dx + dy*dy + dz*dz
          if d2 <= combinedCollisionRadius2 then
            blocked[p] = true
            hitIdx[p] = i
            hitPos[p] = world
            hitOpp[p] = oppIdx[oi]
            break
          end
        end
      end
      -- ----------------------------------------------------------------------
    end

    log("[PF] car=%d path[%d] targetN=%.2f samples=%d blocked=%s",
      carIndex, p, targetOffsetN, counts[p], tostring(blocked[p]))
  end
end

-- Public: draw the five paths like in the sketch: a fan from the car front with labels.
function Pathfinding.drawPaths(carIndex)
  local anchorWorld = navigation_anchorWorld[carIndex]
  if not anchorWorld then return end

  -- Draw anchor (small pole and label).
  render.debugSphere(anchorWorld, 0.12, colAnchor)
  render.debugText(anchorWorld + vec3(0, 0.35, 0), navigation_anchorText[carIndex])

  -- Optionally show opponent discs we cached (very faint; helps to reason about hits).
  local oppCount = navigation_opponentsCount[carIndex] or 0
  local oppPos   = navigation_opponentsPos[carIndex]
  if oppCount > 0 and oppPos then
    for i = 1, oppCount do
      render.debugSphere(oppPos[i], approxCarRadiusMeters, colOpponent)
    end
  end

  -- Draw each path:
  --   • Clear path → thin green polyline.
  --   • Blocked path → red polyline and a highlighted sphere at the first hit sample.
  local offsets = navigation_pathOffsetN[carIndex]
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
        local label = string.format("%.1f", offsets[p])
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
-- “Best” here = first clear path by simple preference order (0, +0.5, -0.5, +1, -1).
-- Sticky behavior: if previously chosen path is still clear, keep it to avoid wobbling.
-- If all five are blocked, returns the one that gets the furthest before the first hit.
function Pathfinding.getBestLateralOffset(carIndex)
  ensureCarArrays(carIndex)

  local offsets = navigation_pathOffsetN[carIndex]
  local counts  = navigation_pathCount[carIndex]
  local blocked = navigation_pathBlocked[carIndex]

  -- If all paths are present and NONE are blocked, default to center (offset 0).
  do
    local haveAll, allClear = true, true
    for i = 1, #offsets do
      if not (counts[i] and counts[i] > 0) then haveAll = false break end
      if blocked[i] then allClear = false break end
    end
    if haveAll and allClear then
      navigation_lastChosenPathIndex[carIndex] = 3  -- center path index
      log("[PF] bestOffset car=%d all-clear -> center n=%.2f", carIndex, offsets[3])
      return offsets[3]
    end
  end

  -- Sticky choice: if last chosen path still exists and is not blocked, keep it.
  local lastIdx = navigation_lastChosenPathIndex[carIndex]
  if lastIdx and counts[lastIdx] and counts[lastIdx] > 0 and not blocked[lastIdx] then
    log("[PF] bestOffset car=%d STICK idx=%d -> n=%.2f", carIndex, lastIdx, offsets[lastIdx])
    return offsets[lastIdx]
  end

  -- Preference over the five stored paths:
  -- offsets = { -1.0, -0.5, 0.0, +0.5, +1.0 }
  -- prefer center, then slight right, slight left, full right, full left
  local preference = { 3, 4, 2, 5, 1 }

  -- First, try to pick the first CLEAR path by preference.
  for _, idx in ipairs(preference) do
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

return Pathfinding
