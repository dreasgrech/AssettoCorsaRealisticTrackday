local SettingsManager = {}

SettingsManager.enabled = true
SettingsManager.debugDraw = false
SettingsManager.drawOnTop = false

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
    { k = 'enabled',              get = function() return SettingsManager.enabled end,              set = function(v) SettingsManager.enabled = v end },
    { k = 'debugDraw',            get = function() return SettingsManager.debugDraw end,            set = function(v) SettingsManager.debugDraw = v end },
    { k = 'drawOnTop',            get = function() return SettingsManager.drawOnTop end,            set = function(v) SettingsManager.drawOnTop = v end },
    { k = 'DETECT_INNER_M',       get = function() return SettingsManager.DETECT_INNER_M end,       set = function(v) SettingsManager.DETECT_INNER_M = v end },
    { k = 'DETECT_HYSTERESIS_M',  get = function() return SettingsManager.DETECT_HYSTERESIS_M end,  set = function(v) SettingsManager.DETECT_HYSTERESIS_M = v end },
    { k = 'MIN_PLAYER_SPEED_KMH', get = function() return SettingsManager.MIN_PLAYER_SPEED_KMH end, set = function(v) SettingsManager.MIN_PLAYER_SPEED_KMH = v end },
    { k = 'MIN_SPEED_DELTA_KMH',  get = function() return SettingsManager.MIN_SPEED_DELTA_KMH end,  set = function(v) SettingsManager.MIN_SPEED_DELTA_KMH = v end },
    { k = 'YIELD_OFFSET_M',       get = function() return SettingsManager.YIELD_OFFSET_M end,       set = function(v) SettingsManager.YIELD_OFFSET_M = v end },
    { k = 'RAMP_SPEED_MPS',       get = function() return SettingsManager.RAMP_SPEED_MPS end,       set = function(v) SettingsManager.RAMP_SPEED_MPS = v end },
    { k = 'RAMP_RELEASE_MPS',     get = function() return SettingsManager.RAMP_RELEASE_MPS end,     set = function(v) SettingsManager.RAMP_RELEASE_MPS = v end },
    { k = 'CLEAR_AHEAD_M',        get = function() return SettingsManager.CLEAR_AHEAD_M end,        set = function(v) SettingsManager.CLEAR_AHEAD_M = v end },
    { k = 'RIGHT_MARGIN_M',       get = function() return SettingsManager.RIGHT_MARGIN_M end,       set = function(v) SettingsManager.RIGHT_MARGIN_M = v end },
    { k = 'LIST_RADIUS_FILTER_M', get = function() return SettingsManager.LIST_RADIUS_FILTER_M end, set = function(v) SettingsManager.LIST_RADIUS_FILTER_M = v end },
    { k = 'MIN_AI_SPEED_KMH',     get = function() return SettingsManager.MIN_AI_SPEED_KMH end,     set = function(v) SettingsManager.MIN_AI_SPEED_KMH = v end },
    { k = 'YIELD_TO_LEFT',        get = function() return SettingsManager.YIELD_TO_LEFT end,        set = function(v) SettingsManager.YIELD_TO_LEFT = v end },
}

-- Storage that survives LAZY unloads
SettingsManager.P = (ac.store and ac.store('AC_AICarsOvertake'))
        or (ac.storage and ac.storage('AC_AICarsOvertake')) or nil


SettingsManager.SETTINGS = {}
SettingsManager.CFG_PATH = nil
SettingsManager.lastSaveOk = false
SettingsManager.lastSaveErr = ''

-- File persistence
SettingsManager.CFG_RESOLVE_NOTE = "<none>"
SettingsManager.BOOT_LOADING = true

-- >>> Debounced save (declared before _persist to avoid global/local split)
SettingsManager.SAVE_INTERVAL = 0.5   -- seconds without changes before we write
SettingsManager._autosaveTimer = 0
SettingsManager._dirty = false

local _lazyResolved = false

function SettingsManager._ensureConfig()
    if _lazyResolved and SettingsManager.CFG_PATH then return end
    if not SettingsManager.CFG_PATH then
        local p = SettingsManager._userIniPath()
        if p then
            SettingsManager.CFG_PATH = p
            local wasBoot = SettingsManager.BOOT_LOADING
            SettingsManager.BOOT_LOADING = true
            SettingsManager._loadIni()

            -- Apply loaded values immediately (so sliders show persisted values)
            SettingsManager.settings_apply(SettingsManager.SETTINGS)

            -- unlock saving *after* values are applied
            SettingsManager.BOOT_LOADING = false
            if wasBoot == false then SettingsManager.BOOT_LOADING = false end
            _lazyResolved = true
            return
        end
    else
        _lazyResolved = true
    end
end

function SettingsManager._loadIni()
    SettingsManager.SETTINGS = {}
    SettingsManager.CFG_PATH = SettingsManager._userIniPath()
    if not SettingsManager.CFG_PATH then return end
    local f = io.open(SettingsManager.CFG_PATH, "r"); if not f then return end
    for line in f:lines() do
        local k, v = line:match("^%s*([%w_]+)%s*=%s*([^;%s]+)")
        if k and v then
            if v == "true" then v = true
            elseif v == "false" then v = false
            else v = tonumber(v) or v end
            SettingsManager.SETTINGS[k] = v
        end
    end
    f:close()
end

