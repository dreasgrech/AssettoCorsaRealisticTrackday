local STATE = CarStateMachine.CarStateType.NAVIGATING_AROUND_ACCIDENT

CarStateMachine.CarStateTypeStrings[STATE] = "NavigatingAroundAccident"
CarStateMachine.states_minimumTimeInState[STATE] = 0

-- ENTRY FUNCTION
CarStateMachine.states_entryFunctions[STATE] = function (carIndex, dt, sortedCarsList, sortedCarsListIndex, storage)

end

-- UPDATE FUNCTION
CarStateMachine.states_updateFunctions[STATE] = function (carIndex, dt, sortedCarsList, sortedCarsListIndex, storage)
    local accidentIndex = CarManager.cars_navigatingAroundAccidentIndex[carIndex]
    if accidentIndex == 0 then
        Logger.error(string.format("accidentIndex is 0! in car #%d", carIndex))
        -- CarStateMachine.changeCarState(carIndex, CarStateMachine.CarStateType.DRIVING_NORMALLY)
        return
    end

    CarOperations.setAICaution(carIndex, 3)
    CarOperations.setAITopSpeed(carIndex, 50)
    CarOperations.setPedalPosition(carIndex, CarOperations.CarPedals.Accelerate, 0.2)
    CarOperations.setPedalPosition(carIndex, CarOperations.CarPedals.Brake, 0.2)

    local culpritCarIndex = AccidentManager.accidents_carIndex[accidentIndex]
    local culpritCar = ac.getCar(culpritCarIndex)
    local victimCarIndex = AccidentManager.accidents_collidedWithCarIndex[accidentIndex]
    local victimCar = ac.getCar(victimCarIndex)

    -- determine which car is closest to us by comparing spline positions 
    local car = sortedCarsList[sortedCarsListIndex]
    local culpritCarSplineDistance = math.abs(car.splinePosition - culpritCar.splinePosition)
    local victimCarSplineDistance = math.abs(car.splinePosition - victimCar.splinePosition)

    local carToNavigateAroundSplineDistance
    local carToNavigateAround = nil
    if culpritCarSplineDistance < victimCarSplineDistance then
        carToNavigateAround = culpritCar
        carToNavigateAroundSplineDistance = culpritCarSplineDistance
    else
        carToNavigateAround = victimCar
        carToNavigateAroundSplineDistance = victimCarSplineDistance
    end

    if carToNavigateAroundSplineDistance > 0.01 then
        -- we're more than 1 centimeter away from the car to navigate around, so just drive normally for now
        return
    end

    local targetOffset = 0

    -- local accidentWorldPosition = AccidentManager.accidents_worldPosition[accidentIndex]
    -- local distanceToAccident = car.position:distance(accidentWorldPosition)

    local carToNavigateAroundLateralOffset = CarManager.getActualTrackLateralOffset(carToNavigateAround.position)
    -- now we need to calculate our own offset to use to go around the car to navigating around
    if (math.abs(carToNavigateAroundLateralOffset) < 0.1) then
        -- the car to navigate around is in the middle of the track, so we can pick a side to go around it
        targetOffset = -1 -- todo: need to decide the corect side
    else
        -- the car to navigate around is already to one side, so we need to go to the other side
        targetOffset = -carToNavigateAroundLateralOffset
    end

    local sideToDriveTo = targetOffset < 0 and RaceTrackManager.TrackSide.LEFT or RaceTrackManager.TrackSide.RIGHT
    CarOperations.driveSafelyToSide(carIndex, dt, car, sideToDriveTo, math.abs(targetOffset), 5, true)
end

-- TRANSITION FUNCTION
CarStateMachine.states_transitionFunctions[STATE] = function (carIndex, dt, sortedCarsList, sortedCarsListIndex, storage)
    local accidentIndex = CarManager.cars_navigatingAroundAccidentIndex[carIndex]
    if accidentIndex == 0 then
        -- Logger.error(string.format("accidentIndex is 0! in car #%d", carIndex))
        -- CarStateMachine.changeCarState(carIndex, CarStateMachine.CarStateType.DRIVING_NORMALLY)
        return CarStateMachine.CarStateType.DRIVING_NORMALLY
    end

    local accidentWorldPosition = AccidentManager.accidents_worldPosition[accidentIndex]
    local car = sortedCarsList[sortedCarsListIndex]
    local carPosition = car.position
    local distanceToAccident = carPosition:distance(accidentWorldPosition)
end

-- EXIT FUNCTION
CarStateMachine.states_exitFunctions[STATE] = function (carIndex, dt, sortedCarsList, sortedCarsListIndex, storage)
    CarOperations.removeAICaution(carIndex)
    CarOperations.removeAITopSpeed(carIndex)
    CarOperations.resetPedalPosition(carIndex, CarOperations.CarPedals.Accelerate)
    CarOperations.resetPedalPosition(carIndex, CarOperations.CarPedals.Brake)
end
