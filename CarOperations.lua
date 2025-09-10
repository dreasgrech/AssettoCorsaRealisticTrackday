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

-- Returns the six lateral anchor points plus some helpers
---@param car ac.StateCar
---@return table
CarOperations.getSideAnchorPoints = function(carIndex, car)
  local carForward, carLeft, carUp = car.look, car.side, car.up  -- all normalized

  -- Half-extents from AABB (x=width, y=height, z=length)
  -- local carAABBSize = car.aabbSize
  -- local carAABBSize = CarManager.cars_AABBSIZE[carIndex]
  -- local carHalfWidth = carAABBSize.x * 0.5
  -- local carHalfHeight = carAABBSize.y * 0.5
  -- local carHalfLength = carAABBSize.z * 0.5

  local halfAABBSize = CarManager.cars_HALF_AABSIZE[carIndex]
  -- local halfAABBSize = car.aabbSize * 0.5
  local carHalfWidth = halfAABBSize.x
  local carHalfHeight = halfAABBSize.y
  local carHalfLength = halfAABBSize.z

  -- Center at mid-height
  local carCenterWorldPosition = car.position + carUp * carHalfHeight

  local carRight = -carLeft

  local frontLeftWorldPosition   = carCenterWorldPosition + carForward *  carHalfLength + carLeft * carHalfWidth
  local centerLeftWorldPosition  = carCenterWorldPosition + carLeft * carHalfWidth
  local rearLeftWorldPosition    = carCenterWorldPosition - carForward *  carHalfLength + carLeft * carHalfWidth

  local frontRightWorldPosition  = carCenterWorldPosition + carForward *  carHalfLength + carRight * carHalfWidth
  local centerRightWorldPosition = carCenterWorldPosition + carRight * carHalfWidth
  local rearRightWorldPosition   = carCenterWorldPosition - carForward *  carHalfLength + carRight * carHalfWidth

  return {
    frontLeft = frontLeftWorldPosition,
    centerLeft = centerLeftWorldPosition,
    rearLeft = rearLeftWorldPosition,
    frontRight = frontRightWorldPosition,
    centerRight = centerRightWorldPosition,
    rearRight = rearRightWorldPosition,
    center = carCenterWorldPosition,
    forwardDirection = carForward,
    leftDirection = carLeft,
    rightDirection = carRight,
    upDirection = carUp,
  }
end

local SIDE_DISTANCE_TO_CHECK_FOR_BLOCKING = 5.0
local BACKFACE_CULLING_FOR_BLOCKING = 1 -- set to 0 to disable backface culling, or to -1 to hit backfaces only. Default value: 1.

local checkForOtherCars = function(worldPosition, direction, distance)
  local carRay = render.createRay(worldPosition,  direction, distance)
  local instersectionDistance = carRay:cars(BACKFACE_CULLING_FOR_BLOCKING)
  -- render.debugLine(carRay.pos, carRay.dir * carRay.length, rgbm(1,1,0,1)) -- cant be drawn here
  local rayHit = not (instersectionDistance == -1)
  return rayHit, instersectionDistance
end

local isOtherCarPresentAtDirection = function(directionName, worldPosition, direction, distance)
  local rayHit, instersectionDistance = checkForOtherCars(worldPosition, direction, distance)
  if rayHit then
    Logger.log(string.format("Ray hit at %s direction, distance: %.2f m", directionName, instersectionDistance))
  end

  return rayHit, instersectionDistance
end

