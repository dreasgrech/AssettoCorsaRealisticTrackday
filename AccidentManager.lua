local AccidentManager = {}

local lastAccidentIndexCreated = 0
local firstNonResolvedAccidentIndex = 1

AccidentManager.accidents_carIndex = {}
AccidentManager.accidents_worldPosition = {}
AccidentManager.accidents_splinePosition = {}
AccidentManager.accidents_collidedWithTrack = {}
AccidentManager.accidents_collidedWithCarIndex = {}
AccidentManager.accidents_resolved = {}

-- TODO: when a car jumped (resets in ai flood or pits), we should also clear any accidents it was involved in
-- TODO: when a car jumped (resets in ai flood or pits), we should also clear any accidents it was involved in
-- TODO: when a car jumped (resets in ai flood or pits), we should also clear any accidents it was involved in
-- TODO: when a car jumped (resets in ai flood or pits), we should also clear any accidents it was involved in

AccidentManager.informAboutCarReset = function(carIndex)
    local accidentIndexAsCulprit = CarManager.cars_culpritInAccidentIndex[carIndex]
    if accidentIndexAsCulprit > 0 then
        -- Logger.log(string.format("AccidentManager: Car #%d has reset, clearing it from accident #%d", carIndex, accidentIndexAsCulprit))
        Logger.log(string.format("[AccidentManager] Car #%d has reset, clearing accident #%d", carIndex, accidentIndexAsCulprit))

        AccidentManager.accidents_carIndex[accidentIndexAsCulprit] = nil
        AccidentManager.accidents_worldPosition[accidentIndexAsCulprit] = nil
        AccidentManager.accidents_splinePosition[accidentIndexAsCulprit] = nil
        AccidentManager.accidents_collidedWithTrack[accidentIndexAsCulprit] = nil
        AccidentManager.accidents_collidedWithCarIndex[accidentIndexAsCulprit] = nil
        AccidentManager.accidents_resolved[accidentIndexAsCulprit] = true

        --CarManager.cars_culpritInAccidentIndex[carIndex] = nil
    end
end

