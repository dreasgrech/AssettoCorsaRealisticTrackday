-- AC_AICarsOvertake.lua
-- Nudge AI to one side so the player can pass on the other (Trackday / AI Flood).

DequeManager = require("DataStructures.DequeManager")
StackManager = require("DataStructures.StackManager")
QueueManager = require("DataStructures.QueueManager")
Constants = require("Constants")
ColorManager = require("ColorManager")
Logger = require("Logger")
StorageManager = require("StorageManager")
MathHelpers = require("MathHelpers")
UIManager = require("UIManager")
CarOperations = require("CarOperations")
CarManager = require("CarManager")
CarStateMachine = require("CarStateMachine")
AccidentManager = require("AccidentManager")
RaceFlagManager = require("RaceFlagManager")

---
-- Andreas: I tried making this a self-invoked anonymous function but the interpreter didn’t like it
---
local function awake()
  if (not Constants.CAN_APP_RUN) then
    Logger.log('App can not run.  Online? ' .. tostring(Constants.IS_ONLINE))
    return
  end

  -- Logger.log('Initializing')
  CarManager.ensureDefaults(0) -- ensure defaults on local player car
end
awake()

local function shouldAppRun()
    local storage = StorageManager.getStorage()
    return
        Constants.CAN_APP_RUN
        and storage.enabled
end

-- Monitor car collisions so we can register an accident
ac.onCarCollision(-1, function (carIndex)
    local accidentIndex = AccidentManager.registerCollision(carIndex)

    CarStateMachine.informAboutAccident(accidentIndex)
end)

local CARSTATES_TO_UICOLOR = {
  [CarStateMachine.CarStateType.TRYING_TO_START_DRIVING_NORMALLY] = ColorManager.RGBM_Colors.Gray,
  [CarStateMachine.CarStateType.DRIVING_NORMALLY] = ColorManager.RGBM_Colors.White,
  [CarStateMachine.CarStateType.TRYING_TO_START_YIELDING_TO_THE_SIDE] = ColorManager.RGBM_Colors.DarkGreen,
  [CarStateMachine.CarStateType.YIELDING_TO_THE_SIDE] = ColorManager.RGBM_Colors.LimeGreen,
  [CarStateMachine.CarStateType.STAYING_ON_YIELDING_LANE] = ColorManager.RGBM_Colors.YellowGreen,
  [CarStateMachine.CarStateType.TRYING_TO_START_EASING_OUT_YIELD] = ColorManager.RGBM_Colors.Orange,
  [CarStateMachine.CarStateType.EASING_OUT_YIELD] = ColorManager.RGBM_Colors.Yellow,
  [CarStateMachine.CarStateType.WAITING_AFTER_ACCIDENT] = ColorManager.RGBM_Colors.Red,
  [CarStateMachine.CarStateType.COLLIDED_WITH_TRACK] = ColorManager.RGBM_Colors.DarkRed,
  [CarStateMachine.CarStateType.COLLIDED_WITH_CAR] = ColorManager.RGBM_Colors.Rose,
  [CarStateMachine.CarStateType.ANOTHER_CAR_COLLIDED_INTO_ME] = ColorManager.RGBM_Colors.OrangeRed,
}

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
      local d = CarManager.cars_distanceFromPlayerToCar[i]
      if not d or d <= 0 then d = MathHelpers.vlen(MathHelpers.vsub(player.position, car.position)) end
      table.insert(order, { i = i, d = d })
    end
  end
  table.sort(order, function(a, b) return (a.d or 1e9) < (b.d or 1e9) end)

  for n = 1, #order do
    local i = order[n].i
    local car = ac.getCar(i)
    if car and CarManager.cars_initialized[i] then
      local distShown = order[n].d or CarManager.cars_distanceFromPlayerToCar[i]
        local state = CarStateMachine.getCurrentState(i)
        local base = string.format(
          "#%02d d=%6.3fm  v=%3dkm/h  offset=%4.3f  targetOffset=%4.3f state=%s",
          i, distShown, math.floor(car.speedKmh),
          CarManager.cars_currentSplineOffset[i],
          CarManager.cars_targetSplineOffset[i],
          CarStateMachine.CarStateTypeStrings[state]
        )
        -- do
          -- local indTxt = UIManager.indicatorStatusText(i)
          -- base = base .. string.format("  ind=%s", indTxt)
        -- end
        local reason = CarManager.cars_reasonWhyCantYield[i] or ''
        local fullString
        if CarManager.cars_currentlyYielding[i] then
            -- ui.textColored(base, rgbm(0.2, 0.95, 0.2, 1.0))

          -- ui.textColored(base, uiColor)
          -- ui.sameLine()
          -- ui.text(string.format(" (%s) (yield %.1fs)", reason, CarManager.cars_yieldTime[i]))

          -- ui.textColored(string.format("%s (%s) (yield %.1fs)", base, reason, CarManager.cars_yieldTime[i]), uiColor)
          fullString = string.format("%s (%s) (yield %.1fs)", base, reason, CarManager.cars_yieldTime[i])
        else
          -- ui.text(string.format("%s  reason: %s", base, reason))
          -- ui.textColored(string.format("%s  reason: %s", base, reason), uiColor)
          fullString = string.format("%s  reason: %s", base, reason)
        end

        local uiColor = CARSTATES_TO_UICOLOR[state]
        ui.textColored(fullString, uiColor)
    end
  end