CarOperations.isTargetSideBlocked = function(carIndex)
  local car = ac.getCar(carIndex)
  if not car then return false end

  -- local storage = StorageManager.getStorage()

  local carAnchorPoints = CarOperations.getSideAnchorPoints(carIndex,car)
  -- CarOperations.logCarAnchorPoints(carIndex, carAnchorPoints)

  isOtherCarPresentAtDirection("frontLeft", carAnchorPoints.frontLeft,  carAnchorPoints.leftDirection, SIDE_DISTANCE_TO_CHECK_FOR_BLOCKING)
  isOtherCarPresentAtDirection("centerLeft", carAnchorPoints.centerLeft, carAnchorPoints.leftDirection, SIDE_DISTANCE_TO_CHECK_FOR_BLOCKING)
  isOtherCarPresentAtDirection("rearLeft", carAnchorPoints.rearLeft, carAnchorPoints.leftDirection, SIDE_DISTANCE_TO_CHECK_FOR_BLOCKING)
  isOtherCarPresentAtDirection("frontRight", carAnchorPoints.frontRight,  carAnchorPoints.rightDirection, SIDE_DISTANCE_TO_CHECK_FOR_BLOCKING)
  isOtherCarPresentAtDirection("centerRight", carAnchorPoints.centerRight, carAnchorPoints.rightDirection, SIDE_DISTANCE_TO_CHECK_FOR_BLOCKING)
  isOtherCarPresentAtDirection("rearRight", carAnchorPoints.rearRight, carAnchorPoints.rightDirection, SIDE_DISTANCE_TO_CHECK_FOR_BLOCKING)

end

CarOperations.logCarAnchorPoints = function(carIndex, carAnchorPoints)
  Logger.log(string.format(
    "Car %d anchor points: frontLeft=(%.2f, %.2f, %.2f), centerLeft=(%.2f, %.2f, %.2f), rearLeft=(%.2f, %.2f, %.2f), frontRight=(%.2f, %.2f, %.2f), centerRight=(%.2f, %.2f, %.2f), rearRight=(%.2f, %.2f, %.2f), forwardDirection=(%.2f, %.2f, %.2f), leftDirection=(%.2f, %.2f, %.2f), upDirection=(%.2f, %.2f, %.2f)",
    carIndex,
    carAnchorPoints.frontLeft.x, carAnchorPoints.frontLeft.y, carAnchorPoints.frontLeft.z,
    carAnchorPoints.centerLeft.x, carAnchorPoints.centerLeft.y, carAnchorPoints.centerLeft.z,
    carAnchorPoints.rearLeft.x, carAnchorPoints.rearLeft.y, carAnchorPoints.rearLeft.z,
    carAnchorPoints.frontRight.x, carAnchorPoints.frontRight.y, carAnchorPoints.frontRight.z,
    carAnchorPoints.centerRight.x, carAnchorPoints.centerRight.y, carAnchorPoints.centerRight.z,
    carAnchorPoints.rearRight.x, carAnchorPoints.rearRight.y, carAnchorPoints.rearRight.z,
    carAnchorPoints.forwardDirection.x, carAnchorPoints.forwardDirection.y, carAnchorPoints.forwardDirection.z,
    carAnchorPoints.leftDirection.x, carAnchorPoints.leftDirection.y, carAnchorPoints.leftDirection.z,
    carAnchorPoints.upDirection.x, carAnchorPoints.upDirection.y, carAnchorPoints.upDirection.z
  ))
end

local RENDER_CAR_BLOCK_CHECK_RAYS_LEFT_COLOR = rgbm(0,0,1,1) -- blue
local RENDER_CAR_BLOCK_CHECK_RAYS_RIGHT_COLOR = rgbm(1,0,0,1) -- red

