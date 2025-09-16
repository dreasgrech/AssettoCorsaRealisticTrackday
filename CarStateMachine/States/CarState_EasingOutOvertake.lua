local STATE = CarStateMachine.CarStateType.EASING_OUT_OVERTAKE

CarStateMachine.CarStateTypeStrings[STATE] = "EasingOutOvertake"
CarStateMachine.states_minimumTimeInState[STATE] = 0

-- ENTRY FUNCTION
CarStateMachine.states_entryFunctions[STATE] = function (carIndex, dt, sortedCarsList, sortedCarsListIndex, storage)
  -- make sure the state before us has saved the carIndex of the car we're overtaking
  local currentlyOvertakingCarIndex = CarManager.cars_currentlyOvertakingCarIndex[carIndex]
  if not currentlyOvertakingCarIndex then
    Logger.error(string.format('Car %d in state EasingOutOvertake but has no reference to the car it is overtaking!  Previous state needs to set it.', carIndex))
  end

end

-- UPDATE FUNCTION
CarStateMachine.states_updateFunctions[STATE] = function (carIndex, dt, sortedCarsList, sortedCarsListIndex, storage)
    local car = sortedCarsList[sortedCarsListIndex]
    -- local carFront = sortedCarsList[sortedCarsListIndex - 1]
    -- if (not carFront) then
        -- return
    -- end

    --local carFrontIndex = carFront.index
    -- local carFrontCurrentSideOffset = CarManager.cars_currentSplineOffset[carFrontIndex]
    -- local carFrontTargetSideOffset = CarManager.cars_targetSplineOffset[carFrontIndex]
    --storage.yieldSide 

    -- the drive to side is now the same side as the yielding side since we're easing out of the overtake
    local driveToSide = storage.yieldSide
    local targetOffset = 0
    local droveSafelyToSide = CarOperations.driveSafelyToSide(carIndex, dt, car, driveToSide, targetOffset, storage.overtakeRampRelease_mps, storage.overrideAiAwareness)
    if not droveSafelyToSide then
        -- TODO: Continue here: what should we do if we can't ease out the overtake because the side is blocked?
    end
end

-- TRANSITION FUNCTION
CarStateMachine.states_transitionFunctions[STATE] = function (carIndex, dt, sortedCarsList, sortedCarsListIndex, storage)
      local car = sortedCarsList[sortedCarsListIndex]
      local carBehind = sortedCarsList[sortedCarsListIndex + 1]
      local carFront = sortedCarsList[sortedCarsListIndex - 1]

      -- if there's a car behind us, check if we should start yielding to it
      local newStateDueToCarBehind = CarStateMachine.handleShouldWeYieldToBehindCar(carIndex, car, carBehind, carFront, storage)
      if newStateDueToCarBehind then
        CarManager.cars_currentlyOvertakingCarIndex[carIndex] = nil
        return newStateDueToCarBehind
      end

      -- if we're back to the center, return to normal driving
      -- local currentSplineOffset = CarManager.cars_currentSplineOffset[carIndex]
      local currentSplineOffset = CarManager.getCalculatedTrackLateralOffset(carIndex)
      -- local arrivedBackToNormal = currentSplineOffset == 0
      local arrivedBackToNormal
      local driveToSide = storage.yieldSide
      if driveToSide == RaceTrackManager.TrackSide.LEFT then
        arrivedBackToNormal = currentSplineOffset <= 0
      else
        arrivedBackToNormal = currentSplineOffset >= 0
      end

      if arrivedBackToNormal then
        CarManager.cars_currentlyOvertakingCarIndex[carIndex] = nil -- clear the reference to the car we were overtaking since we'll now go back to normal driving
        return CarStateMachine.CarStateType.DRIVING_NORMALLY
      end
end

-- EXIT FUNCTION
CarStateMachine.states_exitFunctions[STATE] = function (carIndex, dt, sortedCarsList, sortedCarsListIndex, storage)

end
