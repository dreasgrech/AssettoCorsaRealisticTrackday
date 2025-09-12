local STATE = CarStateMachine.CarStateType.YIELDING_TO_THE_SIDE

CarStateMachine.CarStateTypeStrings[STATE] = "YieldingToTheSide"
CarStateMachine.states_minimumTimeInState[STATE] = 1

-- ENTRY FUNCTION
CarStateMachine.states_entryFunctions[STATE] = function (carIndex, dt, car, carBehind, storage)
      -- turn on turning lights
      local turningLights = storage.yieldSide == RaceTrackManager.TrackSide.LEFT and ac.TurningLights.Left or ac.TurningLights.Right
      CarOperations.toggleTurningLights(carIndex, car, turningLights)
end

-- UPDATE FUNCTION
CarStateMachine.states_updateFunctions[STATE] = function (carIndex, dt, car, carBehind, storage)
      local yieldSide = storage.yieldSide

      local yieldingToLeft = yieldSide == RaceTrackManager.TrackSide.LEFT
      local sideSign = yieldingToLeft and -1 or 1
      local currentSplineOffset = CarManager.cars_currentSplineOffset[carIndex]
      local targetSplineOffset = storage.yieldMaxOffset_normalized * sideSign

      -- make sure there isn't any car on the side we're trying to yield to so we don't crash into it
      local isSideSafeToYield = CarStateMachine.isSafeToDriveToTheSide(carIndex, yieldSide)
      if not isSideSafeToYield then
        -- reduce the car speed so that we can find a gap
        CarOperations.setAIThrottleLimit(carIndex, 0.4)

        -- set the brake pedal to something low to help slow down the car while waiting for a gap
        CarOperations.setPedalPosition(carIndex, CarOperations.CarPedals.Brake, 0.2)

        return
      end

      CarOperations.resetPedalPosition(carIndex, CarOperations.CarPedals.Brake)

      CarManager.cars_reasonWhyCantYield[carIndex] = nil
      CarOperations.setAIThrottleLimit(carIndex, 1) -- remove any speed limit we may have applied while waiting for a gap

      -- if we are driving at high speed, we need to increase the ramp speed slower so that our car doesn't jolt out of control
      local splineOffsetTransitionSpeed = CarOperations.limitSplitOffsetRampUpSpeed(car.speedKmh, storage.rampSpeed_mps)

      currentSplineOffset = MathHelpers.approach(currentSplineOffset, targetSplineOffset, splineOffsetTransitionSpeed * dt)

      -- set the spline offset on the ai car
      local overrideAiAwareness = storage.overrideAiAwareness -- TODO: check what this does
      physics.setAISplineOffset(carIndex, currentSplineOffset, overrideAiAwareness)

      -- keep the turning lights on while yielding
      local turningLights = yieldingToLeft and ac.TurningLights.Left or ac.TurningLights.Right
      CarOperations.toggleTurningLights(carIndex, car, turningLights)

      CarManager.cars_currentSplineOffset[carIndex] = currentSplineOffset
      CarManager.cars_targetSplineOffset[carIndex] = targetSplineOffset

      CarManager.cars_yieldTime[carIndex] = CarManager.cars_yieldTime[carIndex] + dt
end

-- TRANSITION FUNCTION
CarStateMachine.states_transitionFunctions[STATE] = function (carIndex, dt, car, carBehind, storage)
      -- If the yielding car is yielding and the overtaking car is now clearly ahead, we can ease out our yielding
      local isOvertakingCarClearlyAheadOfYieldingCar = CarOperations.isSecondCarClearlyAhead(car, carBehind, storage.clearAhead_meters)
      if isOvertakingCarClearlyAheadOfYieldingCar then
        CarManager.cars_reasonWhyCantYield[carIndex] = 'Overtaking car clearly ahead, so easing out yield'

        -- go to trying to start easing out yield state
        return CarStateMachine.CarStateType.EASING_OUT_YIELD
      end

      -- --  if we're currently faster than the car trying to overtake us, we can ease out our yielding
      -- local areWeFasterThanCarTryingToOvertake = CarOperations.isFirstCarCurrentlyFasterThanSecondCar(car, playerCar)
      -- if areWeFasterThanCarTryingToOvertake then
        -- -- go to trying to start easing out yield state
        -- CarManager.cars_reasonWhyCantYield[carIndex] = 'We are now faster than the car behind, so easing out yield'
        -- return CarStateMachine.CarStateType.EASING_OUT_YIELD
      -- end

      -- if we have reached the target offset, we can go to the next state
      local yieldSide = storage.yieldSide
      local yieldingToLeft = yieldSide == RaceTrackManager.TrackSide.LEFT
      local sideSign = yieldingToLeft and -1 or 1
      local currentSplineOffset = CarManager.cars_currentSplineOffset[carIndex]
      local targetSplineOffset = storage.yieldMaxOffset_normalized * sideSign
      local arrivedAtTargetOffset = currentSplineOffset == targetSplineOffset
      if arrivedAtTargetOffset then
        -- CarStateMachine.changeState(carIndex, CarStateMachine.CarStateType.STAYING_ON_YIELDING_LANE)
        return CarStateMachine.CarStateType.STAYING_ON_YIELDING_LANE
      end
end

-- EXIT FUNCTION
CarStateMachine.states_exitFunctions[STATE] = function (carIndex, dt, car, carBehind, storage)

end