CarOperations.renderCarBlockCheckRays = function(carIndex)
  local car = ac.getCar(carIndex)
  if not car then return end

  local carAnchorPoints = CarOperations.getSideAnchorPoints(carIndex,car)
  -- CarOperations.logCarAnchorPoints(carIndex, carAnchorPoints)

  render.debugLine(carAnchorPoints.frontLeft,  carAnchorPoints.frontLeft  + carAnchorPoints.leftDirection  * SIDE_DISTANCE_TO_CHECK_FOR_BLOCKING, RENDER_CAR_BLOCK_CHECK_RAYS_LEFT_COLOR)
  render.debugLine(carAnchorPoints.centerLeft, carAnchorPoints.centerLeft + carAnchorPoints.leftDirection  * SIDE_DISTANCE_TO_CHECK_FOR_BLOCKING, RENDER_CAR_BLOCK_CHECK_RAYS_LEFT_COLOR)
  render.debugLine(carAnchorPoints.rearLeft,   carAnchorPoints.rearLeft   + carAnchorPoints.leftDirection  * SIDE_DISTANCE_TO_CHECK_FOR_BLOCKING, RENDER_CAR_BLOCK_CHECK_RAYS_LEFT_COLOR)

  render.debugLine(carAnchorPoints.frontRight,  carAnchorPoints.frontRight  + carAnchorPoints.rightDirection * SIDE_DISTANCE_TO_CHECK_FOR_BLOCKING, RENDER_CAR_BLOCK_CHECK_RAYS_RIGHT_COLOR)
  render.debugLine(carAnchorPoints.centerRight, carAnchorPoints.centerRight + carAnchorPoints.rightDirection * SIDE_DISTANCE_TO_CHECK_FOR_BLOCKING, RENDER_CAR_BLOCK_CHECK_RAYS_RIGHT_COLOR)
  render.debugLine(carAnchorPoints.rearRight,   carAnchorPoints.rearRight   + carAnchorPoints.rightDirection * SIDE_DISTANCE_TO_CHECK_FOR_BLOCKING, RENDER_CAR_BLOCK_CHECK_RAYS_RIGHT_COLOR)
end

CarOperations.drawSideAnchorPoints = function(carIndex)
  local car = ac.getCar(carIndex)
  if not car then
    return
  end

  local p = CarOperations.getSideAnchorPoints(carIndex, car)

  local gizmoColor_left = rgbm(0,0,1,1) -- blue
  local gizmoColor_right = rgbm(1,0,0,1) -- right

  render.debugSphere(p.frontLeft,   0.15, gizmoColor_left)
  render.debugSphere(p.centerLeft,  0.15, gizmoColor_left)
  render.debugSphere(p.rearLeft,    0.15, gizmoColor_left)

  render.debugSphere(p.frontRight,  0.15, gizmoColor_right)
  render.debugSphere(p.centerRight, 0.15, gizmoColor_right)
  render.debugSphere(p.rearRight,   0.15, gizmoColor_right)

  render.debugSphere(p.center,      0.12, rgbm(0,1,0,1))

  -- Optional: draw short axis arrows to verify directions in-game
  -- render.debugLine(p.center, p.center + p.forwardDirection * 2.0, rgbm(0,1,0,1)) -- forward
  -- render.debugLine(p.center, p.center + -p.leftDirection   * 2.0, rgbm(0,0,1,1)) -- left
  -- render.debugLine(p.center, p.center + p.upDirection      * 2.0, rgbm(1,1,0,1)) -- up
end


-- -- Check if target side of car i is occupied by another AI alongside (prevents unsafe lateral move)
-- function CarOperations.isTargetSideBlocked(carIndex, sideSign)
    -- local storage = StorageManager.getStorage()
    -- local car = ac.getCar(carIndex)
    -- if not car then return false end
    -- local sim = ac.getSim()
    -- local carSide = car.side or vec3(1,0,0)
    -- local carLook = car.look or vec3(0,0,1)
    -- for otherCarIndex = 1, (sim.carsCount or 0) - 1 do
        -- if otherCarIndex ~= carIndex then
            -- local otherCar = ac.getCar(otherCarIndex)
            -- if otherCar and otherCar.isAIControlled then
                -- local rel = MathHelpers.vsub(otherCar.position, car.position)
                -- local lat = MathHelpers.dot(rel, carSide)   -- + right, - left
                -- local fwd = MathHelpers.dot(rel, carLook)   -- + ahead, - behind
                -- if lat*sideSign > 0 and math.abs(lat) <= storage.blockSideLateral_meters and math.abs(fwd) <= storage.blockSideLongitudinal_meters then
                    -- return true, otherCarIndex
                -- end
            -- end
        -- end
    -- end
    -- return false
