local CollisionAvoidanceManager = {}

-- ============================== Internal state ==============================

-- Per-car persistent state (no allocations in hot path)
local _stateByCar = {}  -- [carIndex] = { last_d = 0, last_norm = 0, lastAvoidCarIndex = -1 }

-- Reused scratch (low-GC): DP buffers and horizon samples
local _sNodes = {}          -- progress samples (0..1) along centerline
local _dp     = {}          -- dynamic programming cost rows
local _parent = {}          -- backpointers
local _costAtK1 = {}        -- cost per lateral bin at first step (for debug bars)

-- Debug toggles & per-car last frame snapshot (for drawing outside hot path)
local _debugEnabled = true
local _dbg = {}             -- [carIndex] = { sNodes, dSamples, pathIdxByK, obstacles = { {s,d,idx}... }, chosenK1D, costsK1, trackHalf, edgeMargin }

-- Utils
local function clamp(x, a, b) if x < a then return a elseif x > b then return x and b or b end end
local function wrap01Signed(ds) if ds > 0.5 then return ds - 1.0 elseif ds < -0.5 then return ds + 1.0 else return ds end end

---@param carIndex integer
---@return table
local function getState(carIndex)
  local s = _stateByCar[carIndex]
  if not s then s = { last_d = 0.0, last_norm = 0.0, lastAvoidCarIndex = -1 } _stateByCar[carIndex] = s end
  return s
end

-- ============================== Public API =================================

--- Enable/disable gizmo drawing (when disabled, hot path does zero extra work).
--- @param enabled boolean
function CollisionAvoidanceManager.setDebugEnabled(enabled)
  _debugEnabled = not not enabled
end

--- Get last debug snapshot for a car (useful for custom UIs/logs).
--- @param carIndex integer
--- @return table|nil snapshot
function CollisionAvoidanceManager.getLastDebug(carIndex)
  return _dbg[carIndex]
end

