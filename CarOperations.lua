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
-- Assumes: CarOperations table exists; running under CSP (ac.* available)
function CarOperations.findCarAlongside(carIndex, ignoreCarIndex)
  -- Tunables
  local SEARCH_RADIUS_M       = 25.0   -- broad-phase cull
  local LAT_MARGIN_M          = 0.25   -- lateral jitter allowance
  local LONG_MARGIN_M         = 0.60   -- length allowance beyond wheels
  local HEADING_MAX_DEG       = 40     -- max heading delta to be considered “driving next to”
  local MIN_OVERLAP_FRAC      = 0.20   -- require at least 20% overlap of the shorter car

  -- Math helpers
  local function dot(ax, ay, az, bx, by, bz) return ax*bx + ay*by + az*bz end
  local function abs(x) return x < 0 and -x or x end
  local function max(a, b) return a > b and a or b end
  local function min(a, b) return a < b and a or b end
  local function normalize(x, y, z)
    local n = math.sqrt(x*x + y*y + z*z)
    if n == 0 then return x, y, z end
    return x/n, y/n, z/n
  end

  local HEADING_COS = math.cos(math.rad(HEADING_MAX_DEG))

  -- Extents from wheels, projected onto *normalized* local axes
  local function computeExtents(car)
    local px, py, pz = car.position.x, car.position.y, car.position.z
    local sx, sy, sz = normalize(car.side.x, car.side.y, car.side.z)
    local lx, ly, lz = normalize(car.look.x, car.look.y, car.look.z)

    local halfW = 0.0
    local frontZ = -1e9
    local rearZ  =  1e9

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

    -- Use half of span plus a margin (more accurate than max(|front|, |rear|))
    local halfL = 0.5 * (frontZ - rearZ) + LONG_MARGIN_M
    if halfL < 0 then halfL = -halfL end
    return halfW, halfL
  end

  local me    = ac.getCar(carIndex)
  local mePos = me.position
  local msx, msy, msz = normalize(me.side.x, me.side.y, me.side.z)
  local mlx, mly, mlz = normalize(me.look.x, me.look.y, me.look.z)
  local meHalfW, meHalfL = computeExtents(me)

  local bestIdx, bestGap, bestSide = -1, 1e9, nil

  for otherIdx, other in ac.iterateCars() do
    if otherIdx ~= carIndex and otherIdx ~= ignoreCarIndex then
      local dx = other.position.x - mePos.x
      local dy = other.position.y - mePos.y
      local dz = other.position.z - mePos.z

      -- Broad-phase (horizontal distance is fine; vertical differences don’t help here)
      local d2 = dx*dx + dz*dz
      if d2 <= SEARCH_RADIUS_M * SEARCH_RADIUS_M then
        -- Heading alignment (parallel-ish cars only)
        local olx, oly, olz = normalize(other.look.x, other.look.y, other.look.z)
        if dot(mlx, mly, mlz, olx, oly, olz) >= HEADING_COS then
          -- Project relative vector into my local frame
          local lat = dot(msx, msy, msz, dx, dy, dz)   -- +right / −left
          local fwd = dot(mlx, mly, mlz, dx, dy, dz)   -- +ahead / −behind

          -- Extents for the other car (only now, after broad-phase + heading)
          local otHalfW, otHalfL = computeExtents(other)

          -- Longitudinal overlap: use SUM of half-lengths (correct), not max
          local totalHalfL = meHalfL + otHalfL
          local overlapL = totalHalfL - abs(fwd)
          if overlapL >= 0 then
            -- Require a minimum fraction of longitudinal overlap (avoid corner kisses)
            if overlapL >= MIN_OVERLAP_FRAC * min(meHalfL, otHalfL) then
              -- Lateral proximity
              local latAbs = abs(lat)
              local allowed = meHalfW + otHalfW + LAT_MARGIN_M
              if latAbs <= allowed then
                local gap = latAbs - (meHalfW + otHalfW) -- negative => body overlap
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
    end
  end

  if bestIdx ~= -1 then
    local gapM = bestGap < 0 and 0 or bestGap
    return true, bestSide, bestIdx, gapM
  else
    return false, nil, -1, math.huge
  end
end



return CarOperations