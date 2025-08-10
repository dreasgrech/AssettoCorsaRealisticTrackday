-- AC_AICarsOvertake.lua
-- Nudge AI to the RIGHT so the player can pass on the LEFT (Trackday / AI Flood).

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

----------------------------------------------------------------------
-- State
----------------------------------------------------------------------
local enabled, debugDraw, drawOnTop = true, true, true
local ai = {}  -- [i] = { offset, yielding, dist, desired, maxRight, prog, reason, yieldTime }

-- Storage that survives LAZY unloads
local P = (ac.store and ac.store('AC_AICarsOvertake'))
       or (ac.storage and ac.storage('AC_AICarsOvertake')) or nil

-- File persistence
local SETTINGS = {}
local CFG_PATH, lastSaveOk, lastSaveErr = nil, false, ''
local CFG_RESOLVE_NOTE = "<none>"
local BOOT_LOADING = true

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
  local dir = path:match("^(.*)[/\\][^/\\]+$")
  if not dir or dir == '' then return end
  os.execute(('cmd /c mkdir "%s" >nul 2>&1'):format(dir))
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
  w("enabled",               enabled)
  w("debugDraw",             debugDraw)
  w("drawOnTop",             drawOnTop)
  w("DETECT_INNER_M",        DETECT_INNER_M)
  w("DETECT_HYSTERESIS_M",   DETECT_HYSTERESIS_M)
  w("MIN_PLAYER_SPEED_KMH",  MIN_PLAYER_SPEED_KMH)
  w("MIN_SPEED_DELTA_KMH",   MIN_SPEED_DELTA_KMH)
  w("YIELD_OFFSET_M",        YIELD_OFFSET_M)
  w("RAMP_SPEED_MPS",        RAMP_SPEED_MPS)
  w("CLEAR_AHEAD_M",         CLEAR_AHEAD_M)
  w("RIGHT_MARGIN_M",        RIGHT_MARGIN_M)
  w("LIST_RADIUS_FILTER_M",  LIST_RADIUS_FILTER_M)
  f:close()
  lastSaveOk, lastSaveErr = true, ''
  if ac.log then ac.log(('AC_AICarsOvertake: saved %s'):format(CFG_PATH)) end
end

local function _persist(k, v)
  if P then P[k] = v end
  SETTINGS[k] = v
  _saveIni()
end

-- Lazy config resolver
local _lazyResolved = false
local _lastSaved = nil
local SAVE_INTERVAL = 0.5
local _autosaveTimer = 0

local function _snapshot()
  return {
    enabled=enabled, debugDraw=debugDraw, drawOnTop=drawOnTop,
    DETECT_INNER_M=DETECT_INNER_M, DETECT_HYSTERESIS_M=DETECT_HYSTERESIS_M,
    MIN_PLAYER_SPEED_KMH=MIN_PLAYER_SPEED_KMH, MIN_SPEED_DELTA_KMH=MIN_SPEED_DELTA_KMH,
    YIELD_OFFSET_M=YIELD_OFFSET_M, RAMP_SPEED_MPS=RAMP_SPEED_MPS,
    CLEAR_AHEAD_M=CLEAR_AHEAD_M, RIGHT_MARGIN_M=RIGHT_MARGIN_M,
    LIST_RADIUS_FILTER_M=LIST_RADIUS_FILTER_M
  }
end

