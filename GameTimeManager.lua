local GameTimeManager = {}

-- 0.0 when the game starts, increases only when the sim is not paused.
-- Resets to 0 on scripts reload.
local playingGameTime = 0.0

local sim = ac.getSim()

---Returns the amount of time (in seconds) the game has been played.
---This value increases only when the simulation is not paused and resets to 0 on scripts reload.
---@return number
GameTimeManager.getPlayingGameTime = function()
    return playingGameTime
end

GameTimeManager.update = function(dt)
    if not sim.isPaused then
        playingGameTime = playingGameTime + dt
    end
    -- Logger.log(playingGameTime)
end

return GameTimeManager