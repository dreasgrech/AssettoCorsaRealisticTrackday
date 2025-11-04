local CarOperations = {}

-- bindings
local ac = ac
local physics = physics
local vec3 = vec3
local rgbm = rgbm
local approach = MathHelpers.approach
local vsub = MathHelpers.vsub
local dot = MathHelpers.dot
local CarManager = CarManager

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

-- local SIDE_DISTANCE_TO_CHECK_FOR_BLOCKING = 3.0
-- local BACKFACE_CULLING_FOR_BLOCKING = 1 -- set to 0 to disable backface culling, or to -1 to hit backfaces only. Default value: 1.

local INV_SQRT2 = 0.7071067811865476 -- 1/sqrt(2) for exact 45° blend

-- local RENDER_CAR_BLOCK_CHECK_RAYS_LEFT_COLOR = rgbm(0,0,1,1) -- blue
-- local RENDER_CAR_BLOCK_CHECK_RAYS_RIGHT_COLOR = rgbm(1,0,0,1) -- red
local RENDER_CAR_BLOCK_CHECK_RAYS_NON_HIT_COLOR = ColorManager.RGBM_Colors.Red
local RENDER_CAR_BLOCK_CHECK_RAYS_HIT_COLOR = ColorManager.RGBM_Colors.SeaGreen

local DISTANCE_TO_UPCOMING_CORNER_TO_INCREASE_AICAUTION = 25 -- if an upcoming corner is closer than this, increase the caution level

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

-- local ARRIVED_AT_TARGET_SPLINE_OFFSET_EPSILON = 0.02 -- in lateral spline offset units
local ARRIVED_AT_TARGET_SPLINE_OFFSET_EPSILON = 0.1 -- in lateral spline offset units

---Returns a boolean value indicating whether the car has arrived at its target spline offset
---@param carIndex integer
---@param drivingToSide RaceTrackManager.TrackSide
---@return boolean
CarOperations.hasArrivedAtTargetSplineOffset = function(carIndex, drivingToSide)
    -- local currentSplineOffset = CarManager.getCalculatedTrackLateralOffset(carIndex)
    local currentSplineOffset = CarManager.getActualTrackLateralOffset(ac.getCar(carIndex).position)
    local targetSplineOffset = CarManager.cars_targetSplineOffset[carIndex]
      if drivingToSide == RaceTrackManager.TrackSide.LEFT then
        return currentSplineOffset - ARRIVED_AT_TARGET_SPLINE_OFFSET_EPSILON <= targetSplineOffset
      end

      return currentSplineOffset + ARRIVED_AT_TARGET_SPLINE_OFFSET_EPSILON >= targetSplineOffset
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

---Changes AI aggression.
---@param carIndex integer @0-based car index.
---@param aggression number @AI aggression from 0 to 1. Note: aggression level set in a launcher will be multiplied by 0.95, so to set 100% aggression here, pass 0.95.
CarOperations.setAIAggression = function(carIndex, aggression)
    physics.setAIAggression(carIndex, aggression)
    CarManager.cars_aiAggression[carIndex] = aggression
end

---Removes any AI aggression and sets it back to the default value.
---@param carIndex integer @0-based car index.
CarOperations.setDefaultAIAggression = function(carIndex)
  local aiAggression = CarManager.getDefaultAIAggression(carIndex)
  CarOperations.setAIAggression(carIndex, aiAggression)
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
  CarOperations.setGrip(carIndex, CarManager.GripValues.NORMAL)
end

---Toggles a car's colliders
---@param carIndex integer
---@param collisionsEnabled boolean
CarOperations.toggleCarCollisions = function(carIndex, collisionsEnabled)
  physics.disableCarCollisions(carIndex, not collisionsEnabled, true)
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
    local rel = vsub(secondCar.position, firstCar.position)
    return dot(fwd, rel) > meters
end

---Returns a boolean value indicating whether the second car is clearly behind the first car.
---@param firstCar ac.StateCar
---@param secondCar ac.StateCar
---@param meters number
---@return boolean
function CarOperations.isSecondCarClearlyBehindFirstCar(firstCar, secondCar, meters)
    local fwd = firstCar.look
    local rel = vsub(secondCar.position, firstCar.position)
    return dot(fwd, rel) < -meters
end

