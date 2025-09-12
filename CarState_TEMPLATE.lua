--[=====[ 
A template for creating new car states. 

----------------------------------------------------------------

local STATE = CarStateMachine.CarStateType.THIS_STATE

CarStateMachine.CarStateTypeStrings[STATE] = "ThisState"
CarStateMachine.states_minimumTimeInState[STATE] = 0

-- ENTRY FUNCTION
CarStateMachine.states_entryFunctions[STATE] = function (carIndex, dt, car, playerCar, storage)

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
--]=====]