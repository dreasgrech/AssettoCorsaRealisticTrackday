-- FrenetAvoid.lua — multi-car safe, TTC-aware, normalized output [-1..+1]
-- Quintic lateral planning in Frenet space with early planning + emergency densification.
-- Heavy debug draw + round–trip audit so we can PROVE the exact value fed to physics.

local FrenetAvoid = {}

---------------------------------------------------------------------------------------------------
-- Tunables (adjust from your settings UI if desired)
---------------------------------------------------------------------------------------------------

-- Base horizon and candidate grid (auto-expands with TTC below)
local planningHorizonSeconds         = 1.60
local sampleTimeStepSeconds          = 0.08
local candidateEndTimesSecondsBase   = { 0.8, 1.2, 1.6 }
local candidateTerminalOffsetsNBase  = { -0.9,-0.7,-0.5,-0.3, 0.0, 0.3, 0.5, 0.7, 0.9 }

-- TTC-aware early planning (so we start avoiding sooner, not when already nose-to-tail)
local ttcEarlyPlanStart_s            = 3.0     -- widen search once TTC below this
local ttcEmergency_s                 = 1.6     -- densify hard if we are very close

-- Opponent prefilter window (progress in [0..1]), grow when TTC < ttcEarlyPlanStart_s
local longitudinalWindowAheadZ       = 0.020
local longitudinalWindowBehindZ      = 0.006
local extraAheadZ_whenEarly          = 0.020

-- Sampling anchor and spacing
local firstSampleSeconds             = 0.03    -- first step is very close to the bumper
local startMetersAhead               = 0.0
local useSpeedAwareLookahead         = true
local minAheadMetersAtLowSpeed       = 6.0
local maxAheadMetersAtHighSpeed      = 45.0
local nominalTrackLengthMeters       = 20000.0 -- fallback for meters→Δz

-- Simple disc footprints (fast and robust). This *does* account for car “size”.
local opponentRadiusMeters           = 1.45
local egoRadiusMeters                = 1.45

-- Lateral bounds & slew-rate limiter for the command we send to physics
local maxAbsOffsetNormalized         = 0.95
local maxOffsetChangePerSecondN      = 2.6

-- Cost weights
local costWeight_Clearance           = 3.0
local costWeight_TerminalCenter      = 0.7
local costWeight_JerkComfort         = 0.22

-- Emergency densification when space is tight
local minClrTight_m                  = 1.2
local densifyOffsetsExtra            = { -1.0, -0.8, -0.6, 0.6, 0.8, 1.0 }
local densifyEndTimesExtra           = { 0.6, 1.0 }

-- Output is normalized for physics.setAISplineOffset(idx, n, true)
local OUTPUT_IS_NORMALIZED           = true

-- Debug drawing + audit
local debugMaxPathsDrawn             = 24
local drawSamplesAsSpheres           = true
local drawOpponentDiscs              = true
local drawRejectionMarkers           = true
local drawEgoFootprint               = true
local drawAnchorLink                 = true

-- Round-trip audit: show what we RETURNED (command) vs what AC actually APPLIED
local drawReturnedOffsetPole         = true   -- magenta/cyan pole = command outN
local drawActualOffsetPole           = true   -- yellow pole = actual tc.x after physics
local auditWarnDeltaN                = 0.15   -- warn if |applied - commanded| exceeds this

-- Colors
local colAll     = rgbm(0.3, 0.9, 0.3, 0.15)  -- candidates
local colChosen  = rgbm(1.0, 0.2, 0.9, 1.0)   -- chosen path (thick)
local colPoleCmd = rgbm(0.2, 1.0, 1.0, 0.9)   -- pole for command
local colPoleAct = rgbm(1.0, 1.0, 0.2, 0.9)   -- pole for actual

---------------------------------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------------------------------

