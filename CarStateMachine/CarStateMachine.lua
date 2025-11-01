--[====[
---@ext:verbose
--]====]
local CarStateMachine = {}

-- local LOG_CAR_STATEMACHINE_IN_CSP_LOG = true
local LOG_CAR_STATEMACHINE_IN_CSP_LOG = false

---@type table<CarStateMachine.CarStateType,string>
CarStateMachine.CarStateTypeStrings = {}
---@type table<integer,number>
CarStateMachine.states_minimumTimeInState = { }

---@type table<integer,CarStateMachine.CarStateType>
local cars_state = {}

---@type table<integer,CarStateMachine.CarStateType>
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

local StateExitReason = Strings.StringNames[Strings.StringCategories.StateExitReason]

---Changes the state of the car to the new state
---@param carIndex integer
---@param newState CarStateMachine.CarStateType
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

---Returns the current state of the car
---@param carIndex integer
---@return CarStateMachine.CarStateType
CarStateMachine.getCurrentState = function(carIndex)
    return cars_state[carIndex]
end

---Returns the previous state of the car
---@param carIndex integer
---@return CarStateMachine.CarStateType
CarStateMachine.getPreviousState = function(carIndex)
    return CarStateMachine.cars_previousState[carIndex]
end

---@type Strings.ReasonWhyCantYield
local ReasonWhyCantYieldStringNames = Strings.StringNames[Strings.StringCategories.ReasonWhyCantYield]
---@type Strings.ReasonWhyCantOvertake
local ReasonWhyCantOvertakeStringNames = Strings.StringNames[Strings.StringCategories.ReasonWhyCantOvertake]

--- TODO: This function should probably be moved to CarOperations
---@param carIndex number
---@param drivingToSide RaceTrackManager.TrackSide|integer
---@return boolean
-- local isSafeToDriveToTheSide = function(carIndex, drivingToSide)
CarStateMachine.isSafeToDriveToTheSide = function(carIndex, drivingToSide)
  -- check if there's a car on our side
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

---@type table<CarStateMachine.CarStateType,function>
CarStateMachine.states_entryFunctions = {}
---@type table<CarStateMachine.CarStateType,function>
CarStateMachine.states_updateFunctions = {}
---@type table<CarStateMachine.CarStateType,function>
CarStateMachine.states_transitionFunctions = {}
---@type table<CarStateMachine.CarStateType,function>
CarStateMachine.states_exitFunctions = {}

local queuedCollidedWithTrackAccidents = QueueManager.createQueue()
local queuedCollidedWithCarAccidents = QueueManager.createQueue()
local queuedCarCollidedWithMeAccidents = QueueManager.createQueue()

-- Logger.log("[CarStateMachine] Initialized 3 queues: "..queuedCollidedWithTrackAccidents..", "..queuedCollidedWithCarAccidents..", "..queuedCarCollidedWithMeAccidents)

-- a dictionary which holds, if available, the state to transition to next in the upcoming frame
---@type table<integer,CarStateMachine.CarStateType>
local queuedStatesToTransitionInto = {}

CarStateMachine.setReasonWhyCantYield = function(carIndex, reason)
  StringsManager.setString(carIndex, Strings.StringCategories.ReasonWhyCantYield, reason)
end

--- Sets the reason why the car can't overtake
---@param carIndex integer
-- ---@param reason Strings.ReasonWhyCantOvertake
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

---comment
---@param carIndex integer
---@param dt number
---@param sortedCarList table<integer,ac.StateCar>
---@param sortedCarListIndex integer #1-based index of the car in sortedCarList
---@param storage StorageTable
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
      local storage_Debugging = StorageManager.getStorage_Debugging()
      local logFastStateChanges = storage_Debugging.debugLogFastStateChanges
      if logFastStateChanges then
        local currentStateBeforeChange = CarStateMachine.getCurrentState(carIndex)
        if currentStateBeforeChange then
          local timeInStateBeforeChange = CarManager.cars_timeInCurrentState[carIndex]
          local previousState = CarStateMachine.getPreviousState(carIndex)
          if timeInStateBeforeChange < 0.1 then
            -- local cars_statesExitReason = CarManager.cars_statesExitReason[carIndex][currentStateBeforeChange] or ""
            local stateExitReason = StringsManager.resolveStringValue(Strings.StringCategories.StateExitReason, CarManager.cars_statesExitReason_NAME[carIndex][previousState]) or ''
            Logger.warn(string.format(
            "[CarStateMachine] #%d changing state too quickly: %.3fs in state %s (previous: %s) before changing to %s (%s)",
            carIndex,
            timeInStateBeforeChange,
            CarStateMachine.CarStateTypeStrings[currentStateBeforeChange],
            CarStateMachine.CarStateTypeStrings[previousState],
            CarStateMachine.CarStateTypeStrings[newStateToTransitionIntoThisFrame],
            stateExitReason))
          end
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

