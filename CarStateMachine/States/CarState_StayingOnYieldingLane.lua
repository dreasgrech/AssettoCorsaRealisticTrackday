--[====[
---@ext:verbose
local constTable = const({
  value=42
})
local v = constTable.value
ac.log(string.format("Const value is %d", v))
--]====]

local STATE = CarStateMachine.CarStateType.STAYING_ON_YIELDING_LANE

CarStateMachine.CarStateTypeStrings[STATE] = "StayingOnYieldingLane"
-- CarStateMachine.states_minimumTimeInState[STATE] = 2
CarStateMachine.states_minimumTimeInState[STATE] = 0

local OVERTAKING_CAR_FASTER_LEEWAY = 20 -- the leeway given to the yielding car to be considered "faster" than the car trying to overtake it.  This means that the yielding car needs to be at least this much faster than the car behind it to consider it faster
local AICAUTION_WHILE_YIELDING = 4 -- the AI caution level while yielding

local StateExitReason = Strings.StringNames[Strings.StringCategories.StateExitReason]

-- ENTRY FUNCTION
CarStateMachine.states_entryFunctions[STATE] = function (carIndex, dt, sortedCarsList, sortedCarsListIndex, storage)
  -- make sure the state before us has saved the carIndex of the car we're yielding to
  local currentlyYieldingToCarIndex = CarManager.cars_currentlyYieldingCarToIndex[carIndex]
  if not currentlyYieldingToCarIndex then
    Logger.error(string.format('Car %d in state StayingOnYieldingLane but has no reference to the car it is yielding to!  Previous state needs to set it.', carIndex))
  end

  -- CarManager.cars_reasonWhyCantYield[carIndex] = nil
  CarStateMachine.setReasonWhyCantYield(carIndex, Strings.StringNames[Strings.StringCategories.ReasonWhyCantYield].None)
end

-- UPDATE FUNCTION
CarStateMachine.states_updateFunctions[STATE] = function (carIndex, dt, sortedCarsList, sortedCarsListIndex, storage)
      -- local carBehind = sortedCarsList[sortedCarsListIndex + 1]
      local currentlyYieldingToCarIndex = CarManager.cars_currentlyYieldingCarToIndex[carIndex]
      local carWeAreCurrentlyYieldingTo = ac.getCar(currentlyYieldingToCarIndex)

      -- if the car we're yielding to doesn't exist anymore, don't do anything and then we'll transition out of this state in the transition function
      if not carWeAreCurrentlyYieldingTo then
        return
      end

      -- CarManager.cars_reasonWhyCantYield[carIndex] = nil

      CarManager.cars_yieldTime[carIndex] = CarManager.cars_yieldTime[carIndex] + dt

      -- make the yielding car leave more space in between the car in front while driving on the yielding lane
      CarOperations.setAICaution(carIndex, AICAUTION_WHILE_YIELDING)

      -- limit the yielding car throttle while driving on the yielding lane
      CarOperations.setAIThrottleLimit(carIndex, 0.5)

      local car = sortedCarsList[sortedCarsListIndex]
      local topSpeed = math.min(car.speedKmh, carWeAreCurrentlyYieldingTo.speedKmh*0.7)
      CarOperations.setAITopSpeed(carIndex, topSpeed) -- limit the yielding car top speed based on the overtaking car speed while driving on the yielding lane
      
      -- press some brake to help slow down the car a bit because the top speed limit is broken in csp atm in trackday ai flood mode
      -- Andreas: be careful about this because if the ai keeps on pressing the gas while we're pressing the brake here, the car can spin out...
      -- CarOperations.setPedalPosition(carIndex, CarOperations.CarPedals.Brake, 0.1) 
      -- CarOperations.setPedalPosition(carIndex, CarOperations.CarPedals.Gas, 0.8)

      -- TODO: Here continue driving to the side but using the real offset
      -- TODO: Here continue driving to the side but using the real offset
      -- TODO: Here continue driving to the side but using the real offset
      -- TODO: Here continue driving to the side but using the real offset
end