end

---
-- wiki: called after a whole simulation update
---
function script.MANIFEST__UPDATE(dt)
  if (not shouldAppRun()) then return end

  ----------------------------------------------------------------
  -- local isBlocked, direction, distance = CarOperations.isTargetSideBlocked(0)
  -- if isBlocked then
    -- -- ui.textColored(string.format("Player car side is BLOCKED on %s (distance %.2f m)", tostring(direction), distance or -1), rgbm(1.0, 0.2, 0.2, 1.0))
    -- Logger.log(string.format("Car %d left side is BLOCKED (hit at %s, distance %.2f m)", 0, CarOperations.CarDirectionsStrings[direction], distance or -1))
  -- else
    -- -- ui.textColored("Player car side is clear", rgbm(0.2, 1.0, 0.2, 1.0))
  -- end
  ----------------------------------------------------------------

  local sim = ac.getSim()
  if sim.isPaused then return end

  -- doCarYieldingLogic_old(dt)
  local storage = StorageManager.getStorage()
  local playerCar = ac.getCar(0)
  -- if not playerCar then return end

  -- TODO: ac.iterateCars.ordered could be useful when we start applying the overtaking/yielding logic to ai cars too instead of just the local player

  -- check if the player is coming up to an accident so we can set a caution flag
  local isPlayerComingUpToAccident = AccidentManager.isCarComingUpToAccident(playerCar)
  if isPlayerComingUpToAccident then
    RaceFlagManager.setRaceFlag(ac.FlagType.Caution)
  else
    RaceFlagManager.removeRaceFlag()
  end

  for carIndex = 1, sim.carsCount - 1 do
    local car = ac.getCar(carIndex)
    if
      car and
      car.isAIControlled -- only run the yielding logic on ai cars
      -- and not CarManager.cars_evacuating[carIndex] -- don't run yielding logic if car is evacuating
    then
      CarManager.ensureDefaults(carIndex) -- Ensure defaults are set if this car hasn't been initialized yet

      -- execute the state machine for this car
      CarStateMachine.update(carIndex, dt, car, playerCar, storage)

      local carState = CarStateMachine.getCurrentState(carIndex)
      local aiCarCurrentlyYielding = (carState == CarStateMachine.CarStateType.YIELDING_TO_THE_SIDE) or (carState == CarStateMachine.CarStateType.STAYING_ON_YIELDING_LANE)

      CarManager.cars_currentlyYielding[carIndex] = aiCarCurrentlyYielding

      local distanceFromPlayerCarToAICar = MathHelpers.vlen(MathHelpers.vsub(playerCar.position, car.position))
      CarManager.cars_distanceFromPlayerToCar[carIndex] = distanceFromPlayerCarToAICar
    end
  end
end

---
-- wiki: called when transparent objects are finished rendering
---
function script.MANIFEST__TRANSPARENT(dt)
  if (not shouldAppRun()) then return end
  UIManager.draw3DOverheadText()

  -- render.debugSphere(playerCarPosition, 1, rgbm(1, 0, 0, 1))
  -- render.debugBox(playerCarPosition + vec3(0, 1, 0), vec3(1, 1, 1), rgbm(0, 1, 0, 1))
  -- render.debugCross(playerCarPosition + vec3(0, 2, 0), 1.0, rgbm(0, 0, 1, 1))
  -- render.debugArrow(playerCarPosition + vec3(0, 3, 0), playerCarPosition + vec3(0, 3, 5), 0.7, rgbm(0.2, 0.2, 1.0, 1))
  -- render.debugLine(playerCarPosition + vec3(0, 1, 0), playerCarPosition + vec3(0, 1, 5), rgbm(1.0, 0.2, 0.2, 1))
  -- render.debugLine(playerCarPosition + vec3(0, 0, 0), playerCarPosition + (playerCarSide * 2), rgbm(1.0, 0.2, 0.2, 1))


  -- ----------------------------------------------------------------
  -- -- Draw car block check rays for player car for debugging purposes
  -- CarOperations.drawSideAnchorPoints(0)
  -- local carBlocked, carOnSideDirection, carOnSideDistance = CarOperations.checkIfCarIsBlockedByAnotherCarAndSaveAnchorPoints(0)
  -- if carBlocked then
    -- -- ui.textColored(string.format("Player car side is BLOCKED on %s (distance %.2f m)", tostring(carOnSideDirection), carOnSideDistance or -1), rgbm(1.0, 0.2, 0.2, 1.0))
    -- Logger.log(string.format("Player Car left side is BLOCKED (hit at %s, distance %.2f m)", CarOperations.CarDirectionsStrings[carOnSideDirection], carOnSideDistance or -1))
  -- end
  -- CarOperations.renderCarBlockCheckRays(0)
  -- ----------------------------------------------------------------
  

  local sim = ac.getSim()
  for carIndex = 1, sim.carsCount - 1 do
    local carAnchorPoints = CarManager.cars_anchorPoints[carIndex]
    if carAnchorPoints then
      -- CarOperations.drawSideAnchorPoints(carIndex)
      CarOperations.renderCarBlockCheckRays(carIndex)
    end
  end

  -- render.setDepthMode(render.DepthMode.Normal)
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
