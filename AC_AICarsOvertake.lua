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
      -- local show = (storage.listRadiusFilter_meters <= 0) or (distShown <= storage.listRadiusFilter_meters)
      -- if show then
        local base = string.format(
          -- "#%02d d=%5.1fm  v=%3dkm/h  offset=%4.1f  targetOffset=%4.1f  max=%4.1f  prog=%.3f",
          -- i, distShown, math.floor(car.speedKmh or 0), CarManager.cars_currentSplineOffset_meters[i] or 0, CarManager.cars_targetSplineOffset_meters[i] or 0, CarManager.cars_maxSideMargin[i] or 0, CarManager.cars_currentNormalizedTrackProgress[i] or -1
          "#%02d d=%6.3fm  v=%3dkm/h  offset=%4.3f  targetOffset=%4.3f state=%s",
          i, distShown, math.floor(car.speedKmh),
          CarManager.cars_currentSplineOffset[i],
          CarManager.cars_targetSplineOffset[i],
          CarManager.cars_state[i]
        )
        -- do
          -- local indTxt = UIManager.indicatorStatusText(i)
          -- base = base .. string.format("  ind=%s", indTxt)
        -- end
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
      -- end
    end
  end
end

local function doCarYieldingLogic_old(dt)
  local storage = StorageManager.getStorage()
  local sim = ac.getSim()
  local player = ac.getCar(0)

  for carIndex = 1, (sim.carsCount or 0) - 1 do
    local car = ac.getCar(carIndex)
    if
      car and
      car.isAIControlled and  -- only run the yielding logic on ai cars
      not CarManager.cars_evacuating[carIndex] -- don't run yielding logic if car is evacuating
    then
      CarManager.ensureDefaults(carIndex) -- Ensure defaults are set if this car hasn't been initialized yet

      local targetSplineOffset_meters, distanceFromPlayerCarToAICar, normalizedTrackProgress, maxSideMargin_meters, reason = CarOperations.desiredAbsoluteOffsetFor(car, player, CarManager.cars_currentlyYielding[carIndex])

      CarManager.cars_distanceFromPlayerToCar[carIndex] = distanceFromPlayerCarToAICar
      CarManager.cars_currentNormalizedTrackProgress[carIndex] = normalizedTrackProgress
      CarManager.cars_maxSideMargin[carIndex] = maxSideMargin_meters
      CarManager.cars_reason[carIndex] = reason -- or '-'

      -- Release logic: ease desired to 0 once the player is clearly ahead
      local carReturningBackToNormal = false
      if CarManager.cars_currentlyYielding[carIndex] and CarOperations.playerIsClearlyAhead(car, player, storage.clearAhead_meters) then
        carReturningBackToNormal = true
      end

      -- Side-by-side guard: if the target side is occupied, don’t cut in — create space first
      local sideSign = storage.yieldToLeft and -1 or 1
      local intendsSideMove = math.abs(targetSplineOffset_meters) > 0.01
      local isTargetSideBlocked, blockerCarIndex = false, nil
      if intendsSideMove then
        isTargetSideBlocked, blockerCarIndex = CarOperations.isTargetSideBlocked(carIndex, sideSign)
      end
      CarManager.cars_isSideBlocked[carIndex] = isTargetSideBlocked
      CarManager.cars_sideBlockedCarIndex[carIndex] = blockerCarIndex

      local currentSplineOffset_meters
      if isTargetSideBlocked and not carReturningBackToNormal then
        -- keep indicators on, but don’t move laterally yet
        currentSplineOffset_meters = MathHelpers.approach((CarManager.cars_targetSplineOffset_meters[carIndex] or targetSplineOffset_meters or 0), 0.0, storage.rampRelease_mps * dt)
      elseif carReturningBackToNormal then
        -- TODO: Is there a bug here because this line is exactly the same as above?
        -- TODO: Is there a bug here because this line is exactly the same as above?
        -- TODO: Is there a bug here because this line is exactly the same as above?
        currentSplineOffset_meters = MathHelpers.approach((CarManager.cars_targetSplineOffset_meters[carIndex] or targetSplineOffset_meters or 0), 0.0, storage.rampRelease_mps * dt)
      else
        currentSplineOffset_meters = targetSplineOffset_meters
      end

      CarManager.cars_targetSplineOffset_meters[carIndex] = currentSplineOffset_meters

      -- Keep yielding (blinkers) while blocked to signal intent
      local willYield = (isTargetSideBlocked and intendsSideMove) or (math.abs(currentSplineOffset_meters) > 0.01)
      if willYield then CarManager.cars_yieldTime[carIndex] = (CarManager.cars_yieldTime[carIndex] or 0) + dt end
      CarManager.cars_currentlyYielding[carIndex] = willYield

      -- Apply offset with appropriate ramp (slower when releasing or blocked)
      local stepMps = (carReturningBackToNormal or isTargetSideBlocked) and storage.rampRelease_mps or storage.rampSpeed_mps
      CarManager.cars_currentSplineOffset_meters[carIndex] = MathHelpers.approach(CarManager.cars_currentSplineOffset_meters[carIndex], currentSplineOffset_meters, stepMps * dt)
      physics.setAISplineAbsoluteOffset(carIndex, CarManager.cars_currentSplineOffset_meters[carIndex], true)

      -- TODO: also try using physics.setAICaution(...)

      -- Temporarily cap speed if blocked to create a gap; remove caps otherwise
      if isTargetSideBlocked and intendsSideMove then
        local cap = math.max((car.speedKmh or 0) - storage.blockSlowdownKmh, 5)
        physics.setAITopSpeed(carIndex, cap)
        physics.setAIThrottleLimit(carIndex, storage.blockThrottleLimit)
        CarManager.cars_reason[carIndex] = 'Blocked by car on side'
      else
        physics.setAITopSpeed(carIndex, 1e9)
        physics.setAIThrottleLimit(carIndex, 1)
      end

      CarOperations.applyIndicators(carIndex, willYield, car)
    end
  end
