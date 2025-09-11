local CarOperations = {}

CarOperations.CarDirections = {
  None = 0,
  FrontLeft = 1,
  CenterLeft = 2,
  RearLeft = 3,
  FrontRight = 4,
  CenterRight = 5,
  RearRight = 6,
  FrontLeftAngled = 7,
  RearLeftAngled = 8,
  FrontRightAngled = 9,
  RearRightAngled = 10,
}

CarOperations.CarDirectionsStrings = {
  [CarOperations.CarDirections.None] = "None",
  [CarOperations.CarDirections.FrontLeft] = "FrontLeft",
  [CarOperations.CarDirections.CenterLeft] = "CenterLeft",
  [CarOperations.CarDirections.RearLeft] = "RearLeft",
  [CarOperations.CarDirections.FrontRight] = "FrontRight",
  [CarOperations.CarDirections.CenterRight] = "CenterRight",
  [CarOperations.CarDirections.RearRight] = "RearRight",
  [CarOperations.CarDirections.FrontLeftAngled] = "FrontLeftAngled",
  [CarOperations.CarDirections.RearLeftAngled] = "RearLeftAngled",
  [CarOperations.CarDirections.FrontRightAngled] = "FrontRightAngled",
  [CarOperations.CarDirections.RearRightAngled] = "RearRightAngled",
}

local SIDE_DISTANCE_TO_CHECK_FOR_BLOCKING = 4.0
local BACKFACE_CULLING_FOR_BLOCKING = 1 -- set to 0 to disable backface culling, or to -1 to hit backfaces only. Default value: 1.

local INV_SQRT2 = 0.7071067811865476 -- 1/sqrt(2) for exact 45° blend

local RENDER_CAR_BLOCK_CHECK_RAYS_LEFT_COLOR = rgbm(0,0,1,1) -- blue
local RENDER_CAR_BLOCK_CHECK_RAYS_RIGHT_COLOR = rgbm(1,0,0,1) -- red

---Limits AI throttle pedal.
---@param carIndex integer @0-based car index.
---@param limit number @0 for limit gas pedal to 0, 1 to remove limitation.
CarOperations.setAIThrottleLimit = function(carIndex, limit)
    physics.setAIThrottleLimit(carIndex, limit)
    CarManager.cars_throttleLimit[carIndex] = limit
end

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

function CarOperations.playerIsClearlyBehind(aiCar, playerCar, meters)
    local fwd = aiCar.look or aiCar.forward or vec3(0,0,1)
    local rel = MathHelpers.vsub(playerCar.position, aiCar.position)
    return MathHelpers.dot(fwd, rel) < -meters
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
-- CarOperations.getSideAnchorPoints = function(carIndex, car)
-- CarOperations.getSideAnchorPoints = function(carPosition, carForward, carLeft, carUp, halfAABBSize)
local getSideAnchorPoints = function(carPosition, carForward, carLeft, carUp, halfAABBSize)
  -- local carForward, carLeft, carUp = car.look, car.side, car.up  -- all normalized

  -- Half-extents from AABB (x=width, y=height, z=length)
  -- local carAABBSize = car.aabbSize
  -- local carAABBSize = CarManager.cars_AABBSIZE[carIndex]
  -- local carHalfWidth = carAABBSize.x * 0.5
  -- local carHalfHeight = carAABBSize.y * 0.5
  -- local carHalfLength = carAABBSize.z * 0.5

  -- local halfAABBSize = CarManager.cars_HALF_AABSIZE[carIndex]
  -- local halfAABBSize = car.aabbSize * 0.5
  local carHalfWidth = halfAABBSize.x
  local carHalfHeight = halfAABBSize.y
  local carHalfLength = halfAABBSize.z

  -- Center at mid-height
  local carCenterWorldPosition = carPosition + carUp * carHalfHeight

  local carRight = -carLeft

  -- todo: ideally I don't calculate everything here since we probably dont need all of them in the calculations

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