local function clampN(n) return math.max(-maxAbsOffsetNormalized, math.min(maxAbsOffsetNormalized, n)) end
local function wrap01(z) z = z % 1.0; if z < 0 then z = z + 1 end; return z end

-- Size-aware clearance (AABB would be costlier; discs are enough for avoidance logic)
local function minClearanceToOpponentsMeters(worldPos, opponents)
  local best = 1e9
  for i = 1, opponents.count do
    local opp = opponents[i]
    local d = (opp.position - worldPos):length()
    local clearance = d - (opponentRadiusMeters + egoRadiusMeters)
    if clearance < best then best = clearance end
  end
  return best
end

-- Collect nearby opponents by progress span, **skipping ego** (critical bugfix)
local function collectNearbyOpponents(egoIndex, egoZ, allCars, outList, aheadZ, behindZ)
  local count = 0
  for i = 1, #allCars do
    local car = allCars[i]
    if car and car.index ~= egoIndex then
      local tc = ac.worldCoordinateToTrack(car.position)    -- x=offsetN, z=progress
      if tc then
        local dzAhead  = wrap01(tc.z - egoZ)
        local dzBehind = wrap01(egoZ - tc.z)
        if dzAhead <= aheadZ or dzBehind <= behindZ then
          count = count + 1
          outList[count] = car
        end
      end
    end
  end
  outList.count = count
  for j = count + 1, #outList do outList[j] = nil end
  return count
end

-- Quintic lateral (x(t)) with zero end rate – smooth and feasible
local function makeLateralQuintic(x0, v0, x1, T)
  -- Solve for coefficients a0..a5 such that x(0)=x0, x'(0)=v0, x''(0)=0; x(T)=x1, x'(T)=0, x''(T)=0
  local T2, T3, T4, T5 = T*T, T*T*T, T*T*T*T, T*T*T*T*T
  local a0 = x0
  local a1 = v0
  local a2 = 0
  local a3 = (10*(x1 - x0) - (6*v0)*T) / T3
  local a4 = (-15*(x1 - x0) + (8*v0)*T) / T4
  local a5 = (6*(x1 - x0) - (3*v0)*T) / T5
  return function(t)
    if t < 0 then t = 0 elseif t > T then t = T end
    return a0 + a1*t + a2*t*t + a3*t*t*t + a4*t*t*t*t + a5*t*t*t*t*t
  end,
  function(t)
    -- absolute jerk proxy (comfort term), not exact but monotonic enough for our cost
    local tt = math.max(0, math.min(T, t))
    local j = 6*a3 + 24*a4*tt + 60*a5*tt*tt
    return math.abs(j)
  end
end

-- Speed-aware lookahead → delta-z for a given t
local function progressAt(egoZ, egoSpeedMps, t)
  local aheadMeters = math.max(minAheadMetersAtLowSpeed,
                        math.min(maxAheadMetersAtHighSpeed, egoSpeedMps * planningHorizonSeconds))
  local meters = (t / planningHorizonSeconds) * aheadMeters + startMetersAhead
  local dz = meters / nominalTrackLengthMeters
  return wrap01(egoZ + dz)
end

---------------------------------------------------------------------------------------------------
-- Per-car scratch arena (SoA; zero allocs per frame)
---------------------------------------------------------------------------------------------------
local __arena = {}
local function A(carIndex)
  local a = __arena[carIndex]
  if a then return a end
  a = {
    -- inputs/nearby
    nearbyCars = {}, nearbyCount = 0,

    -- samples (flat SoA for cache friendliness)
    samplesPos = {}, samplesClr = {}, samplesN = {}, samplesCount = 0,

    -- candidates: start/end indices and costs
    candStart = {}, candEnd = {}, candCost = {}, candMinClr = {}, candDT = {}, candT = {}, candCount = 0,

    -- rejections (for red X draw)
    rejectsPos = {}, rejectsCount = 0,

    -- last command & actual for audit
    lastOutN = 0.0, lastActualN = 0.0, lastEgoZ = 0.0
  }
  __arena[carIndex] = a
  return a
