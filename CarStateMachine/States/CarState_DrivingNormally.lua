local STATE = CarStateMachine.CarStateType.DRIVING_NORMALLY

CarStateMachine.CarStateTypeStrings[STATE] = "DrivingNormally"
CarStateMachine.states_minimumTimeInState[STATE] = 0

---@type Strings.StateExitReason
local StateExitReason = Strings.StringNames[Strings.StringCategories.StateExitReason]
---@type Strings.ReasonWhyCantYield
local ReasonWhyCantYield = Strings.StringNames[Strings.StringCategories.ReasonWhyCantYield]

-- ENTRY FUNCTION
---@param carIndex integer
---@param dt number
---@param sortedCarsList table<integer,ac.StateCar>
---@param sortedCarsListIndex integer
---@param storage StorageTable
CarStateMachine.states_entryFunctions[STATE] = function (carIndex, dt, sortedCarsList, sortedCarsListIndex, storage)
      CarManager.cars_currentSplineOffset[carIndex] = 0
      CarManager.cars_targetSplineOffset[carIndex] = 0
      -- CarManager.cars_reasonWhyCantYield[carIndex] = nil
      CarStateMachine.setReasonWhyCantYield(carIndex, ReasonWhyCantYield.None)

      -- remove any reference to a car we may have been overtaking or yielding
      CarManager.cars_currentlyOvertakingCarIndex[carIndex] = nil
      CarManager.cars_currentlyYieldingCarToIndex[carIndex] = nil

      -- turn off turning lights
      CarOperations.toggleTurningLights(carIndex, ac.TurningLights.None)

      -- reset the yielding car caution back to normal
      CarOperations.removeAICaution(carIndex)

      -- remove the yielding car throttle limit since we will now be driving normally
      CarOperations.resetAIThrottleLimit(carIndex)
      
      CarOperations.setDefaultAIGrip(carIndex)
end

-- UPDATE FUNCTION
---@param carIndex integer
---@param dt number
---@param sortedCarsList table<integer,ac.StateCar>
---@param sortedCarsListIndex integer
---@param storage StorageTable
CarStateMachine.states_updateFunctions[STATE] = function (carIndex, dt, sortedCarsList, sortedCarsListIndex, storage)
      local rampSpeed_mps = 1000 -- high value so they keep on the lane as much as possible?
      local targetOffset = storage.defaultLateralOffset

      local car = sortedCarsList[sortedCarsListIndex]

      -- Keep driving towards the default lateral offset to try and keep the lane as much as possible
      CarOperations.driveSafelyToSide(carIndex, dt, car, targetOffset, rampSpeed_mps, storage.overrideAiAwareness, true)
end

-- TRANSITION FUNCTION
---@param carIndex integer
---@param dt number
---@param sortedCarsList table<integer,ac.StateCar>
---@param sortedCarsListIndex integer
---@param storage StorageTable
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

      -- don't do anything if we're in the pits
      -- TODO: This should be changed such that being in pits should have it's own separate state for the state machine
      local areWeInPits = CarOperations.isCarInPits(car)
      if areWeInPits then
        return
      end

      local carBehind = sortedCarsList[sortedCarsListIndex + 1]
      local carFront = sortedCarsList[sortedCarsListIndex - 1]

      -- check if we're now in a yellow flag zone
      local newStateDueToYellowFlagZone = CarStateMachine.handleYellowFlagZone(carIndex, car)
      if newStateDueToYellowFlagZone then
        CarStateMachine.setStateExitReason(carIndex, StateExitReason.EnteringYellowFlagZone)
        return newStateDueToYellowFlagZone
      end

      -- If there's a car behind us, check if we should start yielding to it
      -- local newStateDueToCarBehind = CarStateMachine.handleShouldWeYieldToBehindCar(carIndex, car, carBehind, carFront, storage)
      local newStateDueToCarBehind = CarStateMachine.handleShouldWeYieldToBehindCar(sortedCarsList, sortedCarsListIndex, storage)
      if newStateDueToCarBehind then
        -- CarStateMachine.setStateExitReason(carIndex, string.format("Yielding to car #%d", carBehind.index))
        CarStateMachine.setStateExitReason(carIndex, StateExitReason.YieldingToCar)
        return newStateDueToCarBehind
      end

      -- if there's a car in front of us, check if we can overtake it
      local newStateDueToCarFront = CarStateMachine.handleCanWeOvertakeFrontCar(carIndex, car, carFront, carBehind, storage)
      if newStateDueToCarFront then
        -- CarStateMachine.setStateExitReason(carIndex, string.format("Overtaking car #%d", carFront.index))
        CarStateMachine.setStateExitReason(carIndex, StateExitReason.OvertakingCar)
        return newStateDueToCarFront
      end
end

-- EXIT FUNCTION
---@param carIndex integer
---@param dt number
---@param sortedCarsList table<integer,ac.StateCar>
---@param sortedCarsListIndex integer
---@param storage StorageTable
CarStateMachine.states_exitFunctions[STATE] = function (carIndex, dt, sortedCarsList, sortedCarsListIndex, storage)
      CarStateMachine.setReasonWhyCantYield(carIndex, ReasonWhyCantYield.None)
end