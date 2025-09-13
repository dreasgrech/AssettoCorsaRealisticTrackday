local STATE = CarStateMachine.CarStateType.EASING_OUT_YIELD

CarStateMachine.CarStateTypeStrings[STATE] = "EasingOutYield"
CarStateMachine.states_minimumTimeInState[STATE] = 1

-- ENTRY FUNCTION
CarStateMachine.states_entryFunctions[STATE] = function (carIndex, dt, sortedCarsList, sortedCarListIndex, storage)
  -- make sure the state before us has saved the carIndex of the car we're yielding to
  local currentlyYieldingToCarIndex = CarManager.cars_currentlyYieldingCarToIndex[carIndex]
  if not currentlyYieldingToCarIndex then
    Logger.error(string.format('Car %d in state EasingOutYield but has no reference to the car it is yielding to!  Previous state needs to set it.', carIndex))
  end

  local car = sortedCarsList[sortedCarListIndex]

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
CarStateMachine.states_updateFunctions[STATE] = function (carIndex, dt, sortedCarsList, sortedCarListIndex, storage)
      local car = sortedCarsList[sortedCarListIndex]

      local yieldSide = storage.yieldSide
      -- this is the side we're currently easing out to, which is the inverse of the side we yielded to
      local easeOutYieldSide = (yieldSide == RaceTrackManager.TrackSide.LEFT) and RaceTrackManager.TrackSide.RIGHT or RaceTrackManager.TrackSide.LEFT
      local droveSafelyToSide = CarOperations.driveSafelyToSide(carIndex, dt, car, easeOutYieldSide, 0, storage.rampRelease_mps, storage.overrideAiAwareness)

      -- can't ease out yield because the side is blocked, just wait
      if not droveSafelyToSide then
        -- -- isSafeToDriveToTheSide already logs the reason why we can't yield
        -- -- CarManager.cars_reasonWhyCantYield[carIndex] = string.format('Target side %s blocked so not easing out yield', RaceTrackManager.TrackSideStrings[easeOutYieldSide])
        -- return
        return
      end

      -- local sideSafeToYield = CarStateMachine.isSafeToDriveToTheSide(carIndex, easeOutYieldSide)
      -- if not sideSafeToYield then
        -- -- isSafeToDriveToTheSide already logs the reason why we can't yield
        -- -- CarManager.cars_reasonWhyCantYield[carIndex] = string.format('Target side %s blocked so not easing out yield', RaceTrackManager.TrackSideStrings[easeOutYieldSide])
        -- return
      -- end

      -- -- todo move the targetsplineoffset assignment to trying to start easing out yield state?
      -- local targetSplineOffset = 0
      -- local splineOffsetTransitionSpeed = storage.rampRelease_mps
      -- local currentSplineOffset = CarManager.cars_currentSplineOffset[carIndex]
      -- currentSplineOffset = MathHelpers.approach(currentSplineOffset, targetSplineOffset, splineOffsetTransitionSpeed * dt)

      -- -- set the spline offset on the yielding car
      -- local overrideAiAwareness = storage.overrideAiAwareness -- TODO: check what this does
      -- physics.setAISplineOffset(carIndex, currentSplineOffset, overrideAiAwareness)

      -- -- keep inverted turning lights on while easing out yield (inverted yield direction since the car is now going back to center)
      -- local turningLights = (not storage.yieldSide == RaceTrackManager.TrackSide.LEFT) and ac.TurningLights.Left or ac.TurningLights.Right
      -- CarOperations.toggleTurningLights(carIndex, car, turningLights)

      -- CarManager.cars_currentSplineOffset[carIndex] = currentSplineOffset
      -- CarManager.cars_targetSplineOffset[carIndex] = targetSplineOffset
end

-- TRANSITION FUNCTION
CarStateMachine.states_transitionFunctions[STATE] = function (carIndex, dt, sortedCarsList, sortedCarListIndex, storage)
      local car = sortedCarsList[sortedCarListIndex]
      local carBehind = sortedCarsList[sortedCarListIndex + 1]
      local carFront = sortedCarsList[sortedCarListIndex - 1]

      -- if there's a car behind us, check if we should start yielding to it
      local newStateDueToCarBehind = CarStateMachine.handleShouldWeYieldToBehindCar(carIndex, car, carBehind, carFront, storage)
      if newStateDueToCarBehind then
        return newStateDueToCarBehind
      end

      -- if we're back to the center, return to normal driving
      local currentSplineOffset = CarManager.cars_currentSplineOffset[carIndex]
      local arrivedBackToNormal = currentSplineOffset == 0
      if arrivedBackToNormal then
        return CarStateMachine.CarStateType.DRIVING_NORMALLY
      end
end

-- EXIT FUNCTION
CarStateMachine.states_exitFunctions[STATE] = function (carIndex, dt, sortedCarList, sortedCarListIndex, storage)

end
