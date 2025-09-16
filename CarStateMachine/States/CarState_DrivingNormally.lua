local STATE = CarStateMachine.CarStateType.DRIVING_NORMALLY

CarStateMachine.CarStateTypeStrings[STATE] = "DrivingNormally"
CarStateMachine.states_minimumTimeInState[STATE] = 0

-- ENTRY FUNCTION
CarStateMachine.states_entryFunctions[STATE] = function (carIndex, dt, car, carBehind, storage)
      CarManager.cars_yieldTime[carIndex] = 0
      CarManager.cars_currentSplineOffset[carIndex] = 0
      CarManager.cars_targetSplineOffset[carIndex] = 0
      CarManager.cars_reasonWhyCantYield[carIndex] = nil

      -- remove any reference to a car we may have been overtaking or yielding
      CarManager.cars_currentlyOvertakingCarIndex[carIndex] = nil
      CarManager.cars_currentlyYieldingCarToIndex[carIndex] = nil

      -- turn off turning lights
      CarOperations.toggleTurningLights(carIndex, car, ac.TurningLights.None)
      
    -- start driving normally
    -- CarStateMachine.changeState(carIndex, CarStateMachine.CarStateType.DRIVING_NORMALLY)

      -- reset the yielding car caution back to normal
      CarOperations.removeAICaution(carIndex)

      -- remove the yielding car throttle limit since we will now be driving normally
      CarOperations.setAIThrottleLimit(carIndex, 1)

end

-- UPDATE FUNCTION
CarStateMachine.states_updateFunctions[STATE] = function (carIndex, dt, car, carBehind, storage)
end


-- TRANSITION FUNCTION
-- CarStateMachine.states_transitionFunctions[STATE] = function (carIndex, dt, car, carBehind, storage)
CarStateMachine.states_transitionFunctions[STATE] = function (carIndex, dt, sortedCarsList, sortedCarsListIndex, storage)
      -- render.debugSphere(ac.getCar(carIndex).position, 1, rgbm(0.2, 0.2, 1.0, 1))

      -- DEBUG DEBUG DEBUG
      -- local anyHit, rays = CarOperations.simpleSideRaycasts(carIndex, 10.0)
      -- if anyHit then
          -- -- Logger.log(string.format("Car %d: Side raycast hit something, not yielding", carIndex))
          -- -- CarManager.cars_reasonWhyCantYield[carIndex] = 'Target side blocked by another car so not yielding (raycast)'
      -- end
      -- DEBUG DEBUG DEBUG

      local car = sortedCarsList[sortedCarsListIndex]

      -- if not carBehind then
        -- CarManager.cars_reasonWhyCantYield[carIndex] = 'No overtaking car so not yielding'
        -- return
      -- end
      local carBehind = sortedCarsList[sortedCarsListIndex + 1]
      local carFront = sortedCarsList[sortedCarsListIndex - 1]

      -- If there's a car behind us, check if we should start yielding to it
      local newStateDueToCarBehind = CarStateMachine.handleShouldWeYieldToBehindCar(carIndex, car, carBehind, carFront, storage)
      if newStateDueToCarBehind then
        return newStateDueToCarBehind
      end

      -- if there's a car in front of us, check if we can overtake it
      local newStateDueToCarFront = CarStateMachine.handleCanWeOvertakeFrontCar(carIndex, car, carFront, carBehind, storage)
      if newStateDueToCarFront then
        return newStateDueToCarFront
      end
end

-- EXIT FUNCTION
CarStateMachine.states_exitFunctions[STATE] = function (carIndex, dt, sortedCarList, sortedCarListIndex, storage)
      CarManager.cars_reasonWhyCantYield[carIndex] = nil
end