-- AC_AICarsOvertake.lua
-- Nudge AI to one side so the player can pass on the other (Trackday / AI Flood).

----------------------------------------------------------------------
-- Tunables (live-editable in UI)
----------------------------------------------------------------------
local DETECT_INNER_M        = 42.0
local DETECT_HYSTERESIS_M   = 60.0
local MIN_PLAYER_SPEED_KMH  = 70.0
local MIN_SPEED_DELTA_KMH   = 5.0
local YIELD_OFFSET_M        = 2.5
local RAMP_SPEED_MPS        = 4.0
local CLEAR_AHEAD_M         = 6.0
local RIGHT_MARGIN_M        = 0.6
local LIST_RADIUS_FILTER_M  = 400.0
local MIN_AI_SPEED_KMH      = 35.0
local YIELD_TO_LEFT         = false

----------------------------------------------------------------------
-- State
----------------------------------------------------------------------
local enabled, debugDraw, drawOnTop = true, true, true
local ai = {}  -- [i] = { offset, yielding, dist, desired, maxRight, prog, reason, yieldTime, blink }

-- Storage that survives LAZY unloads
local P = (ac.store and ac.store('AC_AICarsOvertake'))
       or (ac.storage and ac.storage('AC_AICarsOvertake')) or nil

-- File persistence
local SETTINGS = {}
local CFG_PATH, lastSaveOk, lastSaveErr = nil, false, ''
local CFG_RESOLVE_NOTE = "<none>"
local BOOT_LOADING = true

-- >>> Debounced save (declared before _persist to avoid global/local split)
local SAVE_INTERVAL = 0.5   -- seconds without changes before we write
local _autosaveTimer = 0
local _dirty = false
-- <<< Debounced save

----------------------------------------------------------------------
-- Centralized settings spec & helpers (NO functional changes)
----------------------------------------------------------------------
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
  { k = 'CLEAR_AHEAD_M',        get = function() return CLEAR_AHEAD_M end,        set = function(v) CLEAR_AHEAD_M = v end },
  { k = 'RIGHT_MARGIN_M',       get = function() return RIGHT_MARGIN_M end,       set = function(v) RIGHT_MARGIN_M = v end },
  { k = 'LIST_RADIUS_FILTER_M', get = function() return LIST_RADIUS_FILTER_M end, set = function(v) LIST_RADIUS_FILTER_M = v end },
  { k = 'MIN_AI_SPEED_KMH',     get = function() return MIN_AI_SPEED_KMH end,     set = function(v) MIN_AI_SPEED_KMH = v end },
  { k = 'YIELD_TO_LEFT',        get = function() return YIELD_TO_LEFT end,        set = function(v) YIELD_TO_LEFT = v end },
}

-- Fast lookup by key for UI code
local SETTINGS_SPEC_BY_KEY = {}
for _, s in ipairs(SETTINGS_SPEC) do SETTINGS_SPEC_BY_KEY[s.k] = s end

local function settings_apply(t)
  if not t then return end
  for _, s in ipairs(SETTINGS_SPEC) do
    local v = t[s.k]; if v ~= nil then s.set(v) end
  end
  if P then
    for _, s in ipairs(SETTINGS_SPEC) do P[s.k] = s.get() end
  end
end

local function settings_snapshot()
  local out = {}
  for _, s in ipairs(SETTINGS_SPEC) do out[s.k] = s.get() end
  return out
end

local function settings_write(writekv)
  for _, s in ipairs(SETTINGS_SPEC) do writekv(s.k, s.get()) end
end

local function settings_differs(a, b)
  if not a or not b then return true end
  for _, s in ipairs(SETTINGS_SPEC) do
    local va, vb = a[s.k], b[s.k]
    if type(va) == 'number' and type(vb) == 'number' then
      if math.abs(va - vb) > 1e-6 then return true end
    else
      if va ~= vb then return true end
    end
  end
  return false
end

----------------------------------------------------------------------
-- Path helpers & INI I/O
----------------------------------------------------------------------
local function _join(a, b)
  if not a or a == '' then return b end
  local last = a:sub(-1); if last == '\\' or last == '/' then return a..b end
  return a..'\\'..b