---limits the ramp up speed of the spline offset when the car is driving at high speed
---@param carSpeedKmh number
---@param rampSpeed number
---@return number rampSpeed
function CarOperations.limitSplineOffsetRampUpSpeed(carSpeedKmh, rampSpeed)
  if carSpeedKmh > 300 then
    return rampSpeed * 0.1
  elseif carSpeedKmh > 200 then
    return rampSpeed * 0.25
  elseif carSpeedKmh > 100 then
    return rampSpeed * 0.8
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
    CarOperations.setAICaution(carIndex, CarManager.AICautionValues.AFTER_ACCIDENT) -- be very cautious

    CarOperations.preventAIFromRetiring(carIndex)
end

---Prevent an AI from retiring for some time. 
---If not moving, they will still retire some time after this function is called, unless you’ll keep calling it.
---@param carIndex integer @0-based car index.
function CarOperations.preventAIFromRetiring(carIndex)
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

-- TODO: I'm thinking maybe the side parameter should be removed and we instead feed an absolute driveToSideMaxOffset which is [-1..1] 
-- TODO: and then determining the side from it since the value will be [-1..0]
--- Drives the car to the specified side while making sure there are no cars blocking the side we're trying to drive to.
---@param carIndex number @0-based car index.
---@param dt number @Delta time in seconds.
---@param car ac.StateCar @The ac.StateCar table of the car.
-- ---@param side RaceTrackManager.TrackSide @The side to drive to.
-- ---@param driveToSideMaxOffset number @The maximum lateral offset to drive to on the specified side.
---@param targetLateralOffset number @The maximum lateral offset to drive to on the specified side.
---@param rampSpeed_mps number @The speed at which to ramp up the lateral offset.
---@param overrideAiAwareness boolean @Whether to override AI awareness.
---@param sideCheck boolean @Whether to check if the side is safe to drive to.
---@param useIndicatorLights boolean @Whether to use indicator lights while driving to the side.
---@return boolean
-- function CarOperations.driveSafelyToSide(carIndex, dt, car, side, driveToSideMaxOffset, rampSpeed_mps, overrideAiAwareness, sideCheck)
function CarOperations.driveSafelyToSide(carIndex, dt, car, targetLateralOffset, rampSpeed_mps, overrideAiAwareness, sideCheck, useIndicatorLights)
    -- calculate the side we're driving to based on the car's current lateral offset and the target lateral offset
    local carPosition = car.position
    local currentActualTrackLateralOffset = CarManager.getActualTrackLateralOffset(carPosition)
    local side = targetLateralOffset < currentActualTrackLateralOffset and RaceTrackManager.TrackSide.LEFT or RaceTrackManager.TrackSide.RIGHT

    -- save a copy of the original side for indicator lights because we may change the side variable later
    local sideForIndicatorLights = side

    -- make sure there isn't any car on the side we're trying to drive to so we don't crash into it
    if sideCheck then
      local isSideSafeToDrive = CarStateMachine.isSafeToDriveToTheSide(carIndex, side)
      local isCarOffTrack = CarManager.isCarOffTrack(car, side)
      local sideNotSafe = not isSideSafeToDrive
      -- if not isSideSafeToDrive then
      if sideNotSafe or isCarOffTrack then
          -- return false since we can't drive to the side safely
          -- return false
          -- drive to the other side to avoid colliding with the car on this side
          side = RaceTrackManager.getOppositeSide(side) -- if the side is not safe, drive to the other side temporarily

          -- do another side check on the other side since we're driving to the other side now
          local isOtherSideSafeToDrive = CarStateMachine.isSafeToDriveToTheSide(carIndex, side)
          if not isOtherSideSafeToDrive then
            -- both sides are blocked, so we can't drive to either side safely
            return false
          end

          -- driveToSideMaxOffset = driveToSideMaxOffset * 0.5 -- drive to the other side but not fully
          -- targetLateralOffset = targetLateralOffset * 0.5 -- drive to the other side but not fully
          targetLateralOffset = -targetLateralOffset * 0.5 -- drive to the other side but not fully
          rampSpeed_mps = rampSpeed_mps * 0.5 -- drive more slowly to the other side
          -- useIndicatorLights = false -- don't use indicator lights when driving to the other side temporarily
      end
    end

      -- todo: should these operations be here?
      -- todo: should these operations be here?
      -- todo: should these operations be here?
      -- todo: should these operations be here?
      -- CarOperations.resetPedalPosition(carIndex, CarOperations.CarPedals.Brake)
      -- CarOperations.resetAIThrottleLimit(carIndex) -- remove any speed limit we may have applied while waiting for a gap
      CarOperations.setGrip(carIndex, CarManager.GripValues.DRIVING_TO_THE_SIDE) -- increase grip while driving to the side

      -- if we are driving at high speed, we need to decrease the ramp speed so that our car doesn't jolt out of control
      -- local splineOffsetTransitionSpeed = CarOperations.limitSplitOffsetRampUpSpeed(car.speedKmh, storage.rampSpeed_mps)
      local splineOffsetTransitionSpeed = CarOperations.limitSplineOffsetRampUpSpeed(car.speedKmh, rampSpeed_mps)

      -- local sideSign = drivingToTheLeft and -1 or 1

      -- TODO: Are you sure we shouldn't be using the actual track lateral offset here?
      local currentSplineOffset = CarManager.getCalculatedTrackLateralOffset(carIndex)
      -- local currentSplineOffset = currentActualTrackLateralOffset -- the problem with this one is that if the increase in offset is too low, the ai can override it and still go the other direction

      -- local targetSplineOffset = storage.maxLateralOffset_normalized * sideSign
      -- TODO: limit the target offset when we are approaching a corner or in mid corner!
      -- TODO: https://github.com/dreasgrech/AssettoCorsaRealisticTrackday/issues/41

      -- local targetSplineOffset = driveToSideMaxOffset * sideSign
      local targetSplineOffset = targetLateralOffset

      local step = splineOffsetTransitionSpeed * dt
      currentSplineOffset = approach(currentSplineOffset, targetSplineOffset, step)

      -- set the spline offset on the ai car
      -- local overrideAiAwareness = storage.overrideAiAwareness -- TODO: check what this does
      physics.setAISplineOffset(carIndex, currentSplineOffset, overrideAiAwareness)

      -- keep the turning lights on while driving to the side
      if useIndicatorLights then
        local drivingToTheLeft = sideForIndicatorLights == RaceTrackManager.TrackSide.LEFT
        local turningLights = drivingToTheLeft and ac.TurningLights.Left or ac.TurningLights.Right
        CarOperations.toggleTurningLights(carIndex, turningLights)
      end

      CarManager.cars_currentSplineOffset[carIndex] = currentSplineOffset
      CarManager.cars_targetSplineOffset[carIndex] = targetSplineOffset

      return true
