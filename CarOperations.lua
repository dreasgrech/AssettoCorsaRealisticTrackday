local CarOperations = {}

--[====[
---@alias CarOperations.CarDirections 
---| `CarOperations.CarDirections.None` @Value: 0.
---| `CarOperations.CarDirections.FrontLeft` @Value: 1.
---| `CarOperations.CarDirections.CenterLeft` @Value: 2.
---| `CarOperations.CarDirections.RearLeft` @Value: 3.
---| `CarOperations.CarDirections.FrontRight` @Value: 4.
---| `CarOperations.CarDirections.CenterRight` @Value: 5.
---| `CarOperations.CarDirections.RearRight` @Value: 6.
---| `CarOperations.CarDirections.FrontLeftAngled` @Value: 7.
---| `CarOperations.CarDirections.RearLeftAngled` @Value: 8.
---| `CarOperations.CarDirections.FrontRightAngled` @Value: 9.
---| `CarOperations.CarDirections.RearRightAngled` @Value: 10.
--]====]

---@enum CarOperations.CarDirections
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

---This 1.2 default value is fetched from the comment of physics.setExtraAIGrip
---which says that the default AI cars grip is 120%
local DEFAULT_AICARS_GRIP = 1.2

local SIDE_DISTANCE_TO_CHECK_FOR_BLOCKING = 3.0
local BACKFACE_CULLING_FOR_BLOCKING = 1 -- set to 0 to disable backface culling, or to -1 to hit backfaces only. Default value: 1.

local INV_SQRT2 = 0.7071067811865476 -- 1/sqrt(2) for exact 45° blend

local RENDER_CAR_BLOCK_CHECK_RAYS_LEFT_COLOR = rgbm(0,0,1,1) -- blue
local RENDER_CAR_BLOCK_CHECK_RAYS_RIGHT_COLOR = rgbm(1,0,0,1) -- red

--[===[
https://discord.com/channels/453595061788344330/962668819933982720/1423344738576109741

* Caution affects how hard they're trying to avoid other cars front to back
* Aggression affects how hard they're trying to avoid other cars left to right
* Difficulty (level) affects how fast they drive through corners as well as how hard they press the throttle
--]===]

---@enum CarOperations.CarPedals
CarOperations.CarPedals = {
  Gas = 1,
  Brake = 2,
  Clutch = 3,
}

---Value from 0 to 1. Final value will be the maximum of original and this.
---(For clutch: 1 is for clutch pedal fully depressed, 0 for pressed).
---@param carIndex integer
---@param carPedal CarOperations.CarPedals
---@param pedalPosition number
CarOperations.setPedalPosition = function(carIndex, carPedal, pedalPosition)
  local carInput = ac.overrideCarControls(carIndex)
  if not carInput then return end

  if carPedal == CarOperations.CarPedals.Gas then
    carInput.gas = pedalPosition
  elseif carPedal == CarOperations.CarPedals.Brake then
    carInput.brake = pedalPosition
  elseif carPedal == CarOperations.CarPedals.Clutch then
    carInput.clutch = pedalPosition
  end
end

---Resets the specified pedal to the original value
---@param carIndex integer
---@param carPedal CarOperations.CarPedals
CarOperations.resetPedalPosition = function(carIndex, carPedal)
  local carInput = ac.overrideCarControls(carIndex)
  if not carInput then return end

  if carPedal == CarOperations.CarPedals.Gas then
    carInput.gas = 0
  elseif carPedal == CarOperations.CarPedals.Brake then
    carInput.brake = 0
  elseif carPedal == CarOperations.CarPedals.Clutch then
    carInput.clutch = 1 -- For clutch: 1 is for clutch pedal fully depressed, 0 for pressed
  end
end

---Returns a boolean value indicating whether the car has arrived at its target spline offset
---@param carIndex integer
---@param drivingToSide RaceTrackManager.TrackSide
---@return boolean
CarOperations.hasArrivedAtTargetSplineOffset = function(carIndex, drivingToSide)
    -- local currentSplineOffset = CarManager.getCalculatedTrackLateralOffset(carIndex)
    local currentSplineOffset = CarManager.getActualTrackLateralOffset(ac.getCar(carIndex).position)
    local targetSplineOffset = CarManager.cars_targetSplineOffset[carIndex]
      if drivingToSide == RaceTrackManager.TrackSide.LEFT then
        return currentSplineOffset <= targetSplineOffset
      end

      return currentSplineOffset >= targetSplineOffset
