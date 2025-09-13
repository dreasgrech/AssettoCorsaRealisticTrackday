local CarStateMachine = {}

-- local LOG_CAR_STATEMACHINE_IN_CSP_LOG = true
local LOG_CAR_STATEMACHINE_IN_CSP_LOG = false

-- [Flags]
local CarStateType = {
  DRIVING_NORMALLY = 1,
  YIELDING_TO_THE_SIDE = 4, 
  STAYING_ON_YIELDING_LANE = 8,
  EASING_OUT_YIELD = 32,
  WAITING_AFTER_ACCIDENT = 64,
  COLLIDED_WITH_TRACK = 128,
  COLLIDED_WITH_CAR = 256,
  ANOTHER_CAR_COLLIDED_INTO_ME = 512,
  DRIVING_TO_SIDE_TO_OVERTAKE = 1024,
  STAYING_ON_OVERTAKING_LANE = 2048,
}

CarStateMachine.CarStateTypeStrings = {}
CarStateMachine.states_minimumTimeInState = { }

local cars_previousState = {}
local cars_state = {}

local timeInStates = {}

CarStateMachine.CarStateType = CarStateType

CarStateMachine.changeState = function(carIndex, newState)
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

    cars_previousState[carIndex] = currentState

    -- reset the time in state counter
    timeInStates[carIndex] = 0

    -- Logger.log(string.format("Car %d: Changing state (%d) from %s to %s", carIndex, currentState))

    -- change to the new state
    cars_state[carIndex] = newState
end

CarStateMachine.getCurrentState = function(carIndex)
    return cars_state[carIndex]
end

---comment
---@param carIndex number
---@param drivingToSide TraceTrackManager.TrackSide|integer
---@return boolean
-- local isSafeToDriveToTheSide = function(carIndex, drivingToSide)
CarStateMachine.isSafeToDriveToTheSide = function(carIndex, drivingToSide)
    -- check if there's a car on our side
    local isCarOnSide, carOnSideDirection, carOnSideDistance = CarOperations.checkIfCarIsBlockedByAnotherCarAndSaveAnchorPoints(carIndex)
    if isCarOnSide then
        -- if the car on our side is on the same side as the side we're trying to yield to, then we cannot yield
        local trackSideOfBlockingCar = CarOperations.getTrackSideFromCarDirection(carOnSideDirection)
        local isSideCarOnTheSameSideAsYielding = drivingToSide == trackSideOfBlockingCar
        
        if isSideCarOnTheSameSideAsYielding then
          -- Logger.log(string.format("Car %d: Car on side detected: %s  distance=%.2f m", carIndex, CarOperations.CarDirectionsStrings[carOnSideDirection], carOnSideDistance or -1))
          CarManager.cars_reasonWhyCantYield[carIndex] = 'Target side blocked by another car so not driving to the side: ' .. CarOperations.CarDirectionsStrings[carOnSideDirection] .. '  gap=' .. string.format('%.2f', carOnSideDistance) .. 'm'
          return false
        end
    end

    -- Check car blind spot
    -- Andreas: I've never seen this code working yet...
    local distanceToNearestCarInBlindSpot_L, distanceToNearestCarInBlindSpot_R = ac.getCarBlindSpot(carIndex)
    local isSideBlocked_L = (not (distanceToNearestCarInBlindSpot_L == nil))-- and distanceToNearestCarInBlindSpot_L > 0
    local isSideBlocked_R = (not (distanceToNearestCarInBlindSpot_R == nil))-- and distanceToNearestCarInBlindSpot_R > 0

    if (isSideBlocked_L or isSideBlocked_R) then
        Logger.log(string.format("Car %d: Blindspot L=%.2f  R=%.2f", carIndex, distanceToNearestCarInBlindSpot_L or -1, distanceToNearestCarInBlindSpot_R or -1))
        CarManager.cars_reasonWhyCantYield[carIndex] = 'Car in blind spot so not driving to the side: ' ..tostring(distanceToNearestCarInBlindSpot_L) .. 'm'
        return false
    end

    return true
end

CarStateMachine.states_entryFunctions = {}
CarStateMachine.states_updateFunctions = {}
CarStateMachine.states_transitionFunctions = {}
CarStateMachine.states_exitFunctions = {}

-- todo: wip
local queuedCollidedWithTrackAccidents = QueueManager.createQueue()
local queuedCollidedWithCarAccidents = QueueManager.createQueue()
local queuedCarCollidedWithMeAccidents = QueueManager.createQueue()

-- Logger.log("[CarStateMachine] Initialized 3 queues: "..queuedCollidedWithTrackAccidents..", "..queuedCollidedWithCarAccidents..", "..queuedCarCollidedWithMeAccidents)

