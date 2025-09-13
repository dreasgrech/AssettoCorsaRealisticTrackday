local STATE = CarStateMachine.CarStateType.DRIVING_NORMALLY

CarStateMachine.CarStateTypeStrings[STATE] = "DrivingNormally"
CarStateMachine.states_minimumTimeInState[STATE] = 2

-- ENTRY FUNCTION
CarStateMachine.states_entryFunctions[STATE] = function (carIndex, dt, car, carBehind, storage)
      CarManager.cars_yieldTime[carIndex] = 0
      CarManager.cars_currentSplineOffset[carIndex] = 0
      CarManager.cars_targetSplineOffset[carIndex] = 0

      -- turn off turning lights
      CarOperations.toggleTurningLights(carIndex, car, ac.TurningLights.None)
      
    -- start driving normally
    -- CarStateMachine.changeState(carIndex, CarStateMachine.CarStateType.DRIVING_NORMALLY)

      -- reset the yielding car caution back to normal
      CarOperations.setAICaution(carIndex, 1)

      -- remove the yielding car throttle limit since we will now be driving normally
      CarOperations.setAIThrottleLimit(carIndex, 1)

      -- remove any reference to a car we may have been overtaking
      CarManager.cars_currentlyOvertakingCarIndex[carIndex] = nil
end

-- UPDATE FUNCTION
CarStateMachine.states_updateFunctions[STATE] = function (carIndex, dt, car, carBehind, storage)
end

local handleCarFront = function(carIndex, car, carFront, storage)
  -- If we're not faster than the car in front, do nothing
  local areWeFasterThenTheCarInFront = CarOperations.isFirstCarCurrentlyFasterThanSecondCar(car, carFront, 5)
  if not areWeFasterThenTheCarInFront then
    CarManager.cars_reasonWhyCantOvertake[carIndex] = 'Car in front is faster so not overtaking'
    return
  end

  -- check if the car in front of us is yielding
  local carFrontIndex = carFront.index
  local isCarInFrontYielding = CarManager.cars_currentlyYielding[carFrontIndex]
  if not isCarInFrontYielding then
    CarManager.cars_reasonWhyCantOvertake[carIndex] = 'Car in front not yielding so not overtaking'
    return
  end

  -- start driving to the side to initiate an overtake
  -- save a reference to the car we're overtaking because the next state needs it
  CarManager.cars_currentlyOvertakingCarIndex[carIndex] = carFrontIndex
  return CarStateMachine.CarStateType.EASING_IN_OVERTAKE
end

local handleCarBehind = function(carIndex, car, carBehind, storage)
    -- If this car is not close to the overtaking car, do nothing
    local distanceFromOvertakingCarToYieldingCar = MathHelpers.vlen(MathHelpers.vsub(carBehind.position, car.position))
    local radius = storage.detectCarBehind_meters
    local isYieldingCarCloseToOvertakingCar = distanceFromOvertakingCarToYieldingCar <= radius
    if not isYieldingCarCloseToOvertakingCar then
      CarManager.cars_reasonWhyCantYield[carIndex] = 'Too far (outside detect radius) so not yielding'
      return
    end

    -- Check if the overtaking car is behind the yielding car
    local isOvertakingCarBehindYieldingCar = CarOperations.isFirstCarBehindSecondCar(carBehind, car)
    if not isOvertakingCarBehindYieldingCar then
      CarManager.cars_reasonWhyCantYield[carIndex] = 'Overtaking car not behind (clear) so not yielding'
      return
    end

    -- Check if the overtaking car is above the minimum speed
    local isOvertakingCarAboveMinSpeed = carBehind.speedKmh >= storage.minPlayerSpeed_kmh
    if not isOvertakingCarAboveMinSpeed then
      CarManager.cars_reasonWhyCantYield[carIndex] = 'Overtaking car below minimum speed so not yielding'
      return
    end

    local yieldingCarSpeedKmh = car.speedKmh
    local overtakingCarSpeedKmh = carBehind.speedKmh

    -- Check if we're faster than the overtaking car
    local isYieldingCarSlowerThanOvertakingCar = yieldingCarSpeedKmh < overtakingCarSpeedKmh
    if not isYieldingCarSlowerThanOvertakingCar then
      CarManager.cars_reasonWhyCantYield[carIndex] = 'We are faster than the car behind so not yielding'
      return
    end

    -- local playerCarHasClosingSpeedToAiCar = (overtakingCarSpeedKmh - carSpeedKmh) >= storage.minSpeedDelta_kmh
    -- if not playerCarHasClosingSpeedToAiCar then
      -- CarManager.cars_reasonWhyCantYield[carIndex] = 'Player does not have closing speed so not yielding'
    -- end

    -- Check if the yielding car is above the minimum speed
    local isYieldingCarAboveMinSpeed = car.speedKmh >= storage.minAISpeed_kmh
    if not isYieldingCarAboveMinSpeed then
      CarManager.cars_reasonWhyCantYield[carIndex] = 'Yielding car speed too low (corner/traffic) so not yielding'
      return
    end

    -- CarManager.cars_reasonWhyCantYield[carIndex] = nil

    -- Since all the checks have passed, the yielding car can now start to yield
    return CarStateMachine.CarStateType.EASING_IN_YIELD
end


-- TRANSITION FUNCTION
-- CarStateMachine.states_transitionFunctions[STATE] = function (carIndex, dt, car, carBehind, storage)
CarStateMachine.states_transitionFunctions[STATE] = function (carIndex, dt, sortedCarList, sortedCarListIndex, storage)
      -- render.debugSphere(ac.getCar(carIndex).position, 1, rgbm(0.2, 0.2, 1.0, 1))

      -- DEBUG DEBUG DEBUG
      -- local anyHit, rays = CarOperations.simpleSideRaycasts(carIndex, 10.0)
      -- if anyHit then
          -- -- Logger.log(string.format("Car %d: Side raycast hit something, not yielding", carIndex))
          -- -- CarManager.cars_reasonWhyCantYield[carIndex] = 'Target side blocked by another car so not yielding (raycast)'
      -- end
      -- DEBUG DEBUG DEBUG

      local car = sortedCarList[sortedCarListIndex]

      -- if not carBehind then
        -- CarManager.cars_reasonWhyCantYield[carIndex] = 'No overtaking car so not yielding'
        -- return
      -- end

      -- If there's a car behind us, check if we should start yielding to it
      local carBehind = sortedCarList[sortedCarListIndex + 1]
      if carBehind then
        local newStateDueToCarBehind = handleCarBehind(carIndex, car, carBehind, storage)
        if newStateDueToCarBehind then
          return newStateDueToCarBehind
        end
      end

      -- if there's a car in front of us, check if we can overtake it
      local carFront = sortedCarList[sortedCarListIndex - 1]
      if carFront then
        local newStateDueToCarFront = handleCarFront(carIndex, car, carFront, storage)
        if newStateDueToCarFront then
          return newStateDueToCarFront
        end
      end
end

-- EXIT FUNCTION
CarStateMachine.states_exitFunctions[STATE] = function (carIndex, dt, sortedCarList, sortedCarListIndex, storage)
      CarManager.cars_reasonWhyCantYield[carIndex] = nil
end