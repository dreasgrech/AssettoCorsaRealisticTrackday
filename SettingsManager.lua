local SettingsManager = {}

SettingsManager.DETECT_INNER_M        = 42.0
SettingsManager.DETECT_HYSTERESIS_M   = 60.0
SettingsManager.MIN_PLAYER_SPEED_KMH  = 70.0
SettingsManager.MIN_SPEED_DELTA_KMH   = 5.0
SettingsManager.YIELD_OFFSET_M        = 2.5
SettingsManager.RAMP_SPEED_MPS        = 4.0
SettingsManager.RAMP_RELEASE_MPS      = 1.6  -- slower return to center to avoid “snap back” once player is clearly ahead
SettingsManager.CLEAR_AHEAD_M         = 6.0
SettingsManager.RIGHT_MARGIN_M        = 0.6
SettingsManager.LIST_RADIUS_FILTER_M  = 400.0
SettingsManager.MIN_AI_SPEED_KMH      = 35.0
SettingsManager.YIELD_TO_LEFT         = false

-- Side-by-side guard: if target side is occupied, don’t cut in — briefly slow down to find a gap
SettingsManager.BLOCK_SIDE_LAT_M      = 2.2   -- lateral threshold (m) to consider another AI “next to” us
SettingsManager.BLOCK_SIDE_LONG_M     = 5.5   -- longitudinal window (m) for “alongside”
SettingsManager.BLOCK_SLOWDOWN_KMH    = 12.0  -- temporary speed reduction while blocked
SettingsManager.BLOCK_THROTTLE_LIMIT  = 0.92  -- soft throttle cap while blocked (1 = no cap)

local SETTINGS_SPEC = {
    { k = 'enabled',              get = function() return enabled end,              set = function(v) enabled = v end },
    { k = 'debugDraw',            get = function() return debugDraw end,            set = function(v) debugDraw = v end },
    { k = 'drawOnTop',            get = function() return drawOnTop end,            set = function(v) drawOnTop = v end },
    { k = 'DETECT_INNER_M',       get = function() return DETECT_INNER_M end,       set = function(v) DETECT_INNER_M = v end },
    { k = 'DETECT_HYSTERESIS_M',  get = function() return DETECT_HYSTERESIS_M end,  set = function(v) DETECT_HYSTERESIS_M = v end },
    { k = 'MIN_PLAYER_SPEED_KMH', get = function() return MIN_PLAYER_SPEED_KMH end, set = function(v) MIN_PLAYER_SPEED_KMH = v end },
    { k = 'MIN_SPEED_DELTA_KMH',  get = function() return MIN_SPEED_DELTA_KMH end,  set = function(v) MIN_SPEED_DELTA_KMH = v end },
    { k = 'YIELD_OFFSET_M',       get = function() return YIELD_OFFSET_M end,       set = function(v) YIELD_OFFSET_M = v end },
    { k = 'RAMP_SPEED_MPS',       get = function() return RAMP_SPEED_MPS end,       set = function(v) RAMP_SPEED_MPS = v end },
    { k = 'RAMP_RELEASE_MPS',     get = function() return RAMP_RELEASE_MPS end,     set = function(v) RAMP_RELEASE_MPS = v end },
    { k = 'CLEAR_AHEAD_M',        get = function() return CLEAR_AHEAD_M end,        set = function(v) CLEAR_AHEAD_M = v end },
    { k = 'RIGHT_MARGIN_M',       get = function() return RIGHT_MARGIN_M end,       set = function(v) RIGHT_MARGIN_M = v end },
    { k = 'LIST_RADIUS_FILTER_M', get = function() return LIST_RADIUS_FILTER_M end, set = function(v) LIST_RADIUS_FILTER_M = v end },
    { k = 'MIN_AI_SPEED_KMH',     get = function() return MIN_AI_SPEED_KMH end,     set = function(v) MIN_AI_SPEED_KMH = v end },
    { k = 'YIELD_TO_LEFT',        get = function() return YIELD_TO_LEFT end,        set = function(v) YIELD_TO_LEFT = v end },
}

SettingsManager.SETTINGS = {}
SettingsManager.CFG_PATH = nil
SettingsManager.lastSaveOk = false
SettingsManager.lastSaveErr = ''


-- Fast lookup by key for UI code
SettingsManager.SETTINGS_SPEC_BY_KEY = {}
for _, s in ipairs(SETTINGS_SPEC) do SettingsManager.SETTINGS_SPEC_BY_KEY[s.k] = s end

function SettingsManager.settings_apply(t)
    if not t then return end
    for _, s in ipairs(SETTINGS_SPEC) do
        local v = t[s.k]; if v ~= nil then s.set(v) end
    end
    if P then
        for _, s in ipairs(SETTINGS_SPEC) do P[s.k] = s.get() end
    end
end

function SettingsManager.settings_snapshot()
    local out = {}
    for _, s in ipairs(SETTINGS_SPEC) do out[s.k] = s.get() end
    return out
end

function SettingsManager.settings_write(writekv)
    for _, s in ipairs(SETTINGS_SPEC) do writekv(s.k, s.get()) end
end

return SettingsManager;
