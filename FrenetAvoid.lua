-- FrenetAvoid.lua — anchored start + early sample + richer debug
-- Rationale:
--  • Anchor polylines at the ego car so curves don’t “begin far ahead”.
--  • Add a very-early first sample so expansion begins close to the bumper.
--  • (Optional) make longitudinal stepping speed-aware (common in Frenet planners).

local FrenetAvoid = {}

---------------------------------------------------------------------------------------------------
-- Tunables
---------------------------------------------------------------------------------------------------
local planningHorizonSeconds     = 1.60
local sampleTimeStepSeconds      = 0.08

-- Try multiple maneuver durations (how long we take to reach terminal lateral offset)
local candidateEndTimesSeconds   = { 0.8, 1.2, 1.6 }

-- Terminal lateral offsets (normalized -1..+1). Will be clamped to safe bounds below.
local candidateTerminalOffsetsN  = { -0.8,-0.6,-0.4,-0.2, 0.0, 0.2, 0.4, 0.6, 0.8 }

-- Longitudinal window of interest in progress (wrap-aware). This sets the *furthest* sample.
local longitudinalWindowAheadZ   = 0.020
local longitudinalWindowBehindZ  = 0.006

-- NEW: begin drawing/expansion essentially at the bumper
local firstSampleSeconds         = 0.03   -- very early first sample after t=0 (seconds)
local startMetersAhead           = 0.0    -- 0.0 draws right under the car; ≥0.5 if you want a tiny lead

-- Optional: make forward progress speed-aware (common in Frenet). If false, we use a flat fraction.
local useSpeedAwareLookahead     = true
local minAheadMetersAtLowSpeed   = 6.0    -- clamp forward sweep so we still see some path when creeping
local maxAheadMetersAtHighSpeed  = 45.0   -- and don’t go crazy at Vmax

-- Collision disk sizes (meters). Inflate if you want more conservative clearances.
local opponentRadiusMeters       = 1.35
local egoRadiusMeters            = 1.35

-- Lateral bounds and smoothing
local maxAbsOffsetNormalized     = 0.95
local maxOffsetChangePerSecondN  = 2.2

-- Cost weights
local costWeight_Clearance       = 3.0
local costWeight_TerminalCenter  = 0.8
local costWeight_JerkComfort     = 0.25

-- Output units
local OUTPUT_IS_NORMALIZED       = true

-- Debug drawing controls
local debugMaxPathsDrawn         = 24
local drawSamplesAsSpheres       = true
local drawOpponentDiscs          = true
local drawRejectionMarkers       = true
local drawEgoFootprint           = true
local drawAnchorLink             = true    -- draw a tiny line from ego to first sample point

---------------------------------------------------------------------------------------------------
-- Scratch and helpers
---------------------------------------------------------------------------------------------------
local scratch_CandidatePaths = {}   -- survivors for drawing + chosen best
local scratch_Samples        = {}   -- reused buffer per candidate
local scratch_NearbyCars     = {}
local scratch_Rejections     = {}   -- { {pos=vec3, reason="collision"}, ... }

local function wrap01(z) z = z % 1.0; return (z < 0) and (z + 1.0) or z end

local function clampOffsetToRoad(n)
  return math.max(-maxAbsOffsetNormalized, math.min(maxAbsOffsetNormalized, n))
end

local function offsetNormToMeters(offsetN, progressZ)
  local sides = ac.getTrackAISplineSides(progressZ) -- vec2: left/right meters
  return (offsetN < 0) and (offsetN * sides.x) or (offsetN * sides.y)
end

-- Quintic lateral motion from d0 -> dT with flat end (v=a=0). Standard in Frenet planning. 
-- See Werling et al. (2010), quartic/quintic profiles in Frenet frame. 
-- (We use quintic for lateral, start at current state.)  :contentReference[oaicite:1]{index=1}
local function makeLateralQuintic(d0, dDot0, dT, T)
  local a0, a1, a2 = d0, dDot0, 0.0
  local T2, T3, T4, T5 = T*T, T*T*T, T*T*T*T, T*T*T*T*T
  local C0 = dT - (a0 + a1*T + a2*T2)
  local a3 = (10*C0/T3) - (4*a1/T2)
  local a4 = (-15*C0/T4) + (7*a1/T3)
  local a5 = (  6*C0/T5) - (3*a1/T4)
  local function dAt(t) local t2,t3,t4,t5=t*t,t*t*t,t*t*t*t,t*t*t*t*t; return a0 + a1*t + a2*t2 + a3*t3 + a4*t4 + a5*t5 end
  local function jerkMag(t) return math.abs(6*a3 + 24*a4*t + 60*a5*t*t) end
  return dAt, jerkMag
