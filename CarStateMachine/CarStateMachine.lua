--[====[
---@ext:verbose
--]====]
local CarStateMachine = {}

-- local LOG_CAR_STATEMACHINE_IN_CSP_LOG = true
local LOG_CAR_STATEMACHINE_IN_CSP_LOG = false

-- [Flags]
CarStateMachine.CarStateTypeStrings = {}
CarStateMachine.states_minimumTimeInState = { }

local cars_state = {}

CarStateMachine.cars_previousState = {}

---@enum CarStateMachine.CarStateType
CarStateMachine.CarStateType = {
  DRIVING_NORMALLY = 1, -- normal driving state, driving on the racing line
  EASING_IN_YIELD = 4, 
  STAYING_ON_YIELDING_LANE = 8,
  EASING_OUT_YIELD = 32,
  WAITING_AFTER_ACCIDENT = 64,
  COLLIDED_WITH_TRACK = 128,
  COLLIDED_WITH_CAR = 256,
  ANOTHER_CAR_COLLIDED_INTO_ME = 512,
  EASING_IN_OVERTAKE = 1024,
  STAYING_ON_OVERTAKING_LANE = 2048,
  EASING_OUT_OVERTAKE = 4096,
  NAVIGATING_AROUND_ACCIDENT = 8192,
  DRIVING_IN_YELLOW_FLAG_ZONE = 16384,
  AFTER_CUSTOMAIFLOOD_TELEPORT = 32768,
}

--[====[
CarStateMachine.CarStateType = const({
  DRIVING_NORMALLY = 1,
  EASING_IN_YIELD = 4, 
  STAYING_ON_YIELDING_LANE = 8,
  EASING_OUT_YIELD = 32,
  WAITING_AFTER_ACCIDENT = 64,
  COLLIDED_WITH_TRACK = 128,
  COLLIDED_WITH_CAR = 256,
  ANOTHER_CAR_COLLIDED_INTO_ME = 512,
  EASING_IN_OVERTAKE = 1024,
  STAYING_ON_OVERTAKING_LANE = 2048,
  EASING_OUT_OVERTAKE = 4096,
  NAVIGATING_AROUND_ACCIDENT = 8192,
  DRIVING_IN_YELLOW_FLAG_ZONE = 16384,
})

local debug_state = CarStateMachine.CarStateType.DRIVING_NORMALLY
ac.log(string.format("CarStateMachine debug_state = %d", debug_state))
--]====]

local changeState = function(carIndex, newState)
    -- save a reference to the current state before changing it
    local currentState = CarStateMachine.getCurrentState(carIndex)
    local isFirstState = currentState == nil -- is this the first state we're setting for this car?
    -- if not isFirstState and currentState == newState then
        -- Logger.warn(string.format("Car %d: Tried to change to the same state: %s", carIndex, CarStateMachine.CarStateTypeStrings[newState]))
        -- return
    -- end

    if isFirstState then
      currentState = newState
    end

    CarStateMachine.cars_previousState[carIndex] = currentState

    -- reset the time in state counter
    CarManager.cars_timeInCurrentState[carIndex] = 0

    -- Logger.log(string.format("Car %d: Changing state (%d) from %s to %s", carIndex, currentState))

    -- change to the new state
    cars_state[carIndex] = newState
end

CarStateMachine.getCurrentState = function(carIndex)
    return cars_state[carIndex]
end

CarStateMachine.getPreviousState = function(carIndex)
    return CarStateMachine.cars_previousState[carIndex]
end

local ReasonWhyCantYieldStringNames = Strings.StringNames[Strings.StringCategories.ReasonWhyCantYield]
local ReasonWhyCantOvertakeStringNames = Strings.StringNames[Strings.StringCategories.ReasonWhyCantOvertake]

