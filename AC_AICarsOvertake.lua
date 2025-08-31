-- AC_AICarsOvertake.lua
-- Nudge AI to one side so the player can pass on the other (Trackday / AI Flood).

SettingsManager = require("SettingsManager")
MathHelpers = require("MathHelpers")
UIManager = require("UIManager")
CarOperations = require("CarOperations")
CarManager = require("CarManager")

----------------------------------------------------------------------
-- State
----------------------------------------------------------------------
local enabled, debugDraw, drawOnTop = true, true, true

----------------------------------------------------------------------
-- CSP entry points
----------------------------------------------------------------------
function script.__init__()
  if ac.log then ac.log('AC_AICarsOvertake: init') end
  SettingsManager._loadIni()

  -- Apply values from INI and storage (keeps UI in sync on start)
  SettingsManager.settings_apply(SettingsManager.SETTINGS)
  SettingsManager.settings_apply(SettingsManager.P)

  SettingsManager.BOOT_LOADING = false
end

function script.update(dt)
  SettingsManager._ensureConfig()

  -- Debounced autosave: write once after no changes for SAVE_INTERVAL
  if not SettingsManager.BOOT_LOADING and SettingsManager.CFG_PATH then
    if SettingsManager._dirty then
      SettingsManager._autosaveTimer = SettingsManager._autosaveTimer + dt
      if SettingsManager._autosaveTimer >= SettingsManager.SAVE_INTERVAL then
        SettingsManager._saveIni()
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
      CarManager.ai[i] = CarManager.ai[i] or { offset=0.0, yielding=false, dist=0, desired=0, maxRight=0, prog=-1, reason='-', yieldTime=0, blink=nil, blocked=false, blocker=nil }
      local desired, dist, prog, sideMax, reason = CarOperations.desiredOffsetFor(c, player, CarManager.ai[i].yielding)

      CarManager.ai[i].dist = dist or CarManager.ai[i].dist or 0
      CarManager.ai[i].prog = prog or -1
      CarManager.ai[i].maxRight = sideMax or 0
      CarManager.ai[i].reason = reason or '-'

      -- Release logic: ease desired to 0 once the player is clearly ahead
      local releasing = false
      if CarManager.ai[i].yielding and CarOperations.playerIsClearlyAhead(c, player, SettingsManager.CLEAR_AHEAD_M) then
        releasing = true
      end

      -- Side-by-side guard: if the target side is occupied, don’t cut in — create space first
      local sideSign = SettingsManager.YIELD_TO_LEFT and -1 or 1
      local intendsSideMove = desired and math.abs(desired) > 0.01
      local blocked, blocker = false, nil
      if intendsSideMove then
        blocked, blocker = CarOperations._isTargetSideBlocked(i, sideSign)
      end
      CarManager.ai[i].blocked = blocked
      CarManager.ai[i].blocker = blocker

      local targetDesired
      if blocked and not releasing then
        -- keep indicators on, but don’t move laterally yet
        targetDesired = MathHelpers.approach((CarManager.ai[i].desired or desired or 0), 0.0, SettingsManager.RAMP_RELEASE_MPS * dt)
      elseif releasing then
        targetDesired = MathHelpers.approach((CarManager.ai[i].desired or desired or 0), 0.0, SettingsManager.RAMP_RELEASE_MPS * dt)
      else
        targetDesired = desired or 0
      end
      CarManager.ai[i].desired = targetDesired

      -- Keep yielding (blinkers) while blocked to signal intent
      local willYield = (blocked and intendsSideMove) or (math.abs(targetDesired) > 0.01)
      if willYield then CarManager.ai[i].yieldTime = (CarManager.ai[i].yieldTime or 0) + dt end
      CarManager.ai[i].yielding = willYield

      -- Apply offset with appropriate ramp (slower when releasing or blocked)
      local stepMps = (releasing or blocked) and SettingsManager.RAMP_RELEASE_MPS or SettingsManager.RAMP_SPEED_MPS
      CarManager.ai[i].offset = MathHelpers.approach(CarManager.ai[i].offset, targetDesired, stepMps * dt)
      physics.setAISplineAbsoluteOffset(i, CarManager.ai[i].offset, true)

      -- Temporarily cap speed if blocked to create a gap; remove caps otherwise
      if blocked and intendsSideMove then
        local cap = math.max((c.speedKmh or 0) - SettingsManager.BLOCK_SLOWDOWN_KMH, 5)
        if physics.setAITopSpeed then physics.setAITopSpeed(i, cap) end
        if physics.setAIThrottleLimit then physics.setAIThrottleLimit(i, SettingsManager.BLOCK_THROTTLE_LIMIT) end
        CarManager.ai[i].reason = 'Blocked by car on side'
      else
        if physics.setAITopSpeed then physics.setAITopSpeed(i, 1e9) end
        if physics.setAIThrottleLimit then physics.setAIThrottleLimit(i, 1) end
      end

      CarOperations._applyIndicators(i, willYield, c, CarManager.ai[i])
    end
  end
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
    local st = CarManager.ai[i]
    if st and (math.abs(st.offset or 0) > 0.02 or st.blocked) then
      local c = ac.getCar(i)
      if c then
        local txt = string.format(
          "#%02d d=%5.1fm  v=%3dkm/h  offset=%4.1f",
          i, st.dist, math.floor(c.speedKmh or 0), st.offset or 0
        )
        do
          local indTxt = UIManager.indicatorStatusText(st)
          txt = txt .. string.format("  ind=%s", indTxt)
        end
        render.debugText(c.position + vec3(0, 2.0, 0), txt)
      end
    end
  end
  render.setDepthMode(render.DepthMode.Normal)
