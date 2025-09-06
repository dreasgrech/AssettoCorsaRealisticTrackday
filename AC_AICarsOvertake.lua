-- AC_AICarsOvertake.lua
-- Nudge AI to one side so the player can pass on the other (Trackday / AI Flood).

---
--[=====[ 
local dreasStorage = ac.storage{
  myAddress = 'default home',
  myName = 'Default Jeronimo',
}

ac.log('before change storage.  myAddress=' .. tostring(dreasStorage.myAddress) .. ', myName=' .. tostring(dreasStorage.myName))

dreasStorage.myAddress = '123 Main St'
dreasStorage.myName = 'Karl'

ac.log('after change storage.  myAddress=' .. tostring(dreasStorage.myAddress) .. ', myName=' .. tostring(dreasStorage.myName))
--]=====]
---

Constants = require("Constants")
Logger = require("Logger")
StorageManager = require("StorageManager")
SettingsManager = require("SettingsManager")
MathHelpers = require("MathHelpers")
UIManager = require("UIManager")
CarOperations = require("CarOperations")
CarManager = require("CarManager")

---
-- Andreas: I tried making this a self-invoked anonymous function but the interpreter didn’t like it
---
local function awake()
  if (not Constants.CAN_APP_RUN) then
    Logger.log('App can not run.  Online? ' .. tostring(Constants.IS_ONLINE))
    return
  end

  -- Logger.log('Initializing')
  SettingsManager.loadINIFile()

  -- Apply values from INI and storage (keeps UI in sync on start)
  SettingsManager.settings_apply(SettingsManager.SETTINGS)
  SettingsManager.settings_apply(SettingsManager.P)

  SettingsManager.CurrentlyBootloading = false
end
awake()

---
-- Function defined in manifest.ini
-- wiki: function to be called each frame to draw window content
---
function script.MANIFEST__FUNCTION_MAIN(dt)
  if (not SettingsManager.shouldAppRun()) then
    ui.text(string.format('App not running.  Enabled: %s,  Online? %s', tostring(SettingsManager.enabled), tostring(Constants.IS_ONLINE)))
    return
  end

  SettingsManager._ensureConfig()

  ui.text(string.format('AI cars yielding to the %s', (SettingsManager.yieldToLeft and 'LEFT') or 'RIGHT'))

  ui.separator()

  local sim = ac.getSim()
  local yieldingCount = 0
  local totalAI = math.max(0, (sim.carsCount or 1) - 1)
  for i = 1, totalAI do
    if CarManager.cars_yielding[i] then
      yieldingCount = yieldingCount + 1
    end
  end
  ui.text(string.format('Yielding: %d / %d', yieldingCount, totalAI))

  ui.text('Cars:')
  local player = ac.getCar(0)
  -- sort cars by distance to player for clearer list
  local order = {}
  for i = 1, totalAI do
    local c = ac.getCar(i)
    if c and CarManager.cars_initialized[i] then
      local d = CarManager.cars_dist[i]
      if not d or d <= 0 then d = MathHelpers.vlen(MathHelpers.vsub(player.position, c.position)) end
      table.insert(order, { i = i, d = d })
    end
  end
  table.sort(order, function(a, b) return (a.d or 1e9) < (b.d or 1e9) end)

  for n = 1, #order do
    local i = order[n].i
    local c = ac.getCar(i)
    if c and CarManager.cars_initialized[i] then
      local distShown = order[n].d or CarManager.cars_dist[i] or 0
      local show = (SettingsManager.listRadiusFilter_meters <= 0) or (distShown <= SettingsManager.listRadiusFilter_meters)
      if show then
        local base = string.format(
          "#%02d d=%5.1fm  v=%3dkm/h  offset=%4.1f  targetOffset=%4.1f  max=%4.1f  prog=%.3f",
          i, distShown, math.floor(c.speedKmh or 0), CarManager.cars_offset[i] or 0, CarManager.cars_desired[i] or 0, CarManager.cars_maxRight[i] or 0, CarManager.cars_prog[i] or -1
        )
        do
          local indTxt = UIManager.indicatorStatusText(i)
          base = base .. string.format("  ind=%s", indTxt)
        end
        if CarManager.cars_yielding[i] then
          if ui.pushStyleColor and ui.StyleColor and ui.popStyleColor then
            ui.pushStyleColor(ui.StyleColor.Text, rgbm(0.2, 0.95, 0.2, 1.0))
            ui.text(base)
            ui.popStyleColor()
          elseif ui.textColored then
            ui.textColored(base, rgbm(0.2, 0.95, 0.2, 1.0))
          else
            ui.text(base)
          end
          ui.sameLine(); ui.text(string.format("  (yield %.1fs)", CarManager.cars_yieldTime[i] or 0))
        else
          local reason = CarManager.cars_reason[i] or '-'
          ui.text(string.format("%s  reason: %s", base, reason))
        end
      end
    end
  end
end

---
-- wiki: Called each frame after world matrix traversal ends for each app, even if none of its windows are active. 
-- wiki: Please make sure to not do anything too computationally expensive there (unless app needs it for some reason).
---
function script.update(dt)
  if (not SettingsManager.shouldAppRun()) then return end

  -- TODO: We probably don't need these settings checks in here

  SettingsManager._ensureConfig()

  -- Debounced autosave: write once after no changes for SAVE_INTERVAL
  if not SettingsManager.CurrentlyBootloading and SettingsManager.configFilePath then
    if SettingsManager.settingsCurrentlyDirty then
      SettingsManager.autosaveTimer = SettingsManager.autosaveTimer + dt
      if SettingsManager.autosaveTimer >= SettingsManager.saveInterval then
        SettingsManager.saveINIFile()
        SettingsManager.settingsCurrentlyDirty = false
      end
    end
  end
