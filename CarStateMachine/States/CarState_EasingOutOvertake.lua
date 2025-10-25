local STATE = CarStateMachine.CarStateType.EASING_OUT_OVERTAKE

CarStateMachine.CarStateTypeStrings[STATE] = "EasingOutOvertake"
CarStateMachine.states_minimumTimeInState[STATE] = 0

local StateExitReason = Strings.StringNames[Strings.StringCategories.StateExitReason]

-- ENTRY FUNCTION
---@param carIndex integer
---@param dt number
---@param sortedCarsList table<integer,ac.StateCar>
---@param sortedCarsListIndex integer
---@param storage StorageTable
CarStateMachine.states_entryFunctions[STATE] = function (carIndex, dt, sortedCarsList, sortedCarsListIndex, storage)
  -- make sure the state before us has saved the carIndex of the car we're overtaking
  local currentlyOvertakingCarIndex = CarManager.cars_currentlyOvertakingCarIndex[carIndex]
  if not currentlyOvertakingCarIndex then
    Logger.error(string.format('Car %d in state EasingOutOvertake but has no reference to the car it is overtaking!  Previous state needs to set it.', carIndex))
  end

  local car = sortedCarsList[sortedCarsListIndex]
  -- set the current spline offset to our actual lateral offset so we start easing in from the correct position
  CarManager.cars_currentSplineOffset[carIndex] = CarManager.getActualTrackLateralOffset(car.position)
end

-- UPDATE FUNCTION
---@param carIndex integer
---@param dt number
---@param sortedCarsList table<integer,ac.StateCar>
---@param sortedCarsListIndex integer
---@param storage StorageTable
CarStateMachine.states_updateFunctions[STATE] = function (carIndex, dt, sortedCarsList, sortedCarsListIndex, storage)
    local car = sortedCarsList[sortedCarsListIndex]
    -- local carFront = sortedCarsList[sortedCarsListIndex - 1]
    -- if (not carFront) then
        -- return
    -- end

    --local carFrontIndex = carFront.index
    -- local carFrontCurrentSideOffset = CarManager.cars_currentSplineOffset[carFrontIndex]
    -- local carFrontTargetSideOffset = CarManager.cars_targetSplineOffset[carFrontIndex]
    --storage.yieldSide 

    -- the drive to side is now the same side as the yielding side since we're easing out of the overtake
    -- local driveToSide = storage.yieldSide
    -- local driveToSide = RaceTrackManager.getYieldingSide()
    -- local targetOffset = 0
    local targetOffset = storage.defaultLateralOffset
    local rampSpeed_mps = storage.overtakeRampRelease_mps
    -- CarOperations.driveSafelyToSide(carIndex, dt, car, driveToSide, targetOffset, rampSpeed_mps, storage.overrideAiAwareness, true)
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

      local currentlyOvertakingCarIndex = CarManager.cars_currentlyOvertakingCarIndex[carIndex]
      local currentlyOvertakingCar = ac.getCar(currentlyOvertakingCarIndex)
      if not (currentlyOvertakingCar) then
          -- the car we're overtaking is no longer valid, return to driving normally
        -- CarStateMachine.setStateExitReason(carIndex, string.format('Car %d in state EasingOutOvertake but the car it was overtaking (car %d) is no longer valid, returning to driving normally', carIndex, currentlyOvertakingCarIndex))
        CarStateMachine.setStateExitReason(carIndex, StateExitReason.OvertakingCarNoLongerExists)
          return CarStateMachine.CarStateType.DRIVING_NORMALLY
      end

      -- check if there's currently a car behind us
      if carBehind then
        -- check if the car behind us is the same car we're overtaking
        local isCarSameAsCarWeAreOvertaking = carBehind.index == currentlyOvertakingCarIndex
        -- if the car behind us is not the same car we're overtaking, check if we should start yielding to it instead
        if not isCarSameAsCarWeAreOvertaking then
          -- local newStateDueToCarBehind = CarStateMachine.handleShouldWeYieldToBehindCar(carIndex, car, carBehind, carFront, storage)
          local newStateDueToCarBehind = CarStateMachine.handleShouldWeYieldToBehindCar(sortedCarsList, sortedCarsListIndex, storage)
          if newStateDueToCarBehind then
            CarManager.cars_currentlyOvertakingCarIndex[carIndex] = nil
            -- CarStateMachine.setStateExitReason(carIndex, string.format('Yielding to new car behind #%d instead', carBehind.index))
            CarStateMachine.setStateExitReason(carIndex, StateExitReason.YieldingToCar)
            return newStateDueToCarBehind
          end
        end
      end

      -- If there's a different car to the one we're currently overtaking in front of us, check if we can overtake it as well
      local newStateDueToOvertakingNextCar = CarStateMachine.handleOvertakeNextCarWhileAlreadyOvertaking(carIndex, car, carFront, carBehind, storage, currentlyOvertakingCarIndex)
      if newStateDueToOvertakingNextCar then
          CarStateMachine.setStateExitReason(carIndex, StateExitReason.ContinuingOvertakingNextCar)
          -- return newStateDueToOvertakingNextCar
          return CarStateMachine.CarStateType.EASING_IN_OVERTAKE -- since we're currently easing out overtake, we need to go to easing in overtake first before going to staying on overtaking lane
      end

      -- if we're back to the center, return to normal driving
      -- -- local currentSplineOffset = CarManager.cars_currentSplineOffset[carIndex]
      -- local currentSplineOffset = CarManager.getCalculatedTrackLateralOffset(carIndex)
      -- -- local arrivedBackToNormal = currentSplineOffset == 0
      -- local arrivedBackToNormal
      -- local driveToSide = storage.yieldSide
      -- if driveToSide == RaceTrackManager.TrackSide.LEFT then
        -- arrivedBackToNormal = currentSplineOffset <= 0
      -- else
        -- arrivedBackToNormal = currentSplineOffset >= 0
      -- end

      -- if we're back to the center, return to normal driving
      -- local driveToSide = storage.yieldSide
      local driveToSide = RaceTrackManager.getYieldingSide()
      local arrivedAtTargetOffset = CarOperations.hasArrivedAtTargetSplineOffset(carIndex, driveToSide)
      if arrivedAtTargetOffset then
        CarManager.cars_currentlyOvertakingCarIndex[carIndex] = nil -- clear the reference to the car we were overtaking since we'll now go back to normal driving
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
