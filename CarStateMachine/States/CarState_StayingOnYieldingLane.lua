local STATE = CarStateMachine.CarStateType.STAYING_ON_YIELDING_LANE

CarStateMachine.CarStateTypeStrings[STATE] = "StayingOnYieldingLane"
-- CarStateMachine.states_minimumTimeInState[STATE] = 2
CarStateMachine.states_minimumTimeInState[STATE] = 0

local OVERTAKING_CAR_FASTER_LEEWAY = 20 -- the leeway given to the yielding car to be considered "faster" than the car trying to overtake it.  This means that the yielding car needs to be at least this much faster than the car behind it to consider it faster

-- ENTRY FUNCTION
CarStateMachine.states_entryFunctions[STATE] = function (carIndex, dt, sortedCarsList, sortedCarsListIndex, storage)
  -- make sure the state before us has saved the carIndex of the car we're yielding to
  local currentlyYieldingToCarIndex = CarManager.cars_currentlyYieldingCarToIndex[carIndex]
  if not currentlyYieldingToCarIndex then
    Logger.error(string.format('Car %d in state StayingOnYieldingLane but has no reference to the car it is yielding to!  Previous state needs to set it.', carIndex))
  end
end

-- UPDATE FUNCTION
CarStateMachine.states_updateFunctions[STATE] = function (carIndex, dt, sortedCarsList, sortedCarsListIndex, storage)
      -- local carBehind = sortedCarsList[sortedCarsListIndex + 1]
      local currentlyYieldingToCarIndex = CarManager.cars_currentlyYieldingCarToIndex[carIndex]
      local carWeAreCurrentlyYieldingTo = ac.getCar(currentlyYieldingToCarIndex)
      if not carWeAreCurrentlyYieldingTo then
        return
      end

      CarManager.cars_reasonWhyCantYield[carIndex] = nil

      CarManager.cars_yieldTime[carIndex] = CarManager.cars_yieldTime[carIndex] + dt

      -- make the yielding car leave more space in between the car in front while driving on the yielding lane
      CarOperations.setAICaution(carIndex, 2)

      -- limit the yielding car throttle while driving on the yielding lane
      -- CarOperations.setAIThrottleLimit(carIndex, 0.5)
      local car = sortedCarsList[sortedCarsListIndex]
      local topSpeed = math.min(car.speedKmh, carWeAreCurrentlyYieldingTo.speedKmh*0.7)
      CarOperations.setAITopSpeed(carIndex, topSpeed) -- limit the yielding car top speed based on the overtaking car speed while driving on the yielding lane
      -- CarOperations.setPedalPosition(carIndex, CarOperations.CarPedals.Brake, 0.1)
      CarOperations.setPedalPosition(carIndex, CarOperations.CarPedals.Gas, 0.1)

      -- make sure we spend enough time in this state before opening the possibility to ease out
      -- if timeInStates[carIndex] < minimumTimesInState[CarStateMachine.CarStateType.STAYING_ON_YIELDING_LANE] then
        -- return
      -- end
end

