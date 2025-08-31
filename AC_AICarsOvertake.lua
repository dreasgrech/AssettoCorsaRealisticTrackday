-- AC_AICarsOvertake.lua
-- Nudge AI to one side so the player can pass on the other (Trackday / AI Flood).

SettingsManager = require("SettingsManager")
MathHelpers = require("MathHelpers")

----------------------------------------------------------------------
-- State
----------------------------------------------------------------------
local enabled, debugDraw, drawOnTop = true, true, true
local ai = {}  -- [i] = { offset, yielding, dist, desired, maxRight, prog, reason, yieldTime, blink }

----------------------------------------------------------------------
-- Centralized settings spec & helpers (NO functional changes)
----------------------------------------------------------------------
-- Returns absolute path to our INI or nil; also sets CFG_RESOLVE_NOTE
local function _userIniPath()
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

local function _loadIni()
  SettingsManager.SETTINGS = {}
  SettingsManager.CFG_PATH = _userIniPath()
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

local function _saveIni()
  if ac and ac.log then ac.log('AC_AICarsOvertake: saving to '..tostring(SettingsManager.CFG_PATH)) end
  if SettingsManager.BOOT_LOADING then return end
  SettingsManager.CFG_PATH = SettingsManager.CFG_PATH or _userIniPath()
  if not SettingsManager.CFG_PATH then SettingsManager.lastSaveOk=false; SettingsManager.lastSaveErr='no path'; return end
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
  if ac.log then ac.log(('AC_AICarsOvertake: saved %s'):format(SettingsManager.CFG_PATH)) end
end

-- DEBOUNCED PERSIST: mark dirty and coalesce writes in update()
local function _persist(k, v)
  if SettingsManager.P then SettingsManager.P[k] = v end
  SettingsManager.SETTINGS[k] = v
  SettingsManager._dirty = true
  SettingsManager._autosaveTimer = 0
end

-- Lazy config resolver
local _lazyResolved = false

local function _ensureConfig()
  if _lazyResolved and SettingsManager.CFG_PATH then return end
  if not SettingsManager.CFG_PATH then
    local p = _userIniPath()
    if p then
      SettingsManager.CFG_PATH = p
      local wasBoot = SettingsManager.BOOT_LOADING
      SettingsManager.BOOT_LOADING = true
      _loadIni()

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

local function isBehind(aiCar, playerCar)
  local fwd = aiCar.look or aiCar.forward or vec3(0,0,1)
  local rel = MathHelpers.vsub(playerCar.position, aiCar.position)
  return MathHelpers.dot(fwd, rel) < 0
end

local function playerIsClearlyAhead(aiCar, playerCar, meters)
  local fwd = aiCar.look or aiCar.forward or vec3(0,0,1)
  local rel = MathHelpers.vsub(playerCar.position, aiCar.position)
  return MathHelpers.dot(fwd, rel) > meters
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

-- Check if target side of car i is occupied by another AI alongside (prevents unsafe lateral move)
local function _isTargetSideBlocked(i, sideSign)
  local me = ac.getCar(i); if not me then return false end
  local sim = ac.getSim(); if not sim then return false end
  local mySide = me.side or vec3(1,0,0)
  local myLook = me.look or vec3(0,0,1)
  for j = 1, (sim.carsCount or 0) - 1 do
    if j ~= i then
      local o = ac.getCar(j)
      if o and o.isAIControlled ~= false then
        local rel = MathHelpers.vsub(o.position, me.position)
        local lat = MathHelpers.dot(rel, mySide)   -- + right, - left
        local fwd = MathHelpers.dot(rel, myLook)   -- + ahead, - behind
        if lat*sideSign > 0 and math.abs(lat) <= SettingsManager.BLOCK_SIDE_LAT_M and math.abs(fwd) <= SettingsManager.BLOCK_SIDE_LONG_M then
          return true, j
        end
      end
    end
  end
  return false
end

