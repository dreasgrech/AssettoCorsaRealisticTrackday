local CollisionAvoidanceManager = {}

-- ============================== Internal state ==============================

-- Per-car persistent state (no allocations in hot path)
local _stateByCar = {}  -- [carIndex] = { last_d = 0, last_norm = 0, lastAvoidCarIndex = -1 }

-- Reused scratch (no GC): DP buffers and horizon samples
local _sNodes = {}          -- progress samples (0..1) along centerline
local _dp     = {}          -- dynamic programming cost rows
local _parent = {}          -- backpointers
local _costAtK1 = {}        -- cost per lateral bin at first step (for debug bars)

-- Debug toggles & per-car last frame snapshot (for drawing outside hot path)
local _debugEnabled = false
local _dbg = {}             -- [carIndex] = { sNodes, dSamples, pathIdxByK, obstacles = { {s,d,idx}... }, chosenK1D, costsK1, trackHalf, edgeMargin }

-- Utils
local function clamp(x, a, b) if x < a then return a elseif x > b then return b else return x end end
local function wrap01Signed(ds) if ds > 0.5 then return ds - 1.0 elseif ds < -0.5 then return ds + 1.0 else return ds end end

---@param carIndex integer
---@return table
local function getState(carIndex)
  local s = _stateByCar[carIndex]
  if not s then s = { last_d = 0.0, last_norm = 0.0, lastAvoidCarIndex = -1 } _stateByCar[carIndex] = s end
  return s
end

-- ============================== Public API =================================

