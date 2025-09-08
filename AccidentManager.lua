local AccidentManager = {}

local lastAccidentIndexCreated = 0

AccidentManager.accidents_carIndex = {}
AccidentManager.accidents_worldPosition = {}
AccidentManager.accidents_collidedWithTrack = {}
AccidentManager.accidents_collidedWithCarIndex = {}
AccidentManager.accidents_resolved = {}

AccidentManager.registerCollision = function(carIndex)
    local car = ac.getCar(carIndex)
    -- if not car or not car.isAIControlled then return end
    if not car then return end

    -- car.collisionDepth
    local collisionLocalPosition = car.collisionPosition
    local collidedWith = car.collidedWith
    local collidedWithTrack = collidedWith == 0
    
    -- if the car didn’t collide with the track, we need to subtract 1 from the index to get the actual car index since colliderWidth 0 is track
    -- if not collidedWithTrack then
        collidedWith = collidedWith - 1
    -- end

    -- ac.areCarsColliding
    -- physics.setCarBodyDamage(carIndex, bodyDamage)

    -- length of table: #tableName

    -- register a new accident
    lastAccidentIndexCreated = lastAccidentIndexCreated + 1
    local accidentIndex = lastAccidentIndexCreated

    -- todo: also save the track spline progress
    AccidentManager.accidents_carIndex[accidentIndex] = carIndex
    AccidentManager.accidents_worldPosition[accidentIndex] = car.position
    AccidentManager.accidents_collidedWithTrack[accidentIndex] = collidedWithTrack
    AccidentManager.accidents_collidedWithCarIndex[accidentIndex] = collidedWith
    AccidentManager.accidents_resolved[accidentIndex] = false

    Logger.log(string.format("Car #%02d COLLISION at (%.1f, %.1f, %.1f) with %s.  Total accidents: %d", carIndex, collisionLocalPosition.x, collisionLocalPosition.y, collisionLocalPosition.z, collidedWithTrack and "track" or ("car #" .. tostring(collidedWith)), lastAccidentIndexCreated, #AccidentManager.accidents_carIndex))

    return accidentIndex
end

return AccidentManager