----------------------------------------------------------------------
-- Trackside clamping
----------------------------------------------------------------------
local function clampSideOffsetMeters(aiWorldPos, desired, sideSign)
  if not ac.worldCoordinateToTrackProgress or not ac.getTrackAISplineSides then return desired end
  local prog = ac.worldCoordinateToTrackProgress(aiWorldPos); if prog < 0 then return desired end
  local sides = ac.getTrackAISplineSides(prog) -- vec2(left, right)
  if sideSign > 0 then
    local maxRight = math.max(0, (sides.y or 0) - SettingsManager.RIGHT_MARGIN_M)
    local clamped  = math.max(0, math.min(desired, maxRight))
    return clamped, prog, maxRight
  else
    local maxLeft  = math.max(0, (sides.x or 0) - SettingsManager.RIGHT_MARGIN_M)
    local clamped  = math.min(0, math.max(desired, -maxLeft))
    return clamped, prog, maxLeft
  end
end

----------------------------------------------------------------------
-- Decision
----------------------------------------------------------------------
local function desiredOffsetFor(aiCar, playerCar, wasYielding)
  if playerCar.speedKmh < SettingsManager.MIN_PLAYER_SPEED_KMH then return 0, nil, nil, nil, 'Player below minimum speed' end

  -- If cars are abeam (neither clearly behind nor clearly ahead), or we’re already yielding and
  -- player isn’t clearly ahead yet, ignore closing-speed — yielding must persist mid-pass.
  local behind = isBehind(aiCar, playerCar)
  local aheadClear = playerIsClearlyAhead(aiCar, playerCar, SettingsManager.CLEAR_AHEAD_M)
  local sideBySide = (not behind) and (not aheadClear)
  local ignoreDelta = sideBySide or (wasYielding and not aheadClear)

  if not ignoreDelta and (playerCar.speedKmh - aiCar.speedKmh) < SettingsManager.MIN_SPEED_DELTA_KMH then
    return 0, nil, nil, nil, 'No closing speed vs AI'
  end

  if aiCar.speedKmh < SettingsManager.MIN_AI_SPEED_KMH then return 0, nil, nil, nil, 'AI speed too low (corner/traffic)' end

  local radius = wasYielding and (SettingsManager.DETECT_INNER_M + SettingsManager.DETECT_HYSTERESIS_M) or SettingsManager.DETECT_INNER_M
  local d = MathHelpers.vlen(MathHelpers.vsub(playerCar.position, aiCar.position))
  if d > radius then return 0, d, nil, nil, 'Too far (outside detect radius)' end

  -- Keep yielding even if the player pulls alongside; only stop once the player is clearly ahead.
  if not behind then
    if wasYielding and not aheadClear then
      -- continue yielding through the pass; fall through to compute side offset
    else
      return 0, d, nil, nil, 'Player not behind (clear)'
    end
  end

  local sideSign = SettingsManager.YIELD_TO_LEFT and -1 or 1
  local target   = sideSign * SettingsManager.YIELD_OFFSET_M
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
  SettingsManager.settings_apply(SettingsManager.SETTINGS)
  SettingsManager.settings_apply(SettingsManager.P)

  SettingsManager.BOOT_LOADING = false
end