-- a dictionary which holds, if available, the state to transition to next in the upcoming frame
local queuedStatesToTransitionInto = {}

CarStateMachine.initializeCarInStateMachine = function(carIndex)
    -- Logger.log(string.format("CarStateMachine: initializeCarInStateMachine() car %d in state machine, setting initial state to DRIVING_NORMALLY", carIndex))
    -- queue up the DRIVING_NORMALLY state for the car so that it will take effect in the next frame
    queuedStatesToTransitionInto[carIndex] = CarStateMachine.CarStateType.DRIVING_NORMALLY
    -- Logger.log(string.format("CarStateMachine: Car %d Just added normally state: %d", carIndex, queuedStatesToTransitionInto[carIndex]))
    --CarStateMachine.changeState(carIndex, CarStateMachine.CarStateType.DRIVING_NORMALLY)
end

-- CarStateMachine.update = function(carIndex, dt, car, carBehind, storage)
CarStateMachine.update = function(carIndex, dt, sortedCarList, sortedCarListIndex, storage)
    -- while QueueManager.queueLength(queuedCollidedWithTrackAccidents) > 0 do
        -- local carIndex = QueueManager.dequeue(queuedCollidedWithTrackAccidents)
        
        -- Logger.log(string.format("CarStateMachine: Car %d collided with track, switching to COLLIDED_WITH_TRACK state", carIndex))
        -- CarStateMachine.changeState(carIndex, CarStateMachine.CarStateType.COLLIDED_WITH_TRACK)
    -- end

    -- while QueueManager.queueLength(queuedCollidedWithCarAccidents) > 0 do
        -- local carIndex = QueueManager.dequeue(queuedCollidedWithCarAccidents)
        
        -- Logger.log(string.format("CarStateMachine: Car %d collided with another car, switching to COLLIDED_WITH_CAR state", carIndex))
        -- CarStateMachine.changeState(carIndex, CarStateMachine.CarStateType.COLLIDED_WITH_CAR)
    -- end

    -- while QueueManager.queueLength(queuedCarCollidedWithMeAccidents) > 0 do
        -- local carIndex = QueueManager.dequeue(queuedCarCollidedWithMeAccidents)

        -- -- Logger.log(string.format("CarStateMachine: Car %d was collided into by another car, switching to ANOTHER_CAR_COLLIDED_INTO_ME state", carIndex))
        -- Logger.log(string.format("%d ", QueueManager.queueLength(queuedCarCollidedWithMeAccidents)))
        -- CarStateMachine.changeState(carIndex, CarStateMachine.CarStateType.ANOTHER_CAR_COLLIDED_INTO_ME)
    -- end

    CarManager.cars_anchorPoints[carIndex] = nil -- clear the anchor points each frame, they will be recalculated if needed

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

      -- change to the new state
      CarStateMachine.changeState(carIndex, newStateToTransitionIntoThisFrame)

      -- execute the state's entry function
      -- CarStateMachine.states_entryFunctions[newStateToTransitionIntoThisFrame](carIndex, dt, car, carBehind, storage)
      CarStateMachine.states_entryFunctions[newStateToTransitionIntoThisFrame](carIndex, dt, sortedCarList, sortedCarListIndex, storage)
    end

    local state = CarStateMachine.getCurrentState(carIndex)

    if state == nil then
      Logger.error(string.format("CarStateMachine: #%d stat is nil!", carIndex))
      return
    end

    -- run the state loop
    -- Logger.log(string.format("CarStateMachine: Car %d updateFunction of state %s: ", carIndex, CarStateMachine.CarStateTypeStrings[state]) .. tostring(CarStateMachine.states_updateFunctions[carIndex]))
    CarStateMachine.states_updateFunctions[state](carIndex, dt, sortedCarList, sortedCarListIndex, storage)

    local currentTimeInState = timeInStates[carIndex]

    -- increase the time spent in this state
    timeInStates[carIndex] = currentTimeInState + dt

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

      queuedStatesToTransitionInto[carIndex] = newState
    end
end

CarStateMachine.informAboutAccident = function(accidentIndex)
    local collidedWithTrack = AccidentManager.accidents_collidedWithTrack[accidentIndex]
    local carIndex = AccidentManager.accidents_carIndex[accidentIndex]
    local collidedWithCarIndex = AccidentManager.accidents_collidedWithCarIndex[accidentIndex]

    if collidedWithTrack then
        QueueManager.enqueue(queuedCollidedWithTrackAccidents, carIndex)
    else
        -- if the car collided with another car, we need to inform both cars
        QueueManager.enqueue(queuedCollidedWithCarAccidents, carIndex)
        QueueManager.enqueue(queuedCarCollidedWithMeAccidents, collidedWithCarIndex)
    end
end

return CarStateMachine