local RaceTrackManager = {}

local yellowZonesCompletableIndex = CompletableIndexCollectionManager.createNewIndex()

local yellowZones_startSplinePosition = {}
local yellowZones_endSplinePosition = {}
local yellowZones_resolved = {}


---@alias RaceTrackManager.TrackSide
---| `RaceTrackManager.TrackSide.LEFT` @Value: 1.
---| `RaceTrackManager.TrackSide.RIGHT` @Value: 2.
RaceTrackManager.TrackSide = {
    LEFT = 1,
    RIGHT = 2,
}

RaceTrackManager.TrackSideStrings = {
    [RaceTrackManager.TrackSide.LEFT] = "Left",
    [RaceTrackManager.TrackSide.RIGHT] = "Right",
}

local sim = ac.getSim()
local trackLength_meters = sim.trackLengthM

--- Returns the total track length in meters
---@return number
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
    local yieldSide = storage.yieldSide
    return yieldSide
end

---Returns the overtaking side as configured in the settings
---@return RaceTrackManager.TrackSide overtakingSide
RaceTrackManager.getOvertakingSide = function()
    local yieldSide = RaceTrackManager.getYieldingSide()
    local overtakingSide = RaceTrackManager.getOppositeSide(yieldSide)
    return overtakingSide
end

---Creates a new yellow flag zone ending at the given spline position and extending backwards by the configured distance
---@param yellowZoneEndSplinePosition number
---@return number yellowFlagZoneIndex
RaceTrackManager.declareYellowFlagZone = function(yellowZoneEndSplinePosition)
    local yellowFlagZoneIndex = CompletableIndexCollectionManager.incrementLastIndexCreated(yellowZonesCompletableIndex)

    local storage = StorageManager.getStorage()
    local yellowZoneSizeMeters = storage.distanceFromAccidentToSeeYellowFlag_meters
    local yellowZoneSizeNormalized = yellowZoneSizeMeters / trackLength_meters

    local yellowZoneStartSplinePosition = yellowZoneEndSplinePosition - yellowZoneSizeNormalized
    if yellowZoneStartSplinePosition < 0 then
        yellowZoneStartSplinePosition = yellowZoneStartSplinePosition + 1.0
    end

    yellowZones_startSplinePosition[yellowFlagZoneIndex] = yellowZoneStartSplinePosition
    yellowZones_endSplinePosition[yellowFlagZoneIndex] = yellowZoneEndSplinePosition
    yellowZones_resolved[yellowFlagZoneIndex] = false

    Logger.log(string.format("[RaceTrackManager] Declared yellow flag zone #%d: start %.3f end %.3f", yellowFlagZoneIndex, yellowZoneStartSplinePosition, yellowZoneEndSplinePosition))

    return yellowFlagZoneIndex
end

--- Removes a yellow flag zone
---@param yellowFlagZoneIndex number
RaceTrackManager.removeYellowFlagZone = function(yellowFlagZoneIndex)
    yellowZones_startSplinePosition[yellowFlagZoneIndex] = nil
    yellowZones_endSplinePosition[yellowFlagZoneIndex] = nil

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
        if yellowZones_resolved[yellowZoneIndex] == false then
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