local function _differs(a,b)
  if not a or not b then return true end
  local function ne(x,y)
    if type(x)=="number" and type(y)=="number" then return math.abs(x-y)>1e-6 end
    return x~=y
  end
  return ne(a.enabled,b.enabled) or ne(a.debugDraw,b.debugDraw) or ne(a.drawOnTop,b.drawOnTop)
      or ne(a.DETECT_INNER_M,b.DETECT_INNER_M) or ne(a.DETECT_HYSTERESIS_M,b.DETECT_HYSTERESIS_M)
      or ne(a.MIN_PLAYER_SPEED_KMH,b.MIN_PLAYER_SPEED_KMH) or ne(a.MIN_SPEED_DELTA_KMH,b.MIN_SPEED_DELTA_KMH)
      or ne(a.YIELD_OFFSET_M,b.YIELD_OFFSET_M) or ne(a.RAMP_SPEED_MPS,b.RAMP_SPEED_MPS)
      or ne(a.CLEAR_AHEAD_M,b.CLEAR_AHEAD_M) or ne(a.RIGHT_MARGIN_M,b.RIGHT_MARGIN_M)
      or ne(a.LIST_RADIUS_FILTER_M,b.LIST_RADIUS_FILTER_M)
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

      -- >>> APPLY LOADED VALUES IMMEDIATELY (so sliders show persisted values)
      local t = SETTINGS
      if t then
        if t.enabled               ~= nil then enabled               = t.enabled               end
        if t.debugDraw             ~= nil then debugDraw             = t.debugDraw             end
        if t.drawOnTop             ~= nil then drawOnTop             = t.drawOnTop             end
        if t.DETECT_INNER_M        ~= nil then DETECT_INNER_M        = t.DETECT_INNER_M        end
        if t.DETECT_HYSTERESIS_M   ~= nil then DETECT_HYSTERESIS_M   = t.DETECT_HYSTERESIS_M   end
        if t.MIN_PLAYER_SPEED_KMH  ~= nil then MIN_PLAYER_SPEED_KMH  = t.MIN_PLAYER_SPEED_KMH  end
        if t.MIN_SPEED_DELTA_KMH   ~= nil then MIN_SPEED_DELTA_KMH   = t.MIN_SPEED_DELTA_KMH   end
        if t.YIELD_OFFSET_M        ~= nil then YIELD_OFFSET_M        = t.YIELD_OFFSET_M        end
        if t.RAMP_SPEED_MPS        ~= nil then RAMP_SPEED_MPS        = t.RAMP_SPEED_MPS        end
        if t.CLEAR_AHEAD_M         ~= nil then CLEAR_AHEAD_M         = t.CLEAR_AHEAD_M         end
        if t.RIGHT_MARGIN_M        ~= nil then RIGHT_MARGIN_M        = t.RIGHT_MARGIN_M        end
        if t.LIST_RADIUS_FILTER_M  ~= nil then LIST_RADIUS_FILTER_M  = t.LIST_RADIUS_FILTER_M  end
        if P then
          P.enabled=enabled; P.debugDraw=debugDraw; P.drawOnTop=drawOnTop
          P.DETECT_INNER_M=DETECT_INNER_M; P.DETECT_HYSTERESIS_M=DETECT_HYSTERESIS_M
          P.MIN_PLAYER_SPEED_KMH=MIN_PLAYER_SPEED_KMH; P.MIN_SPEED_DELTA_KMH=MIN_SPEED_DELTA_KMH
          P.YIELD_OFFSET_M=YIELD_OFFSET_M; P.RAMP_SPEED_MPS=RAMP_SPEED_MPS
          P.CLEAR_AHEAD_M=CLEAR_AHEAD_M; P.RIGHT_MARGIN_M=RIGHT_MARGIN_M; P.LIST_RADIUS_FILTER_M=LIST_RADIUS_FILTER_M
        end
      end
      -- <<< APPLY LOADED VALUES

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

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------
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
local function clampRightOffsetMeters(aiWorldPos, desired)
  if not ac.worldCoordinateToTrackProgress or not ac.getTrackAISplineSides then return desired end
  local prog = ac.worldCoordinateToTrackProgress(aiWorldPos); if prog < 0 then return desired end
  local sides = ac.getTrackAISplineSides(prog) -- vec2(left, right)
  local maxRight = math.max(0, (sides.y or 0) - RIGHT_MARGIN_M)
  return math.max(0, math.min(desired, maxRight)), prog, (sides.y or 0)
end