function SettingsManager._saveIni()
    ac.log('AC_AICarsOvertake: saving to '..tostring(SettingsManager.CFG_PATH))
    if SettingsManager.BOOT_LOADING then
         return
    end

    SettingsManager.CFG_PATH = SettingsManager.CFG_PATH or SettingsManager._userIniPath()
    if not SettingsManager.CFG_PATH then
        SettingsManager.lastSaveOk=false; 
        SettingsManager.lastSaveErr='no path';
        return 
    end

    SettingsManager._ensureParentDir(SettingsManager.CFG_PATH)
    local f, err = io.open(SettingsManager.CFG_PATH, "w")
    if not f then SettingsManager.lastSaveOk=false; SettingsManager.lastSaveErr=tostring(err or 'open failed'); return end
    local function w(k, v)
        if type(v) == "boolean" then v = v and "true" or "false" end
        f:write(("%s=%s\n"):format(k, tostring(v)))
    end
    -- deduplicated write:
    SettingsManager.settings_write(w)
    f:close()
    SettingsManager.lastSaveOk, SettingsManager.lastSaveErr = true, ''
    ac.log(('AC_AICarsOvertake: saved %s'):format(SettingsManager.CFG_PATH))
end

-- Returns absolute path to our INI or nil; also sets CFG_RESOLVE_NOTE
function SettingsManager._userIniPath()
    local function set(p, how)
        if p and #p > 0 then SettingsManager.CFG_RESOLVE_NOTE = how; return p end
        return nil
    end

    -- 1) Preferred: Documents\Assetto Corsa\cfg
    if ac and ac.getFolder and ac.FolderID and ac.FolderID.DocumentsAC then
        local ok, docs = pcall(function() return ac.getFolder(ac.FolderID.DocumentsAC) end)
        if ok and docs and #docs > 0 then
            return set(SettingsManager._join(SettingsManager._join(docs, "cfg"), "AC_AICarsOvertake.ini"), "DocumentsAC")
        end
    end
    -- 2) Try Logs→Cfg swap (Docs\Assetto Corsa\logs → \cfg)
    if ac and ac.getFolder and ac.FolderID and ac.FolderID.Logs then
        local ok, logs = pcall(function() return ac.getFolder(ac.FolderID.Logs) end)
        if ok and logs and #logs > 0 then
            local cfgRoot = logs:gsub("[/\\]logs[/\\]?$", "\\cfg")
            if cfgRoot ~= logs then
                return set(SettingsManager._join(cfgRoot, "AC_AICarsOvertake.ini"), "Logs→Cfg")
            end
        end
    end
    -- 3) Fallback: game root → apps\lua\AC_AICarsOvertake\…
    if ac and ac.getFolder and ac.FolderID and ac.FolderID.Root then
        local ok, root = pcall(function() return ac.getFolder(ac.FolderID.Root) end)
        if ok and root and #root > 0 then
            return set(SettingsManager._join(root, "apps\\lua\\AC_AICarsOvertake\\AC_AICarsOvertake.ini"), "Root")
        end
    end
    -- 4) Plain Documents → “Assetto Corsa\cfg”
    if ac and ac.getFolder and ac.FolderID and ac.FolderID.Documents then
        local ok, docs = pcall(function() return ac.getFolder(ac.FolderID.Documents) end)
        if ok and docs and #docs > 0 then
            local acDocs = docs:lower():find("assetto corsa", 1, true) and docs or SettingsManager._join(docs, "Assetto Corsa")
            return set(SettingsManager._join(SettingsManager._join(acDocs, "cfg"), "AC_AICarsOvertake.ini"), "Documents")
        end
    end
    -- 5) OS env fallback
    if os and os.getenv then
        local user = os.getenv('USERPROFILE') or ((os.getenv('HOMEDRIVE') or '')..(os.getenv('HOMEPATH') or ''))
        if user and #user > 0 then
            return set(SettingsManager._join(SettingsManager._join(SettingsManager._join(user, "Documents"), "Assetto Corsa\\cfg"), "AC_AICarsOvertake.ini"), "Env Documents")
        end
    end

    SettingsManager.CFG_RESOLVE_NOTE = "<failed>"
    return nil
end

function SettingsManager._ensureParentDir(path)
    local dir = path:match("^(.*[/\\])[^/\\]+$")
    if not dir or dir == '' then return end
    if os and os.execute then os.execute(('mkdir "%s"'):format(dir)) end
    if ac and ac.executeShell then ac.executeShell(('cmd /c mkdir "%s" >nul 2>&1'):format(dir)) end
    if execute then execute(('cmd /c mkdir "%s" >nul 2>&1'):format(dir)) end
end

-- Path join (supports both / and \)
function SettingsManager._join(a, b)
    if not a or a == '' then return b end
    local last = a:sub(-1); if last == '\\' or last == '/' then return a..b end
    return a..'\\'..b
end

-- Fast lookup by key for UI code
SettingsManager.SETTINGS_SPEC_BY_KEY = {}
for _, s in ipairs(SETTINGS_SPEC) do SettingsManager.SETTINGS_SPEC_BY_KEY[s.k] = s end

function SettingsManager.settings_apply(t)
    if not t then return end
    for _, s in ipairs(SETTINGS_SPEC) do
        local v = t[s.k]; if v ~= nil then s.set(v) end
    end
    if SettingsManager.P then
        for _, s in ipairs(SETTINGS_SPEC) do SettingsManager.P[s.k] = s.get() end
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