end

-- local LOG_CAR_STATEMACHINE_IN_CSP_LOG = true
local LOG_CAR_STATEMACHINE_IN_CSP_LOG = false

local carStateMachine = {
  [CarManager.CarStateType.TryingToStartDrivingNormally] = function (carIndex, dt, car, playerCar, storage)

      CarManager.cars_yieldTime[carIndex] = 0
      CarManager.cars_currentSplineOffset[carIndex] = 0
      CarManager.cars_targetSplineOffset[carIndex] = 0

      -- turn off turning lights
      CarOperations.toggleTurningLights(carIndex, car, ac.TurningLights.None)
      
    -- start driving normally
      CarManager.cars_state[carIndex] = CarManager.CarStateType.DrivingNormally
  end,
  [CarManager.CarStateType.DrivingNormally] = function (carIndex, dt, car, playerCar, storage)
      if LOG_CAR_STATEMACHINE_IN_CSP_LOG then Logger.log(string.format("Car %d: In state: %s", carIndex, "DrivingNormally")) end

      -- If this car is not close to the player car, do nothing
      local distanceFromPlayerCarToAICar = MathHelpers.vlen(MathHelpers.vsub(playerCar.position, car.position))
      local radius = storage.detectInner_meters + storage.detectHysteresis_meters
      local isAICarCloseToPlayerCar = distanceFromPlayerCarToAICar <= radius
      if not isAICarCloseToPlayerCar then
        CarManager.cars_reason[carIndex] = 'Too far (outside detect radius) so not yielding'
        return
      end

      local isPlayerCarBehindAICar = CarOperations.isBehind(car, playerCar)
      if not isPlayerCarBehindAICar then
        CarManager.cars_reason[carIndex] = 'Player not behind (clear) so not yielding'
        return
      end

      -- Check if the player car is above the minimum speed
      local isPlayerAboveMinSpeed = playerCar.speedKmh >= storage.minPlayerSpeed_kmh
      if not isPlayerAboveMinSpeed then
        CarManager.cars_reason[carIndex] = 'Player below minimum speed so not yielding'
        return
      end

      -- Check if the player car is currently faster than the ai car 
      local playerCarHasClosingSpeedToAiCar = (playerCar.speedKmh - car.speedKmh) >= storage.minSpeedDelta_kmh
      if not playerCarHasClosingSpeedToAiCar then
        CarManager.cars_reason[carIndex] = 'Player does not have closing speed so not yielding'
      end

      -- Check if the ai car is above the minimum speed
      local isAICarAboveMinSpeed = car.speedKmh >= storage.minAISpeed_kmh
      if not isAICarAboveMinSpeed then
        CarManager.cars_reason[carIndex] = 'AI speed too low (corner/traffic) so not yielding'
      end

      -- Since all the checks have passed, the ai car can now start to yield
      CarManager.cars_state[carIndex] = CarManager.CarStateType.TryingToStartYieldingToTheSide
  end,
  [CarManager.CarStateType.TryingToStartYieldingToTheSide] = function (carIndex, dt, car, playerCar, storage)
      if LOG_CAR_STATEMACHINE_IN_CSP_LOG then Logger.log(string.format("Car %d: In state: %s", carIndex, "TryingToStartYieldingToTheSide")) end

      -- turn on turning lights
      local turningLights = storage.yieldToLeft and ac.TurningLights.Left or ac.TurningLights.Right
      CarOperations.toggleTurningLights(carIndex, car, turningLights)

      -- for now go directly to yielding to the side
      CarManager.cars_state[carIndex] = CarManager.CarStateType.YieldingToTheSide
  end,
  [CarManager.CarStateType.YieldingToTheSide] = function (carIndex, dt, car, playerCar, storage)
      if LOG_CAR_STATEMACHINE_IN_CSP_LOG then Logger.log(string.format("Car %d: In state: %s", carIndex, "YieldingToTheSide")) end

      -- If the ai car is yielding and the player car is now clearly ahead, we can ease out our yielding
      local isPlayerClearlyAheadOfAICar = CarOperations.playerIsClearlyAhead(car, playerCar, storage.clearAhead_meters)
      if isPlayerClearlyAheadOfAICar then
        CarManager.cars_reason[carIndex] = 'Player clearly ahead, so easing out yield'

        -- reset the yield time counter
        CarManager.cars_yieldTime[carIndex] = 0
        CarManager.cars_state[carIndex] = CarManager.CarStateType.TryingToStartEasingOutYield

        return
      end

      -- Since the player car is still close, we must continue yielding

      local sideSign = storage.yieldToLeft and -1 or 1
      local targetSplineOffset = sideSign
      -- local splineOffsetTransitionSpeed = storage.rampSpeed
      local splineOffsetTransitionSpeed = storage.rampSpeed_mps
      local currentSplineOffset = CarManager.cars_currentSplineOffset[carIndex]
      currentSplineOffset = MathHelpers.approach(currentSplineOffset, targetSplineOffset, splineOffsetTransitionSpeed * dt)

      -- set the spline offset on the ai car
      local overrideAiAwareness = storage.overrideAiAwareness -- TODO: check what this does
      physics.setAISplineOffset(carIndex, currentSplineOffset, overrideAiAwareness)

      -- keep the turning lights on while yielding
      local turningLights = storage.yieldToLeft and ac.TurningLights.Left or ac.TurningLights.Right
      CarOperations.toggleTurningLights(carIndex, car, turningLights)

      CarManager.cars_currentSplineOffset[carIndex] = currentSplineOffset
      CarManager.cars_targetSplineOffset[carIndex] = targetSplineOffset

      CarManager.cars_yieldTime[carIndex] = CarManager.cars_yieldTime[carIndex] + dt
  end,
  [CarManager.CarStateType.TryingToStartEasingOutYield] = function (carIndex, dt, car, playerCar, storage)
        if LOG_CAR_STATEMACHINE_IN_CSP_LOG then Logger.log(string.format("Car %d: In state: %s", carIndex, "TryingToStartEasingOutYield")) end

      -- inverse the turning lights while easing out yield (inverted yield direction since the car is now going back to center)
      local turningLights = (not storage.yieldToLeft) and ac.TurningLights.Left or ac.TurningLights.Right
      CarOperations.toggleTurningLights(carIndex, car, turningLights)

        -- for now go directly to easing out yield
        CarManager.cars_state[carIndex] = CarManager.CarStateType.EasingOutYield
  end,
  [CarManager.CarStateType.EasingOutYield] = function (carIndex, dt, car, playerCar, storage)
      if LOG_CAR_STATEMACHINE_IN_CSP_LOG then Logger.log(string.format("Car %d: In state: %s", carIndex, "EasingOutYield")) end

      -- local sideSign = storage.yieldToLeft and -1 or 1
      local targetSplineOffset = 0
      -- local splineOffsetTransitionSpeed = storage.rampRelease
      local splineOffsetTransitionSpeed = storage.rampRelease_mps
      local currentSplineOffset = CarManager.cars_currentSplineOffset[carIndex]
      currentSplineOffset = MathHelpers.approach(currentSplineOffset, targetSplineOffset, splineOffsetTransitionSpeed * dt)
      -- if math.abs(currentSplineOffset) <= 0.01 then
        -- currentSplineOffset = 0
      -- end

      -- set the spline offset on the ai car
      local overrideAiAwareness = storage.overrideAiAwareness -- TODO: check what this does
      physics.setAISplineOffset(carIndex, currentSplineOffset, overrideAiAwareness)

      -- keep inverted turning lights on while easing out yield (inverted yield direction since the car is now going back to center)
      local turningLights = (not storage.yieldToLeft) and ac.TurningLights.Left or ac.TurningLights.Right
      CarOperations.toggleTurningLights(carIndex, car, turningLights)

      CarManager.cars_currentSplineOffset[carIndex] = currentSplineOffset
      CarManager.cars_targetSplineOffset[carIndex] = targetSplineOffset

      local arrivedBackToNormal = currentSplineOffset == 0
      if arrivedBackToNormal then
        CarManager.cars_state[carIndex] = CarManager.CarStateType.TryingToStartDrivingNormally
        return
      end
  end
}

