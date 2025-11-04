-- bindings
local ac = ac
local CarManager = CarManager
local CarManager_getActualTrackLateralOffset = CarManager.getActualTrackLateralOffset
local CarManager_setCalculatedTrackLateralOffset = CarManager.setCalculatedTrackLateralOffset
local CarOperations = CarOperations
local CarOperations_removeAICaution = CarOperations.removeAICaution
local CarOperations_setDefaultAIAggression = CarOperations.setDefaultAIAggression
local CarOperations_toggleTurningLights = CarOperations.toggleTurningLights
local CarOperations_resetAIThrottleLimit = CarOperations.resetAIThrottleLimit
local CarOperations_setDefaultAIGrip = CarOperations.setDefaultAIGrip
local CarOperations_driveSafelyToSide = CarOperations.driveSafelyToSide
local CarOperations_isCarInPits = CarOperations.isCarInPits
local CarStateMachine = CarStateMachine
local CarStateMachine_handleShouldWeYieldToBehindCar = CarStateMachine.handleShouldWeYieldToBehindCar
local CarStateMachine_handleShouldWeOvertakeFrontCar = CarStateMachine.handleShouldWeOvertakeFrontCar
local CarStateMachine_handleYellowFlagZone = CarStateMachine.handleYellowFlagZone
local CarStateMachine_setStateExitReason = CarStateMachine.setStateExitReason
local CarStateMachine_setReasonWhyCantYield = CarStateMachine.setReasonWhyCantYield
local Strings = Strings


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
      local car = sortedCarsList[sortedCarsListIndex]
      local carPosition = car.position

      -- set the current spline offset to our actual lateral offset so we start easing in from the correct position
      local actualLateralOffset = CarManager_getActualTrackLateralOffset(carPosition)
      CarManager_setCalculatedTrackLateralOffset(carIndex, actualLateralOffset)

      local targetOffset = storage.defaultLateralOffset
      CarManager.cars_targetSplineOffset[carIndex] = targetOffset

      -- CarManager.cars_reasonWhyCantYield[carIndex] = nil
      CarStateMachine_setReasonWhyCantYield(carIndex, ReasonWhyCantYield.None)

      -- remove any reference to a car we may have been overtaking or yielding
      CarManager.cars_currentlyOvertakingCarIndex[carIndex] = nil
      CarManager.cars_currentlyYieldingCarToIndex[carIndex] = nil

      -- turn off turning lights
      CarOperations_toggleTurningLights(carIndex, ac.TurningLights.None)

      -- reset the yielding car caution back to normal
      CarOperations_removeAICaution(carIndex)

      CarOperations_setDefaultAIAggression(carIndex)

      -- remove the yielding car throttle limit since we will now be driving normally
      CarOperations_resetAIThrottleLimit(carIndex)
      
      CarOperations_setDefaultAIGrip(carIndex)
end

-- UPDATE FUNCTION
---@param carIndex integer
---@param dt number
---@param sortedCarsList table<integer,ac.StateCar>
---@param sortedCarsListIndex integer
---@param storage StorageTable
CarStateMachine.states_updateFunctions[STATE] = function (carIndex, dt, sortedCarsList, sortedCarsListIndex, storage)
      -- Keep setting this per tick because the default ai aggression can be changed from the settings
      CarOperations_setDefaultAIAggression(carIndex)

      local rampSpeed_mps = 1000 -- high value so they keep on the lane as much as possible?
      local targetOffset = storage.defaultLateralOffset

      local car = sortedCarsList[sortedCarsListIndex]

      -- Keep driving towards the default lateral offset to try and keep the lane as much as possible
      CarOperations_driveSafelyToSide(carIndex, dt, car, targetOffset, rampSpeed_mps, storage.overrideAiAwareness, true, false)
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
      local areWeInPits = CarOperations_isCarInPits(car)
      if areWeInPits then
        return
      end

      local carBehind = sortedCarsList[sortedCarsListIndex + 1]
      local carFront = sortedCarsList[sortedCarsListIndex - 1]

      -- check if we're now in a yellow flag zone
      local newStateDueToYellowFlagZone = CarStateMachine_handleYellowFlagZone(carIndex, car)
      if newStateDueToYellowFlagZone then
        CarStateMachine_setStateExitReason(carIndex, StateExitReason.EnteringYellowFlagZone)
        return newStateDueToYellowFlagZone
      end

      -- If there's a car behind us, check if we should start yielding to it
      -- local newStateDueToCarBehind = CarStateMachine.handleShouldWeYieldToBehindCar(carIndex, car, carBehind, carFront, storage)
      local newStateDueToCarBehind = CarStateMachine_handleShouldWeYieldToBehindCar(sortedCarsList, sortedCarsListIndex)
      if newStateDueToCarBehind then
        -- CarStateMachine.setStateExitReason(carIndex, string.format("Yielding to car #%d", carBehind.index))
        CarStateMachine_setStateExitReason(carIndex, StateExitReason.YieldingToCar)
        return newStateDueToCarBehind
      end

      -- if there's a car in front of us, check if we can overtake it
      local newStateDueToCarFront = CarStateMachine_handleShouldWeOvertakeFrontCar(carIndex, car, carFront, carBehind)
      if newStateDueToCarFront then
        -- CarStateMachine.setStateExitReason(carIndex, string.format("Overtaking car #%d", carFront.index))
        CarStateMachine_setStateExitReason(carIndex, StateExitReason.OvertakingCar)
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
      CarStateMachine_setReasonWhyCantYield(carIndex, ReasonWhyCantYield.None)
end