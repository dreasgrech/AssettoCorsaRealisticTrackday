local CarStateMachine = {}

-- local LOG_CAR_STATEMACHINE_IN_CSP_LOG = true
local LOG_CAR_STATEMACHINE_IN_CSP_LOG = false

-- [Flags]
local CarStateType = {
  TRYING_TO_START_DRIVING_NORMALLY = 0,
  DRIVING_NORMALLY = 1,
  TRYING_TO_START_YIELDING_TO_THE_SIDE = 2,
  YIELDING_TO_THE_SIDE = 4, 
  STAYING_ON_YIELDING_LANE = 8,
  TRYING_TO_START_EASING_OUT_YIELD = 16,
  EASING_OUT_YIELD = 32,
  WAITING_AFTER_ACCIDENT = 64,
  COLLIDED_WITH_TRACK = 128,
  COLLIDED_WITH_CAR = 256,
  ANOTHER_CAR_COLLIDED_INTO_ME = 512,
}

CarStateMachine.CarStateTypeStrings = {
  [CarStateType.TRYING_TO_START_DRIVING_NORMALLY] = "TryingToStartDrivingNormally",
  [CarStateType.DRIVING_NORMALLY] = "DrivingNormally",
  [CarStateType.TRYING_TO_START_YIELDING_TO_THE_SIDE] = "TryingToStartYieldingToTheSide",
  [CarStateType.YIELDING_TO_THE_SIDE] = "YieldingToTheSide",
  [CarStateType.STAYING_ON_YIELDING_LANE] = "StayingOnYieldingLane",
  [CarStateType.TRYING_TO_START_EASING_OUT_YIELD] = "TryingToStartEasingOutYield",
  [CarStateType.EASING_OUT_YIELD] = "EasingOutYield",
  [CarStateType.WAITING_AFTER_ACCIDENT] = "WaitingAfterAccident",
  [CarStateType.COLLIDED_WITH_TRACK] = "CollidedWithTrack",
  [CarStateType.COLLIDED_WITH_CAR] = "CollidedWithCar",
  [CarStateType.ANOTHER_CAR_COLLIDED_INTO_ME] = "AnotherCarCollidedIntoMe",
}

local cars_previousState = {}
local cars_state = {}

local timeInStates = {}

CarStateMachine.CarStateType = CarStateType

CarStateMachine.changeState = function(carIndex, newState)
    -- save a reference to the current state before changing it
    local currentState = CarStateMachine.getCurrentState(carIndex)
    local isFirstState = currentState == nil -- is this the first state we're setting for this car?
    if isFirstState then
      currentState = newState
    end

    cars_previousState[carIndex] = currentState

    -- reset timers for both states
    timeInStates[currentState] = 0
    timeInStates[newState] = 0

    -- Logger.log(string.format("Car %d: Changing state (%d) from %s to %s", carIndex, currentState))

    -- change to the new state
    cars_state[carIndex] = newState
end

CarStateMachine.getCurrentState = function(carIndex)
    return cars_state[carIndex]
end

local stopCarAfterAccident = function(carIndex)
    -- stop the car
    physics.setAIThrottleLimit(carIndex, 0)
    physics.setAITopSpeed(carIndex, 0)
    physics.setAIStopCounter(carIndex, 1)
    physics.setGentleStop(carIndex, true)
    physics.setAICaution(carIndex, 16) -- be very cautious

    physics.preventAIFromRetiring(carIndex)
end

---comment
---@param carIndex number
---@param drivingToSide TraceTrackManager.TrackSide
---@return boolean
local isSafeToDriveToTheSide = function(carIndex, drivingToSide)
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

