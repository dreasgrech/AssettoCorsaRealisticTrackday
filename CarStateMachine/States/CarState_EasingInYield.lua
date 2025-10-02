local STATE = CarStateMachine.CarStateType.EASING_IN_YIELD

CarStateMachine.CarStateTypeStrings[STATE] = "EasingInYield"
CarStateMachine.states_minimumTimeInState[STATE] = 0

local StateExitReason = Strings.StringNames[Strings.StringCategories.StateExitReason]

-- ENTRY FUNCTION
CarStateMachine.states_entryFunctions[STATE] = function (carIndex, dt, sortedCarList, sortedCarListIndex, storage)
  -- make sure the state before us has saved the carIndex of the car we're yielding to
  local currentlyYieldingToCarIndex = CarManager.cars_currentlyYieldingCarToIndex[carIndex]
  if not currentlyYieldingToCarIndex then
    Logger.error(string.format('Car %d in state EasingInYield but has no reference to the car it is yielding to!  Previous state needs to set it.', carIndex))
  end

  -- make sure that we're also not overtaking to another car at the same time
  local currentlyOvertakingCarIndex = CarManager.cars_currentlyOvertakingCarIndex[carIndex]
  if currentlyOvertakingCarIndex then
    local previousState = CarStateMachine.getPreviousState(carIndex)
    Logger.error(string.format('[CarState_EasingInYield] Car %d is both yielding to car %d and overtaking car %d at the same time!  Previous state: %s',
    carIndex, currentlyYieldingToCarIndex, currentlyOvertakingCarIndex, CarStateMachine.CarStateTypeStrings[previousState]))
  end

  local car = sortedCarList[sortedCarListIndex]

  -- set the current spline offset to our actual lateral offset so we start easing in from the correct position
  CarManager.cars_currentSplineOffset[carIndex] = CarManager.getActualTrackLateralOffset(car.position)

  -- turn on turning lights
  local turningLights = storage.yieldSide == RaceTrackManager.TrackSide.LEFT and ac.TurningLights.Left or ac.TurningLights.Right
  CarOperations.toggleTurningLights(carIndex, turningLights)
end

-- UPDATE FUNCTION
CarStateMachine.states_updateFunctions[STATE] = function (carIndex, dt, sortedCarList, sortedCarListIndex, storage)
      local car = sortedCarList[sortedCarListIndex]
      local yieldSide = RaceTrackManager.getYieldingSide()

      local targetOffset = storage.maxLateralOffset_normalized
      local rampSpeed_mps = storage.rampSpeed_mps
      local droveSafelyToSide = CarOperations.driveSafelyToSide(carIndex, dt, car, yieldSide, targetOffset, rampSpeed_mps, storage.overrideAiAwareness)
      if not droveSafelyToSide then
        -- reduce the car speed so that we can find a gap
        CarOperations.setAIThrottleLimit(carIndex, 0.4)

        -- set the brake pedal to something low to help slow down the car while waiting for a gap
        CarOperations.setPedalPosition(carIndex, CarOperations.CarPedals.Brake, 0.2)

        return
      end

      CarOperations.resetAIThrottleLimit(carIndex)
      CarOperations.resetPedalPosition(carIndex, CarOperations.CarPedals.Brake)

      -- CarManager.cars_reasonWhyCantYield[carIndex] = nil
      CarStateMachine.setReasonWhyCantYield(carIndex, Strings.StringNames[Strings.StringCategories.ReasonWhyCantYield].None)

      CarManager.cars_yieldTime[carIndex] = CarManager.cars_yieldTime[carIndex] + dt
end

-- TRANSITION FUNCTION
CarStateMachine.states_transitionFunctions[STATE] = function (carIndex, dt, sortedCarList, sortedCarListIndex, storage)
      local car = sortedCarList[sortedCarListIndex]
      -- local carBehind = sortedCarList[sortedCarListIndex + 1]

      -- check if we're now in a yellow flag zone
      local newStateDueToYellowFlagZone = CarStateMachine.handleYellowFlagZone(carIndex, car)
      if newStateDueToYellowFlagZone then
        CarStateMachine.setStateExitReason(carIndex, StateExitReason.EnteringYellowFlagZone)
        return newStateDueToYellowFlagZone
      end

      local currentlyYieldingToCarIndex = CarManager.cars_currentlyYieldingCarToIndex[carIndex]
      local carWeAreYieldingTo = ac.getCar(currentlyYieldingToCarIndex)

      -- if the car we're yielding to is now clearly ahead of us, we can ease out our yielding
      local isOvertakingCarClearlyAheadOfYieldingCar = CarOperations.isSecondCarClearlyAhead(car, carWeAreYieldingTo, storage.clearAhead_meters)
      if isOvertakingCarClearlyAheadOfYieldingCar then
        -- CarManager.cars_reasonWhyCantYield[carIndex] = 'Overtaking car clearly ahead, so easing out yield'

        -- go to trying to start easing out yield state
        -- CarStateMachine.setStateExitReason(carIndex, 'Overtaking car is clearly ahead of us so easing out yield')
        CarStateMachine.setStateExitReason(carIndex, StateExitReason.OvertakingCarIsClearlyAhead)
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
      local yieldSide = RaceTrackManager.getYieldingSide()
      local arrivedAtTargetOffset = CarOperations.hasArrivedAtTargetSplineOffset(carIndex, yieldSide)
      if arrivedAtTargetOffset then
        -- CarStateMachine.setStateExitReason(carIndex, 'Arrived at yielding position, now staying on yielding lane')
        CarStateMachine.setStateExitReason(carIndex, StateExitReason.ArrivedAtYieldingLane)
        return CarStateMachine.CarStateType.STAYING_ON_YIELDING_LANE
      end
end

-- EXIT FUNCTION
CarStateMachine.states_exitFunctions[STATE] = function (carIndex, dt, sortedCarList, sortedCarListIndex, storage)
    CarOperations.resetPedalPosition(carIndex, CarOperations.CarPedals.Brake)
    CarOperations.resetAIThrottleLimit(carIndex)
end