--- TODO: This function should probably be moved to CarOperations
---@param carIndex number
---@param drivingToSide RaceTrackManager.TrackSide|integer
---@return boolean
-- local isSafeToDriveToTheSide = function(carIndex, drivingToSide)
CarStateMachine.isSafeToDriveToTheSide = function(carIndex, drivingToSide)
    local storage = StorageManager.getStorage()
    -- check if there's a car on our side
    if storage.handleSideChecking then
      local isCarOnSide, carOnSideDirection, carOnSideDistance = CarOperations.checkIfCarIsBlockedByAnotherCarAndSaveSideBlockRays(carIndex, drivingToSide)
      if isCarOnSide then
          -- if the car on our side is on the same side as the side we're trying to yield to, then we cannot yield
          local trackSideOfBlockingCar = CarOperations.getTrackSideFromCarDirection(carOnSideDirection)
          local isSideCarOnTheSameSideAsYielding = drivingToSide == trackSideOfBlockingCar
          
          if isSideCarOnTheSameSideAsYielding then
            -- Logger.log(string.format("Car %d: Car on side detected: %s  distance=%.2f m", carIndex, CarOperations.CarDirectionsStrings[carOnSideDirection], carOnSideDistance or -1))
            -- TODO: get this setReasonWhyCantYield out of here!
            CarStateMachine.setReasonWhyCantYield(carIndex, ReasonWhyCantYieldStringNames.TargetSideBlocked)
            return false
          end
      end
    end

    --[====[
    -- Check car blind spot
    -- Andreas: I've never seen this code working yet...
    local distanceToNearestCarInBlindSpot_L, distanceToNearestCarInBlindSpot_R = ac.getCarBlindSpot(carIndex)
    local isSideBlocked_L = (not (distanceToNearestCarInBlindSpot_L == nil))-- and distanceToNearestCarInBlindSpot_L > 0
    local isSideBlocked_R = (not (distanceToNearestCarInBlindSpot_R == nil))-- and distanceToNearestCarInBlindSpot_R > 0

    if (isSideBlocked_L or isSideBlocked_R) then
        Logger.log(string.format("Car %d: Blindspot L=%.2f  R=%.2f", carIndex, distanceToNearestCarInBlindSpot_L or -1, distanceToNearestCarInBlindSpot_R or -1))
        -- TODO: get this setReasonWhyCantYield out of here!
        CarStateMachine.setReasonWhyCantYield(carIndex, ReasonWhyCantYieldStringNames.CarInBlindSpot)
        return false
    end
    --]====]

    return true
end

CarStateMachine.states_entryFunctions = {}
CarStateMachine.states_updateFunctions = {}
CarStateMachine.states_transitionFunctions = {}
CarStateMachine.states_exitFunctions = {}

local queuedCollidedWithTrackAccidents = QueueManager.createQueue()
local queuedCollidedWithCarAccidents = QueueManager.createQueue()
local queuedCarCollidedWithMeAccidents = QueueManager.createQueue()

-- Logger.log("[CarStateMachine] Initialized 3 queues: "..queuedCollidedWithTrackAccidents..", "..queuedCollidedWithCarAccidents..", "..queuedCarCollidedWithMeAccidents)

-- a dictionary which holds, if available, the state to transition to next in the upcoming frame
local queuedStatesToTransitionInto = {}

CarStateMachine.setReasonWhyCantYield = function(carIndex, reason)
  StringsManager.setString(carIndex, Strings.StringCategories.ReasonWhyCantYield, reason)
end

CarStateMachine.setReasonWhyCantOvertake = function(carIndex, reason)
  StringsManager.setString(carIndex, Strings.StringCategories.ReasonWhyCantOvertake, reason)
end

CarStateMachine.setStateExitReason = function(carIndex, reason)
  StringsManager.setString(carIndex, Strings.StringCategories.StateExitReason, reason)
end

CarStateMachine.initializeCarInStateMachine = function(carIndex)
    -- Logger.log(string.format("CarStateMachine: initializeCarInStateMachine() car %d in state machine, setting initial state to DRIVING_NORMALLY", carIndex))

    -- clear the car's states history since this is could be a recycled car
    CarStateMachine.cars_previousState[carIndex] = nil
    cars_state[carIndex] = nil

    -- queue up the DRIVING_NORMALLY state for the car so that it will take effect in the next frame
    CarStateMachine.queueStateTransition(carIndex, CarStateMachine.CarStateType.DRIVING_NORMALLY)
    -- Logger.log(string.format("CarStateMachine: Car %d Just added normally state: %d", carIndex, queuedStatesToTransitionInto[carIndex]))
    --CarStateMachine.changeState(carIndex, CarStateMachine.CarStateType.DRIVING_NORMALLY)
end

CarStateMachine.queueStateTransition = function(carIndex, newState)
    queuedStatesToTransitionInto[carIndex] = newState
end

