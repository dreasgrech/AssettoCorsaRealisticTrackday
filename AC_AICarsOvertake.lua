-- AC_AICarsOvertake.lua
-- Nudge AI to one side so the player can pass on the other (Trackday / AI Flood).

Constants = require("Constants")
Logger = require("Logger")
StorageManager = require("StorageManager")
MathHelpers = require("MathHelpers")
UIManager = require("UIManager")
CarOperations = require("CarOperations")
CarManager = require("CarManager")

--[=====[ 
---
-- Andreas: I tried making this a self-invoked anonymous function but the interpreter didn’t like it
---
local function awake()
  if (not Constants.CAN_APP_RUN) then
    Logger.log('App can not run.  Online? ' .. tostring(Constants.IS_ONLINE))
    return
  end

  -- Logger.log('Initializing')
end
awake()
--]=====]

local function shouldAppRun()
    local storage = StorageManager.getStorage()
    return
        Constants.CAN_APP_RUN
        and storage.enabled
end

---
-- Function defined in manifest.ini
-- wiki: function to be called each frame to draw window content
---
function script.MANIFEST__FUNCTION_MAIN(dt)
  local storage = StorageManager.getStorage()
  if (not shouldAppRun()) then
    ui.text(string.format('App not running.  Enabled: %s,  Online? %s', tostring(storage.enabled), tostring(Constants.IS_ONLINE)))
    return
  end

  ui.text(string.format('AI cars yielding to the %s', (storage.yieldToLeft and 'LEFT') or 'RIGHT'))

  ui.separator()

  local sim = ac.getSim()
  local yieldingCount = 0
  local totalAI = math.max(0, (sim.carsCount or 1) - 1)
  for i = 1, totalAI do
    if CarManager.cars_currentlyYielding[i] then
      yieldingCount = yieldingCount + 1
    end
  end
  ui.text(string.format('Yielding: %d / %d', yieldingCount, totalAI))

  ui.text('Cars:')
  local player = ac.getCar(0)
  -- sort cars by distance to player for clearer list
  local order = {}
  for i = 1, totalAI do
    local car = ac.getCar(i)
    if car and CarManager.cars_initialized[i] then
      local d = CarManager.cars_dist[i]
      if not d or d <= 0 then d = MathHelpers.vlen(MathHelpers.vsub(player.position, car.position)) end
      table.insert(order, { i = i, d = d })
    end
  end
  table.sort(order, function(a, b) return (a.d or 1e9) < (b.d or 1e9) end)

  for n = 1, #order do
    local i = order[n].i
    local car = ac.getCar(i)
    if car and CarManager.cars_initialized[i] then
      local distShown = order[n].d or CarManager.cars_dist[i] or 0
      local show = (storage.listRadiusFilter_meters <= 0) or (distShown <= storage.listRadiusFilter_meters)
      if show then
        local base = string.format(
          "#%02d d=%5.1fm  v=%3dkm/h  offset=%4.1f  targetOffset=%4.1f  max=%4.1f  prog=%.3f",
          i, distShown, math.floor(car.speedKmh or 0), CarManager.cars_currentSplineOffset[i] or 0, CarManager.cars_targetSplineOffset[i] or 0, CarManager.cars_maxRight[i] or 0, CarManager.cars_prog[i] or -1
        )
        do
          local indTxt = UIManager.indicatorStatusText(i)
          base = base .. string.format("  ind=%s", indTxt)
        end
        if CarManager.cars_currentlyYielding[i] then
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
-- wiki: called after a whole simulation update
---
function script.MANIFEST__UPDATE(dt)
  local storage = StorageManager.getStorage()
  if (not shouldAppRun()) then return end

  local sim = ac.getSim()
  local player = ac.getCar(0)

  for i = 1, (sim.carsCount or 0) - 1 do
    local car = ac.getCar(i)
    if
      car and 
      car.isAIControlled and  -- only run the yielding logic on ai cars
      not CarManager.cars_evacuating[i] -- don't run yielding logic if car is evacuating
    then
      CarManager.ensureDefaults(i) -- Ensure defaults are set if this car hasn't been initialized yet

      local desired, distanceFromPlayerCarToAICar, prog, sideMax, reason = CarOperations.desiredOffsetFor(car, player, CarManager.cars_currentlyYielding[i])

      CarManager.cars_dist[i] = distanceFromPlayerCarToAICar or CarManager.cars_dist[i] or 0
      CarManager.cars_prog[i] = prog or -1
      CarManager.cars_maxRight[i] = sideMax or 0
      CarManager.cars_reason[i] = reason or '-'

      -- Release logic: ease desired to 0 once the player is clearly ahead
      local releasing = false
      if CarManager.cars_currentlyYielding[i] and CarOperations.playerIsClearlyAhead(car, player, storage.clearAhead_meters) then
        releasing = true
      end

      -- Side-by-side guard: if the target side is occupied, don’t cut in — create space first
      local sideSign = storage.yieldToLeft and -1 or 1
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
        targetDesired = MathHelpers.approach((CarManager.cars_targetSplineOffset[i] or desired or 0), 0.0, storage.rampRelease_mps * dt)
      elseif releasing then
        -- TODO: Is there a bug here because this line is exactly the same as above?
        -- TODO: Is there a bug here because this line is exactly the same as above?
        -- TODO: Is there a bug here because this line is exactly the same as above?
        targetDesired = MathHelpers.approach((CarManager.cars_targetSplineOffset[i] or desired or 0), 0.0, storage.rampRelease_mps * dt)
      else
        targetDesired = desired or 0
      end

      CarManager.cars_targetSplineOffset[i] = targetDesired

      -- Keep yielding (blinkers) while blocked to signal intent
      local willYield = (isTargetSideBlocked and intendsSideMove) or (math.abs(targetDesired) > 0.01)
      if willYield then CarManager.cars_yieldTime[i] = (CarManager.cars_yieldTime[i] or 0) + dt end
      CarManager.cars_currentlyYielding[i] = willYield

      -- Apply offset with appropriate ramp (slower when releasing or blocked)
      local stepMps = (releasing or isTargetSideBlocked) and storage.rampRelease_mps or storage.rampSpeed_mps
      CarManager.cars_currentSplineOffset[i] = MathHelpers.approach(CarManager.cars_currentSplineOffset[i], targetDesired, stepMps * dt)
      physics.setAISplineAbsoluteOffset(i, CarManager.cars_currentSplineOffset[i], true)

      -- TODO: also try using physics.setAICaution(...)

      -- Temporarily cap speed if blocked to create a gap; remove caps otherwise
      if isTargetSideBlocked and intendsSideMove then
        local cap = math.max((car.speedKmh or 0) - storage.blockSlowdownKmh, 5)
        physics.setAITopSpeed(i, cap)
        physics.setAIThrottleLimit(i, storage.blockThrottleLimit)
        CarManager.cars_reason[i] = 'Blocked by car on side'
      else
        physics.setAITopSpeed(i, 1e9)
        physics.setAIThrottleLimit(i, 1)
      end

      CarOperations.applyIndicators(i, willYield, car)
    end
  end
end

---
-- wiki: called when transparent objects are finished rendering
---
function script.MANIFEST__TRANSPARENT(dt)
  if (not shouldAppRun()) then return end
  UIManager.draw3DOverheadText()
  render.setDepthMode(render.DepthMode.Normal)
end

---
-- wiki: function to be called to draw content of corresponding settings window (only with “SETTINGS” flag)
---
function script.MANIFEST__FUNCTION_SETTINGS()
  if (not Constants.CAN_APP_RUN) then return end

  UIManager.renderUIOptionsControls()
end

--[=====[ 
---
-- wiki: Called each frame after world matrix traversal ends for each app, even if none of its windows are active. 
-- wiki: Please make sure to not do anything too computationally expensive there (unless app needs it for some reason).
---
function script.update(dt)
  if (not shouldAppRun()) then return end

  -- TODO: We probably don't need these settings checks in here
end
--]=====]

--[=====[ 
---
-- Save when window is closed/hidden as a last resort
-- wiki: function to be called once when window closes
---
function script.MANIFEST__FUNCTION_ON_HIDE()
  if (not shouldAppRun()) then return end
end
--]=====]
