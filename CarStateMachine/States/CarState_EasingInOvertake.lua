-- bindings
local ac = ac
local ac_getCar = ac.getCar
local string = string
local string_format = string.format
local Logger = Logger
local Logger_log = Logger.log
local Logger_error = Logger.error
local Logger_warn = Logger.warn
local CarManager = CarManager
local CarManager_getActualTrackLateralOffset = CarManager.getActualTrackLateralOffset
local CarManager_setCalculatedTrackLateralOffset = CarManager.setCalculatedTrackLateralOffset
local CarOperations = CarOperations
local CarOperations_overtakeSafelyToSide = CarOperations.overtakeSafelyToSide
local CarOperations_calculateAICautionAndAggressionWhileOvertaking = CarOperations.calculateAICautionAndAggressionWhileOvertaking
local CarOperations_setAICaution = CarOperations.setAICaution
local CarOperations_setAIAggression = CarOperations.setAIAggression
local CarOperations_hasArrivedAtTargetSplineOffset = CarOperations.hasArrivedAtTargetSplineOffset
local CarOperations_removeAICaution = CarOperations.removeAICaution
local CarOperations_setDefaultAIAggression = CarOperations.setDefaultAIAggression
local CarOperations_toggleTurningLights = CarOperations.toggleTurningLights
local CarStateMachine = CarStateMachine
local CarStateMachine_getPreviousState = CarStateMachine.getPreviousState
local CarStateMachine_handleShouldWeYieldToBehindCar = CarStateMachine.handleShouldWeYieldToBehindCar
local CarStateMachine_handleYellowFlagZone = CarStateMachine.handleYellowFlagZone
local CarStateMachine_setStateExitReason = CarStateMachine.setStateExitReason
local RaceTrackManager = RaceTrackManager
local RaceTrackManager_getYieldingSide = RaceTrackManager.getYieldingSide
local RaceTrackManager_getOvertakingSide = RaceTrackManager.getOvertakingSide
local StorageManager = StorageManager
local StorageManager_getStorage_Debugging = StorageManager.getStorage_Debugging
local StorageManager_getStorage_Overtaking = StorageManager.getStorage_Overtaking
local Strings = Strings

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
    Logger_error(string_format('Car %d in state EasingInOvertake but has no reference to the car it is overtaking!  Previous state needs to set it.', carIndex))
  end

  -- make sure that we're also not yielding to another car at the same time
  local currentlyYieldingToCarIndex = CarManager.cars_currentlyYieldingCarToIndex[carIndex]
  if currentlyYieldingToCarIndex then
    local previousState = CarStateMachine_getPreviousState(carIndex)
    Logger_error(string_format('[CarState_EasingInOvertake] Car %d is both yielding to car %d and overtaking car %d at the same time!  Previous state: %s', carIndex, currentlyYieldingToCarIndex, currentlyOvertakingCarIndex, CarStateMachine.CarStateTypeStrings[previousState]))
  end

  local car = sortedCarsList[sortedCarsListIndex]
  -- set the current spline offset to our actual lateral offset so we start easing in from the correct position
  CarManager_setCalculatedTrackLateralOffset(carIndex, CarManager_getActualTrackLateralOffset(car.position))

  local storage_Debugging = StorageManager_getStorage_Debugging()
  if storage_Debugging.debugLogCarOvertaking then
    local currentlyOvertakingCar = ac_getCar(currentlyOvertakingCarIndex)
    if currentlyOvertakingCar then
      local carFrontPosition = currentlyOvertakingCar.position
      Logger_log(string_format("[EasingInOvertake] #%d overtaking #%d. YieldingSide: %s, CarFrontPosition: %s, CarFrontLateralOffset: %.3f",
      carIndex,
      currentlyOvertakingCarIndex,
      RaceTrackManager_getYieldingSide(),
      carFrontPosition,
      CarManager_getActualTrackLateralOffset(carFrontPosition)
      ))
    end
  end
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
    local carFront = ac_getCar(currentlyOvertakingCarIndex)
    if (not carFront) then
        return
    end

    -- make the driver more aggressive while overtaking
    -- CarOperations.setAICaution(carIndex, 0) -- andreas: commenting this because they get way too aggressive

    -- local carFrontIndex = carFront.index
    -- local carFrontCurrentSideOffset = CarManager.cars_currentSplineOffset[carFrontIndex]
    -- local carFrontTargetSideOffset = CarManager.cars_targetSplineOffset[carFrontIndex]
    --storage.yieldSide 

    -- set the ai caution while we're overtaking
    local yieldingCarIndex = CarManager.cars_currentlyOvertakingCarIndex[carIndex] -- fetch the index of the car we're overtaking
    local yieldingCar = ac_getCar(yieldingCarIndex)
    -- local aiCaution = CarOperations.calculateAICautionWhileOvertaking(car, carFront)
    local aiCaution, aiAggression = CarOperations_calculateAICautionAndAggressionWhileOvertaking(car, yieldingCar)
    CarOperations_setAICaution(carIndex, aiCaution)
    
    if storage.overrideOriginalAIAggression_overtaking then
      CarOperations_setAIAggression(carIndex, aiAggression)
    end

    -- -- the drive to side is to be opposite side to the the yielding side
    -- local driveToSide = RaceTrackManager.getOvertakingSide()
    -- local targetOffset = storage.maxLateralOffset_normalized
    -- local rampSpeed_mps = storage.overtakeRampSpeed_mps
    -- local droveSafelyToSide = CarOperations.driveSafelyToSide(carIndex, dt, car, driveToSide, targetOffset, rampSpeed_mps, storage.overrideAiAwareness)

    -- ease in to the overtaking lane
    local storage_Overtaking = StorageManager_getStorage_Overtaking()
    local useIndicatorLights = storage_Overtaking.UseIndicatorLightsWhenEasingInOvertaking
    local droveSafelyToSide = CarOperations_overtakeSafelyToSide(carIndex, dt, car, storage, useIndicatorLights)
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
      local newStateDueToYellowFlagZone = CarStateMachine_handleYellowFlagZone(carIndex, car)
      if newStateDueToYellowFlagZone then
        CarStateMachine_setStateExitReason(carIndex, StateExitReason.EnteringYellowFlagZone)
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
    local currentlyOvertakingCar = ac_getCar(currentlyOvertakingCarIndex)
    if (not currentlyOvertakingCar) then
        -- the car we're overtaking is no longer valid, return to easing out overtake
        Logger_warn(string_format('Car %d in state DrivingToSideToOvertake but the car it was overtaking (car %d) is no longer valid, returning to normal driving', carIndex, currentlyOvertakingCarIndex))
        CarManager.cars_currentlyOvertakingCarIndex[carIndex] = nil
        -- CarStateMachine.setStateExitReason(carIndex, string.format('Car %d in state DrivingToSideToOvertake but the car it was overtaking (car %d) is no longer valid, returning to normal driving', carIndex, currentlyOvertakingCarIndex))
        CarStateMachine_setStateExitReason(carIndex, StateExitReason.OvertakingCarNoLongerExists)
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
            -- local newStateDueToCarBehind = CarStateMachine.handleShouldWeYieldToBehindCar(carIndex, car, carBehind, carFront, storage)
            local newStateDueToCarBehind = CarStateMachine_handleShouldWeYieldToBehindCar(sortedCarsList, sortedCarsListIndex)
            if newStateDueToCarBehind then
                CarManager.cars_currentlyOvertakingCarIndex[carIndex] = nil
                -- CarStateMachine.setStateExitReason(carIndex, string.format('Yielding to new car behind #%d instead', carBehind.index))
                CarStateMachine_setStateExitReason(carIndex, StateExitReason.YieldingToCar)
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
    local driveToSide = RaceTrackManager_getOvertakingSide()
    local arrivedAtTargetOffset = CarOperations_hasArrivedAtTargetSplineOffset(carIndex, driveToSide)
    if arrivedAtTargetOffset then
        -- CarStateMachine.setStateExitReason(carIndex, 'Arrived at overtaking position, now staying on overtaking lane')
        CarStateMachine_setStateExitReason(carIndex, StateExitReason.ArrivedAtOvertakingLane)
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
    CarOperations_removeAICaution(carIndex)
    CarOperations_setDefaultAIAggression(carIndex)
    CarOperations_toggleTurningLights(carIndex, ac.TurningLights.None)
end