-- end

-- Six side raycasts (left/right × front/center/rear) — simple & explicit.
-- Returns:
--   anyHit:boolean, results:table
-- Where results has:
--   leftFront/leftCenter/leftRear/rightFront/rightCenter/rightRear
--   Each entry = { hit:boolean, carIndex:integer|-1, distance:number|-1 }
--
-- Debug:
--   CarOperations.simpleSideRaysDebug = true (default) draws ray lines & hit spheres.

-- CarOperations.simpleSideRaysDebug = true

-- function CarOperations.simpleSideRaycasts(carIndex, probeLengthM)
  -- probeLengthM = probeLengthM or 6.0

  -- -- small vec helpers (explicit; no operator overloads)
  -- local function vavg(a, b) return vec3((a.x+b.x)*0.5, (a.y+b.y)*0.5, (a.z+b.z)*0.5) end
  -- local function vmul(a, s) return vec3(a.x*s, a.y*s, a.z*s) end
  -- local function vadd(a, b) return vec3(a.x+b.x, a.y+b.y, a.z+b.z) end
  -- local function vnorm(v)
    -- local n = math.sqrt(v.x*v.x + v.y*v.y + v.z*v.z)
    -- if n == 0 then return v end
    -- return vec3(v.x/n, v.y/n, v.z/n)
  -- end

  -- local me   = ac.getCar(carIndex)
  -- local side = vnorm(me.side)
  -- local look = vnorm(me.look)

  -- -- sample bases from wheels: front axle center, car center, rear axle center
  -- local fl, fr = me.wheels[0].position, me.wheels[1].position
  -- local rl, rr = me.wheels[2].position, me.wheels[3].position
  -- local frontC = vavg(fl, fr)
  -- local rearC  = vavg(rl, rr)
  -- local midC   = vavg(frontC, rearC)

  -- -- ray directions
  -- local leftDir  = vmul(side, -1)
  -- local rightDir = side

  -- -- minimal caster: scan all other cars, keep nearest hit (if any)
  -- local function castRay(origin, dir, isLeft)
    -- if CarOperations.simpleSideRaysDebug then
      -- local tip = vadd(origin, vmul(dir, probeLengthM))
      -- render.debugArrow(origin, tip, 0.06, isLeft and rgbm(1.4,0.2,0.2,1) or rgbm(0.2,1.2,0.2,1))
    -- end

    -- local ray = render.createRay(origin, dir, probeLengthM)
    -- local bestDist, bestIdx = math.huge, -1
    -- for idx, _ in ac.iterateCars() do
      -- if idx ~= carIndex then
        -- local d = ray:carCollider(idx)
        -- if d >= 0 and d < bestDist then
          -- bestDist, bestIdx = d, idx
        -- end
      -- end
    -- end

    -- if bestIdx ~= -1 then
      -- if CarOperations.simpleSideRaysDebug then
        -- local hitPos = vadd(origin, vmul(dir, bestDist))
        -- render.debugSphere(hitPos, 0.10, rgbm(1.8,1.6,0.2,1))
        -- render.debugText(vadd(hitPos, vec3(0,0.22,0)),
          -- string.format("#%d  %.2fm", bestIdx, bestDist), rgbm(1,1,1,1), 0.8)
      -- end
      -- return { hit = true, carIndex = bestIdx, distance = bestDist }
    -- else
      -- return { hit = false, carIndex = -1, distance = -1 }
    -- end
  -- end

  -- -- cast the six rays
  -- local leftFront   = castRay(frontC, leftDir,  true)
  -- local leftCenter  = castRay(midC,   leftDir,  true)
  -- local leftRear    = castRay(rearC,  leftDir,  true)
  -- local rightFront  = castRay(frontC, rightDir, false)
  -- local rightCenter = castRay(midC,   rightDir, false)
  -- local rightRear   = castRay(rearC,  rightDir, false)

  -- local results = {
    -- leftFront   = leftFront,
    -- leftCenter  = leftCenter,
    -- leftRear    = leftRear,
    -- rightFront  = rightFront,
    -- rightCenter = rightCenter,
    -- rightRear   = rightRear
  -- }

  -- local anyHit = leftFront.hit or leftCenter.hit or leftRear.hit
              -- or rightFront.hit or rightCenter.hit or rightRear.hit

  -- return anyHit, results
