local STATE = CarStateMachine.CarStateType.STAYING_ON_OVERTAKING_LANE

CarStateMachine.CarStateTypeStrings[STATE] = "StayingOnOvertakingLane"
CarStateMachine.states_minimumTimeInState[STATE] = 0

local StateExitReason = Strings.StringNames[Strings.StringCategories.StateExitReason]

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

      -- if there's an accident ahead, we need to start navigating around it
      local newStateDueToAccident = CarStateMachine.handleShouldWeStartNavigatingAroundAccident(carIndex, car)
      if newStateDueToAccident then
        CarStateMachine.setStateExitReason(carIndex, StateExitReason.NavigatingAroundAccident)
        return newStateDueToAccident
      end

    local carBehind = sortedCarsList[sortedCarsListIndex + 1]
    local carFront = sortedCarsList[sortedCarsListIndex - 1]

    local currentlyOvertakingCarIndex = CarManager.cars_currentlyOvertakingCarIndex[carIndex]
    local currentlyOvertakingCar = ac.getCar(currentlyOvertakingCarIndex)
    if (not currentlyOvertakingCar) then
        -- the car we're overtaking is no longer valid, return to easing out overtake
        Logger.warn(string.format('Car %d in state StayingOnOvertakingLane but the car it was overtaking (car %d) is no longer valid, returning to ease out overtake', carIndex, currentlyOvertakingCarIndex))
        -- CarManager.cars_currentlyOvertakingCarIndex[carIndex] = nil
        -- CarStateMachine.setStateExitReason(carIndex, string.format('Car %d in state StayingOnOvertakingLane but the car it was overtaking (car %d) is no longer valid, returning to ease out overtake', carIndex, currentlyOvertakingCarIndex))
        CarStateMachine.setStateExitReason(carIndex, StateExitReason.OvertakingCarNoLongerExists)
        return CarStateMachine.CarStateType.EASING_OUT_OVERTAKE
    end

    -- if we don't have an overtaking car anymore, we can ease out our yielding
    -- Andreas: commenting this because it's not good.
    -- Andreas: because if we are the last car in the list, there technically won't be a car behind us anymore while we are overtaking
    -- if not carBehind then
        -- -- CarManager.cars_reasonWhyCantYield[carIndex] = 'No yielding car so not staying on overtaking lane'
        -- CarStateMachine.setStateExitReason(carIndex, 'No yielding car so not staying on overtaking lane')
        -- return CarStateMachine.CarStateType.EASING_OUT_OVERTAKE
    -- end

    -- If there's a car in front of us, check if we can overtake it as well
    if carFront then
        local carFrontIndex = carFront.index
        local isCarInFrontSameAsWeAreOvertaking = carFrontIndex == currentlyOvertakingCarIndex
        if not isCarInFrontSameAsWeAreOvertaking then
            local newStateDueToCarInFront = CarStateMachine.handleCanWeOvertakeFrontCar(carIndex, car, carFront, carBehind, storage)
            if newStateDueToCarInFront then
                -- CarStateMachine.setStateExitReason(carIndex, string.format("Continuing to overtake next front car #%d", carFrontIndex))
                CarStateMachine.setStateExitReason(carIndex, StateExitReason.ContinuingOvertakingNextCar)
                -- return newStateDueToCarInFront
                CarManager.cars_currentlyOvertakingCarIndex[carIndex] = carFrontIndex -- start overtaking the new car in front of us
                return CarStateMachine.CarStateType.STAYING_ON_OVERTAKING_LANE
            end
        end
    end

    -- if we're now clearly ahead of the car we're overtaking, we can ease out our overtaking
    -- local areWeClearlyAheadOfCarWeAreOvertaking = CarOperations.isSecondCarClearlyAhead(carBehind, car, storage.clearAhead_meters)
    local areWeClearlyAheadOfCarWeAreOvertaking = CarOperations.isSecondCarClearlyAhead(currentlyOvertakingCar, car, storage.clearAhead_meters)
    if areWeClearlyAheadOfCarWeAreOvertaking then
        -- go to trying to start easing out yield state
        -- CarStateMachine.setStateExitReason(carIndex, 'Clearly ahead of car we were overtaking so easing out overtake')
        CarStateMachine.setStateExitReason(carIndex, StateExitReason.ClearlyAheadOfYieldingCar)
        return CarStateMachine.CarStateType.EASING_OUT_OVERTAKE
    end

    -- TODO: There's a bug with this isCarWeAreOvertakingIsClearlyAheadOfUs check here because when it's enabled, the cars exit out of this state immediately
    -- TODO: But without it, a car can get stuck in this state if the yielding car suddendly drives far ahead
    -- if on the other hand the car we're overtaking is now clearly ahead of us, than we also need to ease out our overtaking
    -- local isCarWeAreOvertakingIsClearlyAheadOfUs = CarOperations.isSecondCarClearlyAhead(car, carBehind, storage.clearAhead_meters)
    local overtakingCarLeeway = 40
    local isCarWeAreOvertakingIsClearlyAheadOfUs = CarOperations.isSecondCarClearlyAhead(car, currentlyOvertakingCar, storage.clearAhead_meters + overtakingCarLeeway)
    if isCarWeAreOvertakingIsClearlyAheadOfUs then
        -- go to trying to start easing out yield state
        return CarStateMachine.CarStateType.EASING_OUT_OVERTAKE
    end

    -- --  check if we need to yield to a car behind us
    -- local newStateDueToCarBehind = CarStateMachine.handleShouldWeYieldToBehindCar(carIndex, car, carBehind, carFront, storage)
    -- if newStateDueToCarBehind then
        -- CarManager.cars_currentlyOvertakingCarIndex[carIndex] = nil -- clear reference to the overtaking car since we'll now start yielding to the car behind us
        -- return newStateDueToCarBehind
    -- end

    -- check if there's currently a car behind us
    if carBehind then
        -- check if the car behind us is the same car we're overtaking
        local isCarBehindSameAsCarWeAreOvertaking = carBehind.index == currentlyOvertakingCarIndex
        -- if the car behind us is not the same car we're overtaking, check if we should start yielding to it instead
        if not isCarBehindSameAsCarWeAreOvertaking then
            local newStateDueToCarBehind = CarStateMachine.handleShouldWeYieldToBehindCar(carIndex, car, carBehind, carFront, storage)
            if newStateDueToCarBehind then
                CarManager.cars_currentlyOvertakingCarIndex[carIndex] = nil
                -- CarStateMachine.setStateExitReason(carIndex, string.format("Yielding to car #%d instead", carBehind.index))
                CarStateMachine.setStateExitReason(carIndex, StateExitReason.YieldingToCar)
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
