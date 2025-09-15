local RaceTrackManager = {}

RaceTrackManager.TrackSide = {
    LEFT = 1,
    RIGHT = 2,
}

RaceTrackManager.TrackSideStrings = {
    [RaceTrackManager.TrackSide.LEFT] = "Left",
    [RaceTrackManager.TrackSide.RIGHT] = "Right",
}

--- Returns RIGHT if given LEFT and vice versa
---@param side RaceteTrackManager.TrackSide|integer
---@return RaceteTrackManager.TrackSide|integer
RaceTrackManager.getOppositeSide = function(side)
    if side == RaceTrackManager.TrackSide.LEFT then
        return RaceTrackManager.TrackSide.RIGHT
    end

    return RaceTrackManager.TrackSide.LEFT
end

return RaceTrackManager