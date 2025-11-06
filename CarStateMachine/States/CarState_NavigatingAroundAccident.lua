local STATE = CarStateMachine.CarStateType.NAVIGATING_AROUND_ACCIDENT

CarStateMachine.CarStateTypeStrings[STATE] = "NavigatingAroundAccident"
CarStateMachine.states_minimumTimeInState[STATE] = 0

local StateExitReason = Strings.StringNames[Strings.StringCategories.StateExitReason]

-- ENTRY FUNCTION
CarStateMachine.states_entryFunctions[STATE] = function (carIndex, dt, sortedCarsList, sortedCarsListIndex, storage)

end

-- UPDATE FUNCTION
---@param carIndex integer
---@param dt number
---@param sortedCarsList table<integer,ac.StateCar>
---@param sortedCarsListIndex integer
---@param storage StorageTable
CarStateMachine.states_updateFunctions[STATE] = function (carIndex, dt, sortedCarsList, sortedCarsListIndex, storage)
    local accidentIndex = CarManager.cars_navigatingAroundAccidentIndex[carIndex]
    if accidentIndex == 0 then
        Logger.error(string.format("#%d in state NavigatingAroundAccident but has no accident index to navigate around!", carIndex))
        -- CarStateMachine.changeCarState(carIndex, CarStateMachine.CarStateType.DRIVING_NORMALLY)
        return
    end

    --CarOperations.setAICaution(carIndex, 6)
    --CarOperations.setAICaution(carIndex, 1)
    CarOperations.setAICaution(carIndex, 0)

    CarOperations.setAITopSpeed(carIndex, 10)
    -- CarOperations.limitTopSpeed(carIndex, 10)
    -- CarOperations.setPedalPosition(carIndex, CarOperations.CarPedals.Gas, 0.3)
    -- CarOperations.setPedalPosition(carIndex, CarOperations.CarPedals.Brake, 0.8)

    local car = sortedCarsList[sortedCarsListIndex]

    -- fetch the closest accident to us, in case there's a closer one than the one we're currently navigating around
    local closestAccidentIndex, closestAccidentClosestCarIndex = AccidentManager.isCarComingUpToAccident(car, storage.distanceToStartNavigatingAroundCarInAccident_meters)
    if not closestAccidentIndex then
        AccidentManager.setCarNavigatingAroundAccident(carIndex, nil, nil)
        return
    end

    -- if closestAccidentIndex then-- and closestAccidentIndex ~= accidentIndex then
        -- Logger.log(string.format("[CarState_NavigatingAroundAccident] #%d is switching to navigate around closer accident #%d instead of previous accident #%d", carIndex, closestAccidentIndex, accidentIndex))

        -- -- we are closer to a different accident, so switch to navigating around that one instead
        -- CarManager.cars_navigatingAroundAccidentIndex[carIndex] = closestAccidentIndex
    AccidentManager.setCarNavigatingAroundAccident(carIndex, closestAccidentIndex, closestAccidentClosestCarIndex)
    accidentIndex = closestAccidentIndex

    -- end

    -- local culpritCarIndex = AccidentManager.accidents_carIndex[accidentIndex]
    -- local culpritCar = ac.getCar(culpritCarIndex)
    -- local victimCarIndex = AccidentManager.accidents_collidedWithCarIndex[accidentIndex]
    -- local victimCar = ac.getCar(victimCarIndex)

    -- determine which car is closest to us by comparing spline positions 
    -- local culpritCarSplineDistance = math.abs(car.splinePosition - culpritCar.splinePosition)
    -- local victimCarSplineDistance = math.abs(car.splinePosition - victimCar.splinePosition)

    -- local carToNavigateAroundSplineDistance
    -- local carToNavigateAround = nil
    -- if culpritCarSplineDistance < victimCarSplineDistance then
        -- carToNavigateAround = culpritCar
        -- carToNavigateAroundSplineDistance = culpritCarSplineDistance
    -- else
        -- carToNavigateAround = victimCar
        -- carToNavigateAroundSplineDistance = victimCarSplineDistance
    -- end

    -- if carToNavigateAroundSplineDistance > 0.01 then
    local closestAccidentClosestCar = ac.getCar(closestAccidentClosestCarIndex)
    if not closestAccidentClosestCar then
        Logger.error(string.format("Could not get closest car to navigate around for car #%d navigating around accident #%d", carIndex, accidentIndex))
        return
    end

    -- local carToNavigateAroundSplineDistance = math.abs(car.splinePosition - closestAccidentClosestCar.splinePosition)
    -- if carToNavigateAroundSplineDistance > 0.01 then
        -- -- we're more than 1 centimeter away from the car to navigate around, so just drive normally for now
        -- return
    -- end


    -- CarManager.cars_navigatingAroundCarIndex[carIndex] = carToNavigateAround.index

    -- local accidentWorldPosition = AccidentManager.accidents_worldPosition[accidentIndex]
    -- local distanceToAccident = car.position:distance(accidentWorldPosition)


    --[=====[
    local targetOffset = 0
    local carToNavigateAround = closestAccidentClosestCar
    local carToNavigateAroundLateralOffset = CarManager.getActualTrackLateralOffset(carToNavigateAround.position)
    -- local signOfLateralOffset = carToNavigateAroundLateralOffset < 0 and -1 or 1
    -- now we need to calculate our own offset to use to go around the car to navigating around
    if (math.abs(carToNavigateAroundLateralOffset) < 0.1) then
        -- the car to navigate around is in the middle of the track, so we can pick a side to go around it
        targetOffset = -2 -- todo: need to decide the corect side
    else
        -- the car to navigate around is already to one side, so we need to go to the other side
        -- targetOffset = (carToNavigateAroundLateralOffset * signOfLateralOffset) + (2.0 * signOfLateralOffset)
        targetOffset = carToNavigateAroundLateralOffset * -1
    end
    --]=====]


    --[=====[
    -- OLD SIMPLE NAVIGATION
    local carToNavigateAround = closestAccidentClosestCar
    local carToNavigateAroundLateralOffset = CarManager.getActualTrackLateralOffset(carToNavigateAround.position)
    local carToNavigateAroundSide = RaceTrackManager.getSideFromLateralOffset(carToNavigateAroundLateralOffset)
    local carToNavigateAroundOppositeSide = RaceTrackManager.getOppositeSide(carToNavigateAroundSide)
    local targetOffset = carToNavigateAroundOppositeSide == RaceTrackManager.TrackSide.LEFT and -2 or 2
    local sideToDriveTo = carToNavigateAroundOppositeSide
    --]=====]

    ----------------------------------
    local carsInAccident = {AccidentManager.accidents_carIndex[accidentIndex], AccidentManager.accidents_collidedWithCarIndex[accidentIndex]}
    local targetOffset, influencingCarIndex = CollisionAvoidanceManager.computeDesiredLateralOffset(carIndex, carsInAccident, dt
    -- ,{
            -- horizon_meters = 30,
            -- steps = 5,
            -- d_samples = {targetOffset - 1.5, targetOffset, targetOffset + 1.5},
            -- track_half = 10,
            -- edge_margin = 0.5,
            -- max_d_rate = 10,
            -- bias_from_obs = 0.6,
    -- }
    )
    local sideToDriveTo = RaceTrackManager.getSideFromLateralOffset(targetOffset)
    -- TODO: THE CLOSESTACCIDENTINDEX HERE IS NOT CORRECT BECAUSE IT MAY BE DIFFERENT THAT FROM FROM COMPUTEDESIREDLATERALOFFSET GIVES US
    AccidentManager.setCarNavigatingAroundAccident(carIndex, closestAccidentIndex, influencingCarIndex)
    ----------------------------------

    --[=====[
    CarOperations.driveSafelyToSide(carIndex, dt, car, targetOffset, 5, true, false)
    --]=====]

    -- Prevent the car from retiring while navigating around an accident because otherwise when the ai cars are moving very slow, the game tends to teleports them back to the pits
    CarOperations.preventAIFromRetiring(carIndex)

    CarOperations.toggleCarCollisions(carIndex, false)

    --------------------------------------
    -- CollisionAvoidanceManager.debugDraw(carIndex)
    --------------------------------------