--------------------------------------------------------------------------------
--- Compute normalized AISpline offset using a **Frenet corridor** lattice.
--- We discretize forward progress `s` along the track centerline (K slices) and
--- sample a few lateral offsets `d` (in meters) per slice. A tiny dynamic
--- program minimizes:
---   cost = obstacle_clearance + smoothness + track_bounds + small_center_bias.
--- We apply only the first step (receding horizon) and rate-limit `d` per frame.
---
--- Lateral positions of stopped cars are obtained via `ac.worldCoordinateToTrack`,
--- using `.x` (normalized in [-1, 1]) then scaled by `trackHalf` to meters —
--- this is CSP’s canonical track-space mapping for lateral position and progress. :contentReference[oaicite:0]{index=0}
---
--- @param egoCarIndex        integer     -- AI car index (0-based).
--- @param stoppedCarIndices  integer[]   -- Indices of cars considered stopped/hazards.
--- @param dtSeconds          number      -- Frame dt (used for slew).
--- @param cfg                table|nil   -- Optional tuning:
---        .horizon_meters (number)  default 45.0
---        .steps          (integer) default 6
---        .d_samples      (number[]) default {-3,-1.5,0,1.5,3}  -- meters
---        .obstacle_sigma (number)  default 1.2
---        .weight_clear   (number)  default 1.6
---        .weight_smooth  (number)  default 2.0
---        .weight_track   (number)  default 1.0
---        .center_bias    (number)  default 0.2
---        .track_half     (number)  default 7.0
---        .edge_margin    (number)  default 0.7
---        .max_d_rate     (number)  default 6.0      -- m/s slew limit
---        .bias_from_obs  (number)  default 0.4
---
--- @return number normOffset       -- [-1, 1] value for physics.setAISplineOffset()
--- @return integer avoidCarIndex   -- stopped car index most affecting first-step choice, or -1
--------------------------------------------------------------------------------
function CollisionAvoidanceManager.computeDesiredLateralOffset(egoCarIndex, stoppedCarIndices, dtSeconds, cfg)
  local ego = ac.getCar(egoCarIndex)
  if not ego then return 0.0, -1 end

  -- Resolve config (locals help JIT)
  cfg = cfg or {}
  local horizonMeters = cfg.horizon_meters or 45.0
  local steps         = cfg.steps or 6
  local dSamples      = cfg.d_samples or {-3,-1.5,0,1.5,3}
  local obstacleSigma = cfg.obstacle_sigma or 1.2
  local wClear        = cfg.weight_clear or 1.6
  local wSmooth       = cfg.weight_smooth or 2.0
  local wTrack        = cfg.weight_track or 1.0
  local centerBias    = cfg.center_bias or 0.2
  local trackHalf     = cfg.track_half or 7.0
  local edgeMargin    = cfg.edge_margin or 0.7
  local maxDRate      = cfg.max_d_rate or 6.0
  local biasFromObs   = cfg.bias_from_obs or 0.4

  -- Track progress and meter spacing (Frenet s)
  local s0 = ac.worldCoordinateToTrackProgress(ego.position) or 0.0
  
  local trackLengthM = RaceTrackManager.getTrackLengthMeters()
  local invL = 1.0 / trackLengthM

  for k = 1, steps do
    local s = s0 + (horizonMeters * (k / steps)) * invL
    if s >= 1.0 then s = s - 1.0 end
    _sNodes[k] = s
  end

  -- Per-car history
  local S = getState(egoCarIndex)
  local last_d = S.last_d

  -- Preprocess obstacles to Frenet (s, d in meters) using CSP’s track coords
  local obsS, obsD, obsIdx = {}, {}, {}
  local obsCount = 0
  local sWindowN = (horizonMeters * invL) * 1.1

  for i = 1, (stoppedCarIndices and #stoppedCarIndices or 0) do
    local idx = stoppedCarIndices[i]
    if idx ~= egoCarIndex then
      local c = ac.getCar(idx)
      if c then
        local tc = ac.worldCoordinateToTrack(c.position)       -- .x in [-1,1], .z progress
        obsCount = obsCount + 1
        obsS[obsCount]   = tc.z
        obsIdx[obsCount] = idx
        obsD[obsCount]   = tc.x * trackHalf                     -- convert to meters
      end
    end
  end

  -- Prepare DP buffers
  local dCount = #dSamples
  for k = 1, steps do
    local row = _dp[k];     if not row then row = {}; _dp[k] = row end
    local par = _parent[k]; if not par then par = {}; _parent[k] = par end
    for i = 1, dCount do row[i] = 0.0; par[i] = 0 end
  end
  for i = 1, dCount do _costAtK1[i] = 0.0 end

  local invTwoSigma2 = 1.0 / (2.0 * obstacleSigma * obstacleSigma)

  -- Track which obstacle pulls the first step most for each i
  local k1BestObsIdxPerI = {}   -- [i] -> carIndex or -1
  for i=1,dCount do k1BestObsIdxPerI[i] = -1 end

  -- DP over the Frenet corridor lattice
  for k = 1, steps do
    local sK = _sNodes[k]
    local rowK, parK = _dp[k], _parent[k]
    local prevRow = (k > 1) and _dp[k-1] or nil

    for i = 1, dCount do
      local d = dSamples[i]

      -- Soft track bound penalty
      local absD = (d >= 0 and d) or -d
      local edgePen
      if absD > (trackHalf - edgeMargin) then
        local over = absD - (trackHalf - edgeMargin)
        edgePen = wTrack * (over * over)
      else
        local ratio = absD / trackHalf
        edgePen = wTrack * 0.1 * (ratio * ratio)
      end

      -- Obstacle clearance and side bias
      local clearPen = 0.0
      local strongestPull = -1
      local strongestPullMag = 0.0

      for o = 1, obsCount do
        local ds = wrap01Signed(obsS[o] - sK)
        if ds >= -sWindowN and ds <= sWindowN then
          local lateral = d - obsD[o]
          local pen = wClear * math.exp(-(lateral * lateral) * invTwoSigma2)
          clearPen = clearPen + pen
          clearPen = clearPen - (biasFromObs * (lateral / trackHalf))

          if k == 1 then
            if pen > strongestPullMag then
              strongestPullMag = pen
              strongestPull = obsIdx[o]
            end
          end
        end
      end

      if k == 1 then k1BestObsIdxPerI[i] = strongestPull end

      local centerPen = centerBias * (d * d)
      local stageCost = edgePen + clearPen + centerPen

      if k == 1 then
        local smoothFirst = wSmooth * (d - last_d) * (d - last_d)
        local cst = stageCost + smoothFirst
        rowK[i] = cst
        parK[i] = 0
        _costAtK1[i] = cst
      else
        local best, bestJ = 1e18, 0
        for j = 1, dCount do
          local dPrev = dSamples[j]
          local smooth = wSmooth * (d - dPrev) * (d - dPrev)
          local cst = prevRow[j] + stageCost + smooth
          if cst < best then best = cst; bestJ = j end
        end
        rowK[i] = best
        parK[i] = bestJ
      end
    end
  end

  -- Backtrack best path and take first-step decision
  local lastRow = _dp[steps]
  local bestI, bestCost = 1, lastRow[1]
  for i = 2, dCount do local cst = lastRow[i]; if cst < bestCost then bestCost = cst; bestI = i end end
  local idx = bestI
  for k = steps, 2, -1 do idx = _parent[k][idx] end
  local dStar = dSamples[idx]

  local avoidCarIndex = k1BestObsIdxPerI[idx] or -1
  if not avoidCarIndex then avoidCarIndex = -1 end

  -- Rate-limit in meters, then normalize to [-1, 1]
  local dt = (dtSeconds and dtSeconds > 0) and dtSeconds or 1/120
  local maxStep = maxDRate * dt
  local delta = dStar - last_d
  if delta >  maxStep then delta =  maxStep
  elseif delta < -maxStep then delta = -maxStep end
  local desired_d = last_d + delta

  local norm = desired_d / trackHalf
  if norm < -1.0 then norm = -1.0 elseif norm > 1.0 then norm = 1.0 end

  -- Persist
  S.last_d = desired_d
  S.last_norm = norm
  S.lastAvoidCarIndex = avoidCarIndex

  -- Store snapshot for debug draw (cheap; reuses tables)
  if _debugEnabled then
    local snap = _dbg[egoCarIndex]; if not snap then snap = {} _dbg[egoCarIndex] = snap end
    snap.sNodes, snap.dSamples = {}, {}
    for k=1,steps do snap.sNodes[k] = _sNodes[k] end
    for i=1,dCount do snap.dSamples[i] = dSamples[i] end
    local pathIdxByK = {}
    local ii = bestI
    for k = steps, 1, -1 do
      pathIdxByK[k] = ii
      ii = (k > 1) and _parent[k][ii] or ii
    end
    snap.pathIdxByK = pathIdxByK
    local obs = {}
    for o=1,obsCount do obs[o] = { s = obsS[o], d = obsD[o], idx = obsIdx[o] } end
    snap.obstacles = obs
    snap.costsK1 = {}
    for i=1,dCount do snap.costsK1[i] = _costAtK1[i] end
    snap.chosenK1D = dSamples[idx]
    snap.trackHalf = trackHalf
    snap.edgeMargin = edgeMargin
  end

  return norm, avoidCarIndex
end

--------------------------------------------------------------------------------
--- Draw debug gizmos for a given car:
--- • Green rails = each lateral sample d across the s-slices (corridor lattice).
--- • Blue polyline with arrows = chosen path (first step is applied this frame).
--- • Red posts = stopped cars projected into Frenet (s,d).
--- • Yellow bars at first slice = per-d costs (blue-topped is the chosen bin).
---
--- Uses CSP helpers (debug arrows, TrackPaint) to draw in world-space. :contentReference[oaicite:1]{index=1}
---
--- @param carIndex integer
function CollisionAvoidanceManager.debugDraw(carIndex)
  if not _debugEnabled then return end
  local snap = _dbg[carIndex]
  if not snap then return end

  if not CollisionAvoidanceManager._paint then
    CollisionAvoidanceManager._paint = ac.TrackPaint()
    CollisionAvoidanceManager._paint.paddingSize = 0.02
    CollisionAvoidanceManager._paint.defaultThickness = 0.06
  end
  local paint = CollisionAvoidanceManager._paint
  paint:reset()

  local sNodes = snap.sNodes
  local dSamples = snap.dSamples
  local steps = #sNodes
  local dCount = #dSamples

  -- Corridors (green)
  for i=1,dCount do
    local prevW = nil
    for k=1,steps do
      local s = sNodes[k]
      local w = ac.trackProgressToWorldCoordinate(s)
      local side = ac.getCar(carIndex).side
      local p = vec3(w.x + side.x * dSamples[i], w.y + side.y * dSamples[i], w.z + side.z * dSamples[i])
      if prevW then paint:line(prevW, p, rgbm(0,1,0,1), 0.04) end
      prevW = p
    end
  end

  -- Chosen path (blue + arrows)
  local prevP = nil
  for k=1,steps do
    local s = sNodes[k]
    local w = ac.trackProgressToWorldCoordinate(s)
    local side = ac.getCar(carIndex).side
    local d = dSamples[snap.pathIdxByK[k]]
    local p = vec3(w.x + side.x * d, w.y + side.y * d, w.z + side.z * d)
    if prevP then
      paint:line(prevP, p, rgbm(0.2,0.4,1,1), 0.08)
      render.debugArrow(prevP, p, 0.4, rgbm(0.2,0.4,1,1))
    end
    prevP = p
  end

  -- Obstacles (red posts)
  for _,o in ipairs(snap.obstacles) do
    local w = ac.trackProgressToWorldCoordinate(o.s)
    local side = ac.getCar(carIndex).side
    local p = vec3(w.x + side.x * o.d, w.y + side.y * o.d, w.z + side.z * o.d)
    paint:line(p + vec3(0,0.01,0), p + vec3(0,0.6,0), rgbm(1,0,0,1), 0.06)
    paint:text("Consolas", string.format("#%d  d=%.2f", o.idx, o.d), p + vec3(0,0.65,0), 0.5, 0, rgbm(1,0.4,0.2,1))
  end

  -- First-slice cost bars (yellow; blue-topped is chosen)
  do
    local s = sNodes[1]
    local w = ac.trackProgressToWorldCoordinate(s)
    local side = ac.getCar(carIndex).side
    local maxC = 1e-6
    for i=1,dCount do if snap.costsK1[i] > maxC then maxC = snap.costsK1[i] end end
    for i=1,dCount do
      local d = dSamples[i]
      local base = vec3(w.x + side.x * d, w.y + side.y * d, w.z + side.z * d)
      local h = 0.5 * (snap.costsK1[i] / maxC)
      paint:line(base, base + vec3(0,h,0), rgbm(0.95,0.9,0.2,1), 0.04)
      if math.abs(d - snap.chosenK1D) < 1e-3 then
        paint:line(base, base + vec3(0,h+0.15,0), rgbm(0.2,0.6,1,1), 0.06)
      end
    end
  end
end

return CollisionAvoidanceManager
