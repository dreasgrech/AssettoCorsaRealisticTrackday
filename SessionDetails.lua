local SessionDetails = {}

-- bindings
local ac = ac
local ac_getSim = ac.getSim

local sessionStarted = false
local timeSinceSessionStarted = 0

SessionDetails.informSessionInitiated = function()
    -- Logger.log("Session initiated")
    sessionStarted = false
    timeSinceSessionStarted = 0
end

SessionDetails.update = function(dt)
    local sim = ac_getSim()

    -- Check if session has started (ex: sim.isSessionStarted becomes true when a race starts)
    if not sessionStarted and sim.isSessionStarted then
        sessionStarted = true
        Logger.log("Session has started")
    end

    -- If session has started, increment our session timer
    if sessionStarted then
        timeSinceSessionStarted = timeSinceSessionStarted + dt
    end

    -- Logger.log(string_format("Time since session started: %.2f seconds", timeSinceSessionStarted))
end

SessionDetails.getTimeSinceSessionStarted = function()
    return timeSinceSessionStarted
end

return SessionDetails