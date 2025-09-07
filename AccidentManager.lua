local AccidentManager = {}

AccidentManager.registerCollision = function(carIndex)
    local car = ac.getCar(carIndex)
    -- if not car or not car.isAIControlled then return end
    if not car then return end

    -- car.collisionDepth
    local collisionLocalPosition = car.collisionPosition
    local collidedWith = car.collidedWith
    local collidedWithTrack = collidedWith == 0
    
    -- if the car didn’t collide with the track, we need to subtract 1 from the index to get the actual car index since colliderWidth 0 is track
    if not collidedWithTrack then
        collidedWith = collidedWith - 1
    end

    -- ac.areCarsColliding
    -- physics.setCarBodyDamage(carIndex, bodyDamage)

    Logger.log(string.format("Car #%02d COLLISION at (%.1f, %.1f, %.1f) with %s", carIndex, collisionLocalPosition.x, collisionLocalPosition.y, collisionLocalPosition.z, collidedWithTrack and "track" or ("car #" .. tostring(collidedWith))))
end

return AccidentManager