end

--- Drives the car to the overtaking lane while making sure there are no cars blocking the side.
---@param carIndex integer
---@param dt number
---@param car ac.StateCar
---@param storage StorageTable
---@param useIndicatorLights boolean
---@return boolean
function CarOperations.overtakeSafelyToSide(carIndex, dt, car, storage, useIndicatorLights)
    local storage_Overtaking = StorageManager.getStorage_Overtaking()
    local driveToSide = RaceTrackManager.getOvertakingSide()
    -- local targetOffset = storage.maxLateralOffset_normalized
    -- local targetOffset = storage.maxLateralOffset_normalized * RaceTrackManager.getLateralOffsetSign(driveToSide)
    local targetOffset = storage.overtakingLateralOffset
    local rampSpeed_mps = storage_Overtaking.overtakeRampSpeed_mps
    local overrideAiAwareness = storage.overrideAiAwareness

    -- return CarOperations.driveSafelyToSide(carIndex, dt, car, driveToSide, targetOffset, rampSpeed_mps, overrideAiAwareness, true)
    local handleSideCheckingWhenOvertaking = storage_Overtaking.handleSideCheckingWhenOvertaking
    return CarOperations.driveSafelyToSide(carIndex, dt, car, targetOffset, rampSpeed_mps, overrideAiAwareness, handleSideCheckingWhenOvertaking, useIndicatorLights)
end