----------------------------------------------------------------------
-- Decision
----------------------------------------------------------------------
local function desiredOffsetFor(aiCar, playerCar, wasYielding)
  if playerCar.speedKmh < MIN_PLAYER_SPEED_KMH then return 0, nil, nil, nil, 'Player below minimum speed' end
  if (playerCar.speedKmh - aiCar.speedKmh) < MIN_SPEED_DELTA_KMH then return 0, nil, nil, nil, 'No closing speed vs AI' end
  if aiCar.speedKmh < 35.0 then return 0, nil, nil, nil, 'AI speed too low (corner/traffic)' end
  local radius = wasYielding and (DETECT_INNER_M + DETECT_HYSTERESIS_M) or DETECT_INNER_M
  local d = vlen(vsub(playerCar.position, aiCar.position))
  if d > radius then return 0, d, nil, nil, 'Too far (outside detect radius)' end
  if not isBehind(aiCar, playerCar) then return 0, d, nil, nil, 'Player not behind AI' end
  local clamped, prog, rightSide = clampRightOffsetMeters(aiCar.position, YIELD_OFFSET_M)
  if (clamped or 0) <= 0.01 then return 0, d, prog, rightSide, 'No room on the right' end
  return clamped, d, prog, rightSide, 'ok'
end

----------------------------------------------------------------------
-- CSP entry points
----------------------------------------------------------------------
function script.__init__()
  if ac.log then ac.log('AC_AICarsOvertake: init') end
  _loadIni()

  local function applyFrom(t)
    if not t then return end
    if t.enabled               ~= nil then enabled               = t.enabled               end
    if t.debugDraw             ~= nil then debugDraw             = t.debugDraw             end
    if t.drawOnTop             ~= nil then drawOnTop             = t.drawOnTop             end
    if t.DETECT_INNER_M        ~= nil then DETECT_INNER_M        = t.DETECT_INNER_M        end
    if t.DETECT_HYSTERESIS_M   ~= nil then DETECT_HYSTERESIS_M   = t.DETECT_HYSTERESIS_M   end
    if t.MIN_PLAYER_SPEED_KMH  ~= nil then MIN_PLAYER_SPEED_KMH  = t.MIN_PLAYER_SPEED_KMH  end
    if t.MIN_SPEED_DELTA_KMH   ~= nil then MIN_SPEED_DELTA_KMH   = t.MIN_SPEED_DELTA_KMH   end
    if t.YIELD_OFFSET_M        ~= nil then YIELD_OFFSET_M        = t.YIELD_OFFSET_M        end
    if t.RAMP_SPEED_MPS        ~= nil then RAMP_SPEED_MPS        = t.RAMP_SPEED_MPS        end
    if t.CLEAR_AHEAD_M         ~= nil then CLEAR_AHEAD_M         = t.CLEAR_AHEAD_M         end
    if t.RIGHT_MARGIN_M        ~= nil then RIGHT_MARGIN_M        = t.RIGHT_MARGIN_M        end
    if t.LIST_RADIUS_FILTER_M  ~= nil then LIST_RADIUS_FILTER_M  = t.LIST_RADIUS_FILTER_M  end
    if P then
      P.enabled=enabled; P.debugDraw=debugDraw; P.drawOnTop=drawOnTop
      P.DETECT_INNER_M=DETECT_INNER_M; P.DETECT_HYSTERESIS_M=DETECT_HYSTERESIS_M
      P.MIN_PLAYER_SPEED_KMH=MIN_PLAYER_SPEED_KMH; P.MIN_SPEED_DELTA_KMH=MIN_SPEED_DELTA_KMH
      P.YIELD_OFFSET_M=YIELD_OFFSET_M; P.RAMP_SPEED_MPS=RAMP_SPEED_MPS
      P.CLEAR_AHEAD_M=CLEAR_AHEAD_M; P.RIGHT_MARGIN_M=RIGHT_MARGIN_M; P.LIST_RADIUS_FILTER_M=LIST_RADIUS_FILTER_M
    end
  end
  applyFrom(SETTINGS)

  if P then
    if P.enabled               ~= nil then enabled               = P.enabled               end
    if P.debugDraw             ~= nil then debugDraw             = P.debugDraw             end
    if P.drawOnTop             ~= nil then drawOnTop             = P.drawOnTop             end
    if P.DETECT_INNER_M        ~= nil then DETECT_INNER_M        = P.DETECT_INNER_M        end
    if P.DETECT_HYSTERESIS_M   ~= nil then DETECT_HYSTERESIS_M   = P.DETECT_HYSTERESIS_M   end
    if P.MIN_PLAYER_SPEED_KMH  ~= nil then MIN_PLAYER_SPEED_KMH  = P.MIN_PLAYER_SPEED_KMH  end
    if P.MIN_SPEED_DELTA_KMH   ~= nil then MIN_SPEED_DELTA_KMH   = P.MIN_SPEED_DELTA_KMH   end
    if P.YIELD_OFFSET_M        ~= nil then YIELD_OFFSET_M        = P.YIELD_OFFSET_M        end
    if P.RAMP_SPEED_MPS        ~= nil then RAMP_SPEED_MPS        = P.RAMP_SPEED_MPS        end
    if P.CLEAR_AHEAD_M         ~= nil then CLEAR_AHEAD_M         = P.CLEAR_AHEAD_M         end
    if P.RIGHT_MARGIN_M        ~= nil then RIGHT_MARGIN_M        = P.RIGHT_MARGIN_M        end
    if P.LIST_RADIUS_FILTER_M  ~= nil then LIST_RADIUS_FILTER_M  = P.LIST_RADIUS_FILTER_M  end
  end

  _lastSaved = _snapshot()
  BOOT_LOADING = false