-- TRANSITION FUNCTION
CarStateMachine.states_transitionFunctions[STATE] = function (carIndex, dt, sortedCarsList, sortedCarsListIndex, storage)
      local car = sortedCarsList[sortedCarsListIndex]

      -- check if we're now in a yellow flag zone
      local newStateDueToYellowFlagZone = CarStateMachine.handleYellowFlagZone(carIndex, car)
      if newStateDueToYellowFlagZone then
        CarStateMachine.setStateExitReason(carIndex, StateExitReason.EnteringYellowFlagZone)
        return newStateDueToYellowFlagZone
      end

      local currentlyYieldingToCarIndex = CarManager.cars_currentlyYieldingCarToIndex[carIndex]
      local carWeAreYieldingTo = ac.getCar(currentlyYieldingToCarIndex)
      local carBehind = sortedCarsList[sortedCarsListIndex + 1]
      local carFront = sortedCarsList[sortedCarsListIndex - 1]

      if carBehind then
        -- check if the current car behind us is the same car we're yielding to
        local carBehindIndex = carBehind.index
        local isBehindCarSameCarWeAreYieldingTo = carBehindIndex == currentlyYieldingToCarIndex
        
        -- if the car behind us is not the same car we're yielding to, check if we should start yielding to the new car behind us instead
        if not isBehindCarSameCarWeAreYieldingTo then
          local newStateDueToCarBehind = CarStateMachine.handleShouldWeYieldToBehindCar(carIndex, car, carBehind, carFront, storage)
          if newStateDueToCarBehind then
            -- Logger.log(string.format('[StayingOnYieldingLane] Car %d is yielding to car #%d but will now yield to new car behind #%d instead', carIndex, currentlyYieldingToCarIndex, carBehindIndex))
            -- CarStateMachine.setStateExitReason(carIndex, string.format("Yielding to new car behind #%d instead", carBehindIndex))
            CarStateMachine.setStateExitReason(carIndex, StateExitReason.YieldingToCar)
            CarManager.cars_currentlyYieldingCarToIndex[carIndex] = carBehindIndex -- continue yielding to the new car behind us
            -- return newStateDueToCarBehind
            return CarStateMachine.CarStateType.STAYING_ON_YIELDING_LANE
          end
        end
      end

      --todo: make sure that if there's a car behind us that's very close, we don't ease out yield
      --todo: make sure that if there's a car behind us that's very close, we don't ease out yield
      --todo: make sure that if there's a car behind us that's very close, we don't ease out yield
      --todo: make sure that if there's a car behind us that's very close, we don't ease out yield

      -- if we don't have an overtaking car anymore, we can ease out our yielding
      if not carWeAreYieldingTo then
        -- CarStateMachine.setStateExitReason(carIndex, 'No overtaking car so not staying on yielding lane')
        CarStateMachine.setStateExitReason(carIndex, StateExitReason.OvertakingCarNoLongerExists)
        return CarStateMachine.CarStateType.EASING_OUT_YIELD
      end

      -- If the yielding car is yielding and the overtaking car is now clearly ahead, we can ease out our yielding
      local isOvertakingCarClearlyAheadOfYieldingCar = CarOperations.isSecondCarClearlyAhead(car, carWeAreYieldingTo, storage.clearAhead_meters)
      if isOvertakingCarClearlyAheadOfYieldingCar then
        -- CarStateMachine.setStateExitReason(carIndex, 'Overtaking car is clearly ahead of us so easing out yield')
        CarStateMachine.setStateExitReason(carIndex, StateExitReason.OvertakingCarIsClearlyAhead)
        return CarStateMachine.CarStateType.EASING_OUT_YIELD
      end

      -- if the overtaking car is far enough back, then we can begin easing out
      local isOvertakingCarClearlyBehindYieldingCar = CarOperations.isSecondCarClearlyBehindFirstCar(car, carWeAreYieldingTo, storage.detectCarBehind_meters)
      if isOvertakingCarClearlyBehindYieldingCar then
        -- CarStateMachine.setStateExitReason(carIndex, 'Overtaking car is clearly behind us so easing out yield')
        CarStateMachine.setStateExitReason(carIndex, StateExitReason.OvertakingCarIsClearlyBehind)
        return CarStateMachine.CarStateType.EASING_OUT_YIELD
      end

      --  if we're currently faster than the car trying to overtake us, we can ease out our yielding
      -- local isYieldingCarFasterThanOvertakingCar = CarOperations.isFirstCarCurrentlyFasterThanSecondCar(car, carWeAreYieldingTo, OVERTAKING_CAR_FASTER_LEEWAY)
      local isYieldingCarFasterThanOvertakingCar = CarOperations.isFirstCarFasterThanSecondCar(carIndex, currentlyYieldingToCarIndex, OVERTAKING_CAR_FASTER_LEEWAY)
      if isYieldingCarFasterThanOvertakingCar then
        -- CarStateMachine.setStateExitReason(carIndex, 'We are now faster than the car behind, so easing out yield')
        CarStateMachine.setStateExitReason(carIndex, StateExitReason.YieldingCarIsFasterThenOvertakingCar)
        return CarStateMachine.CarStateType.EASING_OUT_YIELD
      end

      -- if the car we're yielding to is no longer on the overtaking lane, we can ease out our yielding
      local carWeAreYieldingToDrivingOnOvertakingLane = CarManager.isCarDrivingOnSide(currentlyYieldingToCarIndex, RaceTrackManager.getOvertakingSide())
      if not carWeAreYieldingToDrivingOnOvertakingLane then
        -- CarStateMachine.setStateExitReason(carIndex, 'Overtaking car no longer on overtaking lane, so easing out yield')
        CarStateMachine.setStateExitReason(carIndex, StateExitReason.OvertakingCarNotOnOvertakingSide)
        return CarStateMachine.CarStateType.EASING_OUT_YIELD
      end
end

-- EXIT FUNCTION
CarStateMachine.states_exitFunctions[STATE] = function (carIndex, dt, sortedCarList, sortedCarListIndex, storage)
  CarOperations.removeAICaution(carIndex)
  CarOperations.removeAITopSpeed(carIndex)
  CarOperations.resetPedalPosition(carIndex, CarOperations.CarPedals.Brake)
  CarOperations.resetPedalPosition(carIndex, CarOperations.CarPedals.Gas)
  CarOperations.resetAIThrottleLimit(carIndex)
end