end

-- Returns absolute path to our INI or nil; also sets CFG_RESOLVE_NOTE
local function _userIniPath()
  local function set(p, how)
    if p and #p > 0 then CFG_RESOLVE_NOTE = how; return p end
    return nil
  end

  -- 1) Preferred: Documents\Assetto Corsa\cfg
  if ac and ac.getFolder and ac.FolderID and ac.FolderID.DocumentsAC then
    local ok, docs = pcall(function() return ac.getFolder(ac.FolderID.DocumentsAC) end)
    if ok and docs and #docs > 0 then
      return set(_join(_join(docs, "cfg"), "AC_AICarsOvertake.ini"), "DocumentsAC")
    end
  end
  -- 2) Try Logs→Cfg swap (Docs\Assetto Corsa\logs → \cfg)
  if ac and ac.getFolder and ac.FolderID and ac.FolderID.Logs then
    local ok, logs = pcall(function() return ac.getFolder(ac.FolderID.Logs) end)
    if ok and logs and #logs > 0 then
      local cfgRoot = logs:gsub("[/\\]logs[/\\]?$", "\\cfg")
      if cfgRoot ~= logs then
        return set(_join(cfgRoot, "AC_AICarsOvertake.ini"), "Logs→Cfg")
      end
    end
  end
  -- 3) Fallback: game root → apps\lua\AC_AICarsOvertake\…
  if ac and ac.getFolder and ac.FolderID and ac.FolderID.Root then
    local ok, root = pcall(function() return ac.getFolder(ac.FolderID.Root) end)
    if ok and root and #root > 0 then
      return set(_join(root, "apps\\lua\\AC_AICarsOvertake\\AC_AICarsOvertake.ini"), "Root")
    end
  end
  -- 4) Plain Documents → “Assetto Corsa\cfg”
  if ac and ac.getFolder and ac.FolderID and ac.FolderID.Documents then
    local ok, docs = pcall(function() return ac.getFolder(ac.FolderID.Documents) end)
    if ok and docs and #docs > 0 then
      local acDocs = docs:lower():find("assetto corsa", 1, true) and docs or _join(docs, "Assetto Corsa")
      return set(_join(_join(acDocs, "cfg"), "AC_AICarsOvertake.ini"), "Documents")
    end
  end
  -- 5) OS env fallback
  if os and os.getenv then
    local user = os.getenv('USERPROFILE') or ((os.getenv('HOMEDRIVE') or '')..(os.getenv('HOMEPATH') or ''))
    if user and #user > 0 then
      return set(_join(_join(_join(user, "Documents"), "Assetto Corsa\\cfg"), "AC_AICarsOvertake.ini"), "Env Documents")
    end
  end

  CFG_RESOLVE_NOTE = "<failed>"
  return nil
end

local function _ensureParentDir(path)
  local dir = path:match("^(.*[/\\])[^/\\]+$")
  if not dir or dir == '' then return end
  if os and os.execute then os.execute(('mkdir "%s"'):format(dir)) end
  if ac and ac.executeShell then ac.executeShell(('cmd /c mkdir "%s" >nul 2>&1'):format(dir)) end
  if execute then execute(('cmd /c mkdir "%s" >nul 2>&1'):format(dir)) end
end

local function _loadIni()
  SETTINGS = {}
  CFG_PATH = _userIniPath()
  if not CFG_PATH then return end
  local f = io.open(CFG_PATH, "r"); if not f then return end
  for line in f:lines() do
    local k, v = line:match("^%s*([%w_]+)%s*=%s*([^;%s]+)")
    if k and v then
      if v == "true" then v = true
      elseif v == "false" then v = false
      else v = tonumber(v) or v end
      SETTINGS[k] = v
    end
  end
  f:close()
end