end

---Limits AI throttle pedal.
---Andreas: I don't think physics.setAIThrottleLimit works as intended because it doesn't seem to have any effect on the car speed.
---Andreas: Or maybe it touches the pedal values?
---@param carIndex integer @0-based car index.
---@param limit number @0 for limit gas pedal to 0, 1 to remove limitation.
CarOperations.setAIThrottleLimit = function(carIndex, limit)
    physics.setAIThrottleLimit(carIndex, limit)
    CarManager.cars_throttleLimit[carIndex] = limit
end

CarOperations.resetAIThrottleLimit = function(carIndex)
  CarOperations.setAIThrottleLimit(carIndex, 1)
end

---Limits AI top speed. Use `math.huge` (or just 1e9) to remove limitation.
---Andreas: I don't think physics.setAITopSpeed works as intended because it doesn't seem to have any effect on the car speed.
---@param carIndex integer @0-based car index.
---@param limit number @Speed in km/h.
CarOperations.setAITopSpeed = function(carIndex, limit)
    physics.setAITopSpeed(carIndex, limit)

    --[===[
    -- Andreas: since physics.setAITopSpeed doesn't seem to work on ai cars atm, I'm also calling the homebrew function here
    CarOperations.limitTopSpeed(carIndex, limit)
    --]===]

    CarManager.cars_aiTopSpeed[carIndex] = limit
end

---Removes the AI top speed limit.
---@param carIndex integer
CarOperations.removeAITopSpeed = function(carIndex)
  CarOperations.setAITopSpeed(carIndex, math.huge)
end

---Changes AI caution, altering the distance it keeps from the car in front of it. Default value: `1`. Experimental.
---@param carIndex integer @0-based car index.
---@param caution number @AI caution from 0 to 16.
CarOperations.setAICaution = function(carIndex, caution)
    physics.setAICaution(carIndex, caution)
    CarManager.cars_aiCaution[carIndex] = caution
end

---Removes any AI caution and sets it back to the default value.
---@param carIndex integer
CarOperations.removeAICaution = function(carIndex)
  local storage = StorageManager.getStorage()
  CarOperations.setAICaution(carIndex, storage.defaultAICaution)
end

---Forces AI to brake for a specified amount of time. Originally, this mechanism is used to get AIs to brake after an incident.
---Subsequent calls overwrite current waiting, pass 0 to get cars to move.
---@param carIndex integer @0-based car index.
---@param time number @Time in seconds.
CarOperations.setAIStopCounter = function(carIndex, time)
    physics.setAIStopCounter(carIndex, time)
    CarManager.cars_aiStopCounter[carIndex] = time
end

---
---@param carIndex integer
---@param grip number @grip value
CarOperations.setGrip = function(carIndex, grip)
    physics.setExtraAIGrip(carIndex, grip)

    CarManager.cars_grip[carIndex] = grip
end

---Sets the AI grip back to the default value.
---@param carIndex integer
CarOperations.setDefaultAIGrip = function(carIndex)
  -- todo: physics.setExtraAIGrip says that the default value is 1 but also says that AI cars have 120% grip
  CarOperations.setGrip(carIndex, DEFAULT_AICARS_GRIP)
end

---Activates or deactivates gentle stopping.
---@param carIndex integer @0-based car index.
---@param stop boolean? @Default value: `true`.
CarOperations.setGentleStop = function(carIndex, stop)
    physics.setGentleStop(carIndex, stop)
    CarManager.cars_gentleStop[carIndex] = stop
end

---Returns a boolean value indicating whether the first car is behind the second car.
---@param firstCar ac.StateCar
---@param secondCar ac.StateCar
---@return boolean
function CarOperations.isFirstCarBehindSecondCar(firstCar, secondCar)
  return firstCar.splinePosition < secondCar.splinePosition

    -- local aiCarFwd = aiCar.look or aiCar.forward or vec3(0,0,1)
    -- local rel = MathHelpers.vsub(playerCar.position, aiCar.position)
    -- return MathHelpers.dot(aiCarFwd, rel) < 0