local checkForOtherCars = function(worldPosition, direction, distance)
  local carRay = render.createRay(worldPosition,  direction, distance)
  local raycastHitDistance = carRay:cars(BACKFACE_CULLING_FOR_BLOCKING)
  local rayHit = not (raycastHitDistance == -1)
  return rayHit, raycastHitDistance
end

CarOperations.isTargetSideBlocked = function(carIndex)
  local car = ac.getCar(carIndex)
  if not car then return false end

  -- local storage = StorageManager.getStorage()

  -- local carAnchorPoints = CarOperations.getSideAnchorPoints(carIndex,car)
  local carAnchorPoints = CarManager.cars_anchorPoints[carIndex]
  if not carAnchorPoints then
    Logger.log(string.format("CarOperations.isTargetSideBlocked: Car %d has no anchor points calculated", carIndex))
    return false
  end
  -- CarOperations.logCarAnchorPoints(carIndex, carAnchorPoints)

  -- TODO: we can probably reduce the number of rays and do a sort of criss cross on the side instead of the rays shooting directly straight

  -- TODO: another idea could be sphere casting if the api provides it instead of many line rays

  local hitCar, hitDistance = checkForOtherCars(carAnchorPoints.frontLeft, carAnchorPoints.leftDirection, SIDE_DISTANCE_TO_CHECK_FOR_BLOCKING)
  if hitCar then
    return true, CarOperations.CarDirections.FrontLeft, hitDistance
  end

  local hitCar, hitDistance = checkForOtherCars(carAnchorPoints.centerLeft, carAnchorPoints.leftDirection, SIDE_DISTANCE_TO_CHECK_FOR_BLOCKING)
  if hitCar then
    return true, CarOperations.CarDirections.CenterLeft, hitDistance
  end

  hitCar, hitDistance = checkForOtherCars(carAnchorPoints.rearLeft, carAnchorPoints.leftDirection, SIDE_DISTANCE_TO_CHECK_FOR_BLOCKING)
  if hitCar then
    return true, CarOperations.CarDirections.RearLeft, hitDistance
  end

  hitCar, hitDistance = checkForOtherCars(carAnchorPoints.frontRight, carAnchorPoints.rightDirection, SIDE_DISTANCE_TO_CHECK_FOR_BLOCKING)
  if hitCar then
    return true, CarOperations.CarDirections.FrontRight, hitDistance
  end

  hitCar, hitDistance = checkForOtherCars(carAnchorPoints.centerRight, carAnchorPoints.rightDirection, SIDE_DISTANCE_TO_CHECK_FOR_BLOCKING)
  if hitCar then
    return true, CarOperations.CarDirections.CenterRight, hitDistance
  end

  hitCar, hitDistance = checkForOtherCars(carAnchorPoints.rearRight, carAnchorPoints.rightDirection, SIDE_DISTANCE_TO_CHECK_FOR_BLOCKING)
  if hitCar then
    return true, CarOperations.CarDirections.RearRight, hitDistance
  end

  -- Angled left rays (front: 45° toward forward, rear: 45° toward BACK)
  local leftAngledDirFront = carAnchorPoints.leftDirection * INV_SQRT2 + carAnchorPoints.forwardDirection * INV_SQRT2
  local leftAngledDirRear  = carAnchorPoints.leftDirection * INV_SQRT2 - carAnchorPoints.forwardDirection * INV_SQRT2

  hitCar, hitDistance = checkForOtherCars(carAnchorPoints.frontLeft, leftAngledDirFront, SIDE_DISTANCE_TO_CHECK_FOR_BLOCKING)
  if hitCar then
    return true, CarOperations.CarDirections.FrontLeftAngled, hitDistance
  end

  hitCar, hitDistance = checkForOtherCars(carAnchorPoints.rearLeft, leftAngledDirRear, SIDE_DISTANCE_TO_CHECK_FOR_BLOCKING)
  if hitCar then
    return true, CarOperations.CarDirections.RearLeftAngled, hitDistance
  end

  -- Angled right rays (front: 45° toward forward, rear: 45° toward BACK)
  local rightAngledDirFront = carAnchorPoints.rightDirection * INV_SQRT2 + carAnchorPoints.forwardDirection * INV_SQRT2
  local rightAngledDirRear  = carAnchorPoints.rightDirection * INV_SQRT2 - carAnchorPoints.forwardDirection * INV_SQRT2

  hitCar, hitDistance = checkForOtherCars(carAnchorPoints.frontRight, rightAngledDirFront, SIDE_DISTANCE_TO_CHECK_FOR_BLOCKING)
  if hitCar then
    return true, CarOperations.CarDirections.FrontRightAngled, hitDistance
  end

  hitCar, hitDistance = checkForOtherCars(carAnchorPoints.rearRight, rightAngledDirRear, SIDE_DISTANCE_TO_CHECK_FOR_BLOCKING)
  if hitCar then
    return true, CarOperations.CarDirections.RearRightAngled, hitDistance
  end

  return false
