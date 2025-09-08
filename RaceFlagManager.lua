local RaceFlagManager = {}

--- Sets the race flag to the specified type.
---@param flagType ac.FlagType
RaceFlagManager.setRaceFlag = function(flagType)
        physics.overrideRacingFlag(flagType)
end

--- Removes the race flag.
RaceFlagManager.removeRaceFlag = function()
        physics.overrideRacingFlag(ac.FlagType.None)
end

return RaceFlagManager