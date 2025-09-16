local STATE = CarStateMachine.CarStateType.STAYING_ON_OVERTAKING_LANE

CarStateMachine.CarStateTypeStrings[STATE] = "StayingOnOvertakingLane"
CarStateMachine.states_minimumTimeInState[STATE] = 0

-- ENTRY FUNCTION
CarStateMachine.states_entryFunctions[STATE] = function (carIndex, dt, sortedCarsList, sortedCarsListIndex, storage)

end

-- UPDATE FUNCTION
CarStateMachine.states_updateFunctions[STATE] = function (carIndex, dt, sortedCarsList, sortedCarsListIndex, storage)
    -- make the driver more aggressive while overtaking
    -- CarOperations.setAICaution(carIndex, 0) -- andreas: commenting this because they get way too aggressive
end

-- TRANSITION FUNCTION
CarStateMachine.states_transitionFunctions[STATE] = function (carIndex, dt, sortedCarsList, sortedCarsListIndex, storage)
    local car = sortedCarsList[sortedCarsListIndex]
    local carBehind = sortedCarsList[sortedCarsListIndex + 1]
    local carFront = sortedCarsList[sortedCarsListIndex - 1]

    local currentlyOvertakingCarIndex = CarManager.cars_currentlyOvertakingCarIndex[carIndex]
    local currentlyOvertakingCar = ac.getCar(currentlyOvertakingCarIndex)
    if (not currentlyOvertakingCar) then
        -- the car we're overtaking is no longer valid, return to easing out overtake
        Logger.warn(string.format('Car %d in state StayingOnOvertakingLane but the car it was overtaking (car %d) is no longer valid, returning to ease out overtake', carIndex, currentlyOvertakingCarIndex))
        -- CarManager.cars_currentlyOvertakingCarIndex[carIndex] = nil
        return CarStateMachine.CarStateType.EASING_OUT_OVERTAKE
    end

    -- if we don't have an overtaking car anymore, we can ease out our yielding
    if not carBehind then
        -- CarManager.cars_reasonWhyCantYield[carIndex] = 'No yielding car so not staying on overtaking lane'
        return CarStateMachine.CarStateType.EASING_OUT_OVERTAKE
    end

    -- if we're now clearly ahead of the car we're overtaking, we can ease out our overtaking
    -- local areWeClearlyAheadOfCarWeAreOvertaking = CarOperations.isSecondCarClearlyAhead(carBehind, car, storage.clearAhead_meters)
    local areWeClearlyAheadOfCarWeAreOvertaking = CarOperations.isSecondCarClearlyAhead(currentlyOvertakingCar, car, storage.clearAhead_meters)
    if areWeClearlyAheadOfCarWeAreOvertaking then
        -- go to trying to start easing out yield state
        return CarStateMachine.CarStateType.EASING_OUT_OVERTAKE
    end

    --[===[
    -- if on the other hand the car we're overtaking is now clearly ahead of us, than we also need to ease out our overtaking
    -- local isCarWeAreOvertakingIsClearlyAheadOfUs = CarOperations.isSecondCarClearlyAhead(car, carBehind, storage.clearAhead_meters)
    local isCarWeAreOvertakingIsClearlyAheadOfUs = CarOperations.isSecondCarClearlyAhead(car, currentlyOvertakingCar, storage.clearAhead_meters)
    if isCarWeAreOvertakingIsClearlyAheadOfUs then
        -- go to trying to start easing out yield state
        return CarStateMachine.CarStateType.EASING_OUT_OVERTAKE
    end
    --]===]

    -- --  check if we need to yield to a car behind us
    -- local newStateDueToCarBehind = CarStateMachine.handleShouldWeYieldToBehindCar(carIndex, car, carBehind, carFront, storage)
    -- if newStateDueToCarBehind then
        -- CarManager.cars_currentlyOvertakingCarIndex[carIndex] = nil -- clear reference to the overtaking car since we'll now start yielding to the car behind us
        -- return newStateDueToCarBehind
    -- end

    -- check if there's currently a car behind us
    if carBehind then
        -- check if the car behind us is the same car we're overtaking
        local isCarSameAsCarWeAreOvertaking = carBehind.index == currentlyOvertakingCarIndex
        -- if the car behind us is not the same car we're overtaking, check if we should start yielding to it instead
        if not isCarSameAsCarWeAreOvertaking then
            local newStateDueToCarBehind = CarStateMachine.handleShouldWeYieldToBehindCar(carIndex, car, carBehind, carFront, storage)
            if newStateDueToCarBehind then
                CarManager.cars_currentlyOvertakingCarIndex[carIndex] = nil
                return newStateDueToCarBehind
            end
        end
    end

end

-- EXIT FUNCTION
CarStateMachine.states_exitFunctions[STATE] = function (carIndex, dt, sortedCarsList, sortedCarsListIndex, storage)
    -- reset the overtaking car caution back to normal
    CarOperations.removeAICaution(carIndex)
end
