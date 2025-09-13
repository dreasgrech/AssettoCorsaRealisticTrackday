local STATE = CarStateMachine.CarStateType.STAYING_ON_OVERTAKING_LANE

CarStateMachine.CarStateTypeStrings[STATE] = "StayingOnOvertakingLane"
CarStateMachine.states_minimumTimeInState[STATE] = 0.5

-- ENTRY FUNCTION
CarStateMachine.states_entryFunctions[STATE] = function (carIndex, dt, sortedCarsList, sortedCarsListIndex, storage)

end

-- UPDATE FUNCTION
CarStateMachine.states_updateFunctions[STATE] = function (carIndex, dt, sortedCarsList, sortedCarsListIndex, storage)

end

-- TRANSITION FUNCTION
CarStateMachine.states_transitionFunctions[STATE] = function (carIndex, dt, sortedCarsList, sortedCarsListIndex, storage)
    local car = sortedCarsList[sortedCarsListIndex]
    local carBehind = sortedCarsList[sortedCarsListIndex + 1]
    local carFront = sortedCarsList[sortedCarsListIndex - 1]

    -- if we don't have an overtaking car anymore, we can ease out our yielding
    if not carBehind then
        CarManager.cars_reasonWhyCantYield[carIndex] = 'No yielding car so not staying on overtaking lane'
        return CarStateMachine.CarStateType.EASING_OUT_OVERTAKE
    end

    -- if we're now clearly ahead of the car behind, we can ease out our overtaking
    local isOvertakingCarClearlyAheadOfYieldingCar = CarOperations.isSecondCarClearlyAhead(carBehind, car, storage.clearAhead_meters)
    if isOvertakingCarClearlyAheadOfYieldingCar then
        -- go to trying to start easing out yield state
        return CarStateMachine.CarStateType.EASING_OUT_OVERTAKE
    end

    -- if on the other hand the car we're overtaking is now clearly ahead of us, than we also need to ease out our overtaking
    local isYieldingCarClearlyAheadOfOvertakingCar = CarOperations.isSecondCarClearlyAhead(car, carBehind, storage.clearAhead_meters)
    if isYieldingCarClearlyAheadOfOvertakingCar then
        -- go to trying to start easing out yield state
        return CarStateMachine.CarStateType.EASING_OUT_OVERTAKE
    end

    -- -- if there's a car behind us that's faster than us, we need to yield to it instead of staying on the overtaking lane
    -- local isCarBehindFasterThanUs = CarOperations.isFirstCarCurrentlyFasterThanSecondCar(carBehind, car, 10)
    -- if isCarBehindFasterThanUs then
        -- return CarStateMachine.CarStateType.EASING_IN_YIELD
    -- end

    --  check if we need to yield to a car behind us
    local newStateDueToCarBehind = CarStateMachine.handleShouldWeYieldToBehindCar(carIndex, car, carBehind, carFront, storage)
    if newStateDueToCarBehind then
        return newStateDueToCarBehind
    end
end

-- EXIT FUNCTION
CarStateMachine.states_exitFunctions[STATE] = function (carIndex, dt, sortedCarsList, sortedCarsListIndex, storage)
end