CarStateMachine.handleQueuedAccidents = function()
    -- while QueueManager.queueLength(queuedCollidedWithTrackAccidents) > 0 do
        -- local carIndex = QueueManager.dequeue(queuedCollidedWithTrackAccidents)
        
        -- Logger.log(string.format("CarStateMachine: Car %d collided with track, switching to COLLIDED_WITH_TRACK state", carIndex))
        -- CarStateMachine.changeState(carIndex, CarStateMachine.CarStateType.COLLIDED_WITH_TRACK)
    -- end

    while QueueManager.queueLength(queuedCollidedWithCarAccidents) > 0 do
        local accidentCarIndex = QueueManager.dequeue(queuedCollidedWithCarAccidents)
        
        Logger.log(string.format("CarStateMachine: #%d collided with another car, switching to COLLIDED_WITH_CAR state", accidentCarIndex))
        CarStateMachine.queueStateTransition(accidentCarIndex, CarStateMachine.CarStateType.COLLIDED_WITH_CAR)
    end

    while QueueManager.queueLength(queuedCarCollidedWithMeAccidents) > 0 do
        local accidentCarIndex = QueueManager.dequeue(queuedCarCollidedWithMeAccidents)

        Logger.log(string.format("CarStateMachine: #%d was collided into by another car, switching to ANOTHER_CAR_COLLIDED_INTO_ME state", accidentCarIndex))
        -- Logger.log(string.format("%d %d ", carIndex, QueueManager.queueLength(queuedCarCollidedWithMeAccidents)))
        -- Logger.log(string.format("%d", carIndex))
        CarStateMachine.queueStateTransition(accidentCarIndex, CarStateMachine.CarStateType.ANOTHER_CAR_COLLIDED_INTO_ME)
    end
end

CarStateMachine.updateCar = function(carIndex, dt, sortedCarList, sortedCarListIndex, storage)
    -- CarManager.cars_anchorPoints[carIndex] = nil -- clear the anchor points each frame, they will be recalculated if needed
    CarManager.cars_totalSideBlockRaysData[carIndex] = 0
    table.clear(CarManager.cars_sideBlockRaysData[carIndex])

    -- check if there's a new state we need to transition into
    local newStateToTransitionIntoThisFrame = queuedStatesToTransitionInto[carIndex]
    -- local shouldTransitionIntoNewState = not (newStateToTransitionIntoThisFrame == nil)
    local shouldTransitionIntoNewState = newStateToTransitionIntoThisFrame --and newStateToTransitionIntoThisFrame > 0
    -- Logger.log(string.format("CarStateMachine: Car %d Checking queued: %d, shouldTransition: %s", carIndex, queuedStatesToTransitionInto[carIndex], tostring(shouldTransitionIntoNewState)))
    
    -- If there's a state we need to transition into, do it now
    if shouldTransitionIntoNewState then
      -- Logger.log(string.format("CarStateMachine: Transitioning car %d into new state: %s", carIndex, CarStateMachine.CarStateTypeStrings[newStateToTransitionIntoThisFrame]))
      -- clear the queued transition since we're now taking care of it
      queuedStatesToTransitionInto[carIndex] = nil

      -- If this is not our first state, check if we've been in the previous state for at least some time, otherwise warn because there might be an issue
      local currentStateBeforeChange = CarStateMachine.getCurrentState(carIndex)
      if currentStateBeforeChange then
        local timeInStateBeforeChange = CarManager.cars_timeInCurrentState[carIndex]
        local previousState = CarStateMachine.getPreviousState(carIndex)
        if timeInStateBeforeChange < 0.1 then
          -- local cars_statesExitReason = CarManager.cars_statesExitReason[carIndex][currentStateBeforeChange] or ""
          local cars_statesExitReason = StringsManager.resolveStringValue(Strings.StringCategories.StateExitReason, CarManager.cars_statesExitReason_NAME[carIndex][previousState]) or ''
          Logger.warn(string.format(
          "CarStateMachine: Car %d changing state too quickly: %.3fs in state %s (previous: %s) before changing to %s (%s)",
          carIndex,
          timeInStateBeforeChange,
          CarStateMachine.CarStateTypeStrings[CarStateMachine.getCurrentState(carIndex)],
          CarStateMachine.CarStateTypeStrings[previousState],
          CarStateMachine.CarStateTypeStrings[newStateToTransitionIntoThisFrame],
          cars_statesExitReason))
        end
      end

      -- change to the new state
      changeState(carIndex, newStateToTransitionIntoThisFrame)

      -- execute the state's entry function
      --[====[
      if not CarStateMachine.states_entryFunctions[newStateToTransitionIntoThisFrame] then
        Logger.error(string.format("CarStateMachine: #%d state %d has no entry function!", carIndex, newStateToTransitionIntoThisFrame))
        return
      end
      --]====]
      CarStateMachine.states_entryFunctions[newStateToTransitionIntoThisFrame](carIndex, dt, sortedCarList, sortedCarListIndex, storage)
    end

    local state = CarStateMachine.getCurrentState(carIndex)

    if state == nil then
      Logger.error(string.format("CarStateMachine: #%d stat is nil!", carIndex))
      return
    end

    -- run the state loop
    -- Logger.log(string.format("CarStateMachine: Car %d updateFunction of state %s: ", carIndex, CarStateMachine.CarStateTypeStrings[state]) .. tostring(CarStateMachine.states_updateFunctions[carIndex]))


    --[====[
    if not CarStateMachine.states_updateFunctions[state] then
      Logger.error(string.format("CarStateMachine: #%d state %d has no update function!", carIndex, state))
      return
    end
    --]====]
    CarStateMachine.states_updateFunctions[state](carIndex, dt, sortedCarList, sortedCarListIndex, storage)

    local currentTimeInState = CarManager.cars_timeInCurrentState[carIndex]

    -- increase the time spent in this state
    CarManager.cars_timeInCurrentState[carIndex] = currentTimeInState + dt

    -- make sure we have spent the minimum required time in this state before we can transition out of it
    local minimumTimeInState = CarStateMachine.states_minimumTimeInState[state]
    if currentTimeInState < minimumTimeInState then
      -- we haven't spent enough time in this state yet, so we cannot transition out of it
      return
    end

    -- check if we need to transition out of the state by executing the state's transition check function
    local newState = CarStateMachine.states_transitionFunctions[state](carIndex, dt, sortedCarList, sortedCarListIndex, storage)
    local shouldTransitionToNextState = newState
    if shouldTransitionToNextState then
      -- execute the state's exit function
      CarStateMachine.states_exitFunctions[state](carIndex, dt, sortedCarList, sortedCarListIndex, storage)

      CarStateMachine.queueStateTransition(carIndex, newState)
    end
