local RaceTrackManager = {}

local yellowZonesCompletableIndex = CompletableIndexCollectionManager.createNewIndex()

local yellowZones_startSplinePosition = {}
local yellowZones_endSplinePosition = {}
local yellowZones_accidentIndex = {}
local yellowZones_resolved = {}

---@enum RaceTrackManager.TrackSide 
RaceTrackManager.TrackSide = {
    LEFT = 1,
    RIGHT = 2,
}

RaceTrackManager.TrackSideStrings = {
    [RaceTrackManager.TrackSide.LEFT] = "Left",
    [RaceTrackManager.TrackSide.RIGHT] = "Right",
}

--- Mapping of TrackSide to lateral offset sign
--- Used in RaceTrackManager.getLateralOffsetSign 
local lateralOffsetSigns = {
    [RaceTrackManager.TrackSide.LEFT] = -1,
    [RaceTrackManager.TrackSide.RIGHT] = 1,
}

local sim = ac.getSim()
local trackLength_meters = sim.trackLengthM -- todo: rename as CONSTANT

--- Returns the total track length in meters
---@return number trackLength_meters
RaceTrackManager.getTrackLengthMeters = function()
    return trackLength_meters
end

--- Converts a spline span value representing a fraction of the track length (0..1) to meters
--- Example: 0.5 = half the track length, 0.25 = quarter of the track length
---@param splineValue number
---@return number
RaceTrackManager.splineSpanToMeters = function(splineValue)
    return splineValue * trackLength_meters
end

---Converts a distance in meters to a spline span value representing a fraction of the track length (0..1)
---Example: 200m on a 1000m track = 0.2
---@param meters number
---@return number
RaceTrackManager.metersToSplineSpan = function(meters)
    return meters / trackLength_meters
end

--- Returns RIGHT if given LEFT and vice versa
---@param side RaceTrackManager.TrackSide
---@return RaceTrackManager.TrackSide
RaceTrackManager.getOppositeSide = function(side)
    if side == RaceTrackManager.TrackSide.LEFT then
        return RaceTrackManager.TrackSide.RIGHT
    end

    return RaceTrackManager.TrackSide.LEFT
end

---Returns the yielding side as configured in the settings
---@return RaceTrackManager.TrackSide yieldSide
RaceTrackManager.getYieldingSide = function()
    local storage = StorageManager.getStorage()
    -- local yieldSide = storage.yieldSide
    local yieldingLateralOffset = storage.yieldingLateralOffset
    local yieldSide = RaceTrackManager.getSideFromLateralOffset(yieldingLateralOffset)
    return yieldSide
end

---Returns the overtaking side as configured in the settings
---@return RaceTrackManager.TrackSide overtakingSide
RaceTrackManager.getOvertakingSide = function()
    -- local yieldSide = RaceTrackManager.getYieldingSide()
    -- local overtakingSide = RaceTrackManager.getOppositeSide(yieldSide)
    local storage = StorageManager.getStorage()
    local overtakingLateralOffset = storage.overtakingLateralOffset
    local overtakingSide = RaceTrackManager.getSideFromLateralOffset(overtakingLateralOffset)
    return overtakingSide
end

---Returns the side of the track based on the lateral offset
---@param lateralOffset number
---@return RaceTrackManager.TrackSide
RaceTrackManager.getSideFromLateralOffset = function(lateralOffset)
    return lateralOffset < 0 and RaceTrackManager.TrackSide.LEFT or RaceTrackManager.TrackSide.RIGHT
end

---@param side RaceTrackManager.TrackSide
---@return integer
RaceTrackManager.getLateralOffsetSign = function(side)
    return lateralOffsetSigns[side]
end

-- local calculateYellowFlagZoneStartSplinePosition = function(yellowZoneEndSplinePosition)
    -- -- todo : this function is not good
    -- local storage = StorageManager.getStorage()
    -- local yellowZoneSizeMeters = storage.distanceFromAccidentToSeeYellowFlag_meters
    -- local yellowZoneSizeNormalized = yellowZoneSizeMeters / trackLength_meters

    -- local yellowZoneStartSplinePosition = yellowZoneEndSplinePosition - yellowZoneSizeNormalized
    -- if yellowZoneStartSplinePosition < 0 then
        -- yellowZoneStartSplinePosition = yellowZoneStartSplinePosition + 1.0
    -- end

    -- return yellowZoneStartSplinePosition
