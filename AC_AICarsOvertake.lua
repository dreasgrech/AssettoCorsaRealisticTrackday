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
local ai = {}  -- per-AI state

-- CSP-managed store (survives LAZY unloads)
-- Docs: Lua apps + LAZY notes (state apart from ac.storage()/ac.store() is lost on unload).
local P = (ac.store and ac.store('AC_AICarsOvertake'))
       or (ac.storage and ac.storage('AC_AICarsOvertake'))
       or nil

-- File-based persistence (Documents, not app folder — avoids hot-reload)
local SETTINGS = {}
local CFG_PATH, lastSaveOk, lastSaveErr = nil, false, ''
local function _userIniPath()
  -- Prefer CSP enum if available, then numeric fallback, then OS env fallback
  local root = nil
  if ac.getFolder then
    if ac.FolderID and ac.FolderID.Documents then
      root = ac.getFolder(ac.FolderID.Documents)
    end
    if (not root or #root == 0) then
      -- numeric fallback; value depends on CSP build, so only if enum missing
      pcall(function() root = ac.getFolder(4) end)
    end
  end
  if (not root or #root == 0) and os and os.getenv then
    local user = os.getenv('USERPROFILE')
      or ((os.getenv('HOMEDRIVE') or '') .. (os.getenv('HOMEPATH') or ''))
    if user and #user > 0 then
      root = user .. "\\Documents\\Assetto Corsa"
    end
  end
  if root and #root > 0 then
    return root .. "\\cfg\\AC_AICarsOvertake.ini"
  end
  return nil
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
  CFG_PATH = CFG_PATH or _userIniPath()
  if not CFG_PATH then lastSaveOk=false; lastSaveErr='no path'; return end
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
  -- Save *immediately* so quitting the game doesn’t drop last change
  _saveIni()
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

-- Robust tooltip (guards different CSP ImGui bindings)
local function tip(text)
  local hovered = false
  if ui and ui.itemHovered then
    local ok, res = pcall(ui.itemHovered); hovered = ok and res or false
  end
  if not hovered then return end
  local fn = (ui and (ui.setTooltip or ui.tooltip or ui.toolTip)) or nil
  if fn then pcall(fn, text); return end
  local beginFn = ui and (ui.beginTooltip or ui.beginItemTooltip)
  local endFn   = ui and (ui.endTooltip   or ui.endItemTooltip)
  if beginFn and endFn then
    if pcall(beginFn) then
      if ui.textWrapped then ui.textWrapped(text) else ui.text(text) end
      pcall(endFn)
    end
  end
end

----------------------------------------------------------------------
-- Clamp desired rightward offset by available right side width
----------------------------------------------------------------------
local function clampRightOffsetMeters(aiWorldPos, desired)
  if not ac.worldCoordinateToTrackProgress or not ac.getTrackAISplineSides then
    return desired
  end
  local prog = ac.worldCoordinateToTrackProgress(aiWorldPos)
  if prog < 0 then return desired end
  local sides = ac.getTrackAISplineSides(prog) -- vec2(left, right)
  local maxRight = math.max(0, (sides.y or 0) - RIGHT_MARGIN_M)
  return math.max(0, math.min(desired, maxRight)), prog, (sides.y or 0)
end

----------------------------------------------------------------------
-- Decide target offset for a single AI (returns desired, dist, prog, rightSide, reason)
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

  -- Load from disk first
  if SETTINGS then
    enabled               = SETTINGS.enabled               ~= nil and SETTINGS.enabled               or enabled
    debugDraw             = SETTINGS.debugDraw             ~= nil and SETTINGS.debugDraw             or debugDraw
    drawOnTop             = SETTINGS.drawOnTop             ~= nil and SETTINGS.drawOnTop             or drawOnTop
    DETECT_INNER_M        = SETTINGS.DETECT_INNER_M        or DETECT_INNER_M
    DETECT_HYSTERESIS_M   = SETTINGS.DETECT_HYSTERESIS_M   or DETECT_HYSTERESIS_M
    MIN_PLAYER_SPEED_KMH  = SETTINGS.MIN_PLAYER_SPEED_KMH  or MIN_PLAYER_SPEED_KMH
    MIN_SPEED_DELTA_KMH   = SETTINGS.MIN_SPEED_DELTA_KMH   or MIN_SPEED_DELTA_KMH
    YIELD_OFFSET_M        = SETTINGS.YIELD_OFFSET_M        or YIELD_OFFSET_M
    RAMP_SPEED_MPS        = SETTINGS.RAMP_SPEED_MPS        or RAMP_SPEED_MPS
    CLEAR_AHEAD_M         = SETTINGS.CLEAR_AHEAD_M         or CLEAR_AHEAD_M
    RIGHT_MARGIN_M        = SETTINGS.RIGHT_MARGIN_M        or RIGHT_MARGIN_M
    LIST_RADIUS_FILTER_M  = SETTINGS.LIST_RADIUS_FILTER_M  or LIST_RADIUS_FILTER_M
  end

  -- Then let CSP store override if it has anything (helps with hot reload)
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
end

function script.update(dt)
  if not enabled then return end
  if not physics or not physics.setAISplineAbsoluteOffset then return end

  local sim = ac.getSim(); if not sim then return end
  local player = ac.getCar(0); if not player then return end

  for i = 1, (sim.carsCount or 0) - 1 do
    local c = ac.getCar(i)
    if c and c.isAIControlled ~= false then
      ai[i] = ai[i] or { offset = 0.0, yielding = false, dist = 0, desired = 0, maxRight = 0, prog = -1, reason='-', yieldTime=0 }

      local desired, dist, prog, rightSide, reason = desiredOffsetFor(c, player, ai[i].yielding)
      ai[i].dist     = dist or ai[i].dist or 0
      ai[i].desired  = desired or 0
      ai[i].prog     = prog or -1
      ai[i].maxRight = rightSide or 0
      ai[i].reason   = reason or '-'

      if ai[i].yielding and playerIsClearlyAhead(c, player, CLEAR_AHEAD_M) then
        desired = 0.0
      end

      local willYield = (desired or 0) > 0.01
      if willYield then ai[i].yieldTime = (ai[i].yieldTime or 0) + dt end
      ai[i].yielding = willYield

      ai[i].offset   = approach(ai[i].offset, desired or 0, RAMP_SPEED_MPS * dt)
      physics.setAISplineAbsoluteOffset(i, ai[i].offset, true)
    end
  end
end

-- IMPORTANT: function name must match manifest’s [RENDER_CALLBACKS]
function script.Draw3D(dt)
  if not debugDraw then return end
  local sim = ac.getSim(); if not sim then return end

  render.setDepthMode(not drawOnTop, true)  -- draw on top if requested

  for i = 1, (sim.carsCount or 0) - 1 do
    local st = ai[i]
    if st and (st.offset or 0) > 0.02 then
      local c = ac.getCar(i)
      if c then
        local txt = string.format("-> %.1fm  (des=%.1f, maxR=%.1f, d=%.1fm)",
          st.offset, st.desired or 0, st.maxRight or 0, st.dist or 0)
        render.debugText(c.position + vec3(0, 2.0, 0), txt)
      end
    end
  end
end

function script.windowMain(dt)
  ui.text('AI Cars Overtake — keep right, pass left')

  -- Small status line for persistence
  if CFG_PATH then
    ui.text(string.format('Config: %s %s', CFG_PATH, lastSaveOk and '(saved ✓)' or (lastSaveErr ~= '' and ('(save error: '..lastSaveErr..')') or '')))
  else
    ui.text('Config: <unresolved>')
  end

  if ui.checkbox('Enabled', enabled) then
    enabled = not enabled
    _persist('enabled', enabled)
  end
  tip('Master switch for this app.')

  if ui.checkbox('Debug markers (3D)', debugDraw) then
    debugDraw = not debugDraw
    _persist('debugDraw', debugDraw)
  end
  tip('Shows floating text above AI cars currently yielding. Uses render callback.')

  if ui.checkbox('Draw markers on top (no depth test)', drawOnTop) then
    drawOnTop = not drawOnTop
    _persist('drawOnTop', drawOnTop)
  end
  tip('If markers are hidden by car bodywork, enable this so text ignores depth testing.')

  ui.separator()

  local v

  v = ui.slider('Detect radius (m)', DETECT_INNER_M, 20, 90)
  if v ~= DETECT_INNER_M then DETECT_INNER_M = v; _persist('DETECT_INNER_M', v) end
  tip('Start yielding if the player is within this distance AND behind the AI car.')

  v = ui.slider('Hysteresis (m)', DETECT_HYSTERESIS_M, 20, 120)
  if v ~= DETECT_HYSTERESIS_M then DETECT_HYSTERESIS_M = v; _persist('DETECT_HYSTERESIS_M', v) end
  tip('Extra distance added while yielding so AI doesn’t flicker on/off near the threshold.')

  v = ui.slider('Right offset (m)', YIELD_OFFSET_M, 0.5, 4.0)
  if v ~= YIELD_OFFSET_M then YIELD_OFFSET_M = v; _persist('YIELD_OFFSET_M', v) end
  tip('How far to move to the right when yielding. Bigger = more obvious, but risk using up road.')

  v = ui.slider('Right margin (m)', RIGHT_MARGIN_M, 0.3, 1.2)
  if v ~= RIGHT_MARGIN_M then RIGHT_MARGIN_M = v; _persist('RIGHT_MARGIN_M', v) end
  tip('Safety gap from right edge. Target offset is clamped so AI keeps at least this much room.')

  v = ui.slider('Min player speed (km/h)', MIN_PLAYER_SPEED_KMH, 40, 160)
  if v ~= MIN_PLAYER_SPEED_KMH then MIN_PLAYER_SPEED_KMH = v; _persist('MIN_PLAYER_SPEED_KMH', v) end
  tip('Ignore very low-speed approaches (pit exits, traffic jams).')

  v = ui.slider('Min speed delta (km/h)', MIN_SPEED_DELTA_KMH, 0, 30)
  if v ~= MIN_SPEED_DELTA_KMH then MIN_SPEED_DELTA_KMH = v; _persist('MIN_SPEED_DELTA_KMH', v) end
  tip('Require some closing speed before asking AI to yield (prevents constant shuffling).')

  v = ui.slider('Offset ramp (m/s)', RAMP_SPEED_MPS, 1.0, 10.0)
  if v ~= RAMP_SPEED_MPS then RAMP_SPEED_MPS = v; _persist('RAMP_SPEED_MPS', v) end
  tip('How quickly AI transitions toward the desired offset; higher = snappier, lower = smoother.')

  ui.separator()
  v = ui.slider('List radius filter (m)', LIST_RADIUS_FILTER_M, 0, 1000)
  if v ~= LIST_RADIUS_FILTER_M then LIST_RADIUS_FILTER_M = v; _persist('LIST_RADIUS_FILTER_M', v) end
  tip('Only show cars within this distance in the list (0 = show all). Helps keep the list readable.')

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
      local c = ac.getCar(i)
      local st = ai[i]
      if c and st then
        local show = (LIST_RADIUS_FILTER_M <= 0) or ((st.dist or 0) <= LIST_RADIUS_FILTER_M)
        if show then
          local base = string.format(
            "#%02d  v=%3dkm/h  d=%5.1fm  off=%4.1f  des=%4.1f  maxR=%4.1f  prog=%.3f",
            i, math.floor(c.speedKmh or 0), st.dist or 0, st.offset or 0,
            st.desired or 0, st.maxRight or 0, st.prog or -1
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