--- Drives the car to the yielding lane while making sure there are no cars blocking the side.
---@param carIndex integer
---@param dt number
---@param car ac.StateCar
---@param storage StorageTable
---@param useIndicatorLights boolean
---@return boolean
function CarOperations.yieldSafelyToSide(carIndex, dt, car, storage, useIndicatorLights)
      local driveToSide = RaceTrackManager.getYieldingSide()
      -- local targetOffset = storage.maxLateralOffset_normalized
      -- local targetOffset = storage.maxLateralOffset_normalized * RaceTrackManager.getLateralOffsetSign(driveToSide)
      local storage_Yielding = StorageManager.getStorage_Yielding()
      local targetOffset = storage.yieldingLateralOffset
      local rampSpeed_mps = storage_Yielding.rampSpeed_mps
      local overrideAiAwareness = storage.overrideAiAwareness

      -- return CarOperations.driveSafelyToSide(carIndex, dt, car, driveToSide, targetOffset, rampSpeed_mps, overrideAiAwareness, true)
      local handleSideCheckingWhenYielding = storage_Yielding.handleSideCheckingWhenYielding
      return CarOperations.driveSafelyToSide(carIndex, dt, car, targetOffset, rampSpeed_mps, overrideAiAwareness, handleSideCheckingWhenYielding, useIndicatorLights)
end

---Calculated the overtaking car's ai caution value while overtaking another car.
---@param overtakingCar ac.StateCar
---@param yieldingCar ac.StateCar?
---@return number aiCaution
---@return number aiAggression 
CarOperations.calculateAICautionAndAggressionWhileOvertaking = function(overtakingCar, yieldingCar)
    local overtakingCarTrackLateralOffset = CarManager.getActualTrackLateralOffset(overtakingCar.position)

    -- by default we use the lowerered ai caution while overtaking so that the cars speed up a bit
    local aiCaution = CarManager.AICautionValues.OVERTAKING_WITH_OBSTACLE_INFRONT
    local aiAggression = CarManager.AIAggressionValues.OVERTAKING_WITH_OBSTACLE_INFRONT

    -- Check if it's safe in front of us to drop the caution to 0 so that we can really step on it
    if yieldingCar then
        -- if the car in front of us is not in front of us, we can drop the caution to 0 to speed up overtaking
        local yieldingCarTrackLateralOffset = CarManager.getActualTrackLateralOffset(yieldingCar.position)
        local lateralOffsetsDelta = math.abs(overtakingCarTrackLateralOffset - yieldingCarTrackLateralOffset)
        if lateralOffsetsDelta > 0.4 then -- if the lateral offset is more than half a lane apart, we can consider it safe
            -- aiCaution = AICAUTION_WHILE_OVERTAKING_AND_NO_OBSTACLE_INFRONT
            aiCaution = CarManager.AICautionValues.OVERTAKING_WITH_NO_OBSTACLE_INFRONT
            aiAggression = CarManager.AIAggressionValues.OVERTAKING_WITH_NO_OBSTACLE_INFRONT
        end
    end

    -- If an upcoming corner is coming , increase the caution a bit so that we don't go flying off the track
    local overtakingCarIndex = overtakingCar.index
    local isMidCorner, distanceToUpcomingTurn = CarManager.isCarMidCorner(overtakingCarIndex)
    if isMidCorner or distanceToUpcomingTurn < DISTANCE_TO_UPCOMING_CORNER_TO_INCREASE_AICAUTION then
        aiCaution = CarManager.AICautionValues.OVERTAKING_WHILE_INCORNER
        aiAggression = CarManager.AIAggressionValues.OVERTAKING_WHILE_INCORNER
    end

    return aiCaution, aiAggression
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

