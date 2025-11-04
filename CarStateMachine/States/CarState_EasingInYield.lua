-- bindings
local ac = ac
local ac_getCar = ac.getCar
local string = string
local string_format = string.format
local Logger = Logger
local Logger_log = Logger.log
local Logger_error = Logger.error
local CarManager = CarManager
local CarManager_getActualTrackLateralOffset = CarManager.getActualTrackLateralOffset
local CarManager_setCalculatedTrackLateralOffset = CarManager.setCalculatedTrackLateralOffset
local CarOperations = CarOperations
local CarOperations_toggleTurningLights = CarOperations.toggleTurningLights
local CarOperations_isSecondCarClearlyAhead = CarOperations.isSecondCarClearlyAhead
local CarOperations_hasArrivedAtTargetSplineOffset = CarOperations.hasArrivedAtTargetSplineOffset
local CarOperations_resetPedalPosition = CarOperations.resetPedalPosition
local CarOperations_resetAIThrottleLimit = CarOperations.resetAIThrottleLimit
local CarOperations_setPedalPosition = CarOperations.setPedalPosition
local CarOperations_setAIThrottleLimit = CarOperations.setAIThrottleLimit
local CarOperations_yieldSafelyToSide = CarOperations.yieldSafelyToSide
local CarStateMachine = CarStateMachine
local CarStateMachine_getPreviousState = CarStateMachine.getPreviousState
local CarStateMachine_handleYellowFlagZone = CarStateMachine.handleYellowFlagZone
local CarStateMachine_setStateExitReason = CarStateMachine.setStateExitReason
local RaceTrackManager = RaceTrackManager
local RaceTrackManager_getYieldingSide = RaceTrackManager.getYieldingSide
local StorageManager = StorageManager
local StorageManager_getStorage_Debugging = StorageManager.getStorage_Debugging
local StorageManager_getStorage_Yielding = StorageManager.getStorage_Yielding
local Strings = Strings


local STATE = CarStateMachine.CarStateType.EASING_IN_YIELD