end

---Returns a boolean value indicating whether the first car is currently faster than the second car.
---@param firstCar ac.StateCar
---@param secondCar ac.StateCar
---@param firstCarSpeedLeeway number @The extra speed that's allowed to the second car to still be considered "faster".
---@return boolean
function CarOperations.isFirstCarCurrentlyFasterThanSecondCar(firstCar, secondCar, firstCarSpeedLeeway)
  return firstCar.speedKmh > secondCar.speedKmh + firstCarSpeedLeeway
end

---Returns a boolean value indicating whether the first car is faster than the second car.
---@param firstCarIndex integer
---@param secondCarIndex integer
---@param secondCarSpeedExtra number @The extra speed that's allowed to the second car to still be considered "faster".
---@return boolean
function CarOperations.isFirstCarFasterThanSecondCar(firstCarIndex, secondCarIndex, secondCarSpeedExtra)
  local firstCarSpeedKmh = CarManager.cars_averageSpeedKmh[firstCarIndex]
  local secondCarSpeedKmh = CarManager.cars_averageSpeedKmh[secondCarIndex]
  return firstCarSpeedKmh > secondCarSpeedKmh + secondCarSpeedExtra
end

---Returns a boolean value indicating whether the second car is clearly ahead of the first car.
---@param firstCar ac.StateCar
---@param secondCar ac.StateCar?
---@param meters number
---@return boolean
function CarOperations.isSecondCarClearlyAhead(firstCar, secondCar, meters)
    if not secondCar then
      return false
    end

    local fwd = firstCar.look
    local rel = MathHelpers.vsub(secondCar.position, firstCar.position)
    return MathHelpers.dot(fwd, rel) > meters
end

---Returns a boolean value indicating whether the second car is clearly behind the first car.
---@param firstCar ac.StateCar
---@param secondCar ac.StateCar
---@param meters number
---@return boolean
function CarOperations.isSecondCarClearlyBehindFirstCar(firstCar, secondCar, meters)
    local fwd = firstCar.look
    local rel = MathHelpers.vsub(secondCar.position, firstCar.position)
    return MathHelpers.dot(fwd, rel) < -meters
end

---limits the ramp up speed of the spline offset when the car is driving at high speed
---@param carSpeedKmh number
---@param rampSpeed number
---@return number rampSpeed
function CarOperations.limitSplitOffsetRampUpSpeed(carSpeedKmh, rampSpeed)
  if carSpeedKmh > 300 then
    return rampSpeed * 0.1
  elseif carSpeedKmh > 200 then
    return rampSpeed * 0.25
  elseif carSpeedKmh > 100 then
    return rampSpeed * 0.5
  end
  return rampSpeed
end

---
---@param car ac.StateCar
---@return boolean
function CarOperations.isCarInPits(car)
  return car.isInPit or car.isInPitlane
end

---Applies a bunch of values to stop the car
---@param carIndex integer
function CarOperations.stopCarAfterAccident(carIndex)
    -- stop the car
    CarOperations.setAIThrottleLimit(carIndex, 0)
    CarOperations.setAITopSpeed(carIndex, 0)
    CarOperations.setAIStopCounter(carIndex, 1)
    CarOperations.setGentleStop(carIndex, true)
    CarOperations.setAICaution(carIndex, 16) -- be very cautious

    physics.preventAIFromRetiring(carIndex)
end

---@param turningLights ac.TurningLights
function CarOperations.toggleTurningLights(carIndex, turningLights)
    -- local c = ac.getCar(carIndex)
    -- if not c.hasTurningLights then
        -- Logger.warn(string.format("CarOperations.toggleTurningLights: Car %d has no turning lights", carIndex))
        -- return
    -- end

    if ac.setTargetCar(carIndex) then
        ac.setTurningLights(turningLights)
    else
      Logger.warn(string.format("CarOperations.toggleTurningLights: Could not set target car to %d", carIndex))
    end

    -- TODO: we don't need all of these
    -- CarManager.cars_currentTurningLights[carIndex] = turningLights
    -- CarManager.cars_indLeft[carIndex] = car.turningLeftLights
    -- CarManager.cars_indRight[carIndex] = car.turningRightLights
    -- CarManager.cars_indPhase[carIndex] = car.turningLightsActivePhase
    -- CarManager.cars_hasTL[carIndex] = car.hasTurningLights