end

function script.windowMain(dt)
  SettingsManager._ensureConfig()
  ui.text(string.format('AI Cars Overtake — yield %s', (SettingsManager.YIELD_TO_LEFT and 'LEFT') or 'RIGHT'))
  if SettingsManager.CFG_PATH then
    ui.text(string.format('Config: %s  [via %s] %s',
      SettingsManager.CFG_PATH, SettingsManager.CFG_RESOLVE_NOTE or '?',
      SettingsManager.lastSaveOk and '(saved ✓)' or (SettingsManager.lastSaveErr ~= '' and ('(save error: '..SettingsManager.lastSaveErr..')') or '')
    ))
  else
    ui.text(string.format('Config: <unresolved>  [via %s]', SettingsManager.CFG_RESOLVE_NOTE or '?'))
  end

  UIManager.drawControls()

  ui.separator()
  local sim = ac.getSim()
  local totalAI, yieldingCount = 0, 0
  if sim then
    totalAI = math.max(0, (sim.carsCount or 1) - 1)
    for i = 1, totalAI do if CarManager.ai[i] and CarManager.ai[i].yielding then yieldingCount = yieldingCount + 1 end end
  end
  ui.text(string.format('Yielding: %d / %d', yieldingCount, totalAI))

  ui.text('Cars:')
  local player = ac.getCar(0)
  if sim and player then
    -- sort cars by distance to player for clearer list
    local order = {}
    for i = 1, totalAI do
      local c = ac.getCar(i); local st = CarManager.ai[i]
      if c and st then
        local d = st.dist
        if not d or d <= 0 then d = MathHelpers.vlen(MathHelpers.vsub(player.position, c.position)) end
        table.insert(order, { i = i, d = d })
      end
    end
    table.sort(order, function(a, b) return (a.d or 1e9) < (b.d or 1e9) end)

    for n = 1, #order do
      local i = order[n].i
      local c = ac.getCar(i); local st = CarManager.ai[i]
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
            local indTxt = UIManager.indicatorStatusText(st)
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
  if SettingsManager._dirty then SettingsManager._saveIni(); SettingsManager._dirty = false end
end
