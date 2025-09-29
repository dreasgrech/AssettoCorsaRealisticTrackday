local STATE = CarStateMachine.CarStateType.DRIVING_IN_YELLOW_FLAG_ZONE

CarStateMachine.CarStateTypeStrings[STATE] = "DrivingInYellowFlagZone"
CarStateMachine.states_minimumTimeInState[STATE] = 0

local StateExitReason = Strings.StringNames[Strings.StringCategories.StateExitReason]

-- ENTRY FUNCTION
CarStateMachine.states_entryFunctions[STATE] = function (carIndex, dt, sortedCarsList, sortedCarsListIndex, storage)

end

-- UPDATE FUNCTION
CarStateMachine.states_updateFunctions[STATE] = function (carIndex, dt, sortedCarsList, sortedCarsListIndex, storage)
    CarOperations.setAICaution(carIndex, 3)
    CarOperations.setAITopSpeed(carIndex, 50)
    CarOperations.setPedalPosition(carIndex, CarOperations.CarPedals.Accelerate, 0.2)
    CarOperations.setPedalPosition(carIndex, CarOperations.CarPedals.Brake, 0.1)

    CarOperations.toggleTurningLights(carIndex, ac.TurningLights.Hazards)

end

-- TRANSITION FUNCTION
CarStateMachine.states_transitionFunctions[STATE] = function (carIndex, dt, sortedCarsList, sortedCarsListIndex, storage)

    -- check if it's time to start navigating around an accident
    local distanceToStartNavigatingAroundCarInAccident_meters = storage.distanceToStartNavigatingAroundCarInAccident_meters
    local car = sortedCarsList[sortedCarsListIndex]
    local upcomingAccidentIndex, upcomingAccidentClosestCarIndex = AccidentManager.isCarComingUpToAccident(car, distanceToStartNavigatingAroundCarInAccident_meters)
    if upcomingAccidentIndex then
        AccidentManager.setCarNavigatingAroundAccident(carIndex, upcomingAccidentIndex, upcomingAccidentClosestCarIndex)
        CarStateMachine.setStateExitReason(carIndex, StateExitReason.NavigatingAroundAccident)
        return CarStateMachine.CarStateType.NAVIGATING_AROUND_ACCIDENT
    end

    -- if we've exited the yellow flag zone, return to normal driving
    local stillInYellowFlagZone = RaceTrackManager.isSplinePositionInYellowZone(car.splinePosition)
    if not stillInYellowFlagZone then
        CarStateMachine.setStateExitReason(carIndex, StateExitReason.ExitedYellowFlagZone)
        return CarStateMachine.CarStateType.DRIVING_NORMALLY
    end
end

-- EXIT FUNCTION
CarStateMachine.states_exitFunctions[STATE] = function (carIndex, dt, sortedCarsList, sortedCarsListIndex, storage)
    CarOperations.toggleTurningLights(carIndex, ac.TurningLights.None)
end
