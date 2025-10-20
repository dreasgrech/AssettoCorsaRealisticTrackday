local STATE = CarStateMachine.CarStateType.DRIVING_IN_YELLOW_FLAG_ZONE

CarStateMachine.CarStateTypeStrings[STATE] = "DrivingInYellowFlagZone"
CarStateMachine.states_minimumTimeInState[STATE] = 0

local StateExitReason = Strings.StringNames[Strings.StringCategories.StateExitReason]

-- ENTRY FUNCTION
---@param carIndex integer
---@param dt number
---@param sortedCarsList table<integer,ac.StateCar>
---@param sortedCarsListIndex integer
---@param storage StorageTable
CarStateMachine.states_entryFunctions[STATE] = function (carIndex, dt, sortedCarsList, sortedCarsListIndex, storage)

end

-- UPDATE FUNCTION
---@param carIndex integer
---@param dt number
---@param sortedCarsList table<integer,ac.StateCar>
---@param sortedCarsListIndex integer
---@param storage StorageTable
CarStateMachine.states_updateFunctions[STATE] = function (carIndex, dt, sortedCarsList, sortedCarsListIndex, storage)
    --[===[
    CarOperations.setAICaution(carIndex, 3)
    --]===]
    CarOperations.setAITopSpeed(carIndex, 50)
    --todo: this pressing of multiple isn't good.  i think you gonna need to write your own limit speed function which fiddles around with the pedals to limit the speed
    -- CarOperations.setPedalPosition(carIndex, CarOperations.CarPedals.Gas, 1)
    -- CarOperations.setPedalPosition(carIndex, CarOperations.CarPedals.Brake, 0.5)
    -- CarOperations.limitTopSpeed(carIndex, 50)

    CarOperations.toggleTurningLights(carIndex, ac.TurningLights.Hazards)

    CarOperations.toggleCarCollisions(carIndex, false)
end

-- TRANSITION FUNCTION
---@param carIndex integer
---@param dt number
---@param sortedCarsList table<integer,ac.StateCar>
---@param sortedCarsListIndex integer
---@param storage StorageTable
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
---@param carIndex integer
---@param dt number
---@param sortedCarsList table<integer,ac.StateCar>
---@param sortedCarsListIndex integer
---@param storage StorageTable
CarStateMachine.states_exitFunctions[STATE] = function (carIndex, dt, sortedCarsList, sortedCarsListIndex, storage)
    CarOperations.removeAITopSpeed(carIndex)
    CarOperations.toggleTurningLights(carIndex, ac.TurningLights.None)
end