-- end

local getYellowZoneSizeNormalized = function()
    local storage = StorageManager.getStorage()
    local yellowZoneSizeMeters = storage.distanceFromAccidentToSeeYellowFlag_meters
    local yellowZoneSizeNormalized = yellowZoneSizeMeters / trackLength_meters
    return yellowZoneSizeNormalized
end

local calculateYellowFlagZoneStartEndPositions = function(accidentIndex, yellowZoneSizeNormalized)
    local closestSplinePosition
    local furthestSplinePosition

    -- start by using the culprit car's spline position
    local culpritCarIndex = AccidentManager.accidents_carIndex[accidentIndex]
    local culpritCar = ac.getCar(culpritCarIndex)
    if culpritCar then
        local culpritCarSplinePosition = culpritCar.splinePosition
        closestSplinePosition = culpritCarSplinePosition
        furthestSplinePosition = culpritCarSplinePosition
    end

    -- if there's a collided-with car, check its spline position too and use the furthest one of the two
    local collidedWithCarIndex = AccidentManager.accidents_collidedWithCarIndex[accidentIndex]
    if collidedWithCarIndex then
        local collidedWithCar = ac.getCar(collidedWithCarIndex)
        if collidedWithCar then
            local collidedWithCarSplinePosition = collidedWithCar.splinePosition
            if collidedWithCarSplinePosition > furthestSplinePosition then
                furthestSplinePosition = collidedWithCarSplinePosition
            else 
                closestSplinePosition = collidedWithCarSplinePosition
            end
        end
    end

    local yellowZoneStartSplinePosition = closestSplinePosition - yellowZoneSizeNormalized
    local yellowZoneEndSplinePosition = furthestSplinePosition

    if yellowZoneStartSplinePosition < 0 then
        yellowZoneStartSplinePosition = yellowZoneStartSplinePosition + 1.0
    end

    return yellowZoneStartSplinePosition, yellowZoneEndSplinePosition
end

---Creates a new yellow flag zone ending at the given spline position and extending backwards by the configured distance
---@param accidentIndex number
---@return number yellowFlagZoneIndex
-- RaceTrackManager.declareYellowFlagZone = function(yellowZoneEndSplinePosition, accidentIndex)
RaceTrackManager.declareYellowFlagZone = function(accidentIndex)

    -- Calculate the start and end spline positions based on the accident's cars' positions
    local yellowZoneSizeNormalized = getYellowZoneSizeNormalized()
    local yellowZoneStartSplinePosition, yellowZoneEndSplinePosition = calculateYellowFlagZoneStartEndPositions(accidentIndex, yellowZoneSizeNormalized)

    local yellowFlagZoneIndex = CompletableIndexCollectionManager.incrementLastIndexCreated(yellowZonesCompletableIndex)
    yellowZones_startSplinePosition[yellowFlagZoneIndex] = yellowZoneStartSplinePosition
    yellowZones_endSplinePosition[yellowFlagZoneIndex] = yellowZoneEndSplinePosition
    yellowZones_accidentIndex[yellowFlagZoneIndex] = accidentIndex
    yellowZones_resolved[yellowFlagZoneIndex] = false

    Logger.log(string.format("[RaceTrackManager] Declared yellow flag zone #%d: start %.3f end %.3f", yellowFlagZoneIndex, yellowZoneStartSplinePosition, yellowZoneEndSplinePosition))

    return yellowFlagZoneIndex
end

