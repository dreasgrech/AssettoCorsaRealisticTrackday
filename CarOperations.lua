local CarOperations = {}

function CarOperations.isBehind(aiCar, playerCar)
    local fwd = aiCar.look or aiCar.forward or vec3(0,0,1)
    local rel = MathHelpers.vsub(playerCar.position, aiCar.position)
    return MathHelpers.dot(fwd, rel) < 0
end

function CarOperations.playerIsClearlyAhead(aiCar, playerCar, meters)
    local fwd = aiCar.look or aiCar.forward or vec3(0,0,1)
    local rel = MathHelpers.vsub(playerCar.position, aiCar.position)
    return MathHelpers.dot(fwd, rel) > meters
end

return CarOperations