end

-- TRANSITION FUNCTION
---@param carIndex integer
---@param dt number
---@param sortedCarsList table<integer,ac.StateCar>
---@param sortedCarsListIndex integer
---@param storage StorageTable
CarStateMachine.states_transitionFunctions[STATE] = function (carIndex, dt, sortedCarsList, sortedCarsListIndex, storage)
    -- If we don't have an accident index to navigate around, return to normal driving
    local accidentIndex = CarManager.cars_navigatingAroundAccidentIndex[carIndex]
    if not accidentIndex or accidentIndex == 0 then
        -- Logger.error(string.format("accidentIndex is 0! in car #%d", carIndex))
        -- CarStateMachine.changeCarState(carIndex, CarStateMachine.CarStateType.DRIVING_NORMALLY)
        AccidentManager.setCarNavigatingAroundAccident(carIndex, nil, nil)
        CarStateMachine.setStateExitReason(carIndex, StateExitReason.NoAccidentIndexToNavigateAround)
        return CarStateMachine.CarStateType.DRIVING_NORMALLY
    end

    -- If the accident has been resolved, return to normal driving
    local accidentResolved = AccidentManager.isAccidentResolved(accidentIndex)
    if accidentResolved then
        Logger.log(string.format("[CarState_NavigatingAroundAccident] Car %d accident #%d has been resolved, returning to normal driving", carIndex, accidentIndex))
        AccidentManager.setCarNavigatingAroundAccident(carIndex, nil, nil)
        CarStateMachine.setStateExitReason(carIndex, StateExitReason.AccidentResolved)
        return CarStateMachine.CarStateType.DRIVING_NORMALLY
    end

    local car = sortedCarsList[sortedCarsListIndex]

    --[====[
    --Andreas: removed this because it's already being handled in the update function which is better because here we switch to the same state and prevents us from resetting data in the exit function
    -- check if there's an even closer accident that we should be navigating around instead
    local distanceToStartNavigatingAroundCarInAccident_meters = storage.distanceToStartNavigatingAroundCarInAccident_meters
    local upcomingAccidentIndex, upcomingAccidentClosestCarIndex = AccidentManager.isCarComingUpToAccident(car, distanceToStartNavigatingAroundCarInAccident_meters)
    if upcomingAccidentIndex then
        if upcomingAccidentIndex ~= accidentIndex then
            Logger.log(string.format("[CarState_NavigatingAroundAccident] Car %d switching to navigate around new accident #%d instead of previous accident #%d", carIndex, upcomingAccidentIndex, accidentIndex))
            AccidentManager.setCarNavigatingAroundAccident(carIndex, upcomingAccidentIndex, upcomingAccidentClosestCarIndex)
            CarStateMachine.setStateExitReason(carIndex, StateExitReason.FoundCloserAccidentToNavigateAround)
            return CarStateMachine.CarStateType.NAVIGATING_AROUND_ACCIDENT
        end
    end
    --]====]

    -- local newStateDueToAccident = CarStateMachine.handleYellowFlagZone(carIndex, car)
    -- if newStateDueToAccident then
        -- if CarManager.cars_navigatingAroundAccidentIndex[carIndex] ~= accidentIndex then
            -- Logger.log(string.format("[CarState_NavigatingAroundAccident] Car %d switching to navigate around new accident #%d instead of previous accident #%d", carIndex, CarManager.cars_navigatingAroundAccidentIndex[carIndex], accidentIndex))
            -- CarStateMachine.setStateExitReason(carIndex, StateExitReason.FoundCloserAccidentToNavigateAround)
            -- return newStateDueToAccident
        -- end
    -- end

    -- If the car we're navigating around is no longer valid, return to normal driving
    local carToNavigateAroundIndex = CarManager.cars_navigatingAroundCarIndex[carIndex]
    local carToNavigateAround = ac.getCar(carToNavigateAroundIndex)
    if not carToNavigateAround then
        Logger.error(string.format("Could not get car to navigate around for car #%d navigating around accident #%d", carIndex, accidentIndex))
        AccidentManager.setCarNavigatingAroundAccident(carIndex, nil, nil)
        CarStateMachine.setStateExitReason(carIndex, StateExitReason.CarToNavigateAroundNotFound)
        return CarStateMachine.CarStateType.DRIVING_NORMALLY
    end

    -- if we are now past the car we are currently navigating around, and are some distance away from it, return to normal driving

    -- make sure that the car we're navigating around is behind us
    local carToNavigateAroundSplineDistance = carToNavigateAround.splinePosition
    local ourCarSplinePosition = car.splinePosition
    if ourCarSplinePosition > carToNavigateAroundSplineDistance then
        -- make sure we're some distance away from the car we're navigating around
        local carToNavigateAroundWorldPosition = carToNavigateAround.position
        local ourCarWorldPosition = car.position
        -- local distanceToCarToNavigateAround = MathHelpers.distanceBetweenVec3s(ourCarWorldPosition, carToNavigateAroundWorldPosition)
        local distanceToCarToNavigateAroundSqr = MathHelpers.distanceBetweenVec3sSqr(ourCarWorldPosition, carToNavigateAroundWorldPosition)
        -- jif distanceToCarToNavigateAround > 10 then
        if distanceToCarToNavigateAroundSqr > 10*10 then
            -- we're more than some meters away from the car we were navigating around, so return to normal driving
            AccidentManager.setCarNavigatingAroundAccident(carIndex, nil, nil)
            CarStateMachine.setStateExitReason(carIndex, StateExitReason.AccidentIsFarBehindUs)
            return CarStateMachine.CarStateType.DRIVING_NORMALLY
        end
    end

    --[=====[
    local accidentWorldPosition = AccidentManager.accidents_worldPosition[accidentIndex]
    local carPosition = car.position
    local carSplinePosition = car.splinePosition
    local accidentSplinePosition = AccidentManager.accidents_splinePosition[accidentIndex]
    
    -- if the accident is far behind us, return to normal driving
    if carSplinePosition > accidentSplinePosition then
        local distanceToAccident = MathHelpers.distanceBetweenVec3s(carPosition, accidentWorldPosition)
        if distanceToAccident > 10 then
            -- we're more than some meters away from the accident, so return to normal driving
            CarManager.cars_navigatingAroundAccidentIndex[carIndex] = 0
            CarStateMachine.setStateExitReason(carIndex, StateExitReason.AccidentIsFarBehindUs)
            return CarStateMachine.CarStateType.DRIVING_NORMALLY
        end
    end
    -]=====]
end

-- EXIT FUNCTION
---@param carIndex integer
---@param dt number
---@param sortedCarsList table<integer,ac.StateCar>
---@param sortedCarsListIndex integer
---@param storage StorageTable
CarStateMachine.states_exitFunctions[STATE] = function (carIndex, dt, sortedCarsList, sortedCarsListIndex, storage)
    CarOperations.removeAICaution(carIndex)
    CarOperations.removeAITopSpeed(carIndex)
    CarOperations.resetPedalPosition(carIndex, CarOperations.CarPedals.Gas)
    CarOperations.resetPedalPosition(carIndex, CarOperations.CarPedals.Brake)

    -- Andreas: do not clear here because we use it when changing accident
    -- Andreas: Update: re-enabled it here because we handle changing accident in the update function now, not in the transition function
    CarManager.cars_navigatingAroundAccidentIndex[carIndex] = 0 -- clear the accident we're navigating around since we're now exiting the state
end