local function _indModeForYielding(willYield)
  local TL = ac and ac.TurningLights
  if willYield then
    return TL and ((SettingsManager.YIELD_TO_LEFT and TL.Left) or TL.Right) or ((SettingsManager.YIELD_TO_LEFT and 1) or 2)
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
  if not SettingsManager.BOOT_LOADING and SettingsManager.CFG_PATH then
    if SettingsManager._dirty then
      SettingsManager._autosaveTimer = SettingsManager._autosaveTimer + dt
      if SettingsManager._autosaveTimer >= SettingsManager.SAVE_INTERVAL then
        _saveIni()
        SettingsManager._dirty = false
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
      ai[i] = ai[i] or { offset=0.0, yielding=false, dist=0, desired=0, maxRight=0, prog=-1, reason='-', yieldTime=0, blink=nil, blocked=false, blocker=nil }
      local desired, dist, prog, sideMax, reason = desiredOffsetFor(c, player, ai[i].yielding)

      ai[i].dist = dist or ai[i].dist or 0
      ai[i].prog = prog or -1
      ai[i].maxRight = sideMax or 0
      ai[i].reason = reason or '-'

      -- Release logic: ease desired to 0 once the player is clearly ahead
      local releasing = false
      if ai[i].yielding and playerIsClearlyAhead(c, player, SettingsManager.CLEAR_AHEAD_M) then
        releasing = true
      end

      -- Side-by-side guard: if the target side is occupied, don’t cut in — create space first
      local sideSign = SettingsManager.YIELD_TO_LEFT and -1 or 1
      local intendsSideMove = desired and math.abs(desired) > 0.01
      local blocked, blocker = false, nil
      if intendsSideMove then
        blocked, blocker = _isTargetSideBlocked(i, sideSign)
      end
      ai[i].blocked = blocked
      ai[i].blocker = blocker

      local targetDesired
      if blocked and not releasing then
        -- keep indicators on, but don’t move laterally yet
        targetDesired = MathHelpers.approach((ai[i].desired or desired or 0), 0.0, SettingsManager.RAMP_RELEASE_MPS * dt)
      elseif releasing then
        targetDesired = MathHelpers.approach((ai[i].desired or desired or 0), 0.0, SettingsManager.RAMP_RELEASE_MPS * dt)
      else
        targetDesired = desired or 0
      end
      ai[i].desired = targetDesired

      -- Keep yielding (blinkers) while blocked to signal intent
      local willYield = (blocked and intendsSideMove) or (math.abs(targetDesired) > 0.01)
      if willYield then ai[i].yieldTime = (ai[i].yieldTime or 0) + dt end
      ai[i].yielding = willYield

      -- Apply offset with appropriate ramp (slower when releasing or blocked)
      local stepMps = (releasing or blocked) and SettingsManager.RAMP_RELEASE_MPS or SettingsManager.RAMP_SPEED_MPS
      ai[i].offset = MathHelpers.approach(ai[i].offset, targetDesired, stepMps * dt)
      physics.setAISplineAbsoluteOffset(i, ai[i].offset, true)

      -- Temporarily cap speed if blocked to create a gap; remove caps otherwise
      if blocked and intendsSideMove then
        local cap = math.max((c.speedKmh or 0) - SettingsManager.BLOCK_SLOWDOWN_KMH, 5)
        if physics.setAITopSpeed then physics.setAITopSpeed(i, cap) end
        if physics.setAIThrottleLimit then physics.setAIThrottleLimit(i, SettingsManager.BLOCK_THROTTLE_LIMIT) end
        ai[i].reason = 'Blocked by car on side'
      else
        if physics.setAITopSpeed then physics.setAITopSpeed(i, 1e9) end
        if physics.setAIThrottleLimit then physics.setAIThrottleLimit(i, 1) end
      end

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
  if st.blocked then
    -- explicitly show that we’re not able to move over yet and are slowing to create space
    indTxt = (indTxt ~= '-' and (indTxt .. ' ') or '') .. '(slowing due to yield lane blocked)'
  end
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
    if st and (math.abs(st.offset or 0) > 0.02 or st.blocked) then
      local c = ac.getCar(i)
      if c then
        local txt = string.format(
          "#%02d d=%5.1fm  v=%3dkm/h  offset=%4.1f",
          i, st.dist, math.floor(c.speedKmh or 0), st.offset or 0
        )
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
  { kind='checkbox', k='YIELD_TO_LEFT', label='Yield to LEFT (instead of RIGHT)', tip='If enabled, AI moves left to let you pass on the right. Otherwise AI moves right so you pass on the left.' },
  { kind='slider',   k='DETECT_INNER_M', label='Detect radius (m)', min=5,  max=90, tip='Start yielding if the player is within this distance AND behind the AI car.' },
  { kind='slider',   k='DETECT_HYSTERESIS_M', label='Hysteresis (m)', min=20, max=120, tip='Extra distance while yielding so AI doesn’t flicker on/off near threshold.' },
  { kind='slider',   k='YIELD_OFFSET_M', label='Side offset (m)', min=0.5, max=4.0, tip='How far to move towards the chosen side when yielding.' },
  { kind='slider',   k='RIGHT_MARGIN_M', label='Edge margin (m)', min=0.3, max=1.2, tip='Safety gap from the outer edge on the chosen side.' },
  { kind='slider',   k='MIN_PLAYER_SPEED_KMH', label='Min player speed (km/h)', min=0, max=160, tip='Ignore very low-speed approaches (pit exits, traffic jams).' },
  { kind='slider',   k='MIN_SPEED_DELTA_KMH',  label='Min speed delta (km/h)', min=0,  max=30, tip='Require some closing speed before asking AI to yield.' },
  { kind='slider',   k='RAMP_SPEED_MPS', label='Offset ramp (m/s)', min=1.0, max=10.0, tip='Ramp speed of offset change.' },
  { kind='slider',   k='RAMP_RELEASE_MPS', label='Offset release (m/s)', min=0.2, max=6.0, tip='How quickly offset returns to center once you’re past the AI.' },
  { kind='slider',   k='LIST_RADIUS_FILTER_M', label='List radius filter (m)', min=0, max=1000, tip='Only show cars within this distance in the list (0 = show all).' },
  { kind='slider',   k='MIN_AI_SPEED_KMH', label='Min AI speed (km/h)', min=0, max=120, tip='Don’t ask AI to yield if its own speed is below this (corners/traffic).' },
}