end

-- Clearance from a point to opponent disks
local function minClearanceMeters(worldPos, opponents, egoIndex)
  local best = 1e9
  for i = 1, #opponents do
    local opp = opponents[i]
    if opp and opp.index ~= egoIndex then
      local d = (opp.position - worldPos):length()
      local clr = d - (opponentRadiusMeters + egoRadiusMeters)
      if clr < best then best = clr end
    end
  end
  return best
end

-- Build opponent list around ego progress (wrap-aware)
local function collectNearbyOpponents(egoZ, allCars, outList, egoIndex)
  local n = 0
  for i = 1, #allCars do
    local c = allCars[i]
    if c and c.index ~= egoIndex then
      local tc = ac.worldCoordinateToTrack(c.position)
      if tc then
        local ahead  = wrap01(tc.z - egoZ)
        local behind = wrap01(egoZ - tc.z)
        if ahead <= longitudinalWindowAheadZ or behind <= longitudinalWindowBehindZ then
          n = n + 1; outList[n] = c
        end
      end
    end
  end
  for j = n + 1, #outList do outList[j] = nil end
  return n
end

-- (Optional) speed-aware mapping time→progress, clamped to an ahead window
local function progressAtTime(egoZ, egoSpeedMps, t)
  if not useSpeedAwareLookahead then
    local frac = t / planningHorizonSeconds
    return wrap01(egoZ + frac * longitudinalWindowAheadZ)
  end
  -- Convert “meters ahead” to “delta progress” using current track length (CSP provides length via world<->spline).
  -- If you keep a track-length helper elsewhere, pipe it in; here we infer from ahead window limits.
  local aheadMeters = math.max(minAheadMetersAtLowSpeed,
                        math.min(maxAheadMetersAtHighSpeed, egoSpeedMps * planningHorizonSeconds))
  -- At time t within the horizon, scale linearly 0..aheadMeters:
  local meters = (t / planningHorizonSeconds) * aheadMeters + startMetersAhead
  -- Convert meters→delta progress using local lane widths as a fallback: CSP doesn’t give length here,
  -- but delta-z only sets sampling spacing for visualization; the collision test uses world positions.
  -- Approximate with meters → small delta-z by proportion to a nominal track length (~20 km max).
  -- If you have RaceTrackManager.getTrackLengthMeters(), swap it in here.
  local nominalLen = 20000.0
  local dz = meters / nominalLen
  return wrap01(egoZ + dz)
end