---Returns the STAYING_ON_YIELDING_LANE state if we can overtake the car in front of us while we're currently overtaking another car
---@param carIndex integer
---@param car ac.StateCar
---@param carFront ac.StateCar
---@param carBehind ac.StateCar
---@param storage StorageTable
---@param currentlyOvertakingCarIndex integer
---@return CarStateMachine.CarStateType|nil
CarStateMachine.handleOvertakeNextCarWhileAlreadyOvertaking = function(carIndex, car, carFront, carBehind, storage, currentlyOvertakingCarIndex)
    if not carFront then
      return
    end

    -- If there's a car in front of us, check if we can overtake it as well
    local carFrontIndex = carFront.index
    local isCarInFrontSameAsWeAreOvertaking = carFrontIndex == currentlyOvertakingCarIndex
    if not isCarInFrontSameAsWeAreOvertaking then
        local newStateDueToCarInFront = CarStateMachine.handleCanWeOvertakeFrontCar(carIndex, car, carFront, carBehind, storage)
        if newStateDueToCarInFront then
            CarStateMachine.setStateExitReason(carIndex, StateExitReason.ContinuingOvertakingNextCar)
            CarManager.cars_currentlyOvertakingCarIndex[carIndex] = carFrontIndex -- start overtaking the new car in front of us
            return CarStateMachine.CarStateType.STAYING_ON_OVERTAKING_LANE
        end
    end
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
  -- if distanceToFrontCar > storage.distanceToFrontCarToOvertake then
  local detectCarAhead_meters = storage.detectCarAhead_meters 
  local detectCarAhead_metersSqr = detectCarAhead_meters * detectCarAhead_meters
  -- local distanceToFrontCar = MathHelpers.distanceBetweenVec3s(carFrontPosition, carPosition)
  local distanceToFrontCarSqr = MathHelpers.distanceBetweenVec3sSqr(carFrontPosition, carPosition)
  -- if distanceToFrontCar > storage.detectCarAhead_meters then
  if distanceToFrontCarSqr > detectCarAhead_metersSqr then
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

  -- check if the car in front of us is on the yielding lane
  local carFrontDrivingOnYieldingLane = CarManager.isCarDrivingOnSide(carFrontIndex, RaceTrackManager.getYieldingSide())
  if not carFrontDrivingOnYieldingLane then
    -- CarManager.cars_reasonWhyCantOvertake[carIndex] = 'Car in front not on yielding lane so not overtaking'
    CarStateMachine.setReasonWhyCantOvertake(carIndex, ReasonWhyCantOvertakeStringNames.YieldingCarIsNotOnYieldingSide)
    return
  end

  -- consider the car behind us
  if carBehind then
  -- if there's a car behind us, make sure it's not too close before we start overtaking
    -- local distanceFromCarBehindToUs = MathHelpers.vlen(MathHelpers.vsub(carBehind.position, carPosition))
    -- local distanceFromCarBehindToUs = MathHelpers.distanceBetweenVec3s(carBehind.position, carPosition)
    local distanceFromCarBehindToUsSqr = MathHelpers.distanceBetweenVec3sSqr(carBehind.position, carPosition)
    -- if distanceFromCarBehindToUs < 5.0 then
    if distanceFromCarBehindToUsSqr < 5*5 then
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