local function doCarYieldingLogic_STATEMACHINE(dt)
  local storage = StorageManager.getStorage()
  local sim = ac.getSim()
  local playerCar = ac.getCar(0)
  if not playerCar then return end

  -- TODO: ac.iterateCars.ordered could be useful when we start applying the overtaking/yielding logic to ai cars too instead of just the local player

  for carIndex = 1, (sim.carsCount or 0) - 1 do
    local car = ac.getCar(carIndex)
    if
      car and
      car.isAIControlled and  -- only run the yielding logic on ai cars
      not CarManager.cars_evacuating[carIndex] -- don't run yielding logic if car is evacuating
    then
      CarManager.ensureDefaults(carIndex) -- Ensure defaults are set if this car hasn't been initialized yet

      -- execute the state machine for this car
      carStateMachine[CarManager.cars_state[carIndex]](carIndex, dt, car, playerCar, storage)

      local carState = CarManager.cars_state[carIndex]
      -- local aiCarCurrentlyYielding = not (carState == CarManager.CarStateType.DrivingNormally)
      local aiCarCurrentlyYielding = carState == CarManager.CarStateType.YieldingToTheSide

      CarManager.cars_currentlyYielding[carIndex] = aiCarCurrentlyYielding

      local distanceFromPlayerCarToAICar = MathHelpers.vlen(MathHelpers.vsub(playerCar.position, car.position))
      CarManager.cars_distanceFromPlayerToCar[carIndex] = distanceFromPlayerCarToAICar
    end
  end