AccidentManager.registerCollision = function(culpritCarIndex)
    -- local storage = StorageManager.getStorage()
    -- if not storage.handleAccidents then
        -- return
    -- end

    -- TODO: need to handle what happens when a player car is the culprit car
    -- TODO: need to handle what happens when a player car is the culprit car
    -- TODO: need to handle what happens when a player car is the culprit car
    -- TODO: need to handle what happens when a player car is the culprit car


    if culpritCarIndex == 0 then
        Logger.log("AccidentManager.registerCollision called with culpritCarIndex 0 local player, ignoring")
        return
    end

    local culpritCar = ac.getCar(culpritCarIndex)
    if not culpritCar then return end

    -- if the culprit car is already a culprit in another accident, ignore this collision
    local culpritCarAsCulpritInAnotherAccidentIndex = CarManager.cars_culpritInAccidentIndex[culpritCarIndex]
    if culpritCarAsCulpritInAnotherAccidentIndex > 0 then
        -- Logger.log(string.format("#%d is already a culprit in accident #%d, ignoring new collision", culpritCarIndex, CarManager.cars_culpritInAccident[culpritCarIndex]))
        return
    end

    -- car.collisionDepth
    local collisionLocalPosition = culpritCar.collisionPosition
    local collidedWith = culpritCar.collidedWith
    local collidedWithTrack = collidedWith == 0

    -- CURRENTLY IGNORING TRACK COLLISIONS WHILE WORKING ON CAR-TO-CAR COLLISIONS
    -- CURRENTLY IGNORING TRACK COLLISIONS WHILE WORKING ON CAR-TO-CAR COLLISIONS
    -- CURRENTLY IGNORING TRACK COLLISIONS WHILE WORKING ON CAR-TO-CAR COLLISIONS
    -- CURRENTLY IGNORING TRACK COLLISIONS WHILE WORKING ON CAR-TO-CAR COLLISIONS
    if collidedWithTrack then
        --Logger.warn(string.format("#%d collided with the track but ignoring track collisions for now", culpritCarIndex))
        return
    end
    
    -- if the car didn’t collide with the track, we need to subtract 1 from the index to get the actual car index since colliderWidth 0 is track
    -- if not collidedWithTrack then
        collidedWith = collidedWith - 1
    -- end

    -- ac.areCarsColliding
    -- physics.setCarBodyDamage(carIndex, bodyDamage)

    -- length of table: #tableName

    -- local collisionCarAccidentsInvolvedIn = CarManager.cars_culpritInAccident[culpritCarIndex]

    local collidedWithAnotherCar = not collidedWithTrack
    if collidedWithAnotherCar then
        -- if the victim car the culprit car collided with is already in an accident with the culprit car, ignore this collision
        local victimCarCulpritInAnotherAccidentIndex = CarManager.cars_culpritInAccidentIndex[collidedWith]
        if victimCarCulpritInAnotherAccidentIndex > 0 then
            if AccidentManager.accidents_collidedWithCarIndex[victimCarCulpritInAnotherAccidentIndex] == culpritCarIndex then
                Logger.log(string.format(
                "#%d collided with car #%d but that victim car is already involved in accident #%d with culprit car, ignoring new collision",
                culpritCarIndex,
                collidedWith,
                victimCarCulpritInAnotherAccidentIndex))
                return
            end
        end
    end

    -- register a new accident
    lastAccidentIndexCreated = lastAccidentIndexCreated + 1
    local accidentIndex = lastAccidentIndexCreated

    local carSplinePosition = culpritCar.splinePosition

    -- todo: also save the track spline progress
    AccidentManager.accidents_carIndex[accidentIndex] = culpritCarIndex
    AccidentManager.accidents_worldPosition[accidentIndex] = culpritCar.position
    AccidentManager.accidents_splinePosition[accidentIndex] = carSplinePosition
    AccidentManager.accidents_collidedWithTrack[accidentIndex] = collidedWithTrack
    AccidentManager.accidents_collidedWithCarIndex[accidentIndex] = collidedWith
    AccidentManager.accidents_resolved[accidentIndex] = false

    CarManager.cars_culpritInAccidentIndex[culpritCarIndex] = accidentIndex

    Logger.log(string.format("Car #%02d COLLISION at (%.1f, %.1f, %.1f) with %s.  Total accidents: %d", culpritCarIndex, collisionLocalPosition.x, collisionLocalPosition.y, collisionLocalPosition.z, collidedWithTrack and "track" or ("car #" .. tostring(collidedWith)), lastAccidentIndexCreated, #AccidentManager.accidents_carIndex))

    -- check the existing accidents and update the first non-resolved accident index so that loops iterating over accidents can start from there
    for i = firstNonResolvedAccidentIndex, lastAccidentIndexCreated do
        if not AccidentManager.accidents_resolved[i] then
            Logger.log(string.format("AccidentManager: Updating firstNonResolvedAccidentIndex from %d to %d", firstNonResolvedAccidentIndex, i))
            firstNonResolvedAccidentIndex = i
            break
        end
    end

    return accidentIndex
end

---Andreas: this function is O(n)
---@param car ac.StateCar?
---@return boolean
AccidentManager.isCarComingUpToAccident = function(car)
    if lastAccidentIndexCreated == 0 then
        return false
    end

    if not car then return false end

    local carSplinePosition = car.splinePosition

    -- for i = 1, lastAccidentIndexCreated do
    for i = firstNonResolvedAccidentIndex, lastAccidentIndexCreated do
        if not AccidentManager.accidents_resolved[i] then
            local accidentSplinePosition = AccidentManager.accidents_splinePosition[i]
            local carIsCloseButHasntYetPassedTheAccidentPosition =
                carSplinePosition < accidentSplinePosition and
                accidentSplinePosition - carSplinePosition < 0.05 -- 50 meters

            if carIsCloseButHasntYetPassedTheAccidentPosition then
                return true
            end
        end
    end

    return false
end

return AccidentManager