end

--[======[
---Tries to limit the top speed of the car by adjusting the gas and brake pedals.
---Andreas: I wrote this function because physics.setAITopSpeed doesn't seem to work on ai cars right now
---Andreas: Update: I can't do proper pedal modulation because the api doesn't allow me to set absolute pedal values and always chooses the maximum of my value and the original ai value.
---@param carIndex number
---@param maxSpeedKmh number
CarOperations.limitTopSpeed = function(carIndex, maxSpeedKmh)
    local car = ac.getCar(carIndex)
    if not car then return end

    --[===[
    -- determine the amount of brake we need to apply to keep the car at or below the max speed
    local brakeAmount = math.min(math.max((car.speedKmh - maxSpeedKmh) / 50, 0), 1)

    if car.speedKmh > maxSpeedKmh then
        CarOperations.setPedalPosition(carIndex, CarOperations.CarPedals.Brake, brakeAmount)
        CarOperations.setPedalPosition(carIndex, CarOperations.CarPedals.Gas, 0)
    else
        CarOperations.resetPedalPosition(carIndex, CarOperations.CarPedals.Brake)
        CarOperations.resetPedalPosition(carIndex, CarOperations.CarPedals.Gas)
    end
    --]===]


    --[===[
    local sim = ac.getSim()
    local dt = sim.dt
    CarSpeedLimiter.limitTopSpeed(carIndex, maxSpeedKmh, dt)
    --]===]
end
--]======]

--- Drives the car to the specified side while making sure there are no cars blocking the side we're trying to drive to.
---@param carIndex number
---@param dt number
---@param car ac.StateCar
---@param side RaceTrackManager.TrackSide
---@param driveToSideMaxOffset number
---@param rampSpeed_mps number
---@param overrideAiAwareness boolean
---@return boolean
function CarOperations.driveSafelyToSide(carIndex, dt, car, side, driveToSideMaxOffset,rampSpeed_mps, overrideAiAwareness)
    -- make sure there isn't any car on the side we're trying to drive to so we don't crash into it
    local isSideSafeToDrive = CarStateMachine.isSafeToDriveToTheSide(carIndex, side)
    if not isSideSafeToDrive then
        -- return false since we can't drive to the side safely
        return false
    end

      -- todo: should these operations be here?
      -- todo: should these operations be here?
      -- todo: should these operations be here?
      -- todo: should these operations be here?
      CarOperations.resetPedalPosition(carIndex, CarOperations.CarPedals.Brake)
      CarOperations.resetAIThrottleLimit(carIndex) -- remove any speed limit we may have applied while waiting for a gap
      CarOperations.setGrip(carIndex, 1.4) -- increase grip while driving to the side

      -- if we are driving at high speed, we need to increase the ramp speed slower so that our car doesn't jolt out of control
      -- local splineOffsetTransitionSpeed = CarOperations.limitSplitOffsetRampUpSpeed(car.speedKmh, storage.rampSpeed_mps)
      local splineOffsetTransitionSpeed = CarOperations.limitSplitOffsetRampUpSpeed(car.speedKmh, rampSpeed_mps)

      local drivingToTheLeft = side == RaceTrackManager.TrackSide.LEFT
      local sideSign = drivingToTheLeft and -1 or 1
      -- local currentSplineOffset = CarManager.cars_currentSplineOffset[carIndex]
      local currentSplineOffset = CarManager.getCalculatedTrackLateralOffset(carIndex)
      -- local currentSplineOffset = CarManager.getActualTrackLateralOffset(car.position)

      -- local targetSplineOffset = storage.maxLateralOffset_normalized * sideSign
      -- TODO: limit the target offset when we are approaching a corner or in mid corner!
      -- TODO: https://github.com/dreasgrech/AssettoCorsaRealisticTrackday/issues/41
      -- TODO: also maybe take a look at physics.setExtraAIGrip
      local targetSplineOffset = driveToSideMaxOffset * sideSign
      currentSplineOffset = MathHelpers.approach(currentSplineOffset, targetSplineOffset, splineOffsetTransitionSpeed * dt)

      -- set the spline offset on the ai car
      -- local overrideAiAwareness = storage.overrideAiAwareness -- TODO: check what this does
      physics.setAISplineOffset(carIndex, currentSplineOffset, overrideAiAwareness)

      -- keep the turning lights on while driving to the side
      local turningLights = drivingToTheLeft and ac.TurningLights.Left or ac.TurningLights.Right
      -- CarOperations.toggleTurningLights(carIndex, car, turningLights)
      CarOperations.toggleTurningLights(carIndex, turningLights)

      CarManager.cars_currentSplineOffset[carIndex] = currentSplineOffset
      CarManager.cars_targetSplineOffset[carIndex] = targetSplineOffset

      return true
