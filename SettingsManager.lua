local SettingsManager = {}

SettingsManager.enabled = true
SettingsManager.debugDraw = false
SettingsManager.drawOnTop = false

SettingsManager.detectInner_meters        = 66
SettingsManager.detectHysteresis_meters   = 60.0
SettingsManager.minPlayerSpeed_kmh  = 0.0
SettingsManager.minSpeedDelta_kmh   = 5.0
SettingsManager.yieldOffset_meters        = 2.5
SettingsManager.rampSpeedMps        = 2.0
SettingsManager.rampRelease_mps      = 1.6  -- slower return to center to avoid “snap back” once player is clearly ahead
SettingsManager.clearAhead_meters         = 6.0
SettingsManager.rightMargin_meters        = 0.6
SettingsManager.listRadiusFilter_meters  = 400.0
SettingsManager.minAISpeed_kmh      = 35.0
SettingsManager.yieldToLeft         = false

-- Side-by-side guard: if target side is occupied, don’t cut in — briefly slow down to find a gap
SettingsManager.blockSideLateral_meters      = 2.2   -- lateral threshold (m) to consider another AI “next to” us
SettingsManager.blockSideLongitudinal_meters     = 5.5   -- longitudinal window (m) for “alongside”
SettingsManager.blockSlowdownKmh    = 12.0  -- temporary speed reduction while blocked
SettingsManager.blockThrottleLimit  = 0.92  -- soft throttle cap while blocked (1 = no cap)


local SETTINGS_SPEC = {
    { k = 'enabled',              get = function() return SettingsManager.enabled end,              set = function(v) SettingsManager.enabled = v end },
    { k = 'debugDraw',            get = function() return SettingsManager.debugDraw end,            set = function(v) SettingsManager.debugDraw = v end },
    { k = 'drawOnTop',            get = function() return SettingsManager.drawOnTop end,            set = function(v) SettingsManager.drawOnTop = v end },
    { k = 'detectInner_meters',       get = function() return SettingsManager.detectInner_meters end,       set = function(v) SettingsManager.detectInner_meters = v end },
    { k = 'detectHysteresis_meters',  get = function() return SettingsManager.detectHysteresis_meters end,  set = function(v) SettingsManager.detectHysteresis_meters = v end },
    { k = 'minPlayerSpeed_kmh', get = function() return SettingsManager.minPlayerSpeed_kmh end, set = function(v) SettingsManager.minPlayerSpeed_kmh = v end },
    { k = 'minSpeedDelta_kmh',  get = function() return SettingsManager.minSpeedDelta_kmh end,  set = function(v) SettingsManager.minSpeedDelta_kmh = v end },
    { k = 'yieldOffset_meters',       get = function() return SettingsManager.yieldOffset_meters end,       set = function(v) SettingsManager.yieldOffset_meters = v end },
    { k = 'rampSpeedMps',       get = function() return SettingsManager.rampSpeedMps end,       set = function(v) SettingsManager.rampSpeedMps = v end },
    { k = 'rampRelease_mps',     get = function() return SettingsManager.rampRelease_mps end,     set = function(v) SettingsManager.rampRelease_mps = v end },
    { k = 'clearAhead_meters',        get = function() return SettingsManager.clearAhead_meters end,        set = function(v) SettingsManager.clearAhead_meters = v end },
    { k = 'rightMargin_meters',       get = function() return SettingsManager.rightMargin_meters end,       set = function(v) SettingsManager.rightMargin_meters = v end },
    { k = 'listRadiusFilter_meters', get = function() return SettingsManager.listRadiusFilter_meters end, set = function(v) SettingsManager.listRadiusFilter_meters = v end },
    { k = 'minAISpeed_kmh',     get = function() return SettingsManager.minAISpeed_kmh end,     set = function(v) SettingsManager.minAISpeed_kmh = v end },
    { k = 'yieldToLeft',        get = function() return SettingsManager.yieldToLeft end,        set = function(v) SettingsManager.yieldToLeft = v end },
}

-- Fast lookup by key for UI code
SettingsManager.SETTINGS_SPEC_BY_KEY = {}
for _, s in ipairs(SETTINGS_SPEC) do SettingsManager.SETTINGS_SPEC_BY_KEY[s.k] = s end

-- Storage that survives LAZY unloads
SettingsManager.P = (ac.store and ac.store('AC_AICarsOvertake'))
        or (ac.storage and ac.storage('AC_AICarsOvertake')) or nil


SettingsManager.SETTINGS = {}
SettingsManager.configFilePath = nil
SettingsManager.lastSaveOk = false
SettingsManager.lastSaveErr = ''

-- File persistence
SettingsManager.configResolveNote = "<none>"
SettingsManager.CurrentlyBootloading = true

-- >>> Debounced save (declared before _persist to avoid global/local split)
SettingsManager.saveInterval = 0.5   -- seconds without changes before we write
SettingsManager.autosaveTimer = 0
SettingsManager.settingsCurrentlyDirty = false

local _lazyResolved = false

function SettingsManager.shouldAppRun()
    return
        Constants.CAN_APP_RUN
        and SettingsManager.enabled
end

function SettingsManager._ensureConfig()
    if _lazyResolved and SettingsManager.configFilePath then return end
    if not SettingsManager.configFilePath then
        local p = SettingsManager._userIniPath()
        if p then
            SettingsManager.configFilePath = p
            local wasBoot = SettingsManager.CurrentlyBootloading
            SettingsManager.CurrentlyBootloading = true
            SettingsManager.loadINIFile()

            -- Apply loaded values immediately (so sliders show persisted values)
            SettingsManager.settings_apply(SettingsManager.SETTINGS)

            -- unlock saving *after* values are applied
            SettingsManager.CurrentlyBootloading = false
            if wasBoot == false then SettingsManager.CurrentlyBootloading = false end
            _lazyResolved = true
            return
        end
    else
        _lazyResolved = true
    end
end

function SettingsManager.loadINIFile()
    SettingsManager.SETTINGS = {}
    SettingsManager.configFilePath = SettingsManager._userIniPath()
    if not SettingsManager.configFilePath then return end
    local f = io.open(SettingsManager.configFilePath, "r"); if not f then return end
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

function SettingsManager.saveINIFile()
    Logger.log('Saving to '..tostring(SettingsManager.configFilePath))
    if SettingsManager.CurrentlyBootloading then
         return
    end

    SettingsManager.configFilePath = SettingsManager.configFilePath or SettingsManager._userIniPath()
    if not SettingsManager.configFilePath then
        SettingsManager.lastSaveOk=false; 
        SettingsManager.lastSaveErr='no path';
        return 
    end

    SettingsManager._ensureParentDir(SettingsManager.configFilePath)
    local f, err = io.open(SettingsManager.configFilePath, "w")
    if not f then SettingsManager.lastSaveOk=false; SettingsManager.lastSaveErr=tostring(err or 'open failed'); return end
    local function w(k, v)
        if type(v) == "boolean" then v = v and "true" or "false" end
        f:write(("%s=%s\n"):format(k, tostring(v)))
    end
    -- deduplicated write:
    SettingsManager.settings_write(w)
    f:close()
    SettingsManager.lastSaveOk, SettingsManager.lastSaveErr = true, ''
    Logger.log(('saved %s'):format(SettingsManager.configFilePath))
end

-- Returns absolute path to our INI or nil; also sets CFG_RESOLVE_NOTE
function SettingsManager._userIniPath()
    local function set(p, how)
        if p and #p > 0 then SettingsManager.configResolveNote = how; return p end
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

    SettingsManager.configResolveNote = "<failed>"
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