end

---comment
---@param carIndex number
---@return boolean
---@return CarOperations.CarDirections
---@return number|nil
CarOperations.checkIfCarIsBlockedByAnotherCarAndSaveAnchorPoints = function(carIndex)
    local car = ac.getCar(carIndex)
    if not car then return false, CarOperations.CarDirections.None, -1 end

    local carPosition = car.position
    local carForward = car.look
    local carLeft = car.side
    local carUp = car.up
    local halfAABBSize = CarManager.cars_HALF_AABSIZE[carIndex]

    local carAnchorPoints = getSideAnchorPoints(carPosition, carForward, carLeft, carUp, halfAABBSize)
    CarManager.cars_anchorPoints[carIndex] = carAnchorPoints

    local isCarOnSide, carOnSideDirection, carOnSideDistance = CarOperations.isTargetSideBlocked(carIndex)
    return isCarOnSide, carOnSideDirection, carOnSideDistance
end

---comment
---@param carDirection CarOperations.CarDirections
CarOperations.getTrackSideFromCarDirection = function(carDirection)
  if carDirection == CarOperations.CarDirections.FrontLeft
  or carDirection == CarOperations.CarDirections.CenterLeft
  or carDirection == CarOperations.CarDirections.RearLeft
  or carDirection == CarOperations.CarDirections.FrontLeftAngled
  or carDirection == CarOperations.CarDirections.RearLeftAngled then
    return RaceTrackManager.TrackSide.LEFT
  elseif carDirection == CarOperations.CarDirections.FrontRight
  or carDirection == CarOperations.CarDirections.CenterRight
  or carDirection == CarOperations.CarDirections.RearRight
  or carDirection == CarOperations.CarDirections.FrontRightAngled
  or carDirection == CarOperations.CarDirections.RearRightAngled then
    return RaceTrackManager.TrackSide.RIGHT
  end

  return nil
end