end

---
-- wiki: called after a whole simulation update
---
function script.MANIFEST__UPDATE(dt)
  if (not SettingsManager.shouldAppRun()) then return end

  local sim = ac.getSim()
  local player = ac.getCar(0)

  for i = 1, (sim.carsCount or 0) - 1 do
    local c = ac.getCar(i)
    if
      c and 
      c.isAIControlled and  -- only run the yielding logic on ai cars
      not CarManager.isCarEvacuating(i) -- don't run yielding logic if car is evacuating
    then
      CarManager.ensureDefaults(i) -- Ensure defaults are set if this car hasn't been initialized yet

      local desired, dist, prog, sideMax, reason = CarOperations.desiredOffsetFor(c, player, CarManager.cars_yielding[i])

      CarManager.cars_dist[i] = dist or CarManager.cars_dist[i] or 0
      CarManager.cars_prog[i] = prog or -1
      CarManager.cars_maxRight[i] = sideMax or 0
      CarManager.cars_reason[i] = reason or '-'

      -- Release logic: ease desired to 0 once the player is clearly ahead
      local releasing = false
      if CarManager.cars_yielding[i] and CarOperations.playerIsClearlyAhead(c, player, SettingsManager.clearAhead_meters) then
        releasing = true
      end

      -- Side-by-side guard: if the target side is occupied, don’t cut in — create space first
      local sideSign = SettingsManager.yieldToLeft and -1 or 1
      local intendsSideMove = desired and math.abs(desired) > 0.01
      local isTargetSideBlocked, blockerCarIndex = false, nil
      if intendsSideMove then
        isTargetSideBlocked, blockerCarIndex = CarOperations.isTargetSideBlocked(i, sideSign)
      end
      CarManager.cars_blocked[i] = isTargetSideBlocked
      CarManager.cars_blocker[i] = blockerCarIndex

      local targetDesired
      if isTargetSideBlocked and not releasing then
        -- keep indicators on, but don’t move laterally yet
        targetDesired = MathHelpers.approach((CarManager.cars_desired[i] or desired or 0), 0.0, SettingsManager.rampRelease_mps * dt)
      elseif releasing then
        -- TODO: Is there a bug here because this line is exactly the same as above?
        -- TODO: Is there a bug here because this line is exactly the same as above?
        -- TODO: Is there a bug here because this line is exactly the same as above?
        targetDesired = MathHelpers.approach((CarManager.cars_desired[i] or desired or 0), 0.0, SettingsManager.rampRelease_mps * dt)
      else
        targetDesired = desired or 0
      end

      CarManager.cars_desired[i] = targetDesired

      -- Keep yielding (blinkers) while blocked to signal intent
      local willYield = (isTargetSideBlocked and intendsSideMove) or (math.abs(targetDesired) > 0.01)
      if willYield then CarManager.cars_yieldTime[i] = (CarManager.cars_yieldTime[i] or 0) + dt end
      CarManager.cars_yielding[i] = willYield

      -- Apply offset with appropriate ramp (slower when releasing or blocked)
      local stepMps = (releasing or isTargetSideBlocked) and SettingsManager.rampRelease_mps or SettingsManager.rampSpeed_mps
      CarManager.cars_offset[i] = MathHelpers.approach(CarManager.cars_offset[i], targetDesired, stepMps * dt)
      physics.setAISplineAbsoluteOffset(i, CarManager.cars_offset[i], true)

      -- TODO: also try using physics.setAICaution(...)

      -- Temporarily cap speed if blocked to create a gap; remove caps otherwise
      if isTargetSideBlocked and intendsSideMove then
        local cap = math.max((c.speedKmh or 0) - SettingsManager.blockSlowdownKmh, 5)
        physics.setAITopSpeed(i, cap)
        physics.setAIThrottleLimit(i, SettingsManager.blockThrottleLimit)
        CarManager.cars_reason[i] = 'Blocked by car on side'
      else
        physics.setAITopSpeed(i, 1e9)
        physics.setAIThrottleLimit(i, 1)
      end

      CarOperations.applyIndicators(i, willYield, c)
    end
  end
end

---
-- wiki: called when transparent objects are finished rendering
---
function script.MANIFEST__TRANSPARENT(dt)
  if (not SettingsManager.shouldAppRun()) then return end
  UIManager.draw3DOverheadText()
  render.setDepthMode(render.DepthMode.Normal)
end

---
-- wiki: function to be called to draw content of corresponding settings window (only with “SETTINGS” flag)
---
function script.MANIFEST__FUNCTION_SETTINGS()
  if (not Constants.CAN_APP_RUN) then return end

  if SettingsManager.configFilePath then
    ui.text(string.format('Config: %s  [via %s] %s',
      SettingsManager.configFilePath, SettingsManager.configResolveNote or '?',
      SettingsManager.lastSaveOk and '(saved ✓)' or (SettingsManager.lastSaveErr ~= '' and ('(save error: '..SettingsManager.lastSaveErr..')') or '')
    ))
  else
    ui.text(string.format('Config: <unresolved>  [via %s]', SettingsManager.configResolveNote or '?'))
  end

  UIManager.renderUIOptionsControls()
  -- UIManager.drawOptionsUIControls()
end

---
-- Save when window is closed/hidden as a last resort
-- wiki: function to be called once when window closes
---
function script.MANIFEST__FUNCTION_ON_HIDE()
  if (not SettingsManager.shouldAppRun()) then return end
  if SettingsManager.settingsCurrentlyDirty then SettingsManager.saveNIFile(); SettingsManager.settingsCurrentlyDirty = false end
end