end

---------------------------------------------------------------------------------------------------
-- Public: compute lateral offset for one car this frame
---------------------------------------------------------------------------------------------------
---@param allCars ac.StateCar[]
---@param egoIndex integer
---@param dt number
---@return number  -- normalized [-1..+1]
function FrenetAvoid.computeOffsetForCar(allCars, egoIndex, dt)
  local ego = ac.getCar(egoIndex)
  if not ego or not ac.hasTrackSpline() then
    Logger.warn("FrenetAvoid: no ego or AI spline")
    return 0.0
  end

  local arena = A(egoIndex)

  -- Ego state (Frenet-like): x=offsetN (-1..+1), z=progress (0..1 wrap)
  local tc = ac.worldCoordinateToTrack(ego.position)
  local egoZ = wrap01(tc.z)
  local egoN = clampN(tc.x)
  local vLat0 = 0.0 -- zero start lateral rate keeps it stable
  local egoSpeedMps = (ego.speedKmh or 0) / 3.6

  Logger.log(string.format("FrenetAvoid: ego#%d z=%.4f x=%.3f dt=%.3f v=%.1f m/s",
    egoIndex, egoZ, egoN, dt or -1, egoSpeedMps))

  -----------------------------------------------------------------------------------------------
  -- Opponents near us (progress window grows if TTC pressure rises)
  -----------------------------------------------------------------------------------------------
  local aheadZ, behindZ = longitudinalWindowAheadZ, longitudinalWindowBehindZ
  -- quick TTC probe: nearest car straight ahead in world distance
  local nearestAhead, nearestAheadD = nil, 1e9
  for i = 1, #allCars do
    local c = allCars[i]
    if c and c.index ~= egoIndex then
      local dz = wrap01(ac.worldCoordinateToTrack(c.position).z - egoZ)
      if dz <= aheadZ + 0.02 then
        local d = (c.position - ego.position):length()
        if d < nearestAheadD then nearestAheadD, nearestAhead = d, c end
      end
    end
  end
  if nearestAhead then
    local relv = math.max(0.1, egoSpeedMps - (nearestAhead.speedKmh or 0)/3.6)
    local ttc = nearestAheadD / relv
    if ttc < ttcEarlyPlanStart_s then aheadZ = aheadZ + extraAheadZ_whenEarly end
    if ttc < ttcEmergency_s then
      -- emergency densification (adds more offsets and quicker end-times)
      Logger.warn(string.format("TTC=%.2fs -> emergency densify", ttc))
    end
  end

  arena.nearbyCount = collectNearbyOpponents(egoIndex, egoZ, allCars, arena.nearbyCars, aheadZ, behindZ)
  Logger.log("Nearby opponents: "..tostring(arena.nearbyCount))

  -----------------------------------------------------------------------------------------------
  -- Build candidate grid (possibly densified)
  -----------------------------------------------------------------------------------------------
  local candidateEndTimesSeconds   = { table.unpack(candidateEndTimesSecondsBase) }
  local candidateTerminalOffsetsN  = { table.unpack(candidateTerminalOffsetsNBase) }
  if nearestAhead then
    -- very cheap rule: if something is close, widen the net
    for i=1,#densifyEndTimesExtra do candidateEndTimesSeconds[#candidateEndTimesSeconds+1] = densifyEndTimesExtra[i] end
    for i=1,#densifyOffsetsExtra do candidateTerminalOffsetsN[#candidateTerminalOffsetsN+1] = densifyOffsetsExtra[i] end
  end

  -----------------------------------------------------------------------------------------------
  -- Evaluate candidates (samples start at the ego bumper; index discipline shared with drawer)
  -----------------------------------------------------------------------------------------------
  arena.candCount, arena.samplesCount, arena.rejectsCount = 0, 0, 0

  -- sample[1] is anchored at ego pose so paths start at the car (fixes “starts far away”)
  local s0 = ac.trackCoordinateToWorld(vec3(egoN, 0.0, egoZ))
  arena.samplesCount = 1
  arena.samplesPos[1] = s0
  arena.samplesN[1]   = egoN
  arena.samplesClr[1] = 99.0  -- special color bucket for anchor

  local bestCost, bestIdx = 1e9, 0

  for _, nT_raw in ipairs(candidateTerminalOffsetsN) do
    local nT = clampN(nT_raw)
    for __, T in ipairs(candidateEndTimesSeconds) do
      local dAt, jerkAbs = makeLateralQuintic(egoN, vLat0, nT, T)

      local startIndex = arena.samplesCount + 1
      local t, collided = 0.0, false
      local minClr, jerkSum, count = 1e9, 0.0, 1   -- count starts at 1 because of anchor

      -- First forward sample (small step so we begin steering immediately)
      t = firstSampleSeconds

      while t <= math.min(T, planningHorizonSeconds) do
        count = count + 1
        local n   = clampN(dAt(t))
        local z   = useSpeedAwareLookahead and progressAt(egoZ, egoSpeedMps, t) or wrap01(egoZ + (t/planningHorizonSeconds)*longitudinalWindowAheadZ)
        local pos = ac.trackCoordinateToWorld(vec3(n, 0.0, z))

        local clr = minClearanceToOpponentsMeters(pos, { count = arena.nearbyCount, table.unpack(arena.nearbyCars) })
        if clr < 0.0 then
          collided = true
          arena.rejectsCount = arena.rejectsCount + 1
          arena.rejectsPos[arena.rejectsCount] = pos
          break
        end
        if clr < minClr then minClr = clr end
        jerkSum = jerkSum + jerkAbs(t)

        arena.samplesCount = arena.samplesCount + 1
        local idx = arena.samplesCount
        arena.samplesPos[idx] = pos
        arena.samplesN[idx]   = n
        arena.samplesClr[idx] = clr

        t = t + sampleTimeStepSeconds
      end

      if not collided and count > 1 then
        arena.candCount = arena.candCount + 1
        local ci = arena.candCount
        arena.candStart[ci]  = startIndex - 1        -- include anchor at [startIndex-1]
        arena.candEnd[ci]    = arena.samplesCount
        arena.candMinClr[ci] = minClr
        arena.candDT[ci]     = nT
        arena.candT[ci]      = T

        -- cost = safety + modest center pull + comfort
        local cost = (costWeight_Clearance * (1.0 / (0.5 + minClr)))
                    + (costWeight_TerminalCenter * math.abs(nT))
                    + (costWeight_JerkComfort * jerkSum)
        arena.candCost[ci] = cost
        if cost < bestCost then bestCost, bestIdx = cost, ci end

        Logger.log(string.format("OK car=%d dT=%.2f T=%.2f samples=%d minClr=%.2f cost=%.3f",
          egoIndex, nT, T, (arena.candEnd[ci] - arena.candStart[ci] + 1), minClr, cost))
      else
        Logger.log(string.format("DROP car=%d dT=%.2f T=%.2f collided=%s", egoIndex, nT, T, tostring(collided)))
      end
    end
  end

  Logger.log(string.format("Survivors=%d bestIdx=%d", arena.candCount, bestIdx))

  -----------------------------------------------------------------------------------------------
  -- Pick output (always derived from the same bestIdx that debugDraw uses)
  -----------------------------------------------------------------------------------------------
  local outN
  if bestIdx == 0 then
    -- Starved: bias gently to center, nudge away from nearest laterally
    Logger.warn("FrenetAvoid: no surviving candidates; safe fallback")
    local desiredN = 0.0
    local nearest, dmin = nil, 1e9
    for i = 1, arena.nearbyCount do
      local c = arena.nearbyCars[i]
      local d = (c.position - ego.position):length()
      if d < dmin then dmin, nearest = d, c end
    end
    if nearest then
      local nOpp = ac.worldCoordinateToTrack(nearest.position).x
      desiredN = clampN(desiredN + ((nOpp >= 0) and -0.25 or 0.25))
    end
    local stepMax = maxOffsetChangePerSecondN * dt
    outN = clampN(egoN + math.max(-stepMax, math.min(stepMax, (desiredN - egoN))))
  else
    -- Follow the chosen path: steer to its **next** sample (very near the bumper)
    local sIdx = arena.candStart[bestIdx]
    local eIdx = arena.candEnd[bestIdx]
    local nextN = arena.samplesN[ math.min(sIdx + 1, eIdx) ]
    local stepMax = maxOffsetChangePerSecondN * dt
    outN = clampN(egoN + math.max(-stepMax, math.min(stepMax, (nextN - egoN))))
    Logger.log(string.format(
      "OUT car=%d chosen=%d egoN=%.3f nextN=%.3f outN=%.3f minClr=%.2f dT=%.2f T=%.2f",
      egoIndex, bestIdx, egoN, nextN, outN, arena.candMinClr[bestIdx], arena.candDT[bestIdx], arena.candT[bestIdx]))
  end

  arena.lastOutN = outN
  arena.lastActualN = egoN   -- updated in debugDraw after physics applies
  arena.lastEgoZ = egoZ

  return OUTPUT_IS_NORMALIZED and outN or outN