CarOperations.renderCarBlockCheckRays = function(carIndex)
  local car = ac.getCar(carIndex)
  if not car then return end

  -- local carAnchorPoints = CarOperations.getSideAnchorPoints(carIndex,car)
  local carAnchorPoints = CarManager.cars_anchorPoints[carIndex]
  if not carAnchorPoints then
    Logger.log(string.format("CarOperations.renderCarBlockCheckRays: Car %d has no anchor points calculated", carIndex))
    return
  end

  -- CarOperations.logCarAnchorPoints(carIndex, carAnchorPoints)

  render.debugLine(carAnchorPoints.frontLeft,  carAnchorPoints.frontLeft  + carAnchorPoints.leftDirection  * SIDE_DISTANCE_TO_CHECK_FOR_BLOCKING, RENDER_CAR_BLOCK_CHECK_RAYS_LEFT_COLOR)
  render.debugLine(carAnchorPoints.centerLeft, carAnchorPoints.centerLeft + carAnchorPoints.leftDirection  * SIDE_DISTANCE_TO_CHECK_FOR_BLOCKING, RENDER_CAR_BLOCK_CHECK_RAYS_LEFT_COLOR)
  render.debugLine(carAnchorPoints.rearLeft,   carAnchorPoints.rearLeft   + carAnchorPoints.leftDirection  * SIDE_DISTANCE_TO_CHECK_FOR_BLOCKING, RENDER_CAR_BLOCK_CHECK_RAYS_LEFT_COLOR)

  render.debugLine(carAnchorPoints.frontRight,  carAnchorPoints.frontRight  + carAnchorPoints.rightDirection * SIDE_DISTANCE_TO_CHECK_FOR_BLOCKING, RENDER_CAR_BLOCK_CHECK_RAYS_RIGHT_COLOR)
  render.debugLine(carAnchorPoints.centerRight, carAnchorPoints.centerRight + carAnchorPoints.rightDirection * SIDE_DISTANCE_TO_CHECK_FOR_BLOCKING, RENDER_CAR_BLOCK_CHECK_RAYS_RIGHT_COLOR)
  render.debugLine(carAnchorPoints.rearRight,   carAnchorPoints.rearRight   + carAnchorPoints.rightDirection * SIDE_DISTANCE_TO_CHECK_FOR_BLOCKING, RENDER_CAR_BLOCK_CHECK_RAYS_RIGHT_COLOR)

  -- Angled fork rays (45° towards forward)
  local leftAngledDirFront  = carAnchorPoints.leftDirection  * INV_SQRT2 + carAnchorPoints.forwardDirection * INV_SQRT2
  local leftAngledDirRear   = carAnchorPoints.leftDirection  * INV_SQRT2 - carAnchorPoints.forwardDirection * INV_SQRT2
  local rightAngledDirFront = carAnchorPoints.rightDirection * INV_SQRT2 + carAnchorPoints.forwardDirection * INV_SQRT2
  local rightAngledDirRear  = carAnchorPoints.rightDirection * INV_SQRT2 - carAnchorPoints.forwardDirection * INV_SQRT2

  render.debugLine(carAnchorPoints.frontLeft,  carAnchorPoints.frontLeft  + leftAngledDirFront  * SIDE_DISTANCE_TO_CHECK_FOR_BLOCKING, RENDER_CAR_BLOCK_CHECK_RAYS_LEFT_COLOR)
  render.debugLine(carAnchorPoints.rearLeft,   carAnchorPoints.rearLeft   + leftAngledDirRear   * SIDE_DISTANCE_TO_CHECK_FOR_BLOCKING, RENDER_CAR_BLOCK_CHECK_RAYS_LEFT_COLOR)

  render.debugLine(carAnchorPoints.frontRight, carAnchorPoints.frontRight + rightAngledDirFront * SIDE_DISTANCE_TO_CHECK_FOR_BLOCKING, RENDER_CAR_BLOCK_CHECK_RAYS_RIGHT_COLOR)
  render.debugLine(carAnchorPoints.rearRight,  carAnchorPoints.rearRight  + rightAngledDirRear  * SIDE_DISTANCE_TO_CHECK_FOR_BLOCKING, RENDER_CAR_BLOCK_CHECK_RAYS_RIGHT_COLOR)

end

CarOperations.drawSideAnchorPoints = function(carIndex)
  local car = ac.getCar(carIndex)
  if not car then
    return
  end

  -- local p = CarOperations.getSideAnchorPoints(carIndex, car)
  local p = CarManager.cars_anchorPoints[carIndex]
  if not p then
    Logger.log(string.format("CarOperations.drawSideAnchorPoints: Car %d has no anchor points calculated", carIndex))
    return
  end

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

return CarOperations