---------------------------------------------------------------------------------------------------
-- Public: compute lateral offset for ego this frame
---------------------------------------------------------------------------------------------------
function FrenetAvoid.computeOffset(allCars, ego, dt)
  if not ego or not ac.hasTrackSpline() then
    if Logger then Logger.warn("FrenetAvoid: no ego or no AI spline; returning 0") end
    return 0.0
  end

  -- Ego state (Frenet-like): x=offsetN (-1..+1), z=progress (0..1 wrap)
  local tc = ac.worldCoordinateToTrack(ego.position)
  local egoZ = wrap01(tc.z)
  local egoN = clampOffsetToRoad(tc.x)
  local vLat0 = 0.0 -- start with zero lateral rate for stability
  local egoSpeedMps = ego.speedKmh and (ego.speedKmh / 3.6) or 0.0

  if Logger then
    Logger.log(string.format("FrenetAvoid: ego idx=%d z=%.4f x=%.3f dt=%.3f v=%.1f m/s",
      ego.index, egoZ, egoN, dt or -1, egoSpeedMps))
  end

  -- Opponents near us
  local nearCount = collectNearbyOpponents(egoZ, allCars, scratch_NearbyCars, ego.index)
  if Logger then Logger.log("Nearby opponents: "..tostring(nearCount)) end

  -- Reset per-frame containers
  for i=1,#scratch_CandidatePaths do scratch_CandidatePaths[i]=nil end
  for i=1,#scratch_Rejections do scratch_Rejections[i]=nil end

  local bestCost, bestIdx = 1e9, 0
  local survivors = 0

  -- Iterate candidates (terminal lateral positions & durations)
  for _, nT_raw in ipairs(candidateTerminalOffsetsN) do
    local nT = clampOffsetToRoad(nT_raw)
    for __, T in ipairs(candidateEndTimesSeconds) do
      local dAt, jerkAbs = makeLateralQuintic(egoN, vLat0, nT, T)
      for i=1,#scratch_Samples do scratch_Samples[i]=nil end

      -- IMPORTANT: anchor sample 0 exactly at ego pose so the line starts AT the car
      local count = 0
      do
        count = 1
        local z0 = egoZ
        local n0 = egoN
        local world0 = ac.trackCoordinateToWorld(vec3(n0, 0.0, z0))
        scratch_Samples[count] = { pos = world0, offsetN = n0, progressZ = z0, clr = minClearanceMeters(world0, scratch_NearbyCars, ego.index) }
      end

      local t = firstSampleSeconds -- start almost immediately after t=0
      local minClr = 1e9
      local jerkSum = 0.0
      local collided = false

      while t <= math.min(T, planningHorizonSeconds) do
        count = count + 1
        local n = clampOffsetToRoad(dAt(t))
        local z = progressAtTime(egoZ, egoSpeedMps, t)
        local world = ac.trackCoordinateToWorld(vec3(n, 0.0, z))

        local clr = minClearanceMeters(world, scratch_NearbyCars, ego.index)
        if clr < 0.0 then
          collided = true
          if drawRejectionMarkers then
            scratch_Rejections[#scratch_Rejections+1] = { pos = world, reason = "collision" }
          end
          if Logger then Logger.log(string.format("REJECT termN=%.2f T=%.2f t=%.2f clr=%.2f", nT, T, t, clr)) end
          break
        end
        if clr < minClr then minClr = clr end
        jerkSum = jerkSum + jerkAbs(t)

        scratch_Samples[count] = scratch_Samples[count] or {}
        local s = scratch_Samples[count]
        s.pos, s.offsetN, s.progressZ, s.clr = world, n, z, clr

        t = t + sampleTimeStepSeconds
      end

      if not collided and count >= 2 then
        -- Interpretable cost: keep distance, prefer center if equal, prefer smoothness (low jerk)
        local cost = (costWeight_Clearance * (1.0 / (0.5 + minClr)))
                   + (costWeight_TerminalCenter * math.abs(nT))
                   + (costWeight_JerkComfort * jerkSum)
        survivors = survivors + 1
        local p = scratch_CandidatePaths[survivors] or {}
        p.samples = {}; for i=1,count do p.samples[i] = scratch_Samples[i] end
        p.terminalOffsetN = nT; p.durationT = T; p.totalCost = cost; p.minClr = minClr
        scratch_CandidatePaths[survivors] = p

        if Logger then
          Logger.log(string.format("OK termN=%.2f T=%.2f samples=%d minClr=%.2f cost=%.3f", nT, T, count, minClr, cost))
        end

        if cost < bestCost then bestCost, bestIdx = cost, survivors end
      else
        if Logger then
          Logger.log(string.format("DROP termN=%.2f T=%.2f collided=%s samples=%d", nT, T, tostring(collided), count))
        end
      end
    end
  end

  if Logger then Logger.log(string.format("Survivors=%d bestIdx=%d", survivors, bestIdx)) end

  -- Fallback: gently move to center if nothing survived
  if bestIdx == 0 then
    if Logger then Logger.warn("FrenetAvoid: no survivors, easing to center") end
    local desiredN = 0.0
    local stepMax = maxOffsetChangePerSecondN * dt
    local outN = clampOffsetToRoad(egoN + math.max(-stepMax, math.min(stepMax, desiredN - egoN)))
    return OUTPUT_IS_NORMALIZED and outN or offsetNormToMeters(outN, egoZ)
  end

  -- Smoothly move toward the *next* sample of the best path (sample[2] is now very close to the car)
  local best = scratch_CandidatePaths[bestIdx]
  local nextN = best.samples[ math.min(2, #best.samples) ].offsetN
  local stepMax = maxOffsetChangePerSecondN * dt
  local outN = clampOffsetToRoad(egoN + math.max(-stepMax, math.min(stepMax, nextN - egoN)))
  if Logger then Logger.log(string.format("OUT nextN=%.3f stepMax=%.3f outN=%.3f", nextN, stepMax, outN)) end
  return OUTPUT_IS_NORMALIZED and outN or offsetNormToMeters(outN, egoZ)
end

---------------------------------------------------------------------------------------------------
-- Debug draw
---------------------------------------------------------------------------------------------------
local colAll  = rgbm(0.3, 0.7, 1.0, 0.35)
local colBest = rgbm(1.0, 0.9, 0.2, 1.0)

local function clrToColor(c)
  -- Red (≤0.5 m), yellow (~2 m), green (≥5 m)
  if c <= 0.5 then return rgbm(1.0, 0.1, 0.1, 0.9) end
  if c <= 2.0 then return rgbm(1.0, 0.8, 0.1, 0.9) end
  return rgbm(0.2, 1.0, 0.2, 0.9)
end

---@param carIndex integer
function FrenetAvoid.debugDraw(carIndex)
  -- Opponents and ego footprints
  if drawOpponentDiscs then
    for i = 1, #scratch_NearbyCars do
      local c = scratch_NearbyCars[i]
      if c then render.debugSphere(c.position, opponentRadiusMeters, rgbm(1,0,0,0.25)) end
    end
  end
  if drawEgoFootprint then
    local ego = ac.getCar(carIndex)
    if ego then render.debugSphere(ego.position, egoRadiusMeters, rgbm(0,1,0,0.25)) end
  end

  if #scratch_CandidatePaths == 0 then
    if Logger then Logger.log("FrenetAvoid.debugDraw: no candidates to draw") end
    if drawRejectionMarkers then
      for i=1,#scratch_Rejections do
        local m = scratch_Rejections[i]
        if m then
          local p = m.pos; local d = 0.6
          render.debugLine(p + vec3(-d,0,-d), p + vec3(d,0,d), rgbm(1,0,0,1))
          render.debugLine(p + vec3(-d,0, d), p + vec3(d,0,-d), rgbm(1,0,0,1))
        end
      end
    end
    return
  end

  -- Draw survivors (thin), with sample spheres (colored by clearance)
  local drawn = 0
  for i=1, #scratch_CandidatePaths do
    local p = scratch_CandidatePaths[i]
    for j=1, #p.samples-1 do
      render.debugLine(p.samples[j].pos, p.samples[j+1].pos, colAll)
    end
    if drawSamplesAsSpheres then
      for j=1,#p.samples do
        local s = p.samples[j]
        render.debugSphere(s.pos, 0.12, clrToColor(s.clr))
      end
    end
    drawn = drawn + 1; if drawn >= debugMaxPathsDrawn then break end
  end

  -- Highlight best path and label
  local bestIdx, bestCost = 1, scratch_CandidatePaths[1].totalCost
  for i=2,#scratch_CandidatePaths do
    if scratch_CandidatePaths[i].totalCost < bestCost then bestIdx, bestCost = i, scratch_CandidatePaths[i].totalCost end
  end
  local bp = scratch_CandidatePaths[bestIdx]
  for j=1,#bp.samples-1 do render.debugLine(bp.samples[j].pos, bp.samples[j+1].pos, colBest) end
  local mid = bp.samples[math.floor(#bp.samples/2)]
  if mid then
    local txt = string.format("best cost=%.2f  minClr=%.2f m  dT=%.2f  T=%.2fs", bp.totalCost, bp.minClr, bp.terminalOffsetN, bp.durationT)
    render.debugText(mid.pos, txt)
  end

  -- Small visual link from ego to first sample (so “start” is obvious)
  if drawAnchorLink then
    local ego = ac.getCar(carIndex)
    if ego and bp and bp.samples[1] then
      render.debugLine(ego.position, bp.samples[1].pos, rgbm(1,1,1,0.6))
    end
  end

  -- Rejection markers (red X)
  if drawRejectionMarkers then
    for i=1,#scratch_Rejections do
      local m = scratch_Rejections[i]
      if m then
        local p = m.pos; local d = 0.6
        render.debugLine(p + vec3(-d,0,-d), p + vec3(d,0,d), rgbm(1,0,0,1))
        render.debugLine(p + vec3(-d,0, d), p + vec3(d,0,-d), rgbm(1,0,0,1))
      end
    end
  end
end

return FrenetAvoid