local checkForOtherCars = function(carIndex, worldPosition, direction, distance)
  --  Maybe using physics.raycastTrack(...) could be faster
  --  Andreas: it seems like physics.raycastTrack does not hit cars, only the track
  -- local raycastHitDistance = physics.raycastTrack(worldPosition, direction, distance) 
  local carRay = render.createRay(worldPosition,  direction, distance)
  --[===[]
  local raycastHitDistance = carRay:cars(BACKFACE_CULLING_FOR_BLOCKING)
  local rayHit = not (raycastHitDistance == -1)
  return rayHit, raycastHitDistance
  --]===]

  -- TODO: Optimize this because we certainly do not need to check all cars every time
  -- TODO: Optimize this because we certainly do not need to check all cars every time
  -- TODO: Optimize this because we certainly do not need to check all cars every time
  local sortedCarsList = CarManager.currentSortedCarsList
  for i = 1, #sortedCarsList do
    local car = sortedCarsList[i]
    local otherCarIndex = car.index
    if otherCarIndex ~= carIndex then
      local raycastHitDistance = carRay:carCollider(otherCarIndex)
      local rayHit = not (raycastHitDistance == -1)
      if rayHit then
        return rayHit, raycastHitDistance
      end
    end
  end
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
    local sideGap = 1

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
    local hitCar, hitCarDistance = checkForOtherCars(carIndex, ray_pos, ray_dir, ray_len)

    CarManager.cars_sideBlockRaysData[carIndex][0] = ray_pos
    CarManager.cars_sideBlockRaysData[carIndex][1] = ray_dir
    CarManager.cars_sideBlockRaysData[carIndex][2] = ray_len
    CarManager.cars_sideBlockRaysData[carIndex][3] = hitCar

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
    local pos = sideBlockRaysData[(i*4)]
    local dir = sideBlockRaysData[(i*4)+1]
    local len = sideBlockRaysData[(i*4)+2]
    local hit = sideBlockRaysData[(i*4)+3]

    -- Logger.log(string.format("CarOperations.renderCarBlockCheckRays_NEWDoDAPPROACH: car #%d pos: %s, dir: %s, len: %s", carIndex, tostring(pos), tostring(dir), tostring(len)))
    local color = hit and RENDER_CAR_BLOCK_CHECK_RAYS_HIT_COLOR or RENDER_CAR_BLOCK_CHECK_RAYS_NON_HIT_COLOR
    render.debugLine(pos, pos + dir * len, color)
  end
end

CarOperations.renderCarSideOffTrack = function(carIndex)
  local car = ac.getCar(carIndex)
  if not car then return end

  local carWheels = car.wheels
  local carOffTrackLeft = CarManager.isCarOffTrack(car, RaceTrackManager.TrackSide.LEFT)
  local carOffTrackRight = CarManager.isCarOffTrack(car, RaceTrackManager.TrackSide.RIGHT)
  -- local carOffTrack = carOffTrackLeft or carOffTrackRight

  for w = 0, 3 do
    local wheel = carWheels[w]
    local wheelPosition = wheel.position
    local tyreWidth = wheel.tyreWidth
    local tyreRadius = wheel.tyreRadius
    local debugBoxSize = vec3(tyreWidth, tyreRadius, tyreRadius)-- * 0.5
    -- local color
    -- if w == 0 then
      -- color = ColorManager.RGBM_Colors.Red
    -- elseif w == 1 then
      -- color = ColorManager.RGBM_Colors.Green
    -- elseif w == 2 then
      -- color = ColorManager.RGBM_Colors.Blue
    -- else
      -- color = ColorManager.RGBM_Colors.Yellow
    -- end

    -- local color = carOffTrack and ColorManager.RGBM_Colors.Red or ColorManager.RGBM_Colors.LimeGreen

    local color = ColorManager.RGBM_Colors.LimeGreen
    if carOffTrackLeft and (w == CarManager.CAR_WHEELS_INDEX.FRONT_LEFT or w == CarManager.CAR_WHEELS_INDEX.REAR_LEFT) then
      color = ColorManager.RGBM_Colors.Red
    elseif carOffTrackRight and (w == CarManager.CAR_WHEELS_INDEX.FRONT_RIGHT or w == CarManager.CAR_WHEELS_INDEX.REAR_RIGHT) then
      color = ColorManager.RGBM_Colors.Red
    end

    render.debugBox(wheelPosition, debugBoxSize, color)
  end
end

--- Calculates the maximum top speed of the car by checking all gears.
--- Andreas: This is a bit pointless because family cars were returning higher speeds than gt3 cars with this
---@param carIndex integer
---@return number
CarOperations.calculateMaxTopSpeed = function(carIndex)
  local car = ac.getCar(carIndex)
  if not car then return 0 end

  -- todo: could you just use highest gear available instead of checking all gears?
  local maxSpeed = 0
  local gearCount = car.gearCount
  for gearIndex = 1, gearCount do
    maxSpeed = math.max(maxSpeed, ac.getCarMaxSpeedWithGear(carIndex, gearIndex))
  end
  return maxSpeed
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