-- TODO: THIS METHOD STILL NEEDS TO BE TESTED AND THEN USED, for example in updateYellowFlagZones()
RaceTrackManager.isSplinePosition1FurtherThanSplinePosition2 = function(splinePosition1, splinePosition2)
    -- splinePositions are normalized 0.0-1.0 values
    -- this function also needs to handle the case where the spline positions wrap around the 0.0/1.0 point

    if splinePosition1 >= splinePosition2 then
        return (splinePosition1 - splinePosition2) < 0.5
    else
        return (splinePosition2 - splinePosition1) > 0.5
    end
end

RaceTrackManager.updateYellowFlagZones = function()
    local lastYellowZoneIndexCreated = CompletableIndexCollectionManager.getLastIndexCreated(yellowZonesCompletableIndex)
    if lastYellowZoneIndexCreated == 0 then
        return false
    end

    local yellowZoneSizeNormalized = getYellowZoneSizeNormalized()

    -- go through all non-resolved yellow zones and update their end spline position based on the furthest spline position of the accident cars
    local firstNonResolvedYellowZoneIndex = CompletableIndexCollectionManager.getFirstNonResolvedIndex(yellowZonesCompletableIndex)
    for yellowZoneIndex = firstNonResolvedYellowZoneIndex, lastYellowZoneIndexCreated do
        local yellowZoneResolved = yellowZones_resolved[yellowZoneIndex]
        if yellowZoneResolved == false then
            local accidentIndex = yellowZones_accidentIndex[yellowZoneIndex]

            -- recalculate start and end spline positions
            local yellowZoneStartSplinePosition, yellowZoneEndSplinePosition = calculateYellowFlagZoneStartEndPositions(accidentIndex, yellowZoneSizeNormalized)

            yellowZones_startSplinePosition[yellowZoneIndex] = yellowZoneStartSplinePosition
            yellowZones_endSplinePosition[yellowZoneIndex] = yellowZoneEndSplinePosition
        end
    end
end
--- Removes a yellow flag zone
---@param yellowFlagZoneIndex number
RaceTrackManager.removeYellowFlagZone = function(yellowFlagZoneIndex)
    yellowZones_startSplinePosition[yellowFlagZoneIndex] = nil
    yellowZones_endSplinePosition[yellowFlagZoneIndex] = nil
    yellowZones_accidentIndex[yellowFlagZoneIndex] = nil

    yellowZones_resolved[yellowFlagZoneIndex] = true
    CompletableIndexCollectionManager.updateFirstNonResolvedIndex(yellowZonesCompletableIndex, yellowZones_resolved)
end

---Returns a boolean value indicating whether the given spline position is inside any active yellow flag zone.
---O(n) where n is approximately (gaps are removed when a zone is resolved) the number of active yellow flag zones
---@param splinePosition number
---@return boolean
RaceTrackManager.isSplinePositionInYellowZone = function(splinePosition)
    local lastYellowZoneIndexCreated = CompletableIndexCollectionManager.getLastIndexCreated(yellowZonesCompletableIndex)
    if lastYellowZoneIndexCreated == 0 then
        return false
    end

    local firstNonResolvedYellowZoneIndex = CompletableIndexCollectionManager.getFirstNonResolvedIndex(yellowZonesCompletableIndex)
    for yellowZoneIndex = firstNonResolvedYellowZoneIndex, lastYellowZoneIndexCreated do
        local yellowZoneResolved = yellowZones_resolved[yellowZoneIndex]
        if yellowZoneResolved == false then
            local yellowZoneStartSplinePosition = yellowZones_startSplinePosition[yellowZoneIndex]
            local yellowZoneEndSplinePosition = yellowZones_endSplinePosition[yellowZoneIndex]

            if yellowZoneStartSplinePosition < yellowZoneEndSplinePosition then
                -- normal case, zone does not wrap around the 0.0/1.0 point
                if splinePosition >= yellowZoneStartSplinePosition and splinePosition <= yellowZoneEndSplinePosition then
                    return true
                end
            else
                -- zone wraps around the 0.0/1.0 point
                if (splinePosition >= yellowZoneStartSplinePosition and splinePosition <= 1.0) or (splinePosition >= 0.0 and splinePosition <= yellowZoneEndSplinePosition) then
                    return true
                end
            end
        end
    end

    return false
end

return RaceTrackManager