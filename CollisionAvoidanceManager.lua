local CollisionAvoidanceManager = {}

-- Internal per-car state (no allocations in hot path)
local __perCarState = {}   -- [carIndex] = { last_d = number }

-- Reused buffers (avoid GC): sized on demand
local __sNodes = {}        -- horizon s-samples
local __dp     = {}        -- dp[k][i] costs
local __parent = {}        -- backpointers

---@param carIndex integer
---@return table state
local function __getState(carIndex)
  local s = __perCarState[carIndex]
  if not s then
    s = { last_d = 0.0 }
    __perCarState[carIndex] = s
  end
  return s
end

local function __clamp(x, a, b)
  if x < a then return a elseif x > b then return b else return x end
end

-- Wrap a delta in [ -0.5, +0.5 ] for normalized progress differences
local function __wrap01Signed(ds)
  if ds > 0.5 then return ds - 1.0 elseif ds < -0.5 then return ds + 1.0 else return ds end
end

--------------------------------------------------------------------------------
--- Compute the **desired lateral offset** (meters) for a given AI car using a
--- short-horizon **Frenet corridor** lattice. The track centerline defines
--- progress `s` (0..1), and we choose among a few lateral offsets `d` at each
--- lookahead slice, minimizing a cost = clearance + smoothness + track-bounds
--- (plus a light centerline bias). Only the **first step’s** `d` is used each
--- frame (receding horizon), then rate-limited for stability.
---
--- The planner is **per-car**: state (last commanded `d`) is saved by car index.
--- It’s designed for **multiple cars per frame**: flat numeric arrays, table
--- reuse, and tiny fixed loops keep GC + CPU low.
---
--- @param egoCarIndex        integer     AI car index being controlled.
--- @param stoppedCarIndices  integer[]   Indices of cars considered “stopped” hazards.
--- @param dtSeconds          number      Delta time for this frame.
--- @param cfg                table|nil   Optional tuning:
---        cfg.horizon_meters (number)  default 45.0
---        cfg.steps          (integer) default 6
---        cfg.d_samples      (number[]) default {-3,-1.5,0,1.5,3}
---        cfg.obstacle_sigma (number)  default 1.2
---        cfg.weight_clear   (number)  default 1.5
---        cfg.weight_smooth  (number)  default 2.0
---        cfg.weight_track   (number)  default 1.0
---        cfg.center_bias    (number)  default 0.2
---        cfg.track_half     (number)  default 7.0    -- fallback half-width (m)
---        cfg.edge_margin    (number)  default 0.7
---        cfg.max_d_rate     (number)  default 6.0    -- m/s slew limit
---        cfg.bias_from_obs  (number)  default 0.4    -- pushes away from obstacle side
---
--- @return number desired_lateral_offset  Signed meters from centerline (+left, −right)
--------------------------------------------------------------------------------
function CollisionAvoidanceManager.computeDesiredLateralOffset(egoCarIndex, stoppedCarIndices, dtSeconds, cfg)
  -- Fast path: ego car
  local ego = ac.getCar(egoCarIndex)
  if not ego then return 0.0 end

  -- Resolve config (locals for JIT friendliness)
  cfg = cfg or {}
  local horizonMeters = cfg.horizon_meters or 45.0
  local steps         = cfg.steps or 6
  local dSamples      = cfg.d_samples or {-3,-1.5,0,1.5,3}
  local obstacleSigma = cfg.obstacle_sigma or 1.2
  local wClear        = cfg.weight_clear or 1.5
  local wSmooth       = cfg.weight_smooth or 2.0
  local wTrack        = cfg.weight_track or 1.0
  local centerBias    = cfg.center_bias or 0.2
  local trackHalf     = cfg.track_half or 7.0
  local edgeMargin    = cfg.edge_margin or 0.7
  local maxDRate      = cfg.max_d_rate or 6.0
  local biasFromObs   = cfg.bias_from_obs or 0.4

  -- Track references
  local s0 = ac.worldCoordinateToTrackProgress(ego.position) or 0.0
  local trackLengthM = (ac.getTrackLengthMeters and ac.getTrackLengthMeters()) or 6500.0
  local invL = 1.0 / trackLengthM

  -- Horizon samples in progress space (even spacing by meters)
  for k = 1, steps do
    local s = s0 + (horizonMeters * (k / steps)) * invL
    if s >= 1.0 then s = s - 1.0 end
    __sNodes[k] = s
  end

  -- Per-car state (previous commanded d)
  local state  = __getState(egoCarIndex)
  local last_d = state.last_d

  -- Preprocess obstacles into (s,d) in numeric flat arrays (no vec3 allocs)
  local obsS, obsD = {}, {}
  local obsCount = 0
  local sWindowN = (horizonMeters * invL) * 1.1   -- consider obstacles within ±this in s

  for i = 1, (stoppedCarIndices and #stoppedCarIndices or 0) do
    local idx = stoppedCarIndices[i]
    if idx ~= egoCarIndex then
      local c = ac.getCar(idx)
      if c then
        obsCount = obsCount + 1
        local so = ac.worldCoordinateToTrackProgress(c.position) or 0.0
        obsS[obsCount] = so

        -- Lateral offset sign via track side vector (fallback: ego.side).
        local wPoint = ac.trackProgressToWorldCoordinate(so)
        local sideV  = ego.side  -- If you have side_at(so), plug it here.
        local dx = c.position.x - wPoint.x
        local dy = c.position.y - wPoint.y
        local dz = c.position.z - wPoint.z
        obsD[obsCount] = dx * sideV.x + dy * sideV.y + dz * sideV.z
      end
    end
  end

  -- Dynamic Programming buffers
  local dCount = #dSamples
  for k = 1, steps do
    local row = __dp[k];     if not row then row = {}; __dp[k] = row end
    local par = __parent[k]; if not par then par = {}; __parent[k] = par end
    for i = 1, dCount do row[i] = 0.0; par[i] = 0 end
  end

  local invTwoSigma2 = 1.0 / (2.0 * obstacleSigma * obstacleSigma)

  -- Lattice evaluation over the Frenet corridor
  for k = 1, steps do
    local sK = __sNodes[k]
    local rowK, parK = __dp[k], __parent[k]
    local prevRow = (k > 1) and __dp[k-1] or nil

    for i = 1, dCount do
      local d = dSamples[i]
      -- Track-edge soft penalty
      local absD = (d >= 0 and d) or -d
      local edgePen
      if absD > (trackHalf - edgeMargin) then
        local over = absD - (trackHalf - edgeMargin)
        edgePen = wTrack * (over * over)
      else
        local ratio = absD / trackHalf
        edgePen = wTrack * 0.1 * (ratio * ratio)
      end

      -- Obstacle clearance: Gaussian-like repulsion if close in s
      local clearPen = 0.0
      for o = 1, obsCount do
        local ds = __wrap01Signed(obsS[o] - sK)
        if ds >= -sWindowN and ds <= sWindowN then
          local lateral = d - obsD[o]
          clearPen = clearPen + wClear * math.exp(-(lateral * lateral) * invTwoSigma2)
          -- Small directional bias: push away from obstacle side
          clearPen = clearPen - (biasFromObs * (lateral / trackHalf))
        end
      end

      -- Centerline bias (weak regularizer)
      local centerPen = centerBias * (d * d)

      local stageCost = edgePen + clearPen + centerPen

      if k == 1 then
        local smoothFirst = wSmooth * (d - last_d) * (d - last_d)
        rowK[i] = stageCost + smoothFirst
        parK[i] = 0
      else
        local best, bestJ = 1e18, 0
        for j = 1, dCount do
          local dPrev = dSamples[j]
          local smooth = wSmooth * (d - dPrev) * (d - dPrev)
          local cost = prevRow[j] + stageCost + smooth
          if cost < best then best = cost; bestJ = j end
        end
        rowK[i] = best
        parK[i] = bestJ
      end
    end
  end

  -- Backtrack terminal best and obtain first-step decision
  local lastRow = __dp[steps]
  local bestI, bestCost = 1, lastRow[1]
  for i = 2, dCount do
    local cst = lastRow[i]
    if cst < bestCost then bestCost = cst; bestI = i end
  end

  local idx = bestI
  for k = steps, 2, -1 do
    idx = __parent[k][idx]
  end
  local dStar = dSamples[idx]

  -- Rate-limit for stability
  local dt = (dtSeconds and dtSeconds > 0) and dtSeconds or 1/120
  local maxStep = maxDRate * dt
  local delta = dStar - last_d
  if delta >  maxStep then delta =  maxStep
  elseif delta < -maxStep then delta = -maxStep end

  local desired_d = last_d + delta
  state.last_d = desired_d
  return desired_d
end

return CollisionAvoidanceManager
