local STATE = CarStateMachine.CarStateType.ANOTHER_CAR_COLLIDED_INTO_ME

-- ENTRY FUNCTION
CarStateMachine.states_entryFunctions[STATE] = function (carIndex, dt, car, playerCar, storage)
    -- todo: look at ac.SetDriverMouthOpened() lmao
    -- todo: look at ac.setDriverDoorOpen(carIndex, isOpen, instant)
    -- todo: look at ac.setBodyDirt(carIndex, dirt)
    -- todo: look at ac.overrideTyreSmoke(tyreIndex, intensity, thickness, surfaceHeat)
    CarOperations.stopCarAfterAccident(carIndex)

    CarManager.cars_reasonWhyCantYield[carIndex] = 'Another car collided into me so we are stopped'

    local carInput = ac.overrideCarControls(carIndex)
    if carInput then
      -- carInput.horn = true
    end
end

-- UPDATE FUNCTION
CarStateMachine.states_updateFunctions[STATE] = function (carIndex, dt, car, playerCar, storage)

end

-- TRANSITION FUNCTION
CarStateMachine.states_transitionFunctions[STATE] = function (carIndex, dt, car, playerCar, storage)

end

-- EXIT FUNCTION
CarStateMachine.states_exitFunctions[STATE] = function (carIndex, dt, car, playerCar, storage)

end