end

-- Returns the six lateral anchor points plus some helpers
---@return table
-- local getSideAnchorPoints = function(carPosition, carForward, carLeft, carUp, halfAABBSize)
CarOperations.getSideAnchorPoints = function(carPosition, carForward, carLeft, carUp, halfAABBSize)
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

  local carForwardHalfCarLengthDirection = carForward * carHalfLength
  local carLeftHalfCarWidthDirection = carLeft * carHalfWidth
  local frontLeftWorldPosition   = carCenterWorldPosition + carForwardHalfCarLengthDirection + carLeftHalfCarWidthDirection
  local centerLeftWorldPosition  = carCenterWorldPosition + carLeftHalfCarWidthDirection
  local rearLeftWorldPosition    = carCenterWorldPosition - carForwardHalfCarLengthDirection + carLeftHalfCarWidthDirection

  local carRightHalfCarWidthDirection = carRight * carHalfWidth
  local frontRightWorldPosition  = carCenterWorldPosition + carForwardHalfCarLengthDirection + carRightHalfCarWidthDirection
  local centerRightWorldPosition = carCenterWorldPosition + carRightHalfCarWidthDirection
  local rearRightWorldPosition   = carCenterWorldPosition - carForwardHalfCarLengthDirection + carRightHalfCarWidthDirection

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
  --  Maybe using physics.raycastTrack(...) could be faster
  --  Andreas: it seems like physics.raycastTrack does not hit cars, only the track
  -- local raycastHitDistance = physics.raycastTrack(worldPosition, direction, distance) 
  local carRay = render.createRay(worldPosition,  direction, distance)
  local raycastHitDistance = carRay:cars(BACKFACE_CULLING_FOR_BLOCKING)
  local rayHit = not (raycastHitDistance == -1)
  return rayHit, raycastHitDistance
end

--[=====[
---comment
---@param carIndex any
---@return boolean
---@return CarOperations.CarDirections
---@return number
CarOperations.isTargetSideBlocked = function(carIndex)
  local car = ac.getCar(carIndex)
  if not car then return false, CarOperations.CarDirections.None, 0 end

  -- local storage = StorageManager.getStorage()

  -- local carAnchorPoints = CarOperations.getSideAnchorPoints(carIndex,car)
  local carAnchorPoints = CarManager.cars_anchorPoints[carIndex]
  if not carAnchorPoints then
    Logger.log(string.format("CarOperations.isTargetSideBlocked: Car %d has no anchor points calculated", carIndex))
    return false, CarOperations.CarDirections.None, 0
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

  return false, CarOperations.CarDirections.None, 0
end
--]=====]

