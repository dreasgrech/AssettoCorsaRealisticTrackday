local STATE = CarStateMachine.CarStateType.DRIVING_TO_SIDE_TO_OVERTAKE

CarStateMachine.CarStateTypeStrings[STATE] = "DrivingToSideToOvertake"
CarStateMachine.states_minimumTimeInState[STATE] = 0

-- ENTRY FUNCTION
CarStateMachine.states_entryFunctions[STATE] = function (carIndex, dt, sortedCarsList, sortedCarsListIndex, storage)

end

-- UPDATE FUNCTION
CarStateMachine.states_updateFunctions[STATE] = function (carIndex, dt, sortedCarsList, sortedCarsListIndex, storage)
    local car = sortedCarsList[sortedCarsListIndex]
    local carFront = sortedCarsList[sortedCarsListIndex - 1]
    if (not carFront) then
        return
    end

    local carFrontIndex = carFront.index
    -- local carFrontCurrentSideOffset = CarManager.cars_currentSplineOffset[carFrontIndex]
    -- local carFrontTargetSideOffset = CarManager.cars_targetSplineOffset[carFrontIndex]
    --storage.yieldSide 

    -- the drive to side is to be opposite side to the the yielding side
    local driveToSide = storage.yieldSide == RaceTrackManager.TrackSide.LEFT and RaceTrackManager.TrackSide.RIGHT or RaceTrackManager.TrackSide.LEFT
    local droveSafelyToSide = CarOperations.driveSafelyToSide(carIndex, dt, car, driveToSide, storage.yieldMaxOffset_normalized, storage.rampSpeed_mps, storage.overrideAiAwareness)
    if not droveSafelyToSide then
        -- TODO: Continue here
        -- TODO: Continue here
        -- TODO: Continue here
        -- TODO: Continue here
        -- TODO: Continue here
        
    end

end

-- TRANSITION FUNCTION
CarStateMachine.states_transitionFunctions[STATE] = function (carIndex, dt, sortedCarsList, sortedCarsListIndex, storage)
    -- if we're suddendly at the front of the pack, return to normal driving
    local carFront = sortedCarsList[sortedCarsListIndex - 1]
    if (not carFront) then
        -- no car in front of us, return to normal driving
        CarManager.cars_currentlyOvertakingCarIndex[carIndex] = nil
        return CarStateMachine.CarStateType.DRIVING_NORMALLY
    end

    -- fetch the car index of the car we're overtaking
    local currentlyOvertakingCarIndex = CarManager.cars_currentlyOvertakingCarIndex[carIndex]
    if (not currentlyOvertakingCarIndex) then
        -- something went wrong, we should have a reference to the car we're overtaking
        Logger.error(string.format('Car %d in state DrivingToSideToOvertake but has no reference to the car it is overtaking, returning to normal driving', carIndex))
        CarManager.cars_currentlyOvertakingCarIndex[carIndex] = nil
        return CarStateMachine.CarStateType.DRIVING_NORMALLY
    end

    -- make sure the car we're overtaking is still valid
    local currentlyOvertakingCar = ac.getCar(currentlyOvertakingCarIndex)
    if (not currentlyOvertakingCar) then
        -- the car we're overtaking is no longer valid, return to normal driving
        Logger.warn(string.format('Car %d in state DrivingToSideToOvertake but the car it was overtaking (car %d) is no longer valid, returning to normal driving', carIndex, currentlyOvertakingCarIndex))
        CarManager.cars_currentlyOvertakingCarIndex[carIndex] = nil
        return CarStateMachine.CarStateType.DRIVING_NORMALLY
    end

    -- if we've arrived at the target side offset, we can now stay on the overtaking lane
    local driveToSide = storage.yieldSide == RaceTrackManager.TrackSide.LEFT and RaceTrackManager.TrackSide.RIGHT or RaceTrackManager.TrackSide.LEFT
    local yieldingToLeft = driveToSide == RaceTrackManager.TrackSide.LEFT
    local sideSign = yieldingToLeft and -1 or 1
    local currentSplineOffset = CarManager.cars_currentSplineOffset[carIndex]
    local targetSplineOffset = storage.yieldMaxOffset_normalized * sideSign
    local arrivedAtTargetOffset = currentSplineOffset == targetSplineOffset
    if arrivedAtTargetOffset then
        return CarStateMachine.CarStateType.STAYING_ON_OVERTAKING_LANE
    end
end

-- EXIT FUNCTION
CarStateMachine.states_exitFunctions[STATE] = function (carIndex, dt, sortedCarsList, sortedCarsListIndex, storage)

end
