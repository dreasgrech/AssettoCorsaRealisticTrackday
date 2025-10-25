local STATE = CarStateMachine.CarStateType.EASING_OUT_YIELD

CarStateMachine.CarStateTypeStrings[STATE] = "EasingOutYield"
CarStateMachine.states_minimumTimeInState[STATE] = 0

local StateExitReason = Strings.StringNames[Strings.StringCategories.StateExitReason]

-- ENTRY FUNCTION
---@param carIndex integer
---@param dt number
---@param sortedCarsList table<integer,ac.StateCar>
---@param sortedCarsListIndex integer
---@param storage StorageTable
CarStateMachine.states_entryFunctions[STATE] = function (carIndex, dt, sortedCarsList, sortedCarsListIndex, storage)
  -- make sure the state before us has saved the carIndex of the car we're yielding to
  local currentlyYieldingToCarIndex = CarManager.cars_currentlyYieldingCarToIndex[carIndex]
  if not currentlyYieldingToCarIndex then
    Logger.error(string.format('Car %d in state EasingOutYield but has no reference to the car it is yielding to!  Previous state needs to set it.', carIndex))
  end

  local car = sortedCarsList[sortedCarsListIndex]

  -- set the current spline offset to our actual lateral offset so we start easing in from the correct position
  CarManager.cars_currentSplineOffset[carIndex] = CarManager.getActualTrackLateralOffset(car.position)

  -- remove the yielding car throttle limit since we will now start easing out the yield
  CarOperations.resetAIThrottleLimit(carIndex)
  CarOperations.removeAITopSpeed(carIndex)

  -- reset the yielding car caution back to normal
  CarOperations.removeAICaution(carIndex)

  -- inverse the turning lights while easing out yield (inverted yield direction since the car is now going back to center)
  local turningLights = (not RaceTrackManager.getYieldingSide() == RaceTrackManager.TrackSide.LEFT) and ac.TurningLights.Left or ac.TurningLights.Right
  -- CarOperations.toggleTurningLights(carIndex, car, turningLights)
  CarOperations.toggleTurningLights(carIndex, turningLights)
end

-- UPDATE FUNCTION
---@param carIndex integer
---@param dt number
---@param sortedCarsList table<integer,ac.StateCar>
---@param sortedCarsListIndex integer
---@param storage StorageTable
CarStateMachine.states_updateFunctions[STATE] = function (carIndex, dt, sortedCarsList, sortedCarsListIndex, storage)
      local car = sortedCarsList[sortedCarsListIndex]

      -- this is the side we're currently easing out to, which is the inverse of the side we yielded to
      -- local easeOutYieldSide = RaceTrackManager.getOvertakingSide() -- always ease out yield to the overtaking side
      -- local targetOffset = 0
      local targetOffset = storage.defaultLateralOffset
      local rampSpeed_mps = storage.rampRelease_mps
      -- CarOperations.driveSafelyToSide(carIndex, dt, car, easeOutYieldSide, targetOffset, rampSpeed_mps, storage.overrideAiAwareness, true)
      CarOperations.driveSafelyToSide(carIndex, dt, car, targetOffset, rampSpeed_mps, storage.overrideAiAwareness, true)
end

-- TRANSITION FUNCTION
---@param carIndex integer
---@param dt number
---@param sortedCarsList table<integer,ac.StateCar>
---@param sortedCarsListIndex integer
---@param storage StorageTable
CarStateMachine.states_transitionFunctions[STATE] = function (carIndex, dt, sortedCarsList, sortedCarsListIndex, storage)
      local car = sortedCarsList[sortedCarsListIndex]

      -- check if we're now in a yellow flag zone
      local newStateDueToYellowFlagZone = CarStateMachine.handleYellowFlagZone(carIndex, car)
      if newStateDueToYellowFlagZone then
        CarStateMachine.setStateExitReason(carIndex, StateExitReason.EnteringYellowFlagZone)
        return newStateDueToYellowFlagZone
      end

      local carBehind = sortedCarsList[sortedCarsListIndex + 1]
      local carFront = sortedCarsList[sortedCarsListIndex - 1]

      -- if there's a car behind us, check if we should start yielding to it
      -- jlocal newStateDueToCarBehind = CarStateMachine.handleShouldWeYieldToBehindCar(carIndex, car, carBehind, carFront, storage)
      local newStateDueToCarBehind = CarStateMachine.handleShouldWeYieldToBehindCar(sortedCarsList, sortedCarsListIndex, storage)
      if newStateDueToCarBehind then
        -- Andreas: don't clear the cars_currentlyYieldingCarToIndex value since handleShouldWeYieldToBehindCar writes to it
        -- CarStateMachine.setStateExitReason(carIndex, string.format('Yielding to new car behind #%d instead', carBehind.index))
        CarStateMachine.setStateExitReason(carIndex, StateExitReason.YieldingToCar)
        return newStateDueToCarBehind
      end

      -- -- if we're back to the center, return to normal driving
      -- -- local currentSplineOffset = CarManager.cars_currentSplineOffset[carIndex]
      -- local currentSplineOffset = CarManager.getCalculatedTrackLateralOffset(carIndex)
      -- -- local arrivedBackToNormal = currentSplineOffset == 0
      -- local arrivedBackToNormal
      -- local yieldSide = storage.yieldSide
      -- -- this is the side we're currently easing out to, which is the inverse of the side we yielded to
      -- -- local easeOutYieldSide = (yieldSide == RaceTrackManager.TrackSide.LEFT) and RaceTrackManager.TrackSide.RIGHT or RaceTrackManager.TrackSide.LEFT
      -- local easeOutYieldSide = RaceTrackManager.getOppositeSide(yieldSide)
      -- if easeOutYieldSide == RaceTrackManager.TrackSide.LEFT then
        -- -- arrivedBackToNormal = currentSplineOffset >= 0
        -- arrivedBackToNormal = currentSplineOffset <= 0
      -- else
        -- -- arrivedBackToNormal = currentSplineOffset <= 0
        -- arrivedBackToNormal = currentSplineOffset >= 0
      -- end

      -- if we're back to the center, return to normal driving
      -- local yieldSide = storage.yieldSide
      -- local easeOutYieldSide = RaceTrackManager.getOppositeSide(yieldSide)
      local easeOutYieldSide = RaceTrackManager.getOvertakingSide()
      local arrivedAtTargetOffset = CarOperations.hasArrivedAtTargetSplineOffset(carIndex, easeOutYieldSide)
      if arrivedAtTargetOffset then
        CarManager.cars_currentlyYieldingCarToIndex[carIndex] = nil -- clear the reference to the car we were yielding to since we'll now go back to normal driving
        -- CarStateMachine.setStateExitReason(carIndex, string.format('Arrived back to normal driving position, no longer yielding'))
        CarStateMachine.setStateExitReason(carIndex, StateExitReason.ArrivedToNormal)
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

end
