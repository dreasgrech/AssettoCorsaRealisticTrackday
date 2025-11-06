-- bindings
local ac = ac
local ac_getCar = ac.getCar
local string = string
local string_format = string.format
local Logger = Logger
local Logger_warn = Logger.warn
local CarManager = CarManager
local CarOperations = CarOperations
local CarOperations_setAICaution = CarOperations.setAICaution
local CarOperations_setAIAggression = CarOperations.setAIAggression
local CarOperations_setAIDifficultyLevel = CarOperations.setAIDifficultyLevel
local CarOperations_toggleTurningLights = CarOperations.toggleTurningLights
local CarOperations_overtakeSafelyToSide = CarOperations.overtakeSafelyToSide
local CarOperations_calculateAICautionAndAggressionWhileOvertaking = CarOperations.calculateAICautionAggressionDifficultyWhileOvertaking
local CarOperations_isSecondCarClearlyAhead = CarOperations.isSecondCarClearlyAhead
local CarOperations_removeAICaution = CarOperations.removeAICaution
local CarOperations_setDefaultAIAggression = CarOperations.setDefaultAIAggression
local CarOperations_setDefaultAIDifficultyLevel = CarOperations.setDefaultAIDifficultyLevel
local CarStateMachine = CarStateMachine
local CarStateMachine_handleYellowFlagZone = CarStateMachine.handleYellowFlagZone
local CarStateMachine_setStateExitReason = CarStateMachine.setStateExitReason
local CarStateMachine_handleShouldWeYieldToBehindCar = CarStateMachine.handleShouldWeYieldToBehindCar
local CarStateMachine_handleOvertakeNextCarWhileAlreadyOvertaking = CarStateMachine.handleOvertakeNextCarWhileAlreadyOvertaking
local StorageManager = StorageManager
local StorageManager_getStorage_Overtaking = StorageManager.getStorage_Overtaking
local Strings = Strings


local STATE = CarStateMachine.CarStateType.STAYING_ON_OVERTAKING_LANE

CarStateMachine.CarStateTypeStrings[STATE] = "StayingOnOvertakingLane"
CarStateMachine.states_minimumTimeInState[STATE] = 0

local StateExitReason = Strings.StringNames[Strings.StringCategories.StateExitReason]

-- ENTRY FUNCTION
CarStateMachine.states_entryFunctions[STATE] = function (carIndex, dt, sortedCarsList, sortedCarsListIndex, storage)

end

---UPDATE FUNCTION
---@param carIndex integer
---@param dt number
---@param sortedCarsList table<integer,ac.StateCar>
---@param sortedCarsListIndex integer
---@param storage StorageTable
CarStateMachine.states_updateFunctions[STATE] = function (carIndex, dt, sortedCarsList, sortedCarsListIndex, storage)
    -- make the driver more aggressive while overtaking
    -- CarOperations.setAICaution(carIndex, 0) -- andreas: commenting this because they get way too aggressive

    -- set the ai caution while we're overtaking
    local car = sortedCarsList[sortedCarsListIndex]
    -- local carFront = sortedCarsList[sortedCarsListIndex - 1]
    -- local aiCaution = CarOperations.calculateAICautionWhileOvertaking(car, carFront)
    local yieldingCarIndex = CarManager.cars_currentlyOvertakingCarIndex[carIndex]
    local yieldingCar = ac_getCar(yieldingCarIndex)
    local aiCaution, aiAggression, aiDifficultyLevel = CarOperations_calculateAICautionAndAggressionWhileOvertaking(car, yieldingCar)
    CarOperations_setAICaution(carIndex, aiCaution)

    if storage.overrideOriginalAIAggression_overtaking then
        CarOperations_setAIAggression(carIndex, aiAggression)
    end

    if storage.overrideOriginalAIDifficultyLevel_overtaking then
        CarOperations_setAIDifficultyLevel(carIndex, aiDifficultyLevel)
    end

    -- keep driving to the overtaking side even while staying on the overtaking lane since sometimes the cars still end up drifting back to the normal lanes mostly because of high speed corners
    local storage_Overtaking = StorageManager_getStorage_Overtaking()
    local useIndicatorLights = storage_Overtaking.UseIndicatorLightsWhenDrivingOnOvertakingLane
    local droveSafelyToSide = CarOperations_overtakeSafelyToSide(carIndex, dt, car, storage, useIndicatorLights)
end