local function drawControls()
  for _, e in ipairs(UI_ELEMENTS) do
    local spec = SettingsManager.SETTINGS_SPEC_BY_KEY[e.k]
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
  ui.text(string.format('AI Cars Overtake — yield %s', (SettingsManager.YIELD_TO_LEFT and 'LEFT') or 'RIGHT'))
  if SettingsManager.CFG_PATH then
    ui.text(string.format('Config: %s  [via %s] %s',
      SettingsManager.CFG_PATH, SettingsManager.CFG_RESOLVE_NOTE or '?',
      SettingsManager.lastSaveOk and '(saved ✓)' or (SettingsManager.lastSaveErr ~= '' and ('(save error: '..SettingsManager.lastSaveErr..')') or '')
    ))
  else
    ui.text(string.format('Config: <unresolved>  [via %s]', SettingsManager.CFG_RESOLVE_NOTE or '?'))
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
    -- sort cars by distance to player for clearer list
    local order = {}
    for i = 1, totalAI do
      local c = ac.getCar(i); local st = ai[i]
      if c and st then
        local d = st.dist
        if not d or d <= 0 then d = MathHelpers.vlen(MathHelpers.vsub(player.position, c.position)) end
        table.insert(order, { i = i, d = d })
      end
    end
    table.sort(order, function(a, b) return (a.d or 1e9) < (b.d or 1e9) end)

    for n = 1, #order do
      local i = order[n].i
      local c = ac.getCar(i); local st = ai[i]
      if c and st then
        local distShown = order[n].d or st.dist or 0
        local show = (SettingsManager.LIST_RADIUS_FILTER_M <= 0) or (distShown <= SettingsManager.LIST_RADIUS_FILTER_M)
        if show then
          local base = string.format(
            -- "#%02d  v=%3dkm/h  d=%5.1fm  off=%4.1f  des=%4.1f  max=%4.1f  prog=%.3f",
            "#%02d d=%5.1fm  v=%3dkm/h  offset=%4.1f  targetOffset=%4.1f  max=%4.1f  prog=%.3f",
            -- i, math.floor(c.speedKmh or 0), distShown, st.offset or 0, st.desired or 0, st.maxRight or 0, st.prog or -1
            i, distShown, math.floor(c.speedKmh or 0), st.offset or 0, st.desired or 0, st.maxRight or 0, st.prog or -1
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
  if SettingsManager._dirty then _saveIni(); SettingsManager._dirty = false end
end