---comment
---@param carIndex any
---@param sideToCheck RaceTrackManager.TrackSide
---@return boolean
---@return integer
---@return integer
CarOperations.checkIfCarIsBlockedByAnotherCarAndSaveSideBlockRays = function(carIndex, sideToCheck)
    local car = ac.getCar(carIndex)
    if not car then return false, CarOperations.CarDirections.None, -1 end

    -- local carIndex = car.index
    local carPosition = car.position
    local carForward  = car.look
    local carLeftDirection     = car.side
    local carUp       = car.up
    local halfAABBSize = CarManager.cars_HALF_AABSIZE[carIndex]
    if not halfAABBSize.z then
      Logger.error(string.format("CarOperations.checkIfCarIsBlockedByAnotherCarAndSaveSideBlockRays_NEWDoDAPPROACH: Car %d has no halfAABBSize.z calculated", carIndex))
    end

    -- TODO: remove use of CarOperations.getSideAnchorPoints here and only calculate what we need
    local p = CarOperations.getSideAnchorPoints(carPosition, carForward, carLeftDirection, carUp, halfAABBSize)  -- returns left/right dirs too
    -- local pLeftDirection = p.leftDirection
    -- local pRightDirection = p.rightDirection
    local sideGap = 2.0

    --[====[
    CarManager.cars_totalSideBlockRaysData[carIndex] = 2

    local pLeftDirection = carLeftDirection
    local pRearLeft  = p.rearLeft
    local leftOffset  = pLeftDirection  * sideGap
    local ray1_pos  = pRearLeft + leftOffset
    local ray1_dir  = carForward
    local ray1_len  = (halfAABBSize.z * 2)-- + 6
    -- todo: cache array here instead of calling carmanager.cars_sideBlockRaysData[carIndex] multiple times
    CarManager.cars_sideBlockRaysData[carIndex][0] = ray1_pos
    CarManager.cars_sideBlockRaysData[carIndex][1] = ray1_dir
    CarManager.cars_sideBlockRaysData[carIndex][2] = ray1_len

    local pRightDirection = -carLeftDirection
    local pRearRight = p.rearRight
    local rightOffset = pRightDirection * sideGap
    local ray2_pos  = pRearRight + rightOffset
    local ray2_dir  = carForward
    local ray2_len  = (halfAABBSize.z * 2)-- + 3
    CarManager.cars_sideBlockRaysData[carIndex][3] = ray2_pos
    CarManager.cars_sideBlockRaysData[carIndex][4] = ray2_dir
    CarManager.cars_sideBlockRaysData[carIndex][5] = ray2_len


    local rightHitCar, rightHitCarDistance = checkForOtherCars(ray2_pos, ray2_dir, ray2_len)
    if rightHitCar then
      -- TODO: can we be more specific with the direction here?
      return true, CarOperations.CarDirections.CenterRight, rightHitCarDistance
    end

    local leftHitCar, leftHitCarDistance = checkForOtherCars(ray1_pos, ray1_dir, ray1_len)
    if leftHitCar then
      -- TODO: can we be more specific with the direction here?
      return true, CarOperations.CarDirections.CenterLeft, leftHitCarDistance
    end
    --]====]

    ---------------------------------
    CarManager.cars_totalSideBlockRaysData[carIndex] = 1
    local pDirection, pRearPosition, hitDirection
    if sideToCheck == RaceTrackManager.TrackSide.LEFT then
      pDirection = carLeftDirection
      pRearPosition = p.rearLeft
      hitDirection = CarOperations.CarDirections.CenterLeft
    else
      pDirection = -carLeftDirection
      pRearPosition = p.rearRight
      hitDirection = CarOperations.CarDirections.CenterRight
    end
      
    local offset = pDirection * sideGap

    local ray_pos = (pRearPosition + offset) + (-carForward * (halfAABBSize.z))
    local ray_dir = carForward
    -- local ray_len = (halfAABBSize.z * 2)
    local ray_len = (halfAABBSize.z * 4)
    CarManager.cars_sideBlockRaysData[carIndex][0] = ray_pos
    CarManager.cars_sideBlockRaysData[carIndex][1] = ray_dir
    CarManager.cars_sideBlockRaysData[carIndex][2] = ray_len

    local hitCar, hitCarDistance = checkForOtherCars(ray_pos, ray_dir, ray_len)
    return hitCar, hitDirection, hitCarDistance
    -- if hitCar then
      -- return true, hitDirection, hitCarDistance
    -- end
    ---------------------------------

    -- return false, CarOperations.CarDirections.None, 0
  end

