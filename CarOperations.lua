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

----------------------------------------------------------------------
-- Trackside clamping
----------------------------------------------------------------------
local function clampSideOffsetMeters(carPosition, targetSplineOffset_meters, sideSign)
    local storage = StorageManager.getStorage()
    local normalizedTrackProgress = ac.worldCoordinateToTrackProgress(carPosition)
    if normalizedTrackProgress < 0 then return targetSplineOffset_meters end
    local sides = ac.getTrackAISplineSides(normalizedTrackProgress) -- vec2(left, right)
    if sideSign > 0 then
        local maxRightMargin_meters = math.max(0, (sides.y or 0) - storage.rightMargin_meters)
        local clampedTargetSplineOffset_meters  = math.max(0, math.min(targetSplineOffset_meters, maxRightMargin_meters))
        return clampedTargetSplineOffset_meters, normalizedTrackProgress, maxRightMargin_meters
    else
        local maxLeftMargin_meters  = math.max(0, (sides.x or 0) - storage.rightMargin_meters)
        local clampedTargetSplineOffset_meters  = math.min(0, math.max(targetSplineOffset_meters, -maxLeftMargin_meters))
        return clampedTargetSplineOffset_meters, normalizedTrackProgress, maxLeftMargin_meters
    end
end

----------------------------------------------------------------------
-- Decision
----------------------------------------------------------------------
function CarOperations.desiredAbsoluteOffsetFor(aiCar, playerCar, aiCarCurrentlyYielding)
    local storage = StorageManager.getStorage()
    local distanceFromPlayerCarToAICar = MathHelpers.vlen(MathHelpers.vsub(playerCar.position, aiCar.position))
    if playerCar.speedKmh < storage.minPlayerSpeed_kmh then return 0, distanceFromPlayerCarToAICar, nil, nil, 'Player below minimum speed' end

    -- If cars are abeam (neither clearly behind nor clearly ahead), or we’re already yielding and
    -- player isn’t clearly ahead yet, ignore closing-speed — yielding must persist mid-pass.
    local isPlayerCarBehindAICar = CarOperations.isBehind(aiCar, playerCar)
    local isPlayerClearlyAheadOfAICar = CarOperations.playerIsClearlyAhead(aiCar, playerCar, storage.clearAhead_meters)
    local areCarsSideBySide = (not isPlayerCarBehindAICar) and (not isPlayerClearlyAheadOfAICar)
    local ignoreDelta = areCarsSideBySide or (aiCarCurrentlyYielding and not isPlayerClearlyAheadOfAICar)

    if not ignoreDelta and (playerCar.speedKmh - aiCar.speedKmh) < storage.minSpeedDelta_kmh then
        return 0, distanceFromPlayerCarToAICar, nil, nil, 'No closing speed vs AI'
    end

    if aiCar.speedKmh < storage.minAISpeed_kmh then return 0, distanceFromPlayerCarToAICar, nil, nil, 'AI speed too low (corner/traffic)' end

    local radius = aiCarCurrentlyYielding and (storage.detectInner_meters + storage.detectHysteresis_meters) or storage.detectInner_meters
    if distanceFromPlayerCarToAICar > radius then return 0, distanceFromPlayerCarToAICar, nil, nil, 'Too far (outside detect radius)' end

    -- Keep yielding even if the player pulls alongside; only stop once the player is clearly ahead.
    if not isPlayerCarBehindAICar then
        if aiCarCurrentlyYielding and not isPlayerClearlyAheadOfAICar then
            -- continue yielding through the pass; fall through to compute side offset
        else
            return 0, distanceFromPlayerCarToAICar, nil, nil, 'Player not behind (clear)'
        end
    end

    local sideSign = storage.yieldToLeft and -1 or 1
    local targetSplineOffset_meters   = sideSign * storage.yieldOffset_meters
    local clampedTargetSplineOffset_meters, normalizedTrackProgress, maxSideMargin_meters = clampSideOffsetMeters(aiCar.position, targetSplineOffset_meters, sideSign)
    if (sideSign > 0 and (clampedTargetSplineOffset_meters or 0) <= 0.01) or (sideSign < 0 and (clampedTargetSplineOffset_meters or 0) >= -0.01) then
        return 0, distanceFromPlayerCarToAICar, normalizedTrackProgress, maxSideMargin_meters, 'No room on chosen side'
    end
    return clampedTargetSplineOffset_meters, distanceFromPlayerCarToAICar, normalizedTrackProgress, maxSideMargin_meters, 'ok'
end

--- old obsolete
function CarOperations.applyIndicators(carIndex, carYielding, car)
    local storage = StorageManager.getStorage()
    local turningLights;
    if not carYielding then
        turningLights = ac.TurningLights.None
    elseif storage.yieldToLeft then
        turningLights = ac.TurningLights.Left
    else
        turningLights = ac.TurningLights.Right
    end

    if ac.setTargetCar(carIndex) then
        ac.setTurningLights(turningLights)
    end

    -- TODO: we don't need all of these
    CarManager.cars_currentTurningLights[carIndex] = turningLights
    CarManager.cars_indLeft[carIndex] = car.turningLeftLights or false
    CarManager.cars_indRight[carIndex] = car.turningRightLights or false
    CarManager.cars_indPhase[carIndex] = car.turningLightsActivePhase or false
    CarManager.cars_hasTL[carIndex] = car.hasTurningLights or false
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