end

local function doCarYieldingLogic_BOOLEANS(dt)
  local storage = StorageManager.getStorage()
  local sim = ac.getSim()
  local playerCar = ac.getCar(0)
  if not playerCar then return end

  -- TODO: ac.iterateCars.ordered could be useful when we start applying the overtaking/yielding logic to ai cars too instead of just the local player

  for carIndex = 1, (sim.carsCount or 0) - 1 do
    local car = ac.getCar(carIndex)
    if
      car and
      car.isAIControlled and  -- only run the yielding logic on ai cars
      not CarManager.cars_evacuating[carIndex] -- don't run yielding logic if car is evacuating
    then
      CarManager.ensureDefaults(carIndex) -- Ensure defaults are set if this car hasn't been initialized yet

      local carStatusText = CarManager.cars_reason[carIndex]
      local aiCarCurrentlyYielding = CarManager.cars_currentlyYielding[carIndex]
      local currentSplineOffset = CarManager.cars_currentSplineOffset[carIndex]
      local targetSplineOffset = CarManager.cars_targetSplineOffset[carIndex]

      local distanceFromPlayerCarToAICar = MathHelpers.vlen(MathHelpers.vsub(playerCar.position, car.position))
      local isPlayerCarBehindAICar = CarOperations.isBehind(car, playerCar)
      local isPlayerClearlyAheadOfAICar = CarOperations.playerIsClearlyAhead(car, playerCar, storage.clearAhead_meters)

      local sideSign = storage.yieldToLeft and -1 or 1

      local radius = storage.detectInner_meters + storage.detectHysteresis_meters
      local isAICarCloseToPlayerCar = distanceFromPlayerCarToAICar <= radius
      if not isAICarCloseToPlayerCar then
        carStatusText = 'Too far (outside detect radius) so not yielding'
        targetSplineOffset = 0
        goto continue
      end

      -- The ai car is currently close to the player car

      if aiCarCurrentlyYielding then -- The ai car is currently yielding
        -- If the ai car is yielding and the player car is now clearly ahead, we can ease out our yielding
        if isPlayerClearlyAheadOfAICar then
          carStatusText = 'Player clearly ahead, so easing out yield'
          targetSplineOffset = 0
          goto continue
        end

        -- Since the player car is still close, we must continue yielding
        carStatusText = 'Continuing to yield'
        targetSplineOffset = sideSign
        goto continue
      else -- The ai car is currently NOT yielding

        -- Check if the player car is above the minimum speed
        local isPlayerAboveMinSpeed = playerCar.speedKmh >= storage.minPlayerSpeed_kmh
        if not isPlayerAboveMinSpeed then
          carStatusText = 'Player below minimum speed so not yielding'
          targetSplineOffset = 0
          goto continue
        end

        -- Check if the player car is currently faster than the ai car 
        local playerCarHasClosingSpeedToAiCar = (playerCar.speedKmh - car.speedKmh) >= storage.minSpeedDelta_kmh
        if not playerCarHasClosingSpeedToAiCar then
          carStatusText = 'Player does not have closing speed so not yielding'
          targetSplineOffset = 0
          goto continue
        end

        -- Check if the ai car is above the minimum speed
        local isAICarAboveMinSpeed = car.speedKmh >= storage.minAISpeed_kmh
        if not isAICarAboveMinSpeed then
          carStatusText = 'AI speed too low (corner/traffic) so not yielding'
          targetSplineOffset = 0
          goto continue
        end

        -- Since all the checks have passed, the ai car can now start to yield
        carStatusText = 'Starting to yield'
        targetSplineOffset = sideSign
        goto continue
      end


      ::continue::

      -- calculate spline offset
      local splineOffsetTransitionSpeed = currentSplineOffset < targetSplineOffset and storage.rampSpeed or storage.rampRelease
      currentSplineOffset = MathHelpers.approach(currentSplineOffset, targetSplineOffset, splineOffsetTransitionSpeed * dt)

      -- aiCarCurrentlyYielding = not (targetSplineOffset == 0)
      aiCarCurrentlyYielding = not (currentSplineOffset == 0)

      -- set the spline offset on the ai car
      local overrideAiAwareness = true -- TODO: check what this does
      physics.setAISplineOffset(carIndex, currentSplineOffset, overrideAiAwareness)

      -- todo: implement the turning lights logic here
      -- CarOperations.applyIndicators(carIndex, willYield, car)

      CarManager.cars_currentlyYielding[carIndex] = aiCarCurrentlyYielding
      CarManager.cars_distanceFromPlayerToCar[carIndex] = distanceFromPlayerCarToAICar
      CarManager.cars_reason[carIndex] = carStatusText
      CarManager.cars_currentSplineOffset[carIndex] = currentSplineOffset
      CarManager.cars_targetSplineOffset[carIndex] = targetSplineOffset
    end
  end
end

---
-- wiki: called after a whole simulation update
---
function script.MANIFEST__UPDATE(dt)
  if (not shouldAppRun()) then return end
  -- doCarYieldingLogic_old(dt)
  -- doCarYieldingLogic_BOOLEANS(dt)
  doCarYieldingLogic_STATEMACHINE(dt)
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