local carStateMachine = {
  [CarStateMachine.CarStateType.TRYING_TO_START_DRIVING_NORMALLY] = function (carIndex, dt, car, playerCar, storage)

      CarManager.cars_yieldTime[carIndex] = 0
      CarManager.cars_currentSplineOffset[carIndex] = 0
      CarManager.cars_targetSplineOffset[carIndex] = 0

      -- turn off turning lights
      CarOperations.toggleTurningLights(carIndex, car, ac.TurningLights.None)
      
    -- start driving normally
      CarStateMachine.changeState(carIndex, CarStateMachine.CarStateType.DRIVING_NORMALLY)

      -- reset the ai car caution back to normal
      physics.setAICaution(carIndex, 1)

      -- remove the ai car throttle limit since we will now be driving normally
      physics.setAIThrottleLimit(carIndex, 1)
  end,
  [CarStateMachine.CarStateType.DRIVING_NORMALLY] = function (carIndex, dt, car, playerCar, storage)
      -- render.debugSphere(ac.getCar(carIndex).position, 1, rgbm(0.2, 0.2, 1.0, 1))

      -- DEBUG DEBUG DEBUG
      -- local anyHit, rays = CarOperations.simpleSideRaycasts(carIndex, 10.0)
      -- if anyHit then
          -- -- Logger.log(string.format("Car %d: Side raycast hit something, not yielding", carIndex))
          -- -- CarManager.cars_reasonWhyCantYield[carIndex] = 'Target side blocked by another car so not yielding (raycast)'
      -- end
      -- DEBUG DEBUG DEBUG

        CarManager.cars_reasonWhyCantYield[carIndex] = nil

      -- If this car is not close to the player car, do nothing
      local distanceFromPlayerCarToAICar = MathHelpers.vlen(MathHelpers.vsub(playerCar.position, car.position))
      local radius = storage.detectCarBehind_meters
      local isAICarCloseToPlayerCar = distanceFromPlayerCarToAICar <= radius
      if not isAICarCloseToPlayerCar then
        CarManager.cars_reasonWhyCantYield[carIndex] = 'Too far (outside detect radius) so not yielding'
        return
      end

      -- Check if the player car is behind the ai car
      local isPlayerCarBehindAICar = CarOperations.isBehind(car, playerCar)
      if not isPlayerCarBehindAICar then
        CarManager.cars_reasonWhyCantYield[carIndex] = 'Player not behind (clear) so not yielding'
        return
      end

      -- Check if the player car is above the minimum speed
      local isPlayerAboveMinSpeed = playerCar.speedKmh >= storage.minPlayerSpeed_kmh
      if not isPlayerAboveMinSpeed then
        CarManager.cars_reasonWhyCantYield[carIndex] = 'Player below minimum speed so not yielding'
        return
      end

      -- Check if the player car is currently faster than the ai car 
      local playerCarHasClosingSpeedToAiCar = (playerCar.speedKmh - car.speedKmh) >= storage.minSpeedDelta_kmh
      if not playerCarHasClosingSpeedToAiCar then
        CarManager.cars_reasonWhyCantYield[carIndex] = 'Player does not have closing speed so not yielding'
      end

      -- Check if the ai car is above the minimum speed
      local isAICarAboveMinSpeed = car.speedKmh >= storage.minAISpeed_kmh
      if not isAICarAboveMinSpeed then
        CarManager.cars_reasonWhyCantYield[carIndex] = 'AI speed too low (corner/traffic) so not yielding'
      end

      CarManager.cars_reasonWhyCantYield[carIndex] = nil

      -- Since all the checks have passed, the ai car can now start to yield
      CarStateMachine.changeState(carIndex, CarStateMachine.CarStateType.TRYING_TO_START_YIELDING_TO_THE_SIDE)
  end,
  [CarStateMachine.CarStateType.TRYING_TO_START_YIELDING_TO_THE_SIDE] = function (carIndex, dt, car, playerCar, storage)
      -- turn on turning lights
      local turningLights = storage.yieldSide == RaceTrackManager.TrackSide.LEFT and ac.TurningLights.Left or ac.TurningLights.Right
      CarOperations.toggleTurningLights(carIndex, car, turningLights)

      -- for now go directly to yielding to the side
      CarStateMachine.changeState(carIndex, CarStateMachine.CarStateType.YIELDING_TO_THE_SIDE)
  end,
  [CarStateMachine.CarStateType.YIELDING_TO_THE_SIDE] = function (carIndex, dt, car, playerCar, storage)
      -- local isSideSafeToYield = isSafeToDriveToTheSide(carIndex, storage)
      local yieldSide = storage.yieldSide
      local isSideSafeToYield = isSafeToDriveToTheSide(carIndex, yieldSide)
      if not isSideSafeToYield then
        -- isSafeToDriveToTheSide already logs the reason why we can't yield
        -- CarManager.cars_reasonWhyCantYield[carIndex] = string.format('Target side %s blocked so not yielding', RaceTrackManager.TrackSideStrings[yieldSide])
        -- reduce the car speed so that we can find a gap
        physics.setAIThrottleLimit(carIndex, 0.4)

        return
      end

      CarManager.cars_reasonWhyCantYield[carIndex] = nil
      physics.setAIThrottleLimit(carIndex, 1) -- remove any speed limit we may have applied while waiting for a gap

      local yieldingToLeft = yieldSide == RaceTrackManager.TrackSide.LEFT
      local sideSign = yieldingToLeft and -1 or 1

      local targetSplineOffset = storage.yieldMaxOffset_normalized * sideSign
      local splineOffsetTransitionSpeed = storage.rampSpeed_mps
      local currentSplineOffset = CarManager.cars_currentSplineOffset[carIndex]
      currentSplineOffset = MathHelpers.approach(currentSplineOffset, targetSplineOffset, splineOffsetTransitionSpeed * dt)

      -- set the spline offset on the ai car
      local overrideAiAwareness = storage.overrideAiAwareness -- TODO: check what this does
      physics.setAISplineOffset(carIndex, currentSplineOffset, overrideAiAwareness)

      -- keep the turning lights on while yielding
      local turningLights = yieldingToLeft and ac.TurningLights.Left or ac.TurningLights.Right
      CarOperations.toggleTurningLights(carIndex, car, turningLights)

      CarManager.cars_currentSplineOffset[carIndex] = currentSplineOffset
      CarManager.cars_targetSplineOffset[carIndex] = targetSplineOffset

      CarManager.cars_yieldTime[carIndex] = CarManager.cars_yieldTime[carIndex] + dt

      -- If the ai car is yielding and the player car is now clearly ahead, we can ease out our yielding
      local isPlayerClearlyAheadOfAICar = CarOperations.playerIsClearlyAhead(car, playerCar, storage.clearAhead_meters)
      if isPlayerClearlyAheadOfAICar then
        -- CarManager.cars_reason[carIndex] = 'Player clearly ahead, so easing out yield'

        -- go to trying to start easing out yield state
        CarStateMachine.changeState(carIndex, CarStateMachine.CarStateType.TRYING_TO_START_EASING_OUT_YIELD)
        return
      end

      -- once we have reached the target offset, we can go to the next state
      local arrivedAtTargetOffset = currentSplineOffset == targetSplineOffset
      if arrivedAtTargetOffset then
        CarStateMachine.changeState(carIndex, CarStateMachine.CarStateType.STAYING_ON_YIELDING_LANE)
        return
      end
  end,
  [CarStateMachine.CarStateType.STAYING_ON_YIELDING_LANE] = function (carIndex, dt, car, playerCar, storage)
      CarManager.cars_reasonWhyCantYield[carIndex] = nil

      -- If the ai car is yielding and the player car is now clearly ahead, we can ease out our yielding
      local isPlayerClearlyAheadOfAICar = CarOperations.playerIsClearlyAhead(car, playerCar, storage.clearAhead_meters)
      if isPlayerClearlyAheadOfAICar then
        -- go to trying to start easing out yield state
        CarStateMachine.changeState(carIndex, CarStateMachine.CarStateType.TRYING_TO_START_EASING_OUT_YIELD)
        return
      end

      -- if the player is far enough back, then we can begin easing out
      local isPlayerClearlyBehindAICar = CarOperations.playerIsClearlyBehind(car, playerCar, storage.detectCarBehind_meters)
      if isPlayerClearlyBehindAICar then
        -- go to trying to start easing out yield state
        CarStateMachine.changeState(carIndex, CarStateMachine.CarStateType.TRYING_TO_START_EASING_OUT_YIELD)
        return
      end

      -- make the ai car leave more space in between the care in front while driving on the yielding lane
      physics.setAICaution(carIndex, 2)

      -- limit the ai car throttle while driving on the yielding lane
      physics.setAIThrottleLimit(carIndex, 0.9)

      CarManager.cars_yieldTime[carIndex] = CarManager.cars_yieldTime[carIndex] + dt
  end,
  [CarStateMachine.CarStateType.TRYING_TO_START_EASING_OUT_YIELD] = function (carIndex, dt, car, playerCar, storage)
      -- reset the yield time counter
      CarManager.cars_yieldTime[carIndex] = 0

      -- remove the ai car throttle limit since we will now start easing out the yield
      physics.setAIThrottleLimit(carIndex, 1)

      -- reset the ai car caution back to normal
      physics.setAICaution(carIndex, 1)

      -- inverse the turning lights while easing out yield (inverted yield direction since the car is now going back to center)
      local turningLights = (not storage.yieldSide == RaceTrackManager.TrackSide.LEFT) and ac.TurningLights.Left or ac.TurningLights.Right
      CarOperations.toggleTurningLights(carIndex, car, turningLights)

      -- for now go directly to easing out yield
      CarStateMachine.changeState(carIndex, CarStateMachine.CarStateType.EASING_OUT_YIELD)
  end,
  [CarStateMachine.CarStateType.EASING_OUT_YIELD] = function (carIndex, dt, car, playerCar, storage)

      local yieldSide = storage.yieldSide
      -- this is the side we're currently easing out to, which is the inverse of the side we yielded to
      local easeOutYieldSide = (yieldSide == RaceTrackManager.TrackSide.LEFT) and RaceTrackManager.TrackSide.RIGHT or RaceTrackManager.TrackSide.LEFT
      local sideSafeToYield = isSafeToDriveToTheSide(carIndex, easeOutYieldSide)
      if not sideSafeToYield then
        -- isSafeToDriveToTheSide already logs the reason why we can't yield
        -- CarManager.cars_reasonWhyCantYield[carIndex] = string.format('Target side %s blocked so not easing out yield', RaceTrackManager.TrackSideStrings[easeOutYieldSide])
        return
      end

      -- todo move the targetsplineoffset assignment to trying to start easing out yield state?
      local targetSplineOffset = 0
      local splineOffsetTransitionSpeed = storage.rampRelease_mps
      local currentSplineOffset = CarManager.cars_currentSplineOffset[carIndex]
      currentSplineOffset = MathHelpers.approach(currentSplineOffset, targetSplineOffset, splineOffsetTransitionSpeed * dt)

      -- set the spline offset on the ai car
      local overrideAiAwareness = storage.overrideAiAwareness -- TODO: check what this does
      physics.setAISplineOffset(carIndex, currentSplineOffset, overrideAiAwareness)

      -- keep inverted turning lights on while easing out yield (inverted yield direction since the car is now going back to center)
      local turningLights = (not storage.yieldSide == RaceTrackManager.TrackSide.LEFT) and ac.TurningLights.Left or ac.TurningLights.Right
      CarOperations.toggleTurningLights(carIndex, car, turningLights)

      CarManager.cars_currentSplineOffset[carIndex] = currentSplineOffset
      CarManager.cars_targetSplineOffset[carIndex] = targetSplineOffset

      local arrivedBackToNormal = currentSplineOffset == 0
      if arrivedBackToNormal then
        CarStateMachine.changeState(carIndex, CarStateMachine.CarStateType.TRYING_TO_START_DRIVING_NORMALLY)
        return
      end
  end,
  [CarStateMachine.CarStateType.COLLIDED_WITH_TRACK] = function (carIndex, dt, car, playerCar, storage)
    stopCarAfterAccident(carIndex)

    CarManager.cars_reasonWhyCantYield[carIndex] = 'Collided with track so we are stopped'
  end,
  [CarStateMachine.CarStateType.COLLIDED_WITH_CAR] = function (carIndex, dt, car, playerCar, storage)
    stopCarAfterAccident(carIndex)

    CarManager.cars_reasonWhyCantYield[carIndex] = 'Collided with another car so we are stopped'
  end,
  [CarStateMachine.CarStateType.ANOTHER_CAR_COLLIDED_INTO_ME] = function (carIndex, dt, car, playerCar, storage)
    stopCarAfterAccident(carIndex)

    CarManager.cars_reasonWhyCantYield[carIndex] = 'Another car collided into me so we are stopped'

    local carInput = ac.overrideCarControls(carIndex)
    if carInput then
      -- carInput.horn = true
    end

  end,
}

-- todo: wip
local queuedCollidedWithTrackAccidents = QueueManager.createQueue()
local queuedCollidedWithCarAccidents = QueueManager.createQueue()
local queuedCarCollidedWithMeAccidents = QueueManager.createQueue()

Logger.log("[CarStateMachine] Initialized 3 queues: "..queuedCollidedWithTrackAccidents..", "..queuedCollidedWithCarAccidents..", "..queuedCarCollidedWithMeAccidents)

CarStateMachine.update = function(carIndex, dt, car, playerCar, storage)
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

    local state = CarStateMachine.getCurrentState(carIndex)

    -- execute the state machine for this car
    if LOG_CAR_STATEMACHINE_IN_CSP_LOG then Logger.log(string.format("Car %d: In state: %s", carIndex, CarStateMachine.CarStateTypeStrings[state])) end
    carStateMachine[state](carIndex, dt, car, playerCar, storage)

    timeInStates[state] = timeInStates[state] + dt
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