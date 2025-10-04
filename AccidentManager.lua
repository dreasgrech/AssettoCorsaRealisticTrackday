local AccidentManager = {}

-- local lastAccidentIndexCreated = 0
-- local firstNonResolvedAccidentIndex = 1

local accidentCompletableIndex = CompletableIndexCollectionManager.createNewIndex()

---@type table<integer,integer>
AccidentManager.accidents_carIndex = {}
---@type table<integer,vec3>
AccidentManager.accidents_worldPosition = {}
---@type table<integer,number>
AccidentManager.accidents_splinePosition = {}
---@type table<integer,boolean>
AccidentManager.accidents_collidedWithTrack = {}
---@type table<integer,integer>
AccidentManager.accidents_collidedWithCarIndex = {}
---@type table<integer,integer>
AccidentManager.accidents_yellowFlagZoneIndex = {}
---@type table<integer,boolean>
AccidentManager.accidents_resolved = {}

---Marks the given accident as resolved and done
---@param accidentIndex integer
local setAccidentAsResolved = function(accidentIndex)
        AccidentManager.accidents_carIndex[accidentIndex] = nil
        AccidentManager.accidents_worldPosition[accidentIndex] = nil
        AccidentManager.accidents_splinePosition[accidentIndex] = nil
        AccidentManager.accidents_collidedWithTrack[accidentIndex] = nil
        AccidentManager.accidents_collidedWithCarIndex[accidentIndex] = nil

        -- remove the yellow flag zone associated with this accident
        local yellowFlagZoneIndex = AccidentManager.accidents_yellowFlagZoneIndex[accidentIndex]
        RaceTrackManager.removeYellowFlagZone(yellowFlagZoneIndex)
        AccidentManager.accidents_yellowFlagZoneIndex[accidentIndex] = nil

        --CarManager.cars_culpritInAccidentIndex[carIndex] = nil

        --[==[
        AccidentManager.accidents_resolved[accidentIndex] = true
        -- check the existing accidents and update the first non-resolved accident index so that loops iterating over accidents can start from there
        for i = firstNonResolvedAccidentIndex, lastAccidentIndexCreated do
            -- if not AccidentManager.accidents_resolved[i] then
            if AccidentManager.accidents_resolved[i] == false then
                Logger.log(string.format("AccidentManager: Updating firstNonResolvedAccidentIndex from %d to %d (last accident index: %d)", firstNonResolvedAccidentIndex, i, lastAccidentIndexCreated))
                firstNonResolvedAccidentIndex = i
                break
            end
        end
        --]==]

        AccidentManager.accidents_resolved[accidentIndex] = true
        CompletableIndexCollectionManager.updateFirstNonResolvedIndex(accidentCompletableIndex, AccidentManager.accidents_resolved)
end

