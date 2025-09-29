local RaceFlagManager = {}

--- Sets the race flag to the specified type.
--- Andreas: I think the flag only shows when the camera is focused on the local player car, not the AI cars
---@param flagType ac.FlagType
RaceFlagManager.setRaceFlag = function(flagType)
        physics.overrideRacingFlag(flagType)
end

--- Removes the race flag.
RaceFlagManager.removeRaceFlag = function()
        physics.overrideRacingFlag(ac.FlagType.None)
end

return RaceFlagManager