local function _saveIni()
  if ac and ac.log then ac.log('AC_AICarsOvertake: saving to '..tostring(CFG_PATH)) end
  if BOOT_LOADING then return end
  CFG_PATH = CFG_PATH or _userIniPath()
  if not CFG_PATH then lastSaveOk=false; lastSaveErr='no path'; return end
  _ensureParentDir(CFG_PATH)
  local f, err = io.open(CFG_PATH, "w")
  if not f then lastSaveOk=false; lastSaveErr=tostring(err or 'open failed'); return end
  local function w(k, v)
    if type(v) == "boolean" then v = v and "true" or "false" end
    f:write(("%s=%s\n"):format(k, tostring(v)))
  end
  -- deduplicated write:
  settings_write(w)
  f:close()
  lastSaveOk, lastSaveErr = true, ''
  if ac.log then ac.log(('AC_AICarsOvertake: saved %s'):format(CFG_PATH)) end
end

-- DEBOUNCED PERSIST: mark dirty and coalesce writes in update()
local function _persist(k, v)
  if P then P[k] = v end
  SETTINGS[k] = v
  _dirty = true
  _autosaveTimer = 0
end

-- Lazy config resolver
local _lazyResolved = false
local _lastSaved = nil

local function _snapshot()
  return settings_snapshot()   -- deduplicated snapshot
end

local function _differs(a,b)
  return settings_differs(a, b)  -- deduplicated compare
end

local function _ensureConfig()
  if _lazyResolved and CFG_PATH then return end
  if not CFG_PATH then
    local p = _userIniPath()
    if p then
      CFG_PATH = p
      local wasBoot = BOOT_LOADING
      BOOT_LOADING = true
      _loadIni()

      -- Apply loaded values immediately (so sliders show persisted values)
      settings_apply(SETTINGS)

      -- unlock saving *after* values are applied
      BOOT_LOADING = false
      _lastSaved = _snapshot()
      if wasBoot == false then BOOT_LOADING = false end
      _lazyResolved = true
      return
    end
  else
    _lazyResolved = true
  end
end

local function vsub(a,b) return vec3(a.x-b.x, a.y-b.y, a.z-b.z) end
local function vlen(v) return math.sqrt(v.x*v.x + v.y*v.y + v.z*v.z) end
local function dot(a,b) return a.x*b.x + a.y*b.y + a.z*b.z end
local function approach(curr, target, step)
  if math.abs(target - curr) <= step then return target end
  return curr + (target > curr and step or -step)
end

local function isBehind(aiCar, playerCar)
  local fwd = aiCar.look or aiCar.forward or vec3(0,0,1)
  local rel = vsub(playerCar.position, aiCar.position)
  return dot(fwd, rel) < 0
end

local function playerIsClearlyAhead(aiCar, playerCar, meters)
  local fwd = aiCar.look or aiCar.forward or vec3(0,0,1)
  local rel = vsub(playerCar.position, aiCar.position)
  return dot(fwd, rel) > meters
end

-- Tooltip helper that works across CSP builds
local function tip(text)
  local hovered=false; if ui and ui.itemHovered then local ok,res=pcall(ui.itemHovered); hovered=ok and res or false end
  if not hovered then return end
  local fn = ui and (ui.setTooltip or ui.tooltip or ui.toolTip)
  if fn then pcall(fn, text); return end
  local b = ui and (ui.beginTooltip or ui.beginItemTooltip)
  local e = ui and (ui.endTooltip or ui.endItemTooltip)
  if b and e and pcall(b) then if ui.textWrapped then ui.textWrapped(text) else ui.text(text) end pcall(e) end
end

----------------------------------------------------------------------
-- Trackside clamping
----------------------------------------------------------------------
local function clampSideOffsetMeters(aiWorldPos, desired, sideSign)
  if not ac.worldCoordinateToTrackProgress or not ac.getTrackAISplineSides then return desired end
  local prog = ac.worldCoordinateToTrackProgress(aiWorldPos); if prog < 0 then return desired end
  local sides = ac.getTrackAISplineSides(prog) -- vec2(left, right)
  if sideSign > 0 then
    local maxRight = math.max(0, (sides.y or 0) - RIGHT_MARGIN_M)
    local clamped  = math.max(0, math.min(desired, maxRight))
    return clamped, prog, maxRight
  else
    local maxLeft  = math.max(0, (sides.x or 0) - RIGHT_MARGIN_M)
    local clamped  = math.min(0, math.max(desired, -maxLeft))
    return clamped, prog, maxLeft
  end