-- TRANSITION FUNCTION
CarStateMachine.states_transitionFunctions[STATE] = function (carIndex, dt, sortedCarsList, sortedCarsListIndex, storage)
      local car = sortedCarsList[sortedCarsListIndex]
      local currentlyYieldingToCarIndex = CarManager.cars_currentlyYieldingCarToIndex[carIndex]
      local carWeAreYieldingTo = ac.getCar(currentlyYieldingToCarIndex)
      local carBehind = sortedCarsList[sortedCarsListIndex + 1]
      local carFront = sortedCarsList[sortedCarsListIndex - 1]

      -- if we don't have an overtaking car anymore, we can ease out our yielding
      if not carWeAreYieldingTo then
        CarManager.cars_reasonWhyCantYield[carIndex] = 'No overtaking car so not staying on yielding lane'
        CarStateMachine.setStateExitReason(carIndex, 'No overtaking car so not staying on yielding lane')
        return CarStateMachine.CarStateType.EASING_OUT_YIELD
      end

      -- If the yielding car is yielding and the overtaking car is now clearly ahead, we can ease out our yielding
      local isOvertakingCarClearlyAheadOfYieldingCar = CarOperations.isSecondCarClearlyAhead(car, carWeAreYieldingTo, storage.clearAhead_meters)
      if isOvertakingCarClearlyAheadOfYieldingCar then
        -- go to trying to start easing out yield state
        CarStateMachine.setStateExitReason(carIndex, 'Overtaking car is clearly ahead of us so easing out yield')
        return CarStateMachine.CarStateType.EASING_OUT_YIELD
      end

      -- if the overtaking car is far enough back, then we can begin easing out
      local isOvertakingCarClearlyBehindYieldingCar = CarOperations.isSecondCarClearlyBehindFirstCar(car, carWeAreYieldingTo, storage.detectCarBehind_meters)
      if isOvertakingCarClearlyBehindYieldingCar then
        -- go to trying to start easing out yield state
        CarStateMachine.setStateExitReason(carIndex, 'Overtaking car is clearly behind us so easing out yield')
        return CarStateMachine.CarStateType.EASING_OUT_YIELD
      end

      --  if we're currently faster than the car trying to overtake us, we can ease out our yielding
      local isYieldingCarFasterThanOvertakingCar = CarOperations.isFirstCarCurrentlyFasterThanSecondCar(car, carWeAreYieldingTo, OVERTAKING_CAR_FASTER_LEEWAY)
      if isYieldingCarFasterThanOvertakingCar then
        -- go to trying to start easing out yield state
        CarManager.cars_reasonWhyCantYield[carIndex] = 'We are now faster than the car behind, so easing out yield'
        CarStateMachine.setStateExitReason(carIndex, 'We are now faster than the car behind, so easing out yield')
        return CarStateMachine.CarStateType.EASING_OUT_YIELD
      end

      ----------------------------------------------------------------
      -- todo: working on this to prevent traffic jams where everyone is yielding to everyone else
      -- todo: but it's causing a state flickering issue probably because of the syncing of the overtaking and yielding cars states
      --todo: maybe also check the lateral offset of the yielding car to make sure it's still on the yielding lane?
      --todo: i thinkk it's also important to check the behind lateral offset when deciding if we should start yielding at all
      -- todo: update: this code is not good because it only works with other ai cars but NOT with the player car, so it needs to be rethinked
      -- if currentlyYieldingToCarIndex ~= 0 then
        -- local overtakingCarIndexOfYieldingCar = CarManager.cars_currentlyOvertakingCarIndex[currentlyYieldingToCarIndex]
        -- local isOvertakingCarAlsoOvertakingUs = overtakingCarIndexOfYieldingCar == carIndex
        -- if not isOvertakingCarAlsoOvertakingUs then
          -- -- the car we're yielding to is not overtaking us, so we can ease out our yielding
          -- CarManager.cars_reasonWhyCantYield[carIndex] = 'The car we are yielding to is not overtaking us, so easing out yield'
          -- CarStateMachine.setStateExitReason(carIndex, 'The car we are yielding to is not overtaking us, so easing out yield')
          -- return CarStateMachine.CarStateType.EASING_OUT_YIELD
        -- end
      -- end
      ----------------------------------------------------------------

      if carBehind then
        -- check if the current car behind us is the same car we're yielding to
        local carBehindIndex = carBehind.index
        local isBehindCarSameCarWeAreYieldingTo = carBehindIndex == currentlyYieldingToCarIndex
        
        -- if the car behind us is not the same car we're yielding to, check if we should start yielding to the new car behind us instead
        if not isBehindCarSameCarWeAreYieldingTo then
          local newStateDueToCarBehind = CarStateMachine.handleShouldWeYieldToBehindCar(carIndex, car, carBehind, carFront, storage)
          if newStateDueToCarBehind then
            -- Logger.log(string.format('[StayingOnYieldingLane] Car %d is yielding to car #%d but will now yield to new car behind #%d instead', carIndex, currentlyYieldingToCarIndex, carBehindIndex))
            CarStateMachine.setStateExitReason(carIndex, string.format("Yielding to new car behind #%d instead", carBehindIndex))
            return newStateDueToCarBehind
          end
        end
      end
end

-- EXIT FUNCTION
CarStateMachine.states_exitFunctions[STATE] = function (carIndex, dt, sortedCarList, sortedCarListIndex, storage)
  CarOperations.removeAICaution(carIndex)
  CarOperations.removeAITopSpeed(carIndex)
  -- CarOperations.resetPedalPosition(carIndex, CarOperations.CarPedals.Brake)
  CarOperations.resetPedalPosition(carIndex, CarOperations.CarPedals.Gas)
end