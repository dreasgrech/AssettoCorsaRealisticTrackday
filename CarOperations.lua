local CarOperations = {}

function CarOperations.isBehind(aiCar, playerCar)
    local aiCarFwd = aiCar.look or aiCar.forward or vec3(0,0,1)
    local rel = MathHelpers.vsub(playerCar.position, aiCar.position)
    return MathHelpers.dot(aiCarFwd, rel) < 0
end

function CarOperations.playerIsClearlyAhead(aiCar, playerCar, meters)
    local fwd = aiCar.look or aiCar.forward or vec3(0,0,1)
    local rel = MathHelpers.vsub(playerCar.position, aiCar.position)
    return MathHelpers.dot(fwd, rel) > meters
end

-- Check if target side of car i is occupied by another AI alongside (prevents unsafe lateral move)
function CarOperations.isTargetSideBlocked(carIndex, sideSign)
    local storage = StorageManager.getStorage()
    local car = ac.getCar(carIndex)
    if not car then return false end
    local sim = ac.getSim()
    local carSide = car.side or vec3(1,0,0)
    local carLook = car.look or vec3(0,0,1)
    for otherCarIndex = 1, (sim.carsCount or 0) - 1 do
        if otherCarIndex ~= carIndex then
            local otherCar = ac.getCar(otherCarIndex)
            if otherCar and otherCar.isAIControlled then
                local rel = MathHelpers.vsub(otherCar.position, car.position)
                local lat = MathHelpers.dot(rel, carSide)   -- + right, - left
                local fwd = MathHelpers.dot(rel, carLook)   -- + ahead, - behind
                if lat*sideSign > 0 and math.abs(lat) <= storage.blockSideLateral_meters and math.abs(fwd) <= storage.blockSideLongitudinal_meters then
                    return true, otherCarIndex
                end
            end
        end
    end
    return false
end

---@param turningLights ac.TurningLights
function CarOperations.toggleTurningLights(carIndex, car, turningLights)
    if ac.setTargetCar(carIndex) then
        ac.setTurningLights(turningLights)
    end

    -- TODO: we don't need all of these
    CarManager.cars_currentTurningLights[carIndex] = turningLights
    CarManager.cars_indLeft[carIndex] = car.turningLeftLights
    CarManager.cars_indRight[carIndex] = car.turningRightLights
    CarManager.cars_indPhase[carIndex] = car.turningLightsActivePhase
    CarManager.cars_hasTL[carIndex] = car.hasTurningLights
end

return CarOperations