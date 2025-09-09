local CarOperations = {}

function CarOperations.isBehind(aiCar, playerCar)
    local aiCarFwd = aiCar.look or aiCar.forward or vec3(0,0,1)
    local rel = MathHelpers.vsub(playerCar.position, aiCar.position)
    return MathHelpers.dot(aiCarFwd, rel) < 0
end

function CarOperations.playerIsClearlyAhead(aiCar, playerCar, meters)
    local fwd = aiCar.look or aiCar.forward or vec3(0,0,1)
    local rel = MathHelpers.vsub(playerCar.position, aiCar.position)
    return MathHelpers.dot(fwd, rel) > meters
end

-- Check if target side of car i is occupied by another AI alongside (prevents unsafe lateral move)
function CarOperations.isTargetSideBlocked(carIndex, sideSign)
    local storage = StorageManager.getStorage()
    local car = ac.getCar(carIndex)
    if not car then return false end
    local sim = ac.getSim()
    local carSide = car.side or vec3(1,0,0)
    local carLook = car.look or vec3(0,0,1)
    for otherCarIndex = 1, (sim.carsCount or 0) - 1 do
        if otherCarIndex ~= carIndex then
            local otherCar = ac.getCar(otherCarIndex)
            if otherCar and otherCar.isAIControlled then
                local rel = MathHelpers.vsub(otherCar.position, car.position)
                local lat = MathHelpers.dot(rel, carSide)   -- + right, - left
                local fwd = MathHelpers.dot(rel, carLook)   -- + ahead, - behind
                if lat*sideSign > 0 and math.abs(lat) <= storage.blockSideLateral_meters and math.abs(fwd) <= storage.blockSideLongitudinal_meters then
                    return true, otherCarIndex
                end
            end
        end
    end
    return false
end

---@param turningLights ac.TurningLights
function CarOperations.toggleTurningLights(carIndex, car, turningLights)
    if ac.setTargetCar(carIndex) then
        ac.setTurningLights(turningLights)
    end

    -- TODO: we don't need all of these
    CarManager.cars_currentTurningLights[carIndex] = turningLights
    CarManager.cars_indLeft[carIndex] = car.turningLeftLights
    CarManager.cars_indRight[carIndex] = car.turningRightLights
    CarManager.cars_indPhase[carIndex] = car.turningLightsActivePhase
    CarManager.cars_hasTL[carIndex] = car.hasTurningLights
end

--- Reliable “car alongside” detection (CSP Lua).
--- Returns:
---   hasSide  : boolean       -- true if another car is alongside
---   side     : 'left'|'right'-- which side the neighbour is on
---   otherIdx : integer       -- 0-based index of the neighbouring car
---   gapM     : number        -- lateral side-to-side gap in meters (0 if overlapping)
---
--- Definition of “alongside”:
---   • Longitudinal overlap: cars overlap along the forward axis (±long margin)
---   • Lateral proximity  : lateral center distance <= sum of half-widths (+lat margin)
---
--- Assumptions:
---   • Running under CSP (ac.* APIs available)
---   • 0-based car indices
function CarOperations.findCarAlongside(carIndex, ignoreCarIndex)
  -- Tunables (keep these small and conservative)
  local SEARCH_RADIUS_M  = 50.0   -- skip far cars early
  local LAT_MARGIN_M     = 0.30   -- extra width so minor jitter doesn’t drop detection
  local LONG_MARGIN_M    = 0.80   -- extra length for bumpers/overhang beyond wheels

  -- Small helpers (no dependencies)
  local function dot(ax, ay, az, bx, by, bz) return ax*bx + ay*by + az*bz end
  local function abs(x) return x < 0 and -x or x end
  local function max(a, b) return a > b and a or b end

  -- Estimate car lateral/longitudinal half-extents from wheel positions (+tyre width).
  -- Uses world positions projected on the car’s local side/forward axes.
  local function computeExtents(car)
    local px, py, pz = car.position.x, car.position.y, car.position.z
    local sx, sy, sz = car.side.x, car.side.y, car.side.z
    local lx, ly, lz = car.look.x, car.look.y, car.look.z

    local halfW = 0.0
    local frontZ = -1e9
    local rearZ  =  1e9

    -- Wheels are indexed 0..3 in CSP; use both axles for robust size estimation.
    for i = 0, 3 do
      local w = car.wheels[i]
      local rx = w.position.x - px
      local ry = w.position.y - py
      local rz = w.position.z - pz

      local lateral = abs(dot(sx, sy, sz, rx, ry, rz)) + (w.tyreWidth or 0) * 0.5
      if lateral > halfW then halfW = lateral end

      local z = dot(lx, ly, lz, rx, ry, rz)
      if z > frontZ then frontZ = z end
      if z < rearZ  then rearZ  = z end
    end

    local halfL = max(abs(frontZ), abs(rearZ)) + LONG_MARGIN_M
    return halfW, halfL
  end

  local me       = ac.getCar(carIndex)
  local mePos    = me.position
  local meLook   = me.look
  local meSide   = me.side
  local meHalfW, meHalfL = computeExtents(me)

  local bestIdx, bestGap, bestSide = -1, 1e9, nil

  -- Broad-phase: iterate all cars (CSP 0-based) and discard non-candidates quickly
  for otherIdx, other in ac.iterateCars() do
    if otherIdx ~= carIndex and otherIdx ~= ignoreCarIndex then
      local dx = other.position.x - mePos.x
      local dy = other.position.y - mePos.y
      local dz = other.position.z - mePos.z

      -- Early distance cull
      if dx*dx + dy*dy + dz*dz <= SEARCH_RADIUS_M * SEARCH_RADIUS_M then
        -- Project relative vector into my local axes
        local lat = dot(meSide.x, meSide.y, meSide.z, dx, dy, dz)     -- +right / −left
        local fwd = dot(meLook.x, meLook.y, meLook.z, dx, dy, dz)     -- +ahead / −behind

        -- Compute other car extents only for close candidates
        local otHalfW, otHalfL = computeExtents(other)

        -- Longitudinal overlap?
        local longOverlap = abs(fwd) <= (max(meHalfL, otHalfL))

        if longOverlap then
          local latAbs = abs(lat)
          local allowed = meHalfW + otHalfW + LAT_MARGIN_M

          if latAbs <= allowed then
            local gap = latAbs - (meHalfW + otHalfW)
            if gap < bestGap then
              bestGap  = gap
              bestIdx  = otherIdx
              bestSide = (lat < 0) and 'left' or 'right'
            end
          end
        end
      end
    end
  end

  if bestIdx ~= -1 then
    -- Return clamped gap (no negative distances); negative means overlap
    local gapM = bestGap < 0 and 0 or bestGap
    return true, bestSide, bestIdx, gapM
  else
    return false, nil, -1, math.huge
  end
end


return CarOperations