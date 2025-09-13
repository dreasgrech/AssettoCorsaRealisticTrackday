local STATE = CarStateMachine.CarStateType.COLLIDED_WITH_CAR

CarStateMachine.CarStateTypeStrings[STATE] = "CollidedWithCar"
CarStateMachine.states_minimumTimeInState[STATE] = 10

-- ENTRY FUNCTION
CarStateMachine.states_entryFunctions[STATE] = function (carIndex, dt, sortedCarList, sortedCarListIndex, storage)
    -- todo: look at ac.SetDriverMouthOpened() lmao
    -- todo: look at ac.setDriverDoorOpen(carIndex, isOpen, instant)
    -- todo: look at ac.setBodyDirt(carIndex, dirt)
    -- todo: look at ac.overrideTyreSmoke(tyreIndex, intensity, thickness, surfaceHeat)
    CarOperations.stopCarAfterAccident(carIndex)

    CarManager.cars_reasonWhyCantYield[carIndex] = 'Collided with another car so we are stopped'
end

-- UPDATE FUNCTION
CarStateMachine.states_updateFunctions[STATE] = function (carIndex, dt, sortedCarList, sortedCarListIndex, storage)

end

-- TRANSITION FUNCTION
CarStateMachine.states_transitionFunctions[STATE] = function (carIndex, dt, sortedCarList, sortedCarListIndex, storage)

end

-- EXIT FUNCTION
CarStateMachine.states_exitFunctions[STATE] = function (carIndex, dt, sortedCarList, sortedCarListIndex, storage)

end
