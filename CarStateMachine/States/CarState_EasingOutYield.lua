local STATE = CarStateMachine.CarStateType.EASING_OUT_YIELD

CarStateMachine.CarStateTypeStrings[STATE] = "EasingOutYield"
CarStateMachine.states_minimumTimeInState[STATE] = 1

-- ENTRY FUNCTION
CarStateMachine.states_entryFunctions[STATE] = function (carIndex, dt, car, carBehind, storage)
      -- reset the yield time counter
      CarManager.cars_yieldTime[carIndex] = 0

      -- remove the yielding car throttle limit since we will now start easing out the yield
      CarOperations.setAIThrottleLimit(carIndex, 1)
      CarOperations.removeAITopSpeed(carIndex)

      -- reset the yielding car caution back to normal
      CarOperations.setAICaution(carIndex, 1)

      -- inverse the turning lights while easing out yield (inverted yield direction since the car is now going back to center)
      local turningLights = (not storage.yieldSide == RaceTrackManager.TrackSide.LEFT) and ac.TurningLights.Left or ac.TurningLights.Right
      CarOperations.toggleTurningLights(carIndex, car, turningLights)
end

-- UPDATE FUNCTION
CarStateMachine.states_updateFunctions[STATE] = function (carIndex, dt, car, carBehind, storage)

      local yieldSide = storage.yieldSide
      -- this is the side we're currently easing out to, which is the inverse of the side we yielded to
      local easeOutYieldSide = (yieldSide == RaceTrackManager.TrackSide.LEFT) and RaceTrackManager.TrackSide.RIGHT or RaceTrackManager.TrackSide.LEFT
      local sideSafeToYield = CarStateMachine.isSafeToDriveToTheSide(carIndex, easeOutYieldSide)
      if not sideSafeToYield then
        -- isSafeToDriveToTheSide already logs the reason why we can't yield
        -- CarManager.cars_reasonWhyCantYield[carIndex] = string.format('Target side %s blocked so not easing out yield', RaceTrackManager.TrackSideStrings[easeOutYieldSide])
        return
      end

      -- todo move the targetsplineoffset assignment to trying to start easing out yield state?
      local targetSplineOffset = 0
      local splineOffsetTransitionSpeed = storage.rampRelease_mps
      local currentSplineOffset = CarManager.cars_currentSplineOffset[carIndex]
      currentSplineOffset = MathHelpers.approach(currentSplineOffset, targetSplineOffset, splineOffsetTransitionSpeed * dt)

      -- set the spline offset on the yielding car
      local overrideAiAwareness = storage.overrideAiAwareness -- TODO: check what this does
      physics.setAISplineOffset(carIndex, currentSplineOffset, overrideAiAwareness)

      -- keep inverted turning lights on while easing out yield (inverted yield direction since the car is now going back to center)
      local turningLights = (not storage.yieldSide == RaceTrackManager.TrackSide.LEFT) and ac.TurningLights.Left or ac.TurningLights.Right
      CarOperations.toggleTurningLights(carIndex, car, turningLights)

      CarManager.cars_currentSplineOffset[carIndex] = currentSplineOffset
      CarManager.cars_targetSplineOffset[carIndex] = targetSplineOffset
end

-- TRANSITION FUNCTION
CarStateMachine.states_transitionFunctions[STATE] = function (carIndex, dt, car, carBehind, storage)
      local currentSplineOffset = CarManager.cars_currentSplineOffset[carIndex]
      local arrivedBackToNormal = currentSplineOffset == 0
      if arrivedBackToNormal then
        return CarStateMachine.CarStateType.DRIVING_NORMALLY
      end
end

-- EXIT FUNCTION
CarStateMachine.states_exitFunctions[STATE] = function (carIndex, dt, car, carBehind, storage)

end