--[=====[
---comment
---@param carIndex number
---@return boolean
---@return CarOperations.CarDirections|integer
---@return number|nil
CarOperations.checkIfCarIsBlockedByAnotherCarAndSaveAnchorPoints = function(carIndex)
    local car = ac.getCar(carIndex)
    if not car then return false, CarOperations.CarDirections.None, -1 end

    local carPosition = car.position
    local carForward = car.look
    local carLeft = car.side
    local carUp = car.up
    local halfAABBSize = CarManager.cars_HALF_AABSIZE[carIndex]

    local carAnchorPoints = CarOperations.getSideAnchorPoints(carPosition, carForward, carLeft, carUp, halfAABBSize)
    CarManager.cars_anchorPoints[carIndex] = carAnchorPoints

    local isCarOnSide, carOnSideDirection, carOnSideDistance = CarOperations.isTargetSideBlocked(carIndex)
    return isCarOnSide, carOnSideDirection, carOnSideDistance
end
--]=====]

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

CarOperations.renderCarBlockCheckRays_NEWDoDAPPROACH = function(carIndex)
  local totalSideBlockRaysData = CarManager.cars_totalSideBlockRaysData[carIndex]
  if not totalSideBlockRaysData then
    return
  end

  local sideBlockRaysData = CarManager.cars_sideBlockRaysData[carIndex]
  for i = 0, totalSideBlockRaysData - 1 do
    local pos = sideBlockRaysData[(i*3)]
    local dir = sideBlockRaysData[(i*3)+1]
    local len = sideBlockRaysData[(i*3)+2]

    -- Logger.log(string.format("CarOperations.renderCarBlockCheckRays_NEWDoDAPPROACH: car #%d pos: %s, dir: %s, len: %s", carIndex, tostring(pos), tostring(dir), tostring(len)))
    render.debugLine(pos, pos + dir * len, RENDER_CAR_BLOCK_CHECK_RAYS_RIGHT_COLOR)
  end
end

-- CarOperations.renderCarBlockCheckRays_PARALLELLINES = function(carIndex)
  -- local car = ac.getCar(carIndex)
  -- if not car then return end

  -- -- Build fresh anchors (front/rear on each side + directions)
  -- local carPosition = car.position
  -- local carForward  = car.look
  -- local carLeft     = car.side
  -- local carUp       = car.up
  -- local halfAABBSize = CarManager.cars_HALF_AABSIZE[carIndex]
  -- local p = CarOperations.getSideAnchorPoints(carPosition, carForward, carLeft, carUp, halfAABBSize)  -- returns left/right dirs too
  -- -- p has: frontLeft, rearLeft, frontRight, rearRight, leftDirection, rightDirection, etc.  

  -- -- How far to place the parallel lines from the car’s sides (meters).
  -- -- You can expose this in UI and store it in storage.parallelLinesSideGap or CarManager.sideParallelLinesGap.
  -- -- local storage = (StorageManager and StorageManager.getStorage) and StorageManager.getStorage() or nil
  -- local sideGap = 
              -- -- (storage and storage.parallelLinesSideGap)
               -- -- or CarManager.sideParallelLinesGap
               -- -- or 
               -- 1.0

  -- -- Offset vectors away from body
  -- local leftOffset  = p.leftDirection  * sideGap
  -- local rightOffset = p.rightDirection * sideGap

  -- -- Draw two long parallel lines, rear→front, one on each side
  -- render.debugLine(p.rearLeft  + leftOffset,  p.frontLeft  + leftOffset,  RENDER_CAR_BLOCK_CHECK_RAYS_LEFT_COLOR)   -- blue by your constants 
  -- render.debugLine(p.rearRight + rightOffset, p.frontRight + rightOffset, RENDER_CAR_BLOCK_CHECK_RAYS_RIGHT_COLOR)  -- red
-- end


--[=====[
CarOperations.renderCarBlockCheckRays = function(carIndex)
-- CarOperations.renderCarBlockCheckRays = function(car)
  -- local car = ac.getCar(carIndex)
  -- if not car then return end

  -- local carAnchorPoints = CarOperations.getSideAnchorPoints(carIndex,car)
  local carAnchorPoints = CarManager.cars_anchorPoints[carIndex]
  if not carAnchorPoints then
    -- Logger.log(string.format("CarOperations.renderCarBlockCheckRays: Car %d has no anchor points calculated", carIndex))
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
--]=====]

--[=====[
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
--]=====]

--[=====[
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
--]=====]

return CarOperations