end

function script.update(dt)
  _ensureConfig()

  -- autosave if anything changed
  if not BOOT_LOADING and CFG_PATH then
    _autosaveTimer = _autosaveTimer + dt
    if _autosaveTimer >= SAVE_INTERVAL then
      _autosaveTimer = 0
      local now = _snapshot()
      if _differs(now, _lastSaved) then
        _saveIni()
        _lastSaved = now
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
      ai[i] = ai[i] or { offset=0.0, yielding=false, dist=0, desired=0, maxRight=0, prog=-1, reason='-', yieldTime=0 }
      local desired, dist, prog, rightSide, reason = desiredOffsetFor(c, player, ai[i].yielding)
      ai[i].dist = dist or ai[i].dist or 0
      ai[i].desired = desired or 0
      ai[i].prog = prog or -1
      ai[i].maxRight = rightSide or 0
      ai[i].reason = reason or '-'
      if ai[i].yielding and playerIsClearlyAhead(c, player, CLEAR_AHEAD_M) then desired = 0.0 end
      local willYield = (desired or 0) > 0.01
      if willYield then ai[i].yieldTime = (ai[i].yieldTime or 0) + dt end
      ai[i].yielding = willYield
      ai[i].offset = approach(ai[i].offset, desired or 0, RAMP_SPEED_MPS * dt)
      physics.setAISplineAbsoluteOffset(i, ai[i].offset, true)
    end
  end
end

-- manifest [RENDER_CALLBACKS]
function script.Draw3D(dt)
  if not debugDraw then return end
  local sim = ac.getSim(); if not sim then return end
  render.setDepthMode(not drawOnTop, true)
  for i = 1, (sim.carsCount or 0) - 1 do
    local st = ai[i]
    if st and (st.offset or 0) > 0.02 then
      local c = ac.getCar(i)
      if c then
        local txt = string.format("-> %.1fm  (des=%.1f, maxR=%.1f, d=%.1fm)", st.offset, st.desired or 0, st.maxRight or 0, st.dist or 0)
        render.debugText(c.position + vec3(0, 2.0, 0), txt)
      end
    end
  end
end