-- end

-- --- Reliable “car alongside” detection (CSP Lua).
-- --- Returns:
-- ---   hasSide  : boolean       -- true if another car is alongside
-- ---   side     : 'left'|'right'-- which side the neighbour is on
-- ---   otherIdx : integer       -- 0-based index of the neighbouring car
-- ---   gapM     : number        -- lateral side-to-side gap in meters (0 if overlapping)
-- ---
-- --- Definition of “alongside”:
-- ---   • Longitudinal overlap: cars overlap along the forward axis (±long margin)
-- ---   • Lateral proximity  : lateral center distance <= sum of half-widths (+lat margin)
-- ---
-- --- Assumptions:
-- ---   • Running under CSP (ac.* APIs available)
-- ---   • 0-based car indices
-- -- Assumes: CarOperations table exists; running under CSP (ac.* available)
-- CarOperations._debugAlongsideRC = CarOperations._debugAlongsideRC or false   -- set true to see probes/hits

-- function CarOperations.findCarAlongside(carIndex, ignoreCarIndex)
  -- -- Tunables
  -- local PROBE_LENGTH_M      = 6.0     -- how far to search sideways with rays
  -- local PROBE_OFFSET_M      = 0.08    -- start rays slightly off body to avoid self intersection occlusion
  -- local LAT_MARGIN_M        = 0.25    -- extra width allowance (jitter, mirrors)
  -- local LONG_MARGIN_M       = 0.60    -- length allowance beyond wheelbase
  -- local MIN_OVERLAP_FRAC    = 0.15    -- require at least 15% overlap of the shorter car along length
  -- local BELTLINE_Y_OFFSET   = 0.35    -- above average wheel center (approx door handle height)
  -- local SAMPLE_Z_FRACTION   = 0.60    -- front/rear sample points as fraction of half-length

  -- -- Helpers
  -- local function dot(ax, ay, az, bx, by, bz) return ax*bx + ay*by + az*bz end
  -- local function abs(x) return x < 0 and -x or x end
  -- local function max(a,b) return a>b and a or b end
  -- local function min(a,b) return a<b and a or b end
  -- local function normalize(x, y, z)
    -- local n = math.sqrt(x*x + y*y + z*z); if n == 0 then return x,y,z end
    -- return x/n, y/n, z/n
  -- end
  -- local function add(x1,y1,z1, x2,y2,z2) return x1+x2, y1+y2, z1+z2 end
  -- local function mul(x,y,z, s) return x*s, y*s, z*s end

  -- -- Size estimation from wheels, projected to normalized local axes
  -- local function computeExtents(car)
    -- local px,py,pz = car.position.x, car.position.y, car.position.z
    -- local sx,sy,sz = normalize(car.side.x, car.side.y, car.side.z)
    -- local lx,ly,lz = normalize(car.look.x, car.look.y, car.look.z)

    -- local halfW, frontZ, rearZ = 0.0, -1e9, 1e9
    -- local avgWheelY = 0.0

    -- for i = 0, 3 do
      -- local w = car.wheels[i]
      -- local rx,ry,rz = w.position.x - px, w.position.y - py, w.position.z - pz
      -- avgWheelY = avgWheelY + w.position.y
      -- local lateral = abs(dot(sx,sy,sz, rx,ry,rz)) + (w.tyreWidth or 0)*0.5
      -- if lateral > halfW then halfW = lateral end
      -- local z = dot(lx,ly,lz, rx,ry,rz)
      -- if z > frontZ then frontZ = z end
      -- if z < rearZ  then rearZ  = z end
    -- end
    -- avgWheelY = avgWheelY * 0.25

    -- local halfL = 0.5 * (frontZ - rearZ) + LONG_MARGIN_M
    -- if halfL < 0 then halfL = -halfL end
    -- return halfW, halfL, avgWheelY
  -- end

  -- -- Compose repeated probe samples along car side (front/mid/rear)
  -- local function buildSideSamples(basePos, sideDir, lookDir, halfL, beltlineY)
    -- local sx,sy,sz = sideDir[1], sideDir[2], sideDir[3]
    -- local lx,ly,lz = lookDir[1], lookDir[2], lookDir[3]
    -- local px,py,pz = basePos[1], basePos[2], basePos[3]

    -- local zOff = SAMPLE_Z_FRACTION * halfL
    -- local samples = {
      -- -- MID
      -- { px, beltlineY, pz },
      -- -- FRONT
      -- add(px,py,pz, mul(lx,ly,lz,  zOff)),
      -- -- REAR
      -- add(px,py,pz, mul(lx,ly,lz, -zOff)),
    -- }
    -- -- shift to beltline Y for front/rear too
    -- samples[2][2] = beltlineY
    -- samples[3][2] = beltlineY
    -- -- nudge outwards from body so rays start just outside skin
    -- for i=1,#samples do
      -- local ox,oy,oz = mul(sx,sy,sz, PROBE_OFFSET_M)
      -- samples[i][1], samples[i][2], samples[i][3] = add(samples[i][1],samples[i][2],samples[i][3], ox,oy,oz)
    -- end
    -- return samples
  -- end

  -- -- Fetch my car & axes
  -- local me = ac.getCar(carIndex)
  -- local mp = me.position
  -- local msx,msy,msz = normalize(me.side.x, me.side.y, me.side.z)
  -- local mlx,mly,mlz = normalize(me.look.x, me.look.y, me.look.z)

  -- local meHalfW, meHalfL, meWheelY = computeExtents(me)
  -- local beltlineY = meWheelY + BELTLINE_Y_OFFSET

  -- -- Precompute side base positions at car center height
  -- local basePos = { mp.x, mp.y, mp.z }
  -- local rightSideDir = {  msx,  msy,  msz }
  -- local leftSideDir  = { -msx, -msy, -msz }

  -- local rightBase = { basePos[1], beltlineY, basePos[3] }
  -- local leftBase  = { basePos[1], beltlineY, basePos[3] }

  -- local rightSamples = buildSideSamples(rightBase, rightSideDir, {mlx,mly,mlz}, meHalfL, beltlineY)
  -- local leftSamples  = buildSideSamples(leftBase,  leftSideDir,  {mlx,mly,mlz}, meHalfL, beltlineY)

  -- -- Iterate other cars, find closest valid hit per side
  -- local best = { idx = -1, side = nil, gap = math.huge, hitPos = nil, fromPos = nil }

  -- local totalCars = ac.getSim().carsCount
  -- for otherIdx = 0, totalCars - 1 do
    -- if otherIdx ~= carIndex and otherIdx ~= ignoreCarIndex then
      -- local other = ac.getCar(otherIdx)
      -- -- Quick vertical gate (cars on bridges, etc.)
      -- if abs(other.position.y - beltlineY) <= 2.0 then
        -- local otHalfW, otHalfL = computeExtents(other)

        -- -- For each side, test its rays
        -- for sideName, dir, samples in
            -- (function()
              -- return coroutine.wrap(function()
                -- coroutine.yield('right', rightSideDir, rightSamples)
                -- coroutine.yield('left',  leftSideDir,  leftSamples)
              -- end)
            -- end)() do

          -- local dx,dy,dz = other.position.x - mp.x, other.position.y - mp.y, other.position.z - mp.z
          -- local fwd = dot(mlx,mly,mlz, dx,dy,dz)
          -- local totalHalfL = meHalfL + otHalfL
          -- local overlapL = totalHalfL - abs(fwd)
          -- if overlapL >= MIN_OVERLAP_FRAC * min(meHalfL, otHalfL) then
            -- -- Raycast this other car from all samples; keep nearest hit
            -- local sideHitDist, sideHitFrom = math.huge, nil
            -- for i=1,#samples do
              -- local from = samples[i]
              -- local ray = render.createRay(vec3(from[1], from[2], from[3]), vec3(dir[1], dir[2], dir[3]), PROBE_LENGTH_M) -- :contentReference[oaicite:5]{index=5}
              -- local d = ray:carCollider(otherIdx)  -- distance or -1 if no hit :contentReference[oaicite:6]{index=6}
              -- -- Debug: draw probe
              -- if CarOperations._debugAlongsideRC then
                -- render.debugArrow(vec3(from[1],from[2],from[3]),
                                  -- vec3(from[1] + dir[1]*PROBE_LENGTH_M, from[2] + dir[2]*PROBE_LENGTH_M, from[3] + dir[3]*PROBE_LENGTH_M),
                                  -- 0.06, sideName=='left' and rgbm(3,0,0,1) or rgbm(0,2.5,0,1))  -- red=left, green=right
              -- end
              -- if d >= 0 and d < sideHitDist then
                -- sideHitDist, sideHitFrom = d, from
              -- end
            -- end

            -- if sideHitFrom then
              -- -- We have a ray hit into the other car on this side.
              -- local hitX = sideHitFrom[1] + dir[1]*sideHitDist
              -- local hitY = sideHitFrom[2] + dir[2]*sideHitDist
              -- local hitZ = sideHitFrom[3] + dir[3]*sideHitDist

              -- -- Compute lateral gap via center separation (robust to offsets):
              -- local lat = dot(msx,msy,msz, dx,dy,dz)
              -- local latAbs = abs(lat)
              -- local allowed = meHalfW + otHalfW + LAT_MARGIN_M
              -- local gap = latAbs - (meHalfW + otHalfW)
              -- if gap < 0 then gap = 0 end

              -- -- Keep the smallest gap candidate overall
              -- if gap < best.gap then
                -- best.gap     = gap
                -- best.idx     = otherIdx
                -- best.side    = sideName
                -- best.hitPos  = { hitX, hitY, hitZ }
                -- best.fromPos = { sideHitFrom[1], sideHitFrom[2], sideHitFrom[3] }
              -- end
            -- end
          -- end
        -- end
      -- end
    -- end
  -- end

  -- -- Debug markers for the final selection
  -- if CarOperations._debugAlongsideRC and best.idx ~= -1 then
    -- render.debugSphere(vec3(best.hitPos[1], best.hitPos[2], best.hitPos[3]), 0.12, rgbm(2.5,2.5,0,1))  -- yellow hit point :contentReference[oaicite:7]{index=7}
    -- render.debugText(vec3(best.hitPos[1], best.hitPos[2]+0.25, best.hitPos[3]),
                     -- string.format("%s #%d  gap: %.2fm", best.side, best.idx, best.gap),
                     -- rgbm(1,1,1,1), 0.8)
    -- render.debugLine(vec3(best.fromPos[1],best.fromPos[2],best.fromPos[3]),
                     -- vec3(best.hitPos[1], best.hitPos[2], best.hitPos[3]),
                     -- rgbm(2.5,2.5,0,1))  -- highlighted final segment
  -- end

  -- if best.idx ~= -1 then
    -- return true, best.side, best.idx, best.gap
  -- else
    -- return false, nil, -1, math.huge
  -- end
-- end



return CarOperations