end

CarStateMachine.informAboutAccident = function(accidentIndex)
  -- Logger.log(string.format("CarStateMachine: informAboutAccident accidentIndex=%d", accidentIndex))
    local collidedWithTrack = AccidentManager.accidents_collidedWithTrack[accidentIndex]
    local carIndex = AccidentManager.accidents_carIndex[accidentIndex]
    local collidedWithCarIndex = AccidentManager.accidents_collidedWithCarIndex[accidentIndex]

    if collidedWithTrack then
        QueueManager.enqueue(queuedCollidedWithTrackAccidents, carIndex)
    else
        -- if the car collided with another car, we need to inform both cars
        -- Logger.log(string.format("Enqueueing accident: car %d collided with car %d", carIndex, collidedWithCarIndex))
        QueueManager.enqueue(queuedCollidedWithCarAccidents, carIndex)
        QueueManager.enqueue(queuedCarCollidedWithMeAccidents, collidedWithCarIndex)
    end
end

-- CarStateMachine.handleShouldWeStartNavigatingAroundAccident = function(carIndex, car)
CarStateMachine.handleYellowFlagZone = function(carIndex, car)
  -- return false
    local storage = StorageManager.getStorage()
    local handleAccidents = storage.handleAccidents
    if not handleAccidents then
      return nil
    end

    local carSplinePosition = car.splinePosition
    local isInYellowFlagZone = RaceTrackManager.isSplinePositionInYellowZone(carSplinePosition)
    if isInYellowFlagZone then
      return CarStateMachine.CarStateType.DRIVING_IN_YELLOW_FLAG_ZONE
    end

    --[====[
    -- todo: currently have a hardcoded value here!!!
    local isCarComingUpToAccidentIndex, accidentClosestCarIndex = AccidentManager.isCarComingUpToAccident(car, 100)
    if isCarComingUpToAccidentIndex then
      -- Logger.log(string.format("CarStateMachine: Car %d coming up to accident, switching to NAVIGATING_AROUND_ACCIDENT state", carIndex))
      AccidentManager.setCarNavigatingAroundAccident(carIndex, isCarComingUpToAccidentIndex, accidentClosestCarIndex)
      return CarStateMachine.CarStateType.NAVIGATING_AROUND_ACCIDENT
    end
    --]====]