end

---------------------------------------------------------------------------------------------------
-- Batch for many cars
---------------------------------------------------------------------------------------------------
---@param allCars ac.StateCar[]
---@param dt number
---@param outOffsets number[]
---@return number[]
function FrenetAvoid.computeOffsetsForAll(allCars, dt, outOffsets)
  for i = 1, #allCars do
    local c = allCars[i]
    if c then outOffsets[c.index + 1] = FrenetAvoid.computeOffsetForCar(allCars, c.index, dt) end
  end
  return outOffsets
end

---------------------------------------------------------------------------------------------------
-- Debug draw + round-trip audit. Uses exactly the same indices as the solver above.
---------------------------------------------------------------------------------------------------
---@param carIndex integer
function FrenetAvoid.debugDraw(carIndex)
  local a = __arena[carIndex]
  if not a then return end

  -- Opponent / ego footprints
  if drawOpponentDiscs then
    for i = 1, a.nearbyCount do
      local c = a.nearbyCars[i]
      if c then render.debugSphere(c.position, opponentRadiusMeters, rgbm(1,0,0,0.25)) end
    end
  end
  if drawEgoFootprint then
    local ego = ac.getCar(carIndex)
    if ego then render.debugSphere(ego.position, egoRadiusMeters, rgbm(0,1,0,0.25)) end
  end

  -- Rejection markers (red X at collision sample)
  if drawRejectionMarkers then
    for i = 1, a.rejectsCount do
      local p = a.rejectsPos[i]
      local d = 0.6
      render.debugLine(p + vec3(-d,0,-d), p + vec3(d,0,d), rgbm(1,0,0,1))
      render.debugLine(p + vec3(-d,0, d),  p + vec3(d,0,-d), rgbm(1,0,0,1))
    end
  end

  -- Draw all candidates thin
  if a.candCount > 0 then
    local drawn = 0
    for ci = 1, a.candCount do
      local sIdx, eIdx = a.candStart[ci], a.candEnd[ci]
      for j = sIdx, eIdx - 1 do
        render.debugLine(a.samplesPos[j], a.samplesPos[j+1], colAll)
      end
      if drawSamplesAsSpheres then
        for j = sIdx, eIdx do
          render.debugSphere(a.samplesPos[j], 0.12,
            (a.samplesClr[j] <= 0.5 and rgbm(1,0.1,0.1,0.9)) or
            (a.samplesClr[j] <= 2.0 and rgbm(1,0.8,0.1,0.9)) or
            rgbm(0.2,1.0,0.2,0.9))
        end
      end
      drawn = drawn + 1; if drawn >= debugMaxPathsDrawn then break end
    end

    -- Find “best” exactly as solver did
    local bestIdx, bestCost = 1, a.candCost[1]
    for ci = 2, a.candCount do
      local c = a.candCost[ci]; if c < bestCost then bestIdx, bestCost = ci, c end
    end

    -- Draw chosen thick + label + anchor link to the steering target (next sample)
    local sIdx, eIdx = a.candStart[bestIdx], a.candEnd[bestIdx]
    for j = sIdx, eIdx - 1 do
      render.debugLine(a.samplesPos[j], a.samplesPos[j+1], colChosen)
      render.debugLine(a.samplesPos[j] + vec3(0,0.01,0), a.samplesPos[j+1] + vec3(0,0.01,0), colChosen)
      render.debugLine(a.samplesPos[j] + vec3(0,0.02,0), a.samplesPos[j+1] + vec3(0,0.02,0), colChosen)
    end

    local head = a.samplesPos[math.min(sIdx + 2, eIdx)]
    if head then render.debugSphere(head, 0.20, colChosen) end

    local mid = a.samplesPos[ math.floor((sIdx + eIdx) * 0.5) ]
    if mid then
      local txt = string.format("CHOSEN car=%d idx=%d  cost=%.2f  minClr=%.2f m  dT=%.2f  T=%.2fs",
        carIndex, bestIdx, a.candCost[bestIdx], a.candMinClr[bestIdx], a.candDT[bestIdx], a.candT[bestIdx])
      render.debugText(mid + vec3(0,0.4,0), txt)
    end

    if drawAnchorLink then
      local ego = ac.getCar(carIndex)
      if ego and sIdx + 1 <= eIdx then
        render.debugLine(ego.position, a.samplesPos[sIdx + 1], rgbm(1,1,1,0.9))
      end
    end
  end

  -- Round-trip audit: show the normalized offset we *returned* vs actual track x now
  local ego = ac.getCar(carIndex)
  if ego then
    local tc = ac.worldCoordinateToTrack(ego.position)
    a.lastActualN = tc.x
    a.lastEgoZ    = tc.z

    if drawReturnedOffsetPole then
      local poleCmd = ac.trackCoordinateToWorld(vec3(a.lastOutN, 0.0, a.lastEgoZ))
      render.debugLine(poleCmd + vec3(0,0.00,0), poleCmd + vec3(0,1.2,0), colPoleCmd)
      render.debugSphere(poleCmd + vec3(0,1.2,0), 0.10, colPoleCmd)
      render.debugText(poleCmd + vec3(0,1.35,0), string.format("cmd outN=%.3f", a.lastOutN))
    end

    if drawActualOffsetPole then
      local poleAct = ac.trackCoordinateToWorld(vec3(a.lastActualN, 0.0, a.lastEgoZ))
      render.debugLine(poleAct + vec3(0,0.00,0), poleAct + vec3(0,1.2,0), colPoleAct)
      render.debugSphere(poleAct + vec3(0,1.2,0), 0.10, colPoleAct)
      render.debugText(poleAct + vec3(0,1.35,0), string.format("act xN=%.3f", a.lastActualN))

      local dN = math.abs(a.lastOutN - a.lastActualN)
      if dN > auditWarnDeltaN then
        Logger.warn(string.format("[AUDIT] car=%d  outN(cmd)=%.3f  actN=%.3f  Δ=%.3f  (controller overriding? slew too low?)",
          carIndex, a.lastOutN, a.lastActualN, dN))
      else
        Logger.log(string.format("[AUDIT] car=%d  outN≈actN  cmd=%.3f act=%.3f Δ=%.3f",
          carIndex, a.lastOutN, a.lastActualN, dN))
      end
    end
  end
end

return FrenetAvoid
