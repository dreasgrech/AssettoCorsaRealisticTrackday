local CarStateMachine = {}

-- local LOG_CAR_STATEMACHINE_IN_CSP_LOG = true
local LOG_CAR_STATEMACHINE_IN_CSP_LOG = false

local carStateMachine = {
  [CarManager.CarStateType.TryingToStartDrivingNormally] = function (carIndex, dt, car, playerCar, storage)

      CarManager.cars_yieldTime[carIndex] = 0
      CarManager.cars_currentSplineOffset[carIndex] = 0
      CarManager.cars_targetSplineOffset[carIndex] = 0

      -- turn off turning lights
      CarOperations.toggleTurningLights(carIndex, car, ac.TurningLights.None)
      
    -- start driving normally
      CarManager.cars_state[carIndex] = CarManager.CarStateType.DrivingNormally

      -- reset the ai car caution back to normal
      physics.setAICaution(carIndex, 1)

      -- remove the ai car throttle limit since we will now be driving normally
      physics.setAIThrottleLimit(carIndex, 1)
  end,
  [CarManager.CarStateType.DrivingNormally] = function (carIndex, dt, car, playerCar, storage)
      if LOG_CAR_STATEMACHINE_IN_CSP_LOG then Logger.log(string.format("Car %d: In state: %s", carIndex, "DrivingNormally")) end

      -- If this car is not close to the player car, do nothing
      local distanceFromPlayerCarToAICar = MathHelpers.vlen(MathHelpers.vsub(playerCar.position, car.position))
      local radius = storage.detectInner_meters + storage.detectHysteresis_meters
      local isAICarCloseToPlayerCar = distanceFromPlayerCarToAICar <= radius
      if not isAICarCloseToPlayerCar then
        CarManager.cars_reason[carIndex] = 'Too far (outside detect radius) so not yielding'
        return
      end

      -- Check if the player car is behind the ai car
      local isPlayerCarBehindAICar = CarOperations.isBehind(car, playerCar)
      if not isPlayerCarBehindAICar then
        CarManager.cars_reason[carIndex] = 'Player not behind (clear) so not yielding'
        return
      end

      -- Check if the player car is above the minimum speed
      local isPlayerAboveMinSpeed = playerCar.speedKmh >= storage.minPlayerSpeed_kmh
      if not isPlayerAboveMinSpeed then
        CarManager.cars_reason[carIndex] = 'Player below minimum speed so not yielding'
        return
      end

      -- Check if the player car is currently faster than the ai car 
      local playerCarHasClosingSpeedToAiCar = (playerCar.speedKmh - car.speedKmh) >= storage.minSpeedDelta_kmh
      if not playerCarHasClosingSpeedToAiCar then
        CarManager.cars_reason[carIndex] = 'Player does not have closing speed so not yielding'
      end

      -- Check if the ai car is above the minimum speed
      local isAICarAboveMinSpeed = car.speedKmh >= storage.minAISpeed_kmh
      if not isAICarAboveMinSpeed then
        CarManager.cars_reason[carIndex] = 'AI speed too low (corner/traffic) so not yielding'
      end

      -- Since all the checks have passed, the ai car can now start to yield
      CarManager.cars_state[carIndex] = CarManager.CarStateType.TryingToStartYieldingToTheSide
  end,
  [CarManager.CarStateType.TryingToStartYieldingToTheSide] = function (carIndex, dt, car, playerCar, storage)
      if LOG_CAR_STATEMACHINE_IN_CSP_LOG then Logger.log(string.format("Car %d: In state: %s", carIndex, "TryingToStartYieldingToTheSide")) end

      -- turn on turning lights
      local turningLights = storage.yieldToLeft and ac.TurningLights.Left or ac.TurningLights.Right
      CarOperations.toggleTurningLights(carIndex, car, turningLights)

      -- for now go directly to yielding to the side
      CarManager.cars_state[carIndex] = CarManager.CarStateType.YieldingToTheSide
  end,
  [CarManager.CarStateType.YieldingToTheSide] = function (carIndex, dt, car, playerCar, storage)
      if LOG_CAR_STATEMACHINE_IN_CSP_LOG then Logger.log(string.format("Car %d: In state: %s", carIndex, "YieldingToTheSide")) end

      -- CarManager.cars_reason[carIndex] = 'Driving on yielding lane'

      -- Since the player car is still close, we must continue yielding
      local sideSign = storage.yieldToLeft and -1 or 1

      -- TODO: I haven't yet seen this "blocked" code working in practice, need to test more
      -- check if the side the car is yielding to is blocked by another car
      local isTargetSideBlocked, blockerCarIndex = CarOperations.isTargetSideBlocked(carIndex, sideSign)
      if isTargetSideBlocked then
        CarManager.cars_reason[carIndex] = 'Target side blocked by another car so not yielding'
        return
      end

      local targetSplineOffset = sideSign
      local splineOffsetTransitionSpeed = storage.rampSpeed_mps
      local currentSplineOffset = CarManager.cars_currentSplineOffset[carIndex]
      currentSplineOffset = MathHelpers.approach(currentSplineOffset, targetSplineOffset, splineOffsetTransitionSpeed * dt)

      -- set the spline offset on the ai car
      local overrideAiAwareness = storage.overrideAiAwareness -- TODO: check what this does
      physics.setAISplineOffset(carIndex, currentSplineOffset, overrideAiAwareness)

      -- keep the turning lights on while yielding
      local turningLights = storage.yieldToLeft and ac.TurningLights.Left or ac.TurningLights.Right
      CarOperations.toggleTurningLights(carIndex, car, turningLights)

      CarManager.cars_currentSplineOffset[carIndex] = currentSplineOffset
      CarManager.cars_targetSplineOffset[carIndex] = targetSplineOffset

      CarManager.cars_yieldTime[carIndex] = CarManager.cars_yieldTime[carIndex] + dt

      -- If the ai car is yielding and the player car is now clearly ahead, we can ease out our yielding
      local isPlayerClearlyAheadOfAICar = CarOperations.playerIsClearlyAhead(car, playerCar, storage.clearAhead_meters)
      if isPlayerClearlyAheadOfAICar then
        -- CarManager.cars_reason[carIndex] = 'Player clearly ahead, so easing out yield'

        -- go to trying to start easing out yield state
        CarManager.cars_state[carIndex] = CarManager.CarStateType.TryingToStartEasingOutYield

        return
      end

      -- once we have reached the target offset, we can go to the next state
      local arrivedAtTargetOffset = currentSplineOffset == targetSplineOffset
      if arrivedAtTargetOffset then
        CarManager.cars_state[carIndex] = CarManager.CarStateType.StayingOnYieldingLane
        return
      end
  end,
  [CarManager.CarStateType.StayingOnYieldingLane] = function (carIndex, dt, car, playerCar, storage)
      if LOG_CAR_STATEMACHINE_IN_CSP_LOG then Logger.log(string.format("Car %d: In state: %s", carIndex, "StayingOnYieldingLane")) end

      -- make the ai car leave more space in between the care in front while driving on the yielding lane
      physics.setAICaution(carIndex, 2)

      -- limit the ai car throttle while driving on the yielding lane
      physics.setAIThrottleLimit(carIndex, 0.4)

      CarManager.cars_yieldTime[carIndex] = CarManager.cars_yieldTime[carIndex] + dt

      -- If the ai car is yielding and the player car is now clearly ahead, we can ease out our yielding
      local isPlayerClearlyAheadOfAICar = CarOperations.playerIsClearlyAhead(car, playerCar, storage.clearAhead_meters)
      if isPlayerClearlyAheadOfAICar then
        -- CarManager.cars_reason[carIndex] = 'Player clearly ahead, so easing out yield'

        -- go to trying to start easing out yield state
        CarManager.cars_state[carIndex] = CarManager.CarStateType.TryingToStartEasingOutYield

        return
      end
  end,
  [CarManager.CarStateType.TryingToStartEasingOutYield] = function (carIndex, dt, car, playerCar, storage)
      if LOG_CAR_STATEMACHINE_IN_CSP_LOG then Logger.log(string.format("Car %d: In state: %s", carIndex, "TryingToStartEasingOutYield")) end

      -- reset the yield time counter
      CarManager.cars_yieldTime[carIndex] = 0

      -- remove the ai car throttle limit since we will now start easing out the yield
      physics.setAIThrottleLimit(carIndex, 1)

      -- reset the ai car caution back to normal
      physics.setAICaution(carIndex, 1)

      -- inverse the turning lights while easing out yield (inverted yield direction since the car is now going back to center)
      local turningLights = (not storage.yieldToLeft) and ac.TurningLights.Left or ac.TurningLights.Right
      CarOperations.toggleTurningLights(carIndex, car, turningLights)

      -- for now go directly to easing out yield
      CarManager.cars_state[carIndex] = CarManager.CarStateType.EasingOutYield
  end,
  [CarManager.CarStateType.EasingOutYield] = function (carIndex, dt, car, playerCar, storage)
      if LOG_CAR_STATEMACHINE_IN_CSP_LOG then Logger.log(string.format("Car %d: In state: %s", carIndex, "EasingOutYield")) end

      local targetSplineOffset = 0
      local splineOffsetTransitionSpeed = storage.rampRelease_mps
      local currentSplineOffset = CarManager.cars_currentSplineOffset[carIndex]
      currentSplineOffset = MathHelpers.approach(currentSplineOffset, targetSplineOffset, splineOffsetTransitionSpeed * dt)

      -- set the spline offset on the ai car
      local overrideAiAwareness = storage.overrideAiAwareness -- TODO: check what this does
      physics.setAISplineOffset(carIndex, currentSplineOffset, overrideAiAwareness)

      -- keep inverted turning lights on while easing out yield (inverted yield direction since the car is now going back to center)
      local turningLights = (not storage.yieldToLeft) and ac.TurningLights.Left or ac.TurningLights.Right
      CarOperations.toggleTurningLights(carIndex, car, turningLights)

      CarManager.cars_currentSplineOffset[carIndex] = currentSplineOffset
      CarManager.cars_targetSplineOffset[carIndex] = targetSplineOffset

      local arrivedBackToNormal = currentSplineOffset == 0
      if arrivedBackToNormal then
        CarManager.cars_state[carIndex] = CarManager.CarStateType.TryingToStartDrivingNormally
        return
      end
  end
}

function CarStateMachine.update(carIndex, dt, car, playerCar, storage)
    local state = CarManager.cars_state[carIndex]

    -- execute the state machine for this car
    carStateMachine[state](carIndex, dt, car, playerCar, storage)
end

return CarStateMachine