end

---Returns the EASING_IN_OVERTAKE state if the car passes all the checks required to start overtaking a car behind it
---@param carIndex integer
---@param car ac.StateCar
---@param carBehind ac.StateCar
---@param carFront ac.StateCar
---@param storage StorageTable
---@return CarStateMachine.CarStateType|nil
CarStateMachine.handleCanWeOvertakeFrontCar = function(carIndex, car, carFront, carBehind, storage)
  local handleOvertaking = storage.handleOvertaking
  if not handleOvertaking then
    return
  end

  -- if there's no car in front of us, do nothing
  if not carFront then
    return
  end

  local carFrontIndex = carFront.index

  if CarOperations.isCarInPits(carFront) then
    -- CarManager.cars_reasonWhyCantOvertake[carIndex] = 'Car in front is in pits so not overtaking'
    CarStateMachine.setReasonWhyCantOvertake(carIndex, ReasonWhyCantOvertakeStringNames.YieldingCarInPits)
    return
  end

  -- If we're not close to the front car, do nothing
  local carPosition = car.position
  local carFrontPosition = carFront.position
  -- local distanceToFrontCar = MathHelpers.vlen(MathHelpers.vsub(carFrontPosition, carPosition))
  local distanceToFrontCar = MathHelpers.distanceBetweenVec3s(carFrontPosition, carPosition)
  -- if distanceToFrontCar > storage.distanceToFrontCarToOvertake then
  if distanceToFrontCar > storage.detectCarBehind_meters then -- Andreas: using the same distance as detecting a car to yield to
    -- CarManager.cars_reasonWhyCantOvertake[carIndex] = 'Too far from front car to consider overtaking: ' .. string.format('%.2f', distanceToFrontCar) .. 'm'
    CarStateMachine.setReasonWhyCantOvertake(carIndex, ReasonWhyCantOvertakeStringNames.YieldingCarTooFarAhead)
    return
  end

  -- If we're not faster than the car in front, do nothing
  local ourSpeedKmh = CarManager.cars_averageSpeedKmh[carIndex]
  local frontCarSpeedKmh = CarManager.cars_averageSpeedKmh[carFrontIndex]
  -- local areWeFasterThenTheCarInFront = CarOperations.isFirstCarCurrentlyFasterThanSecondCar(car, carFront, 5)
  local areWeFasterThenTheCarInFront = ourSpeedKmh > frontCarSpeedKmh
  if not areWeFasterThenTheCarInFront then
    -- CarManager.cars_reasonWhyCantOvertake[carIndex] = 'Car in front is faster so not overtaking'
    CarStateMachine.setReasonWhyCantOvertake(carIndex, ReasonWhyCantOvertakeStringNames.YieldingCarIsFaster)
    return
  end

  -- check if the car in front of us is yielding
  local carFrontDrivingOnYieldingLane = CarManager.isCarDrivingOnSide(carFrontIndex, RaceTrackManager.getYieldingSide())
  if not carFrontDrivingOnYieldingLane then
    -- CarManager.cars_reasonWhyCantOvertake[carIndex] = 'Car in front not on yielding lane so not overtaking'
    CarStateMachine.setReasonWhyCantOvertake(carIndex, ReasonWhyCantOvertakeStringNames.YieldingCarNotOnYieldingLane)
    return
  end

  -- consider the car behind us
  if carBehind then
  -- if there's a car behind us, make sure it's not too close before we start overtaking
    -- local distanceFromCarBehindToUs = MathHelpers.vlen(MathHelpers.vsub(carBehind.position, carPosition))
    local distanceFromCarBehindToUs = MathHelpers.distanceBetweenVec3s(carBehind.position, carPosition)
    if distanceFromCarBehindToUs < 5.0 then
      -- CarManager.cars_reasonWhyCantOvertake[carIndex] = 'Car behind too close so not overtaking'
      CarStateMachine.setReasonWhyCantOvertake(carIndex, ReasonWhyCantOvertakeStringNames.AnotherCarBehindTooClose)
      return
    end
  end

  -- start driving to the side to initiate an overtake
  -- save a reference to the car we're overtaking because the next state needs it
  CarManager.cars_currentlyOvertakingCarIndex[carIndex] = carFrontIndex
  return CarStateMachine.CarStateType.EASING_IN_OVERTAKE