function script.windowMain(dt)
  _ensureConfig()
  ui.text('AI Cars Overtake — keep right, pass left')
  if CFG_PATH then
    ui.text(string.format('Config: %s  [via %s] %s',
      CFG_PATH, CFG_RESOLVE_NOTE or '?',
      lastSaveOk and '(saved ✓)' or (lastSaveErr ~= '' and ('(save error: '..lastSaveErr..')') or '')
    ))
  else
    ui.text(string.format('Config: <unresolved>  [via %s]', CFG_RESOLVE_NOTE or '?'))
  end

  if ui.checkbox('Enabled', enabled) then enabled = not enabled; _persist('enabled', enabled) end
  tip('Master switch for this app.')

  if ui.checkbox('Debug markers (3D)', debugDraw) then debugDraw = not debugDraw; _persist('debugDraw', debugDraw) end
  tip('Shows floating text above AI cars currently yielding.')

  if ui.checkbox('Draw markers on top (no depth test)', drawOnTop) then drawOnTop = not drawOnTop; _persist('drawOnTop', drawOnTop) end
  tip('If markers are hidden by car bodywork, enable this so text ignores depth testing.')

  ui.separator()
  local v
  v = ui.slider('Detect radius (m)', DETECT_INNER_M, 20, 90);  if v ~= DETECT_INNER_M then DETECT_INNER_M = v; _persist('DETECT_INNER_M', v) end
  tip('Start yielding if the player is within this distance AND behind the AI car.')
  v = ui.slider('Hysteresis (m)', DETECT_HYSTERESIS_M, 20, 120); if v ~= DETECT_HYSTERESIS_M then DETECT_HYSTERESIS_M = v; _persist('DETECT_HYSTERESIS_M', v) end
  tip('Extra distance while yielding so AI doesn’t flicker on/off near threshold.')
  v = ui.slider('Right offset (m)', YIELD_OFFSET_M, 0.5, 4.0);  if v ~= YIELD_OFFSET_M then YIELD_OFFSET_M = v; _persist('YIELD_OFFSET_M', v) end
  tip('How far to move to the right when yielding.')
  v = ui.slider('Right margin (m)', RIGHT_MARGIN_M, 0.3, 1.2); if v ~= RIGHT_MARGIN_M then RIGHT_MARGIN_M = v; _persist('RIGHT_MARGIN_M', v) end
  tip('Safety gap from right edge; target offset is clamped by available width.')
  v = ui.slider('Min player speed (km/h)', MIN_PLAYER_SPEED_KMH, 40, 160); if v ~= MIN_PLAYER_SPEED_KMH then MIN_PLAYER_SPEED_KMH = v; _persist('MIN_PLAYER_SPEED_KMH', v) end
  tip('Ignore very low-speed approaches (pit exits, traffic jams).')
  v = ui.slider('Min speed delta (km/h)', MIN_SPEED_DELTA_KMH, 0, 30); if v ~= MIN_SPEED_DELTA_KMH then MIN_SPEED_DELTA_KMH = v; _persist('MIN_SPEED_DELTA_KMH', v) end
  tip('Require some closing speed before asking AI to yield.')
  v = ui.slider('Offset ramp (m/s)', RAMP_SPEED_MPS, 1.0, 10.0); if v ~= RAMP_SPEED_MPS then RAMP_SPEED_MPS = v; _persist('RAMP_SPEED_MPS', v) end
  tip('Ramp speed of rightward offset change.')

  ui.separator()
  v = ui.slider('List radius filter (m)', LIST_RADIUS_FILTER_M, 0, 1000); if v ~= LIST_RADIUS_FILTER_M then LIST_RADIUS_FILTER_M = v; _persist('LIST_RADIUS_FILTER_M', v) end
  tip('Only show cars within this distance in the list (0 = show all).')

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
            "#%02d  v=%3dkm/h  d=%5.1fm  off=%4.1f  des=%4.1f  maxR=%4.1f  prog=%.3f",
            i, math.floor(c.speedKmh or 0), st.dist or 0, st.offset or 0, st.desired or 0, st.maxRight or 0, st.prog or -1
          )
          if st.yielding then
            if ui.pushStyleColor and ui.StyleColor and ui.popStyleColor then
              ui.pushStyleColor(ui.StyleColor.Text, rgbm(0.2, 0.95, 0.2, 1.0))
              ui.text(base)
              ui.popStyleColor()
            elseif ui.textColored then
              ui.textColored(rgbm(0.2, 0.95, 0.2, 1.0), base)
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
  _saveIni()
end