---Resolve any accident the given car is a culprit in
---@param carIndex number
AccidentManager.informAboutCarReset = function(carIndex)
    local accidentIndexAsCulprit = CarManager.cars_culpritInAccidentIndex[carIndex]
    -- Logger.log(string.format("[AccidentManager] informAboutCarReset called for car #%d. culpritInAccident #%d.  Total accidents: %d", carIndex, accidentIndexAsCulprit, #AccidentManager.accidents_carIndex))
    if accidentIndexAsCulprit > 0 then
        -- Logger.log(string.format("AccidentManager: Car #%d has reset, clearing it from accident #%d", carIndex, accidentIndexAsCulprit))
        Logger.log(string.format("[AccidentManager] Car #%d has reset, clearing accident #%d", carIndex, accidentIndexAsCulprit))

        setAccidentAsResolved(accidentIndexAsCulprit)
    end
end

---Registers a collision accident for the given culprit car index
---@param culpritCarIndex integer
---@return integer? accidentIndex
AccidentManager.registerCollision = function(culpritCarIndex)

    -- TODO: need to handle what happens when a player car is the culprit car
    -- TODO: need to handle what happens when a player car is the culprit car
    -- TODO: need to handle what happens when a player car is the culprit car
    -- TODO: need to handle what happens when a player car is the culprit car


    if culpritCarIndex == 0 then
        -- Logger.log("AccidentManager.registerCollision called with culpritCarIndex 0 local player, ignoring")
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

    -- we need to subtract 1 from the index to get the actual car index since colliderWidth 0 is track
    collidedWith = collidedWith - 1

    -- ac.areCarsColliding
    -- physics.setCarBodyDamage(carIndex, bodyDamage)

    local collidedWithAnotherCar = not collidedWithTrack
    if collidedWithAnotherCar then
        -- if the victim car the culprit car collided with is already in an accident with the culprit car, ignore this collision
        local victimCarCulpritInAnotherAccidentIndex = CarManager.cars_culpritInAccidentIndex[collidedWith]
        if victimCarCulpritInAnotherAccidentIndex and victimCarCulpritInAnotherAccidentIndex > 0 then
            local victimCulpritAccidentCollidedWithCarIndex = AccidentManager.accidents_collidedWithCarIndex[victimCarCulpritInAnotherAccidentIndex]
            if victimCulpritAccidentCollidedWithCarIndex and victimCulpritAccidentCollidedWithCarIndex == culpritCarIndex then
                -- Logger.log(string.format(
                -- "#%d collided with car #%d but that victim car is already involved in accident #%d with culprit car, ignoring new collision",
                -- culpritCarIndex,
                -- collidedWith,
                -- victimCarCulpritInAnotherAccidentIndex))
                return
            end
        end
    end

    -- register a new accident
    local accidentIndex = CompletableIndexCollectionManager.incrementLastIndexCreated(accidentCompletableIndex)

    local carSplinePosition = culpritCar.splinePosition

    AccidentManager.accidents_carIndex[accidentIndex] = culpritCarIndex
    AccidentManager.accidents_worldPosition[accidentIndex] = culpritCar.position
    AccidentManager.accidents_splinePosition[accidentIndex] = carSplinePosition
    AccidentManager.accidents_collidedWithTrack[accidentIndex] = collidedWithTrack
    AccidentManager.accidents_collidedWithCarIndex[accidentIndex] = collidedWith
    AccidentManager.accidents_resolved[accidentIndex] = false

    -- mark the culprit car as being in an accident
    CarManager.cars_culpritInAccidentIndex[culpritCarIndex] = accidentIndex

    -- create a yellow flag zone for this accident
    local yellowFlagZoneIndex = RaceTrackManager.declareYellowFlagZone(carSplinePosition)
    AccidentManager.accidents_yellowFlagZoneIndex[accidentIndex] = yellowFlagZoneIndex

    Logger.log(string.format("Car #%02d COLLISION at (%.1f, %.1f, %.1f) with %s.  Total accidents: %d", culpritCarIndex, collisionLocalPosition.x, collisionLocalPosition.y, collisionLocalPosition.z, collidedWithTrack and "track" or ("car #" .. tostring(collidedWith)), accidentIndex, #AccidentManager.accidents_carIndex))

    return accidentIndex
end

---Sets that the given car is navigating around the given accident and car
---@param carIndex integer
---@param accidentIndex integer?
---@param carToNavigateAroundIndex integer?
AccidentManager.setCarNavigatingAroundAccident = function(carIndex, accidentIndex, carToNavigateAroundIndex)
    CarManager.cars_navigatingAroundAccidentIndex[carIndex] = accidentIndex
    CarManager.cars_navigatingAroundCarIndex[carIndex] = carToNavigateAroundIndex
end

---Andreas: this function is O(n) where n is the total number of accidents
---@param car ac.StateCar?
---@return integer? accidentIndex, integer closestCarIndex
AccidentManager.isCarComingUpToAccident = function(car, distanceToDetectAccident)
    local lastAccidentIndexCreated = CompletableIndexCollectionManager.getLastIndexCreated(accidentCompletableIndex)
    if lastAccidentIndexCreated == 0 then
        return nil, -1
    end

    if not car then return nil, -1 end

    local carSplinePosition = car.splinePosition
    local carWorldPosition = car.position

    --[====[
    * For all accidents that are not yet resolved
        * Check which car (culprit or victim) is closest to our car
        * Compare the distance of the closest car of this accident with our saved closest car of previous accidents we iterated
        * If this closest car is closer than our previously saved closest car, then
            * Save this accident index as the closest accident and the closest car index
        * else ignore this accident

    --]====]

    -- TODO: Are you sure there's isn't a better way of doing this?  Such as using the sortedCarList and find the next car that is in an accident??

    local currentClosestAccidentIndex = nil
    local currentClosestAccidentClosestCarIndex = -1
    local currentClosestAccidentClosestCarSplinePosition = nil

     -- for i = 1, lastAccidentIndexCreated do
    local firstNonResolvedAccidentIndex = CompletableIndexCollectionManager.getFirstNonResolvedIndex(accidentCompletableIndex)
    for accidentIndex = firstNonResolvedAccidentIndex, lastAccidentIndexCreated do
        if not AccidentManager.accidents_resolved[accidentIndex] then
            local culpritCarIndex = AccidentManager.accidents_carIndex[accidentIndex]
            local culpritCar = ac.getCar(culpritCarIndex)
            local victimCarIndex = AccidentManager.accidents_collidedWithCarIndex[accidentIndex]
            local victimCar = ac.getCar(victimCarIndex)

            local closestCarSplineDistance = math.huge
            local closestCar = nil

            if culpritCar then
                -- make sure the culprit car is ahead of us
                local culpritCarSplinePosition = culpritCar.splinePosition
                local culpritCarAheadOfUs = culpritCarSplinePosition > carSplinePosition
                if culpritCarAheadOfUs then
                    -- make sure the culprit car is within the distance to detect an accident
                    local culpritCarWorldPosition = culpritCar.position
                    -- local distanceFromOurCarToCulpritCar = (culpritCarWorldPosition - carWorldPosition):length()
                    local distanceFromOurCarToCulpritCar = MathHelpers.distanceBetweenVec3s(carWorldPosition, culpritCarWorldPosition)
                    if distanceFromOurCarToCulpritCar < distanceToDetectAccident then
                        closestCarSplineDistance = math.abs(carSplinePosition - culpritCarSplinePosition)
                        closestCar = culpritCar
                    end
                end
            end

            if victimCar then
                -- make sure the victim car is ahead of us
                local victimCarSplinePosition = victimCar.splinePosition
                local victimCarAheadOfUs = victimCarSplinePosition > carSplinePosition
                if victimCarAheadOfUs then
                    -- make sure the victim car is within the distance to detect an accident
                    local victimCarWorldPosition = victimCar.position
                    local distanceFromOurCarToVictimCar = MathHelpers.distanceBetweenVec3s(carWorldPosition, victimCarWorldPosition)
                    if distanceFromOurCarToVictimCar < distanceToDetectAccident then
                        -- if the victim car is closer than the culprit car, use the victim car as the closest car
                        local victimCarSplineDistance = math.abs(carSplinePosition - victimCarSplinePosition)
                        if victimCarSplineDistance < closestCarSplineDistance then
                            closestCarSplineDistance = victimCarSplineDistance
                            closestCar = victimCar
                        end
                    end

                end
            end

            -- if from this accident we found the closest car to us, check if closest car of this accident is closer than the closest car of previous accidents we iterated
            if closestCar then
                -- if we haven't yet saved a closest accident, use this accident as the closest accident
                if not currentClosestAccidentIndex then
                    currentClosestAccidentIndex = accidentIndex
                    currentClosestAccidentClosestCarIndex = closestCar.index
                    currentClosestAccidentClosestCarSplinePosition = closestCar.splinePosition
                else
                    if closestCarSplineDistance < currentClosestAccidentClosestCarSplinePosition then
                        currentClosestAccidentIndex = accidentIndex
                        currentClosestAccidentClosestCarIndex = closestCar.index
                        currentClosestAccidentClosestCarSplinePosition = closestCar.splinePosition
                    end
                end
            end
        end
    end

    return currentClosestAccidentIndex, currentClosestAccidentClosestCarIndex
end

return AccidentManager