--- Enable/disable gizmo drawing. When disabled, no extra work is done in hot path.
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
--- The corridor samples several lateral offsets `d` at a few lookahead `s`-slices
--- ahead of the ego car, then runs dynamic programming to minimize:
---   cost = obstacle_clearance + smoothness + track_bounds + small_center_bias.
---
--- Notes:
--- • Output is **normalized** in [-1,1] (ready for physics.setAISplineOffset()).
--- • Per-car state (last_d) is stored by index, and a slew limit smooths output.
--- • Also returns `avoidCarIndex`: the stopped car that most influenced the
---   first-step choice this frame (-1 if none).
---
--- @param egoCarIndex        integer     -- AI car index (0-based).
--- @param stoppedCarIndices  integer[]   -- Indices of cars considered stopped/hazards.
--- @param dtSeconds          number      -- Frame dt (used for slew).
--- @param cfg                table|nil   -- Optional tuning:
---        .horizon_meters (number)  default 45.0
---        .steps          (integer) default 6
---        .d_samples      (number[]) default {-3,-1.5,0,1.5,3}  -- in meters
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
--- @return number normOffset       -- [-1, 1] offset for physics.setAISplineOffset()
--- @return integer avoidCarIndex   -- stopped car index most affecting decision, or -1
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
  local trackLengthM = (ac.getTrackLengthMeters and ac.getTrackLengthMeters()) or 6500.0
  local invL = 1.0 / trackLengthM

  for k = 1, steps do
    local s = s0 + (horizonMeters * (k / steps)) * invL
    if s >= 1.0 then s = s - 1.0 end
    _sNodes[k] = s
  end

  -- Per-car history
  local S = getState(egoCarIndex)
  local last_d = S.last_d

  -- Preprocess obstacles to Frenet (s, d)
  local obsS, obsD, obsIdx = {}, {}, {}
  local obsCount = 0
  local sWindowN = (horizonMeters * invL) * 1.1
  local egoSide = ego.side  -- used to compute signed lateral at given s

  for i = 1, (stoppedCarIndices and #stoppedCarIndices or 0) do
    local idx = stoppedCarIndices[i]
    if idx ~= egoCarIndex then
      local c = ac.getCar(idx)
      if c then
        obsCount = obsCount + 1
        local so = ac.worldCoordinateToTrackProgress(c.position) or 0.0
        obsS[obsCount] = so
        obsIdx[obsCount] = idx
        -- project hazard position to lateral w.r.t. track at so
        local wPoint = ac.trackProgressToWorldCoordinate(so)
        local dx = c.position.x - wPoint.x
        local dy = c.position.y - wPoint.y
        local dz = c.position.z - wPoint.z
        obsD[obsCount] = dx * egoSide.x + dy * egoSide.y + dz * egoSide.z  -- signed meters
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

  -- Keep track of which obstacle pulls the first step most
  local k1BestObsIdxPerI = {}   -- [i] -> carIndex or -1
  for i=1,dCount do k1BestObsIdxPerI[i] = -1 end

  -- DP over lattice
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

          -- Remember which obstacle contributed most (for k==1 only)
          if k == 1 then
            local pullMag = pen
            if pullMag > strongestPullMag then
              strongestPullMag = pullMag
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

  -- Backtrack global best and extract first-step decision
  local lastRow = _dp[steps]
  local bestI, bestCost = 1, lastRow[1]
  for i = 2, dCount do
    local cst = lastRow[i]; if cst < bestCost then bestCost = cst; bestI = i end
  end
  local idx = bestI
  for k = steps, 2, -1 do idx = _parent[k][idx] end
  local dStar = dSamples[idx]

  -- Identify which obstacle influenced K=1 choice most for that bin
  local avoidCarIndex = k1BestObsIdxPerI[idx] or -1
  if not avoidCarIndex then avoidCarIndex = -1 end

  -- Rate-limit in meters, then normalize to [-1, 1] by track half-width
  local dt = (dtSeconds and dtSeconds > 0) and dtSeconds or 1/120
  local maxStep = maxDRate * dt
  local delta = dStar - last_d
  if delta >  maxStep then delta =  maxStep
  elseif delta < -maxStep then delta = -maxStep end
  local desired_d = last_d + delta

  local norm = clamp(desired_d / trackHalf, -1.0, 1.0)

  -- Persist
  S.last_d = desired_d
  S.last_norm = norm
  S.lastAvoidCarIndex = avoidCarIndex

  -- Store snapshot for debug draw (cheap; reuses tables)
  if _debugEnabled then
    local snap = _dbg[egoCarIndex]
    if not snap then snap = {} _dbg[egoCarIndex] = snap end
    snap.sNodes, snap.dSamples = {}, {}
    for k=1,steps do snap.sNodes[k] = _sNodes[k] end
    for i=1,dCount do snap.dSamples[i] = dSamples[i] end
    -- backtrack full path to visualize
    local pathIdxByK = {}
    local ii = bestI
    for k = steps, 1, -1 do
      pathIdxByK[k] = ii
      ii = (k > 1) and _parent[k][ii] or ii
    end
    snap.pathIdxByK = pathIdxByK
    -- obstacles
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
--- • Green corridor lines for each d-sample (first few s-slices).
--- • Blue polyline for the chosen path; small arrows show forward s.
--- • Red boxes at stopped cars; text shows their lateral `d` and AC index.
--- • On ground: cost bars at first slice (low=good).
---
--- This uses CSP helpers: render.debugArrow (3D arrows) and TrackPaint to
--- stamp persistent world-space lines/text on the asphalt for readability.
--- See render.debugArrow & ac.TrackPaint docs in lib.lua. 
--- (render.debugArrow, ac.TrackPaint:line, :text) :contentReference[oaicite:5]{index=5} :contentReference[oaicite:6]{index=6}.
---
--- @param carIndex integer
function CollisionAvoidanceManager.debugDraw(carIndex)
  if not _debugEnabled then return end
  local snap = _dbg[carIndex]
  if not snap then return end

  -- World-space painters (reuse one per call to avoid leaks)
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
  local trackHalf = snap.trackHalf

  -- Draw all corridor rails (green)
  for i=1,dCount do
    local prevW = nil
    for k=1,steps do
      local s = sNodes[k]
      local w = ac.trackProgressToWorldCoordinate(s)
      -- shift laterally by d sample
      local side = ac.getCar(carIndex).side
      local p = vec3(w.x + side.x * dSamples[i], w.y + side.y * dSamples[i], w.z + side.z * dSamples[i])
      if prevW then
        paint:line(prevW, p, rgbm(0,1,0,1), 0.04)
      end
      prevW = p
    end
  end

  -- Draw chosen path (blue thick)
  local prevP = nil
  for k=1,steps do
    local s = sNodes[k]
    local w = ac.trackProgressToWorldCoordinate(s)
    local side = ac.getCar(carIndex).side
    local d = dSamples[snap.pathIdxByK[k]]
    local p = vec3(w.x + side.x * d, w.y + side.y * d, w.z + side.z * d)
    if prevP then
      paint:line(prevP, p, rgbm(0.2,0.4,1,1), 0.08)
      render.debugArrow(prevP, p, 0.4, rgbm(0.2,0.4,1,1))  -- arrow tip for direction :contentReference[oaicite:7]{index=7}
    end
    prevP = p
  end

  -- Draw obstacles (red) with index & d-value
  for _,o in ipairs(snap.obstacles) do
    local w = ac.trackProgressToWorldCoordinate(o.s)
    local side = ac.getCar(carIndex).side
    local p = vec3(w.x + side.x * o.d, w.y + side.y * o.d, w.z + side.z * o.d)
    paint:line(p + vec3(0,0.01,0), p + vec3(0,0.6,0), rgbm(1,0,0,1), 0.06)
    paint:text("Consolas", string.format("#%d  d=%.2f", o.idx, o.d), p + vec3(0,0.65,0), 0.5, 0, rgbm(1,0.4,0.2,1))  -- :contentReference[oaicite:8]{index=8}
  end

  -- Cost bars at first slice (lower is better)
  do
    local s = sNodes[1]
    local w = ac.trackProgressToWorldCoordinate(s)
    local side = ac.getCar(carIndex).side
    -- find scale
    local maxC = 1e-6
    for i=1,dCount do if snap.costsK1[i] > maxC then maxC = snap.costsK1[i] end end
    for i=1,dCount do
      local d = dSamples[i]
      local base = vec3(w.x + side.x * d, w.y + side.y * d, w.z + side.z * d)
      local h = 0.5 * (snap.costsK1[i] / maxC)
      paint:line(base, base + vec3(0,h,0), i==1 and rgbm(1,1,0,1) or rgbm(0.9,0.9,0.2,1), 0.04)
      if math.abs(d - snap.chosenK1D) < 1e-3 then
        paint:line(base, base + vec3(0,h+0.15,0), rgbm(0.2,0.6,1,1), 0.06)
      end
    end
  end
end

return CollisionAvoidanceManager