---@param car ac.StateCar
---@param carBehind ac.StateCar
---@param storage StorageTable
---@return CarStateMachine.CarStateType|nil
local handleShouldWeYieldToBehindCar_singleCar = function(car, carBehind, storage)
    local carIndex = car.index

    if CarOperations.isCarInPits(carBehind) then
      CarStateMachine.setReasonWhyCantYield(carIndex, ReasonWhyCantYieldStringNames.OvertakingCarInPits)
      return
    end

    local carBehindIndex = carBehind.index

    -- If this car is not close to the overtaking car, do nothing
    local carPosition = car.position
    local carBehindPosition = carBehind.position
    local detectCarBehind_meters = storage.detectCarBehind_meters
    local detectCarBehind_metersSqr = detectCarBehind_meters * detectCarBehind_meters
    -- local distanceFromOvertakingCarToYieldingCar = MathHelpers.distanceBetweenVec3s(carBehindPosition, carPosition)
    local distanceFromOvertakingCarToYieldingCarSqr = MathHelpers.distanceBetweenVec3sSqr(carBehindPosition, carPosition)
    --TODO: here we should use the full detection radius if the carBehind is directly behind us,
    --TODO: but if the car behind is in in between other cars behind us, then use a small radius since we can't see the car coming that much because there are other cars in the way
    -- local radius = storage.detectCarBehind_meters
    -- local isYieldingCarCloseToOvertakingCar = distanceFromOvertakingCarToYieldingCar <= radius
    local isYieldingCarCloseToOvertakingCar = distanceFromOvertakingCarToYieldingCarSqr <= detectCarBehind_metersSqr
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
    -- TODO: HERE ALSO CHECK THE CLOSING SPEED AND IF THE CLOSING SPEED IS HIGH >5, THEN STILL YIELD EVEN IF THE AVERAGE SPEED IS LOWER
    -- TODO: HERE ALSO CHECK THE CLOSING SPEED AND IF THE CLOSING SPEED IS HIGH >5, THEN STILL YIELD EVEN IF THE AVERAGE SPEED IS LOWER
    -- TODO: HERE ALSO CHECK THE CLOSING SPEED AND IF THE CLOSING SPEED IS HIGH >5, THEN STILL YIELD EVEN IF THE AVERAGE SPEED IS LOWER
    -- TODO: HERE ALSO CHECK THE CLOSING SPEED AND IF THE CLOSING SPEED IS HIGH >5, THEN STILL YIELD EVEN IF THE AVERAGE SPEED IS LOWER
    local isYieldingCarSlowerThanOvertakingCar = yieldingCarSpeedKmh < overtakingCarSpeedKmh
    if not isYieldingCarSlowerThanOvertakingCar then
      CarStateMachine.setReasonWhyCantYield(carIndex, ReasonWhyCantYieldStringNames.WeAreFasterThanOvertakingCar)
      return
    end

    -- check if the car overtaking car is actually driving on the overtaking lane
    local overtakingSide = RaceTrackManager.getOvertakingSide()
    local isOvertakingCarOnOvertakingLane = CarManager.isCarDrivingOnSide(carBehindIndex, overtakingSide)
    if not isOvertakingCarOnOvertakingLane then
      CarStateMachine.setReasonWhyCantYield(carIndex, ReasonWhyCantYieldStringNames.OvertakingCarNotOnOvertakingSide)
      return
    end

    -- TODO: also check if our car is a lot more powerful than the overtaking car, think twice before yielding

    -- CarManager.cars_reasonWhyCantYield[carIndex] = nil


    -- Logger.log(string.format("[%s] #%d yielding to #%d. OvertakingSide: %s, CarBehindPosition: %s, CarBehindLateralOffset: %.3f",
    -- ac.getSim().timestamp, 
    -- carIndex, 
    -- carBehindIndex,
    -- RaceTrackManager.TrackSideStrings[overtakingSide], 
    -- tostring(carBehindPosition),
    -- CarManager.getActualTrackLateralOffset(carBehindPosition)))

    -- Since all the checks have passed, the yielding car can now start to yield
    CarManager.cars_currentlyYieldingCarToIndex[carIndex] = carBehindIndex
    return CarStateMachine.CarStateType.EASING_IN_YIELD
end

-- ---Returns the EASING_IN_YIELD state if the car passes all the checks required to start yielding to a car behind it
-- ---@param carIndex integer
-- ---@param car ac.StateCar
-- ---@param carBehind ac.StateCar
-- ---@param carFront ac.StateCar
-- ---@param storage StorageTable
-- ---@return CarStateMachine.CarStateType|nil
-- CarStateMachine.handleShouldWeYieldToBehindCar = function(carIndex, car, carBehind, carFront, storage)

---Returns the EASING_IN_YIELD state if the car passes all the checks required to start yielding to a car behind it
---@param sortedCarsList table<integer,ac.StateCar>
---@param sortedCarsListIndex integer #1-based index of the car in sortedCarList
---@param storage StorageTable
---@return CarStateMachine.CarStateType|nil
CarStateMachine.handleShouldWeYieldToBehindCar = function(sortedCarsList, sortedCarsListIndex, storage)
  local handleYielding = storage.handleYielding
  if not handleYielding then
    return
  end

    local car = sortedCarsList[sortedCarsListIndex]

    --Check all the cars behind us within our detection radius to see if we need to yield to any of them
    local detectedCarBehind_meters = storage.detectCarBehind_meters
    local detectedCarBehind_metersSqr = detectedCarBehind_meters * detectedCarBehind_meters
    -- for loop through all the cars behind us within our detection radius
    local totalCarsBehindUs = #sortedCarsList - sortedCarsListIndex
    for i = 1, totalCarsBehindUs do
      local carBehind = sortedCarsList[sortedCarsListIndex + i]
      -- todo: there must be a better way of checking the distance between the cars
      -- local distanceFromCarBehindToUs = MathHelpers.distanceBetweenVec3s(carBehind.position, car.position)
      -- local isCarBehindWithinRadius = distanceFromCarBehindToUs <= detectedCarBehind_meters
      local distanceFromCarBehindToUsSqr = MathHelpers.distanceBetweenVec3sSqr(carBehind.position, car.position)
      local isCarBehindWithinRadius = distanceFromCarBehindToUsSqr <= detectedCarBehind_metersSqr
      if isCarBehindWithinRadius then
        local stateDueToYield = handleShouldWeYieldToBehindCar_singleCar(car, carBehind, storage)
        if stateDueToYield then
          return stateDueToYield
        end
      else 
        -- if the car is outside our detection radius, we can stop checking further cars behind us
        break
      end
    end

    -- old way (checking only the car directly behind us):
    -- local carBehind = sortedCarsList[sortedCarsListIndex + 1]
    -- return handleShouldWeYieldToBehindCar_singleCar(car, carBehind, storage)
end


return CarStateMachine