CarStateMachine.CarStateTypeStrings[STATE] = "EasingInYield"
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
    Logger_error(string_format('Car %d in state EasingInYield but has no reference to the car it is yielding to!  Previous state needs to set it.', carIndex))
  end

  -- make sure that we're also not overtaking to another car at the same time
  local currentlyOvertakingCarIndex = CarManager.cars_currentlyOvertakingCarIndex[carIndex]
  if currentlyOvertakingCarIndex then
    local previousState = CarStateMachine_getPreviousState(carIndex)
    Logger_error(string_format('[CarState_EasingInYield] Car %d is both yielding to car %d and overtaking car %d at the same time!  Previous state: %s',
    carIndex, currentlyYieldingToCarIndex, currentlyOvertakingCarIndex, CarStateMachine.CarStateTypeStrings[previousState]))
  end

  local car = sortedCarsList[sortedCarsListIndex]

  -- set the current spline offset to our actual lateral offset so we start easing in from the correct position
  CarManager_setCalculatedTrackLateralOffset(carIndex, CarManager_getActualTrackLateralOffset(car.position))

  -- turn on turning lights
  local turningLights = RaceTrackManager_getYieldingSide()  == RaceTrackManager.TrackSide.LEFT and ac.TurningLights.Left or ac.TurningLights.Right
  CarOperations_toggleTurningLights(carIndex, turningLights)

  local storage_Debugging = StorageManager_getStorage_Debugging()
  if storage_Debugging.debugLogCarYielding then
    local currentlyYieldingToCar = ac_getCar(currentlyYieldingToCarIndex)
    if currentlyYieldingToCar then
      local carBehindPosition = currentlyYieldingToCar.position
      Logger_log(string_format("[EasingInYield] #%d yielding to #%d. CarAvgSpeed: %.3f, CarBehindAvgSpeed: %.3f, CarBehindLateralOffset: %.3f",
      carIndex,
      currentlyYieldingToCarIndex,
      CarManager.cars_averageSpeedKmh[carIndex],
      CarManager.cars_averageSpeedKmh[currentlyYieldingToCarIndex],
      CarManager_getActualTrackLateralOffset(carBehindPosition)
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
      --local yieldSide = getYieldingSide()
      --local targetOffset = storage.maxLateralOffset_normalized
      --local rampSpeed_mps = storage.rampSpeed_mps
      --local droveSafelyToSide = CarOperations.driveSafelyToSide(carIndex, dt, car, yieldSide, targetOffset, rampSpeed_mps, storage.overrideAiAwareness)

      local storage_Yielding = StorageManager_getStorage_Yielding()
      local useIndicatorLights = storage_Yielding.UseIndicatorLightsWhenEasingInYield
      local droveSafelyToSide = CarOperations_yieldSafelyToSide(carIndex, dt, car, storage, useIndicatorLights)
      if not droveSafelyToSide then
        -- reduce the car speed so that we can find a gap
        CarOperations_setAIThrottleLimit(carIndex, 0.4)

        -- set the brake pedal to something low to help slow down the car while waiting for a gap
        CarOperations_setPedalPosition(carIndex, CarOperations.CarPedals.Brake, 0.2)

        return
      end

      CarOperations_resetAIThrottleLimit(carIndex)
      CarOperations_resetPedalPosition(carIndex, CarOperations.CarPedals.Brake)

      CarStateMachine_setStateExitReason(carIndex, Strings.StringNames[Strings.StringCategories.ReasonWhyCantYield].None)

end

-- TRANSITION FUNCTION
---@param carIndex integer
---@param dt number
---@param sortedCarsList table<integer,ac.StateCar>
---@param sortedCarsListIndex integer
---@param storage StorageTable
CarStateMachine.states_transitionFunctions[STATE] = function (carIndex, dt, sortedCarsList, sortedCarsListIndex, storage)
      local car = sortedCarsList[sortedCarsListIndex]
      -- local carBehind = sortedCarList[sortedCarListIndex + 1]

      -- check if we're now in a yellow flag zone
      local newStateDueToYellowFlagZone = CarStateMachine_handleYellowFlagZone(carIndex, car)
      if newStateDueToYellowFlagZone then
        CarStateMachine_setStateExitReason(carIndex, StateExitReason.EnteringYellowFlagZone)
        return newStateDueToYellowFlagZone
      end

      local currentlyYieldingToCarIndex = CarManager.cars_currentlyYieldingCarToIndex[carIndex]
      local carWeAreYieldingTo = ac_getCar(currentlyYieldingToCarIndex)

      -- if the car we're yielding to is now clearly ahead of us, we can ease out our yielding
      local isOvertakingCarClearlyAheadOfYieldingCar = CarOperations_isSecondCarClearlyAhead(car, carWeAreYieldingTo, storage.clearAhead_meters)
      if isOvertakingCarClearlyAheadOfYieldingCar then

        -- go to trying to start easing out yield state
        -- CarStateMachine.setStateExitReason(carIndex, 'Overtaking car is clearly ahead of us so easing out yield')
        CarStateMachine_setStateExitReason(carIndex, StateExitReason.OvertakingCarIsClearlyAhead)
        return CarStateMachine.CarStateType.EASING_OUT_YIELD
      end

      -- --  if we're currently faster than the car trying to overtake us, we can ease out our yielding
      -- local areWeFasterThanCarTryingToOvertake = CarOperations.isFirstCarCurrentlyFasterThanSecondCar(car, playerCar)
      -- if areWeFasterThanCarTryingToOvertake then
        -- -- go to trying to start easing out yield state
        -- CarManager.cars_reasonWhyCantYield[carIndex] = 'We are now faster than the car behind, so easing out yield'
        -- return CarStateMachine.CarStateType.EASING_OUT_YIELD
      -- end

      -- if we have reached the target offset, we can go to the next state
      local yieldSide = RaceTrackManager_getYieldingSide()
      local arrivedAtTargetOffset = CarOperations_hasArrivedAtTargetSplineOffset(carIndex, yieldSide)
      if arrivedAtTargetOffset then
        -- CarStateMachine.setStateExitReason(carIndex, 'Arrived at yielding position, now staying on yielding lane')
        CarStateMachine_setStateExitReason(carIndex, StateExitReason.ArrivedAtYieldingLane)
        return CarStateMachine.CarStateType.STAYING_ON_YIELDING_LANE
      end
end

-- EXIT FUNCTION
---@param carIndex integer
---@param dt number
---@param sortedCarsList table<integer,ac.StateCar>
---@param sortedCarsListIndex integer
---@param storage StorageTable
CarStateMachine.states_exitFunctions[STATE] = function (carIndex, dt, sortedCarsList, sortedCarsListIndex, storage)
    CarOperations_resetPedalPosition(carIndex, CarOperations.CarPedals.Brake)
    CarOperations_resetAIThrottleLimit(carIndex)
    CarOperations_toggleTurningLights(carIndex, ac.TurningLights.None)
end
