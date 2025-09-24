local STATE = CarStateMachine.CarStateType.NAVIGATING_AROUND_ACCIDENT

CarStateMachine.CarStateTypeStrings[STATE] = "NavigatingAroundAccident"
CarStateMachine.states_minimumTimeInState[STATE] = 0

-- ENTRY FUNCTION
CarStateMachine.states_entryFunctions[STATE] = function (carIndex, dt, sortedCarsList, sortedCarsListIndex, storage)

end

-- UPDATE FUNCTION
CarStateMachine.states_updateFunctions[STATE] = function (carIndex, dt, sortedCarsList, sortedCarsListIndex, storage)
    CarOperations.setAITopSpeed(carIndex, 50)
    CarOperations.setPedalPosition(carIndex, CarOperations.CarPedals.Accelerate, 0.2)
    CarOperations.setPedalPosition(carIndex, CarOperations.CarPedals.Brake, 0.2)

end

-- TRANSITION FUNCTION
CarStateMachine.states_transitionFunctions[STATE] = function (carIndex, dt, sortedCarsList, sortedCarsListIndex, storage)

end

-- EXIT FUNCTION
CarStateMachine.states_exitFunctions[STATE] = function (carIndex, dt, sortedCarsList, sortedCarsListIndex, storage)

end
