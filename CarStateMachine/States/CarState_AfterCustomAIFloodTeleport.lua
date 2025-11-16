local STATE = CarStateMachine.CarStateType.AFTER_CUSTOMAIFLOOD_TELEPORT

--[===[
Andreas: Read the comment in CustomFloodManager.lua about why this state exists and also why we can't make use of it
--]===]

CarStateMachine.CarStateTypeStrings[STATE] = "AfterCustomAIFloodTeleport"
CarStateMachine.states_minimumTimeInState[STATE] = 0

-- ENTRY FUNCTION
CarStateMachine.states_entryFunctions[STATE] = function (carIndex, dt, sortedCarsList, sortedCarsListIndex, storage)
      physics.setCarFuel(carIndex, 100)
      physics.engageGear(carIndex, 3)
      physics.setEngineRPM(carIndex, 5000)
      physics.setAIStopCounter(carIndex, 0)
end

-- UPDATE FUNCTION
CarStateMachine.states_updateFunctions[STATE] = function (carIndex, dt, sortedCarsList, sortedCarsListIndex, storage)
    ---@type ac.StateCar
      local car = sortedCarsList[sortedCarsListIndex]
      physics.setGentleStop(carIndex, false)
      -- CarOperations.setPedalPosition(carIndex,CarOperations.CarPedals.Gas, 0.4)
      physics.setAICaution(carIndex, 0)
      -- physics.setCarVelocity(carIndex, car.look * 10)
      -- physics.addForce
      physics.awakeCar(carIndex)
      physics.setAINoInput(carIndex, false, false)
      physics.setAIStopCounter(carIndex, 0)
      -- physics.setCarFuel(carIndex, 100)
      -- physics.engageGear(carIndex, 3)
      -- physics.setEngineRPM(carIndex, 5000)
end

-- TRANSITION FUNCTION
CarStateMachine.states_transitionFunctions[STATE] = function (carIndex, dt, sortedCarsList, sortedCarsListIndex, storage)
      

    ---@type ac.StateCar
    -- local car = sortedCarsList[sortedCarsListIndex]
    -- local carSpeed = car.speedKmh
    -- if carSpeed > 60 then
        -- return CarStateMachine.CarStateType.DRIVING_NORMALLY
    -- end

    -- local timeInCurrentState =CarManager.cars_timeInCurrentState[carIndex]
    -- if timeInCurrentState > 20.0 then
        -- return CarStateMachine.CarStateType.DRIVING_NORMALLY
    -- end
end

-- EXIT FUNCTION
CarStateMachine.states_exitFunctions[STATE] = function (carIndex, dt, sortedCarsList, sortedCarsListIndex, storage)
      physics.setAICaution(carIndex, 1)
      CarOperations.resetPedalPosition(carIndex, CarOperations.CarPedals.Gas)

      CarManager.cars_doNoResetAfterNextCarJump[carIndex] = false
end