end

----------------------------------------------------------------------
-- Decision
----------------------------------------------------------------------
local function desiredOffsetFor(aiCar, playerCar, wasYielding)
  if playerCar.speedKmh < MIN_PLAYER_SPEED_KMH then return 0, nil, nil, nil, 'Player below minimum speed' end
  if (playerCar.speedKmh - aiCar.speedKmh) < MIN_SPEED_DELTA_KMH then return 0, nil, nil, nil, 'No closing speed vs AI' end
  if aiCar.speedKmh < MIN_AI_SPEED_KMH then return 0, nil, nil, nil, 'AI speed too low (corner/traffic)' end
  local radius = wasYielding and (DETECT_INNER_M + DETECT_HYSTERESIS_M) or DETECT_INNER_M
  local d = vlen(vsub(playerCar.position, aiCar.position))
  if d > radius then return 0, d, nil, nil, 'Too far (outside detect radius)' end
  if not isBehind(aiCar, playerCar) then return 0, d, nil, nil, 'Player not behind AI' end

  local sideSign = YIELD_TO_LEFT and -1 or 1
  local target   = sideSign * YIELD_OFFSET_M
  local clamped, prog, sideMax = clampSideOffsetMeters(aiCar.position, target, sideSign)
  if (sideSign > 0 and (clamped or 0) <= 0.01) or (sideSign < 0 and (clamped or 0) >= -0.01) then
    return 0, d, prog, sideMax, 'No room on chosen side'
  end
  return clamped, d, prog, sideMax, 'ok'
end

----------------------------------------------------------------------
-- CSP entry points
----------------------------------------------------------------------
function script.__init__()
  if ac.log then ac.log('AC_AICarsOvertake: init') end
  _loadIni()

  -- Apply values from INI and storage (keeps UI in sync on start)
  settings_apply(SETTINGS)
  settings_apply(P)

  _lastSaved = settings_snapshot()
  BOOT_LOADING = false
end

local function _indModeForYielding(willYield)
  local TL = ac and ac.TurningLights
  if willYield then
    return TL and ((YIELD_TO_LEFT and TL.Left) or TL.Right) or ((YIELD_TO_LEFT and 1) or 2)
  end
  return TL and TL.None or 0
end

local function _applyIndicators(i, willYield, car, st)
  if not (ac and ac.setTurningLights and ac.setTargetCar) then return end
  local mode = _indModeForYielding(willYield)
  if ac.setTargetCar(i) then
    ac.setTurningLights(mode)
    ac.setTargetCar(0)
    st.blink = mode
  end
  st.indLeft = car.turningLeftLights or false
  st.indRight = car.turningRightLights or false
  st.indPhase = car.turningLightsActivePhase or false
  st.hasTL = car.hasTurningLights or false
end

function script.update(dt)
  _ensureConfig()

  -- Debounced autosave: write once after no changes for SAVE_INTERVAL
  if not BOOT_LOADING and CFG_PATH then
    if _dirty then
      _autosaveTimer = _autosaveTimer + dt
      if _autosaveTimer >= SAVE_INTERVAL then
        _saveIni()
        _lastSaved = settings_snapshot()
        _dirty = false
      end
    end
  end

  if not enabled then return end
  if not physics or not physics.setAISplineAbsoluteOffset then return end
  local sim = ac.getSim(); if not sim then return end
  local player = ac.getCar(0); if not player then return end

  for i = 1, (sim.carsCount or 0) - 1 do
    local c = ac.getCar(i)
    if c and c.isAIControlled ~= false then
      ai[i] = ai[i] or { offset=0.0, yielding=false, dist=0, desired=0, maxRight=0, prog=-1, reason='-', yieldTime=0, blink=nil }
      local desired, dist, prog, sideMax, reason = desiredOffsetFor(c, player, ai[i].yielding)
      ai[i].dist = dist or ai[i].dist or 0
      ai[i].desired = desired or 0
      ai[i].prog = prog or -1
      ai[i].maxRight = sideMax or 0
      ai[i].reason = reason or '-'
      if ai[i].yielding and playerIsClearlyAhead(c, player, CLEAR_AHEAD_M) then desired = 0.0 end
      local willYield = math.abs(desired or 0) > 0.01
      if willYield then ai[i].yieldTime = (ai[i].yieldTime or 0) + dt end
      ai[i].yielding = willYield
      ai[i].offset = approach(ai[i].offset, desired or 0, RAMP_SPEED_MPS * dt)
      physics.setAISplineAbsoluteOffset(i, ai[i].offset, true)
      _applyIndicators(i, willYield, c, ai[i])
    end
  end
