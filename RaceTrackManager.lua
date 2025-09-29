local RaceTrackManager = {}

local yellowZonesCompletableIndex = CompletableIndexCollectionManager.createNewIndex()

local yellowZones_startSplinePosition = {}
local yellowZones_endSplinePosition = {}
local yellowZones_resolved = {}


---@type RaceTrackManager.TrackSide
---@enum integer
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

RaceTrackManager.getTrackLengthMeters = function()
    return trackLength_meters
end

--- Returns RIGHT if given LEFT and vice versa
---@param side RaceTrackManager.TrackSide|integer
---@return RaceTrackManager.TrackSide|integer
RaceTrackManager.getOppositeSide = function(side)
    if side == RaceTrackManager.TrackSide.LEFT then
        return RaceTrackManager.TrackSide.RIGHT
    end

    return RaceTrackManager.TrackSide.LEFT
end

RaceTrackManager.getYieldingSide = function()
    local storage = StorageManager.getStorage()
    local yieldSide = storage.yieldSide
    return yieldSide
end

RaceTrackManager.getOvertakingSide = function()
    local yieldSide = RaceTrackManager.getYieldingSide()
    return RaceTrackManager.getOppositeSide(yieldSide)
end

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

RaceTrackManager.removeYellowFlagZone = function(yellowFlagZoneIndex)
    yellowZones_startSplinePosition[yellowFlagZoneIndex] = nil
    yellowZones_endSplinePosition[yellowFlagZoneIndex] = nil

    yellowZones_resolved[yellowFlagZoneIndex] = true
    CompletableIndexCollectionManager.updateFirstNonResolvedIndex(yellowZonesCompletableIndex, yellowZones_resolved)
end

return RaceTrackManager