--- TRANSITION FUNCTION
---@param carIndex integer
---@param dt number
---@param sortedCarsList table<integer,ac.StateCar>
---@param sortedCarsListIndex integer
---@param storage StorageTable
CarStateMachine.states_transitionFunctions[STATE] = function (carIndex, dt, sortedCarsList, sortedCarsListIndex, storage)
    local car = sortedCarsList[sortedCarsListIndex]

    -- check if we're now in a yellow flag zone
    local newStateDueToYellowFlagZone = CarStateMachine_handleYellowFlagZone(carIndex, car)
    if newStateDueToYellowFlagZone then
        CarStateMachine_setStateExitReason(carIndex, StateExitReason.EnteringYellowFlagZone)
        return newStateDueToYellowFlagZone
    end

    local carBehind = sortedCarsList[sortedCarsListIndex + 1]
    local carFront = sortedCarsList[sortedCarsListIndex - 1]

    local currentlyOvertakingCarIndex = CarManager.cars_currentlyOvertakingCarIndex[carIndex]
    local currentlyOvertakingCar = ac_getCar(currentlyOvertakingCarIndex)
    if (not currentlyOvertakingCar) then
        -- the car we're overtaking is no longer valid, return to easing out overtake
        Logger_warn(string_format('Car %d in state StayingOnOvertakingLane but the car it was overtaking (car %d) is no longer valid, returning to ease out overtake', carIndex, currentlyOvertakingCarIndex))
        -- CarManager.cars_currentlyOvertakingCarIndex[carIndex] = nil
        -- CarStateMachine.setStateExitReason(carIndex, string.format('Car %d in state StayingOnOvertakingLane but the car it was overtaking (car %d) is no longer valid, returning to ease out overtake', carIndex, currentlyOvertakingCarIndex))
        CarStateMachine_setStateExitReason(carIndex, StateExitReason.OvertakingCarNoLongerExists)
        return CarStateMachine.CarStateType.EASING_OUT_OVERTAKE
    end

    -- if we don't have an overtaking car anymore, we can ease out our yielding
    -- Andreas: commenting this because it's not good.
    -- Andreas: because if we are the last car in the list, there technically won't be a car behind us anymore while we are overtaking
    -- if not carBehind then
        -- CarStateMachine.setStateExitReason(carIndex, 'No yielding car so not staying on overtaking lane')
        -- return CarStateMachine.CarStateType.EASING_OUT_OVERTAKE
    -- end

    -- If there's a different car to the one we're currently overtaking in front of us, check if we can overtake it as well
    local newStateDueToOvertakingNextCar = CarStateMachine_handleOvertakeNextCarWhileAlreadyOvertaking(carIndex, car, carFront, carBehind, currentlyOvertakingCarIndex)
    if newStateDueToOvertakingNextCar then
        -- CarStateMachine.setStateExitReason(carIndex, StateExitReason.ContinuingOvertakingNextCar)
        -- return newStateDueToOvertakingNextCar
        return -- since we're already on the overtaking lane, just continue staying on it
    end

    -- if we're now clearly ahead of the car we're overtaking, we can ease out our overtaking
    -- local areWeClearlyAheadOfCarWeAreOvertaking = CarOperations.isSecondCarClearlyAhead(carBehind, car, storage.clearAhead_meters)
    local areWeClearlyAheadOfCarWeAreOvertaking = CarOperations_isSecondCarClearlyAhead(currentlyOvertakingCar, car, storage.clearAhead_meters)
    if areWeClearlyAheadOfCarWeAreOvertaking then
        -- go to trying to start easing out yield state
        -- CarStateMachine.setStateExitReason(carIndex, 'Clearly ahead of car we were overtaking so easing out overtake')
        CarStateMachine_setStateExitReason(carIndex, StateExitReason.ClearlyAheadOfYieldingCar)
        return CarStateMachine.CarStateType.EASING_OUT_OVERTAKE
    end

    -- TODO: There's a bug with this isCarWeAreOvertakingIsClearlyAheadOfUs check here because when it's enabled, the cars exit out of this state immediately
    -- TODO: But without it, a car can get stuck in this state if the yielding car suddendly drives far ahead
    -- if the car we're overtaking is now clearly ahead of us, than we also need to ease out our overtaking
    -- local isCarWeAreOvertakingIsClearlyAheadOfUs = CarOperations.isSecondCarClearlyAhead(car, carBehind, storage.clearAhead_meters)
    local overtakingCarLeeway = 40
    local isCarWeAreOvertakingIsClearlyAheadOfUs = CarOperations_isSecondCarClearlyAhead(car, currentlyOvertakingCar, storage.clearAhead_meters + overtakingCarLeeway)
    if isCarWeAreOvertakingIsClearlyAheadOfUs then
        -- go to trying to start easing out yield state
        CarStateMachine_setStateExitReason(carIndex, StateExitReason.OvertakingCarIsClearlyAhead)
        return CarStateMachine.CarStateType.EASING_OUT_OVERTAKE
    end

    -- check if there's currently a car behind us which we might need to yield to
    if carBehind then
        -- check if the car behind us is the same car we're overtaking
        local isCarBehindSameAsCarWeAreOvertaking = carBehind.index == currentlyOvertakingCarIndex
        -- if the car behind us is not the same car we're overtaking, check if we should start yielding to it instead
        if not isCarBehindSameAsCarWeAreOvertaking then
            -- local newStateDueToCarBehind = CarStateMachine.handleShouldWeYieldToBehindCar(carIndex, car, carBehind, carFront, storage)
            local newStateDueToCarBehind = CarStateMachine_handleShouldWeYieldToBehindCar(sortedCarsList, sortedCarsListIndex)
            if newStateDueToCarBehind then
                CarManager.cars_currentlyOvertakingCarIndex[carIndex] = nil
                -- CarStateMachine.setStateExitReason(carIndex, string.format("Yielding to car #%d instead", carBehind.index))
                CarStateMachine_setStateExitReason(carIndex, StateExitReason.YieldingToCar)
                return newStateDueToCarBehind
            end
        end
    end
end

-- EXIT FUNCTION
CarStateMachine.states_exitFunctions[STATE] = function (carIndex, dt, sortedCarsList, sortedCarsListIndex, storage)
    -- reset the overtaking car caution back to normal
    CarOperations_removeAICaution(carIndex)
    CarOperations_setDefaultAIDifficultyLevel(carIndex)
    CarOperations_setDefaultAIAggression(carIndex)
    CarOperations_toggleTurningLights(carIndex, ac.TurningLights.None)
end
