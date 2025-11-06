local SessionDetails = {}

-- bindings
local ac = ac
local ac_getSim = ac.getSim

local sessionStarted = false
local timeSinceSessionStarted = 0

SessionDetails.update = function(dt)
    local sim = ac_getSim()
    if not sessionStarted and sim.isSessionStarted then
        sessionStarted = true
    end

    if sessionStarted then
        timeSinceSessionStarted = timeSinceSessionStarted + dt
    end

    -- Logger.log(string_format("Time since session started: %.2f seconds", timeSinceSessionStarted))
end

-- TODO: This needs to go to the OnCarEventManager or something, but not here.
ac.onSessionStart(function()
    -- Logger.log("Session started")
    sessionStarted = false
    timeSinceSessionStarted = 0
end)

SessionDetails.getTimeSinceSessionStarted = function()
    return timeSinceSessionStarted
end

return SessionDetails