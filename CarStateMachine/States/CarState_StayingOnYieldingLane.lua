local STATE = CarStateMachine.CarStateType.STAYING_ON_YIELDING_LANE

CarStateMachine.CarStateTypeStrings[STATE] = "StayingOnYieldingLane"
CarStateMachine.states_minimumTimeInState[STATE] = 4

local OVERTAKING_CAR_FASTER_LEEWAY = 20 -- the leeway given to the yielding car to be considered "faster" than the car trying to overtake it.  This means that the yielding car needs to be at least this much faster than the car behind it to consider it faster

-- ENTRY FUNCTION
CarStateMachine.states_entryFunctions[STATE] = function (carIndex, dt, car, playerCar, storage)

end

-- UPDATE FUNCTION
CarStateMachine.states_updateFunctions[STATE] = function (carIndex, dt, car, playerCar, storage)
      CarManager.cars_reasonWhyCantYield[carIndex] = nil

      CarManager.cars_yieldTime[carIndex] = CarManager.cars_yieldTime[carIndex] + dt

      -- make the ai car leave more space in between the car in front while driving on the yielding lane
      CarOperations.setAICaution(carIndex, 2)

      -- limit the ai car throttle while driving on the yielding lane
      CarOperations.setAIThrottleLimit(carIndex, 0.5)
      CarOperations.setAITopSpeed(carIndex, playerCar.speedKmh*0.1) -- limit the ai car top speed to half the player car speed while driving on the yielding lane

      -- make sure we spend enough time in this state before opening the possibility to ease out
      -- if timeInStates[carIndex] < minimumTimesInState[CarStateMachine.CarStateType.STAYING_ON_YIELDING_LANE] then
        -- return
      -- end
end

-- TRANSITION FUNCTION
CarStateMachine.states_transitionFunctions[STATE] = function (carIndex, dt, car, playerCar, storage)
      -- If the ai car is yielding and the player car is now clearly ahead, we can ease out our yielding
      local isPlayerClearlyAheadOfAICar = CarOperations.playerIsClearlyAhead(car, playerCar, storage.clearAhead_meters)
      if isPlayerClearlyAheadOfAICar then
        -- go to trying to start easing out yield state
        return CarStateMachine.CarStateType.EASING_OUT_YIELD
      end

      -- if the player is far enough back, then we can begin easing out
      local isPlayerClearlyBehindAICar = CarOperations.playerIsClearlyBehind(car, playerCar, storage.detectCarBehind_meters)
      if isPlayerClearlyBehindAICar then
        -- go to trying to start easing out yield state
        return CarStateMachine.CarStateType.EASING_OUT_YIELD
      end

      --  if we're currently faster than the car trying to overtake us, we can ease out our yielding
      local areWeFasterThanCarTryingToOvertake = CarOperations.isFirstCarCurrentlyFasterThanSecondCar(car, playerCar, OVERTAKING_CAR_FASTER_LEEWAY)
      if areWeFasterThanCarTryingToOvertake then
        -- go to trying to start easing out yield state
        CarManager.cars_reasonWhyCantYield[carIndex] = 'We are now faster than the car behind, so easing out yield'
        return CarStateMachine.CarStateType.EASING_OUT_YIELD
      end
end

-- EXIT FUNCTION
CarStateMachine.states_exitFunctions[STATE] = function (carIndex, dt, car, playerCar, storage)

end