end

local function _indicatorStatusText(st)
  local l = st.indLeft
  local r = st.indRight
  local ph = st.indPhase
  local indTxt = '-'
  if l or r then
    if l and r then
      indTxt = ph and 'H*' or 'H'
    elseif l then
      indTxt = ph and 'L*' or 'L'
    else
      indTxt = ph and 'R*' or 'R'
    end
  end
  if st.hasTL == false then indTxt = indTxt .. '(!)' end
  return indTxt
end

-- manifest [RENDER_CALLBACKS]
function script.Draw3D(dt)
  if not debugDraw then return end
  local sim = ac.getSim(); if not sim then return end
  if drawOnTop then
    -- draw over everything (no depth testing)
    render.setDepthMode(render.DepthMode.Off)
  else
    -- respect existing depth, don’t write to depth (debug text won’t “punch holes”)
    render.setDepthMode(render.DepthMode.ReadOnlyLessEqual)
  end
  for i = 1, (sim.carsCount or 0) - 1 do
    local st = ai[i]
    if st and (math.abs(st.offset or 0) > 0.02) then
      local c = ac.getCar(i)
      if c then
        local txt = string.format("-> %.1fm  (des=%.1f, max=%.1f, d=%.1fm)", st.offset, st.desired or 0, st.maxRight or 0, st.dist or 0)
        do
          local indTxt = _indicatorStatusText(st)
          txt = txt .. string.format("  ind=%s", indTxt)
        end
        render.debugText(c.position + vec3(0, 2.0, 0), txt)
      end
    end
  end
  render.setDepthMode(render.DepthMode.Normal)
end

local UI_ELEMENTS = {
  { kind='checkbox', k='enabled',   label='Enabled', tip='Master switch for this app.' },
  { kind='checkbox', k='debugDraw', label='Debug markers (3D)', tip='Shows floating text above AI cars currently yielding.' },
  { kind='checkbox', k='drawOnTop', label='Draw markers on top (no depth test)', tip='If markers are hidden by car bodywork, enable this so text ignores depth testing.' },
  { kind='slider',   k='DETECT_INNER_M', label='Detect radius (m)', min=20,  max=90, tip='Start yielding if the player is within this distance AND behind the AI car.' },
  { kind='slider',   k='DETECT_HYSTERESIS_M', label='Hysteresis (m)', min=20, max=120, tip='Extra distance while yielding so AI doesn’t flicker on/off near threshold.' },
  { kind='slider',   k='YIELD_OFFSET_M', label='Side offset (m)', min=0.5, max=4.0, tip='How far to move towards the chosen side when yielding.' },
  { kind='slider',   k='RIGHT_MARGIN_M', label='Edge margin (m)', min=0.3, max=1.2, tip='Safety gap from the outer edge on the chosen side.' },
  { kind='slider',   k='MIN_PLAYER_SPEED_KMH', label='Min player speed (km/h)', min=40, max=160, tip='Ignore very low-speed approaches (pit exits, traffic jams).' },
  { kind='slider',   k='MIN_SPEED_DELTA_KMH',  label='Min speed delta (km/h)', min=0,  max=30, tip='Require some closing speed before asking AI to yield.' },
  { kind='slider',   k='RAMP_SPEED_MPS', label='Offset ramp (m/s)', min=1.0, max=10.0, tip='Ramp speed of offset change.' },
  { kind='slider',   k='LIST_RADIUS_FILTER_M', label='List radius filter (m)', min=0, max=1000, tip='Only show cars within this distance in the list (0 = show all).' },
  { kind='slider',   k='MIN_AI_SPEED_KMH', label='Min AI speed (km/h)', min=0, max=120, tip='Don’t ask AI to yield if its own speed is below this (corners/traffic).' },
  { kind='checkbox', k='YIELD_TO_LEFT', label='Yield to LEFT (instead of RIGHT)', tip='If enabled, AI moves left to let you pass on the right. Otherwise AI moves right so you pass on the left.' },
}

