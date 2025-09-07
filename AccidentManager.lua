local AccidentManager = {}

local lastAccidentIndexCreated = 0

local accidents_carIndex = {}
local accidents_worldPosition = {}
local accidents_collidedWithTrack = {}
local accidents_collidedWithCarIndex = {}
local accidents_resolved = {}

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

    accidents_carIndex[accidentIndex] = carIndex
    accidents_worldPosition[accidentIndex] = car.position
    accidents_collidedWithTrack[accidentIndex] = collidedWithTrack
    accidents_collidedWithCarIndex[accidentIndex] = collidedWith
    accidents_resolved[accidentIndex] = false

    -- now we need to inform the state machine that a car has collided so that the state machine can then change state in the next update


    Logger.log(string.format("Car #%02d COLLISION at (%.1f, %.1f, %.1f) with %s.  Total accidents: %d", carIndex, collisionLocalPosition.x, collisionLocalPosition.y, collisionLocalPosition.z, collidedWithTrack and "track" or ("car #" .. tostring(collidedWith)), lastAccidentIndexCreated, #accidents_carIndex))
end

return AccidentManager