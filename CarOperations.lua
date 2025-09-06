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

-- Check if target side of car i is occupied by another AI alongside (prevents unsafe lateral move)
function CarOperations.isTargetSideBlocked(carIndex, sideSign)
    local storage = StorageManager.getStorage()
    local me = ac.getCar(carIndex); if not me then return false end
    local sim = ac.getSim(); if not sim then return false end
    local mySide = me.side or vec3(1,0,0)
    local myLook = me.look or vec3(0,0,1)
    for i = 1, (sim.carsCount or 0) - 1 do
        if i ~= carIndex then
            local o = ac.getCar(i)
            if o and o.isAIControlled ~= false then
                local rel = MathHelpers.vsub(o.position, me.position)
                local lat = MathHelpers.dot(rel, mySide)   -- + right, - left
                local fwd = MathHelpers.dot(rel, myLook)   -- + ahead, - behind
                if lat*sideSign > 0 and math.abs(lat) <= storage.blockSideLateral_meters and math.abs(fwd) <= storage.blockSideLongitudinal_meters then
                    return true, i
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
        local maxRight = math.max(0, (sides.y or 0) - storage.rightMargin_meters)
        local clampedTargetSplineOffset_meters  = math.max(0, math.min(targetSplineOffset_meters, maxRight))
        return clampedTargetSplineOffset_meters, normalizedTrackProgress, maxRight
    else
        local maxLeft  = math.max(0, (sides.x or 0) - storage.rightMargin_meters)
        local clampedTargetSplineOffset_meters  = math.min(0, math.max(targetSplineOffset_meters, -maxLeft))
        return clampedTargetSplineOffset_meters, normalizedTrackProgress, maxLeft
    end
end

----------------------------------------------------------------------
-- Decision
----------------------------------------------------------------------
function CarOperations.desiredOffsetFor(aiCar, playerCar, aiCarCurrentlyYielding)
    local storage = StorageManager.getStorage()
    if playerCar.speedKmh < storage.minPlayerSpeed_kmh then return 0, nil, nil, nil, 'Player below minimum speed' end

    -- If cars are abeam (neither clearly behind nor clearly ahead), or we’re already yielding and
    -- player isn’t clearly ahead yet, ignore closing-speed — yielding must persist mid-pass.
    local behind = CarOperations.isBehind(aiCar, playerCar)
    local aheadClear = CarOperations.playerIsClearlyAhead(aiCar, playerCar, storage.clearAhead_meters)
    local sideBySide = (not behind) and (not aheadClear)
    local ignoreDelta = sideBySide or (aiCarCurrentlyYielding and not aheadClear)

    if not ignoreDelta and (playerCar.speedKmh - aiCar.speedKmh) < storage.minSpeedDelta_kmh then
        return 0, nil, nil, nil, 'No closing speed vs AI'
    end

    if aiCar.speedKmh < storage.minAISpeed_kmh then return 0, nil, nil, nil, 'AI speed too low (corner/traffic)' end

    local radius = aiCarCurrentlyYielding and (storage.detectInner_meters + storage.detectHysteresis_meters) or storage.detectInner_meters
    local distanceFromPlayerCarToAICar = MathHelpers.vlen(MathHelpers.vsub(playerCar.position, aiCar.position))
    if distanceFromPlayerCarToAICar > radius then return 0, distanceFromPlayerCarToAICar, nil, nil, 'Too far (outside detect radius)' end

    -- Keep yielding even if the player pulls alongside; only stop once the player is clearly ahead.
    if not behind then
        if aiCarCurrentlyYielding and not aheadClear then
            -- continue yielding through the pass; fall through to compute side offset
        else
            return 0, distanceFromPlayerCarToAICar, nil, nil, 'Player not behind (clear)'
        end
    end

    local sideSign = storage.yieldToLeft and -1 or 1
    local targetSplineOffset_meters   = sideSign * storage.yieldOffset_meters
    local clampedTargetSplineOffset_meters, normalizedTrackProgress, sideMax = clampSideOffsetMeters(aiCar.position, targetSplineOffset_meters, sideSign)
    if (sideSign > 0 and (clampedTargetSplineOffset_meters or 0) <= 0.01) or (sideSign < 0 and (clampedTargetSplineOffset_meters or 0) >= -0.01) then
        return 0, distanceFromPlayerCarToAICar, normalizedTrackProgress, sideMax, 'No room on chosen side'
    end
    return clampedTargetSplineOffset_meters, distanceFromPlayerCarToAICar, normalizedTrackProgress, sideMax, 'ok'
end

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
        -- ac.setTargetCar(0)
        CarManager.cars_blink[carIndex] = turningLights
    end

    CarManager.cars_indLeft[carIndex] = car.turningLeftLights or false
    CarManager.cars_indRight[carIndex] = car.turningRightLights or false
    CarManager.cars_indPhase[carIndex] = car.turningLightsActivePhase or false
    CarManager.cars_hasTL[carIndex] = car.hasTurningLights or false
end

return CarOperations