local function drawControls()
  for _, e in ipairs(UI_ELEMENTS) do
    local spec = SETTINGS_SPEC_BY_KEY[e.k]
    if spec then
      if e.kind == 'checkbox' then
        local cur = spec.get()
        if ui.checkbox(e.label, cur) then
          local new = not cur
          spec.set(new)
          _persist(e.k, new)
        end
        tip(e.tip)
      elseif e.kind == 'slider' then
        local cur = spec.get()
        local new = ui.slider(e.label, cur, e.min, e.max)
        if new ~= cur then
          spec.set(new)
          _persist(e.k, new)
        end
        tip(e.tip)
      end
    end
  end
end

function script.windowMain(dt)
  _ensureConfig()
  ui.text(string.format('AI Cars Overtake — yield %s', (YIELD_TO_LEFT and 'LEFT') or 'RIGHT'))
  if CFG_PATH then
    ui.text(string.format('Config: %s  [via %s] %s',
      CFG_PATH, CFG_RESOLVE_NOTE or '?',
      lastSaveOk and '(saved ✓)' or (lastSaveErr ~= '' and ('(save error: '..lastSaveErr..')') or '')
    ))
  else
    ui.text(string.format('Config: <unresolved>  [via %s]', CFG_RESOLVE_NOTE or '?'))
  end

  drawControls()

  ui.separator()
  local sim = ac.getSim()
  local totalAI, yieldingCount = 0, 0
  if sim then
    totalAI = math.max(0, (sim.carsCount or 1) - 1)
    for i = 1, totalAI do if ai[i] and ai[i].yielding then yieldingCount = yieldingCount + 1 end end
  end
  ui.text(string.format('Yielding: %d / %d', yieldingCount, totalAI))

  ui.text('Cars:')
  local player = ac.getCar(0)
  if sim and player then
    for i = 1, totalAI do
      local c = ac.getCar(i); local st = ai[i]
      if c and st then
        local show = (LIST_RADIUS_FILTER_M <= 0) or ((st.dist or 0) <= LIST_RADIUS_FILTER_M)
        if show then
          local base = string.format(
            "#%02d  v=%3dkm/h  d=%5.1fm  off=%4.1f  des=%4.1f  max=%4.1f  prog=%.3f",
            i, math.floor(c.speedKmh or 0), st.dist or 0, st.offset or 0, st.desired or 0, st.maxRight or 0, st.prog or -1
          )
          do
            local indTxt = _indicatorStatusText(st)
            base = base .. string.format("  ind=%s", indTxt)
          end
          if st.yielding then
            if ui.pushStyleColor and ui.StyleColor and ui.popStyleColor then
              ui.pushStyleColor(ui.StyleColor.Text, rgbm(0.2, 0.95, 0.2, 1.0))
              ui.text(base)
              ui.popStyleColor()
            elseif ui.textColored then
              ui.textColored(base, rgbm(0.2, 0.95, 0.2, 1.0))
            else
              ui.text(base)
            end
            ui.sameLine(); ui.text(string.format("  (yield %.1fs)", st.yieldTime or 0))
          else
            local reason = st.reason or '-'
            ui.text(string.format("%s  reason: %s", base, reason))
          end
        end
      end
    end
  end
end

-- Save when window is closed/hidden as a last resort
function script.onHide()
  if _dirty then _saveIni(); _lastSaved = settings_snapshot(); _dirty = false end
end
