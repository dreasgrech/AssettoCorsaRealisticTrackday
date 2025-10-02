local STATE = CarStateMachine.CarStateType.EASING_IN_OVERTAKE

CarStateMachine.CarStateTypeStrings[STATE] = "EasingInOvertake"
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
    Logger.error(string.format('Car %d in state EasingInOvertake but has no reference to the car it is overtaking!  Previous state needs to set it.', carIndex))
  end

  -- make sure that we're also not yielding to another car at the same time
  local currentlyYieldingToCarIndex = CarManager.cars_currentlyYieldingCarToIndex[carIndex]
  if currentlyYieldingToCarIndex then
    local previousState = CarStateMachine.getPreviousState(carIndex)
    Logger.error(string.format('[CarState_EasingInOvertake] Car %d is both yielding to car %d and overtaking car %d at the same time!  Previous state: %s', carIndex, currentlyYieldingToCarIndex, currentlyOvertakingCarIndex, CarStateMachine.CarStateTypeStrings[previousState]))
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
    local currentlyOvertakingCarIndex = CarManager.cars_currentlyOvertakingCarIndex[carIndex]
    local carFront = ac.getCar(currentlyOvertakingCarIndex)
    if (not carFront) then
        return
    end

    -- make the driver more aggressive while overtaking
    -- CarOperations.setAICaution(carIndex, 0) -- andreas: commenting this because they get way too aggressive

    -- local carFrontIndex = carFront.index
    -- local carFrontCurrentSideOffset = CarManager.cars_currentSplineOffset[carFrontIndex]
    -- local carFrontTargetSideOffset = CarManager.cars_targetSplineOffset[carFrontIndex]
    --storage.yieldSide 

    -- the drive to side is to be opposite side to the the yielding side
    -- local driveToSide = storage.yieldSide == RaceTrackManager.TrackSide.LEFT and RaceTrackManager.TrackSide.RIGHT or RaceTrackManager.TrackSide.LEFT
    local driveToSide = RaceTrackManager.getOvertakingSide()
    local targetOffset = storage.maxLateralOffset_normalized
    local rampSpeed_mps = storage.overtakeRampSpeed_mps
    local droveSafelyToSide = CarOperations.driveSafelyToSide(carIndex, dt, car, driveToSide, targetOffset, rampSpeed_mps, storage.overrideAiAwareness)
    if not droveSafelyToSide then
        -- TODO: Continue here
        -- TODO: Continue here
        -- TODO: Continue here
        -- TODO: Continue here
        -- TODO: Continue here
        
    end

end