end

---Returns the EASING_IN_YIELD state if the car passes all the checks required to start yielding to a car behind it
---@param carIndex integer
---@param car ac.StateCar
---@param carBehind ac.StateCar
---@param carFront ac.StateCar
---@param storage StorageTable
---@return CarStateMachine.CarStateType|nil
CarStateMachine.handleShouldWeYieldToBehindCar = function(carIndex, car, carBehind, carFront, storage)
    -- if there's no car behind us, do nothing
    if not carBehind then
      return
    end

    if CarOperations.isCarInPits(carBehind) then
      CarStateMachine.setReasonWhyCantYield(carIndex, ReasonWhyCantYieldStringNames.OvertakingCarInPits)
      return
    end

    local carBehindIndex = carBehind.index

    -- If this car is not close to the overtaking car, do nothing
    -- local distanceFromOvertakingCarToYieldingCar = MathHelpers.vlen(MathHelpers.vsub(carBehind.position, car.position))
    local distanceFromOvertakingCarToYieldingCar = MathHelpers.distanceBetweenVec3s(carBehind.position, car.position)
    local radius = storage.detectCarBehind_meters
    local isYieldingCarCloseToOvertakingCar = distanceFromOvertakingCarToYieldingCar <= radius
    if not isYieldingCarCloseToOvertakingCar then
      CarStateMachine.setReasonWhyCantYield(carIndex, ReasonWhyCantYieldStringNames.OvertakingCarTooFarBehind)
      return
    end

    -- Check if the overtaking car is behind the yielding car
    local isOvertakingCarBehindYieldingCar = CarOperations.isFirstCarBehindSecondCar(carBehind, car)
    if not isOvertakingCarBehindYieldingCar then
      CarStateMachine.setReasonWhyCantYield(carIndex, ReasonWhyCantYieldStringNames.OvertakingCarNotBehind)
      return
    end

    -- local yieldingCarSpeedKmh = car.speedKmh
    -- local overtakingCarSpeedKmh = carBehind.speedKmh
    local yieldingCarSpeedKmh = CarManager.cars_averageSpeedKmh[carIndex]
    local overtakingCarSpeedKmh = CarManager.cars_averageSpeedKmh[carBehindIndex]

    -- Check if we're faster than the overtaking car
    local isYieldingCarSlowerThanOvertakingCar = yieldingCarSpeedKmh < overtakingCarSpeedKmh
    if not isYieldingCarSlowerThanOvertakingCar then
      CarStateMachine.setReasonWhyCantYield(carIndex, ReasonWhyCantYieldStringNames.WeAreFasterThanOvertakingCar)
      return
    end

    -- local playerCarHasClosingSpeedToAiCar = (overtakingCarSpeedKmh - carSpeedKmh) >= storage.minSpeedDelta_kmh
    -- if not playerCarHasClosingSpeedToAiCar then
      -- CarManager.cars_reasonWhyCantYield[carIndex] = 'Player does not have closing speed so not yielding'
    -- end

    -- check if the car overtaking car is actually driving on the overtaking lane
    -- local yieldSide = storage.yieldSide
    -- local overtakeSide = RaceTrackManager.getOppositeSide(yieldSide)
    -- local isOvertakingCarOnOvertakingLane = CarManager.isCarDrivingOnSide(carBehindIndex, overtakeSide)
    local isOvertakingCarOnOvertakingLane = CarManager.isCarDrivingOnSide(carBehindIndex, RaceTrackManager.getOvertakingSide())
    if not isOvertakingCarOnOvertakingLane then
      CarStateMachine.setReasonWhyCantYield(carIndex, ReasonWhyCantYieldStringNames.WeAreFasterThanOvertakingCar)
      return
    end

    -- CarManager.cars_reasonWhyCantYield[carIndex] = nil

    -- Since all the checks have passed, the yielding car can now start to yield
    CarManager.cars_currentlyYieldingCarToIndex[carIndex] = carBehindIndex
    return CarStateMachine.CarStateType.EASING_IN_YIELD
end


return CarStateMachine