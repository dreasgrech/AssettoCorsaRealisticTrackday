local AccidentManager = {}

local lastAccidentIndexCreated = 0

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

AccidentManager.registerCollision = function(culpritCarIndex)
    -- local storage = StorageManager.getStorage()
    -- if not storage.handleAccidents then
        -- return
    -- end

    local culpritCar = ac.getCar(culpritCarIndex)
    -- if not car or not car.isAIControlled then return end
    if not culpritCar then return end

    -- if the culprit car is already a culprit in another accident, ignore this collision
    if CarManager.cars_culpritInAccident[culpritCarIndex] > 0 then
        Logger.log(string.format("#%d is already a culprit in accident #%d, ignoring new collision", culpritCarIndex, CarManager.cars_culpritInAccident[culpritCarIndex]))
        return
    end

    -- car.collisionDepth
    local collisionLocalPosition = culpritCar.collisionPosition
    local collidedWith = culpritCar.collidedWith
    local collidedWithTrack = collidedWith == 0

    if collidedWithTrack then
        Logger.warn(string.format("#%d collided with the track but ignoring track collisions for now", culpritCarIndex))
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

    CarManager.cars_culpritInAccident[culpritCarIndex] = accidentIndex

    Logger.log(string.format("Car #%02d COLLISION at (%.1f, %.1f, %.1f) with %s.  Total accidents: %d", culpritCarIndex, collisionLocalPosition.x, collisionLocalPosition.y, collisionLocalPosition.z, collidedWithTrack and "track" or ("car #" .. tostring(collidedWith)), lastAccidentIndexCreated, #AccidentManager.accidents_carIndex))

    return accidentIndex
end

AccidentManager.isCarComingUpToAccident = function(car)
    if lastAccidentIndexCreated == 0 then
        return false
    end

    if not car then return end

    local carSplinePosition = car.splinePosition

    for i = 1, lastAccidentIndexCreated do
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