-- TRANSITION FUNCTION
---@param carIndex integer
---@param dt number
---@param sortedCarsList table<integer,ac.StateCar>
---@param sortedCarsListIndex integer
---@param storage StorageTable
CarStateMachine.states_transitionFunctions[STATE] = function (carIndex, dt, sortedCarsList, sortedCarsListIndex, storage)
    -- -- if we're suddendly at the front of the pack, return to easing out overtake
    -- local carFront = sortedCarsList[sortedCarsListIndex - 1]
    -- if (not carFront) then
        -- -- no car in front of us, return to easing out overtake
        -- CarManager.cars_currentlyOvertakingCarIndex[carIndex] = nil
        -- return CarStateMachine.CarStateType.EASING_OUT_OVERTAKE
    -- end

    local car = sortedCarsList[sortedCarsListIndex]

      -- check if we're now in a yellow flag zone
      local newStateDueToYellowFlagZone = CarStateMachine.handleYellowFlagZone(carIndex, car)
      if newStateDueToYellowFlagZone then
        CarStateMachine.setStateExitReason(carIndex, StateExitReason.EnteringYellowFlagZone)
        return newStateDueToYellowFlagZone
      end

    -- fetch the car index of the car we're overtaking
    local currentlyOvertakingCarIndex = CarManager.cars_currentlyOvertakingCarIndex[carIndex]
    -- if (not currentlyOvertakingCarIndex) then
        -- -- something went wrong, we should have a reference to the car we're overtaking
        -- Logger.error(string.format('Car %d in state DrivingToSideToOvertake but has no reference to the car it is overtaking, returning to normal driving', carIndex))
        -- CarManager.cars_currentlyOvertakingCarIndex[carIndex] = nil
        -- return CarStateMachine.CarStateType.EASING_OUT_OVERTAKE
    -- end

    -- make sure the car we're overtaking is still valid
    local currentlyOvertakingCar = ac.getCar(currentlyOvertakingCarIndex)
    if (not currentlyOvertakingCar) then
        -- the car we're overtaking is no longer valid, return to easing out overtake
        Logger.warn(string.format('Car %d in state DrivingToSideToOvertake but the car it was overtaking (car %d) is no longer valid, returning to normal driving', carIndex, currentlyOvertakingCarIndex))
        CarManager.cars_currentlyOvertakingCarIndex[carIndex] = nil
        -- CarStateMachine.setStateExitReason(carIndex, string.format('Car %d in state DrivingToSideToOvertake but the car it was overtaking (car %d) is no longer valid, returning to normal driving', carIndex, currentlyOvertakingCarIndex))
        CarStateMachine.setStateExitReason(carIndex, StateExitReason.OvertakingCarNoLongerExists)
        return CarStateMachine.CarStateType.EASING_OUT_OVERTAKE
    end

    -- If there's a car behind us, check if we should start yielding to it
    local carFront = sortedCarsList[sortedCarsListIndex - 1]
    local carBehind = sortedCarsList[sortedCarsListIndex + 1]
    -- local newStateDueToCarBehind = CarStateMachine.handleShouldWeYieldToBehindCar(carIndex, car, carBehind, carFront, storage)
    -- if newStateDueToCarBehind then
        -- CarManager.cars_currentlyOvertakingCarIndex[carIndex] = nil
        -- return newStateDueToCarBehind
    -- end
    -- check if there's currently a car behind us
    if carBehind then
        -- check if the car behind us is the same car we're overtaking
        local isCarSameAsCarWeAreOvertaking = carBehind.index == currentlyOvertakingCarIndex
        -- if the car behind us is not the same car we're overtaking, check if we should start yielding to it instead
        if not isCarSameAsCarWeAreOvertaking then
            local newStateDueToCarBehind = CarStateMachine.handleShouldWeYieldToBehindCar(carIndex, car, carBehind, carFront, storage)
            if newStateDueToCarBehind then
                CarManager.cars_currentlyOvertakingCarIndex[carIndex] = nil
                -- CarStateMachine.setStateExitReason(carIndex, string.format('Yielding to new car behind #%d instead', carBehind.index))
                CarStateMachine.setStateExitReason(carIndex, StateExitReason.YieldingToCar)
                return newStateDueToCarBehind
            end
        end
    end

    -- -- if we've arrived at the target side offset, we can now stay on the overtaking lane
    -- -- local currentSplineOffset = CarManager.cars_currentSplineOffset[carIndex]
    -- local currentSplineOffset = CarManager.getCalculatedTrackLateralOffset(carIndex)
    -- local targetSplineOffset = CarManager.cars_targetSplineOffset[carIndex]
    -- -- local arrivedAtTargetOffset = currentSplineOffset == targetSplineOffset
      -- -- calculate by checking if we'rve gone past the target too but the target could be less or greater than our value
      -- local arrivedAtTargetOffset
      -- -- local driveToSide = storage.yieldSide == RaceTrackManager.TrackSide.LEFT and RaceTrackManager.TrackSide.RIGHT or RaceTrackManager.TrackSide.LEFT
      -- local driveToSide = RaceTrackManager.getOppositeSide(storage.yieldSide)
      -- if driveToSide == RaceTrackManager.TrackSide.LEFT then
        -- arrivedAtTargetOffset = currentSplineOffset <= targetSplineOffset
      -- else
        -- arrivedAtTargetOffset = currentSplineOffset >= targetSplineOffset
      -- end

    -- if we've arrived at the target side offset, we can now stay on the overtaking lane
    -- local driveToSide = RaceTrackManager.getOppositeSide(storage.yieldSide)
    local driveToSide = RaceTrackManager.getOvertakingSide()
    local arrivedAtTargetOffset = CarOperations.hasArrivedAtTargetSplineOffset(carIndex, driveToSide)
    if arrivedAtTargetOffset then
        -- CarStateMachine.setStateExitReason(carIndex, 'Arrived at overtaking position, now staying on overtaking lane')
        CarStateMachine.setStateExitReason(carIndex, StateExitReason.ArrivedAtOvertakingLane)
        return CarStateMachine.CarStateType.STAYING_ON_OVERTAKING_LANE
    end
end

-- EXIT FUNCTION
---@param carIndex integer
---@param dt number
---@param sortedCarsList table<integer,ac.StateCar>
---@param sortedCarsListIndex integer
---@param storage StorageTable
CarStateMachine.states_exitFunctions[STATE] = function (carIndex, dt, sortedCarsList, sortedCarsListIndex, storage)
    -- reset the overtaking car caution back to normal
    CarOperations.removeAICaution(carIndex)
end
