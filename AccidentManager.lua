local AccidentManager = {}

AccidentManager.registerCollision = function(carIndex)
    local car = ac.getCar(carIndex)
    if not car or not car.isAIControlled then return end

    -- car.collisionDepth
    local collisionPosition = car.collisionPosition
    local collidedWith = car.collidedWith
    local collidedWithTrack = collidedWith == 0

    -- ac.areCarsColliding
    -- physics.setCarBodyDamage(carIndex, bodyDamage)

    Logger.log(string.format("Car #%02d COLLISION at (%.1f, %.1f, %.1f) with %s", carIndex, collisionPosition.x, collisionPosition.y, collisionPosition.z, collidedWithTrack and "track" or ("car #" .. tostring(collidedWith))))
end

return AccidentManager