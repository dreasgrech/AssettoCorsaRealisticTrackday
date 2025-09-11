local UIManager = {}

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

UIManager.drawMainWindowContent = function()
  local storage = StorageManager.getStorage()
  ui.text(string.format('AI cars yielding to the %s', RaceTrackManager.TrackSideStrings[storage.yieldSide]))

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

  -- Draw as a table: columns with headings
  local COLS = 13
  ui.columns(COLS, true)
  ui.columnSortingHeader('#', 0)
  ui.columnSortingHeader('Distance (m)', -1)
  ui.columnSortingHeader('Velocity (km/h)', 0)
  ui.columnSortingHeader('Offset', 0)
  ui.columnSortingHeader('TargetOffset', 0)
  ui.columnSortingHeader('ThrottleLimit', 0)
  ui.columnSortingHeader('AICaution', 0)
  ui.columnSortingHeader('AITopSpeed', 0)
  ui.columnSortingHeader('AIStopCounter', 0)
  ui.columnSortingHeader('GentleStop', 0)
  ui.columnSortingHeader('State', 0)
  ui.columnSortingHeader('Yielding', 0)
  ui.columnSortingHeader('Reason', 0)

  for n = 1, #order do
    local i = order[n].i
    local car = ac.getCar(i)
    if car and CarManager.cars_initialized[i] then
      local distShown = order[n].d or CarManager.cars_distanceFromPlayerToCar[i]
      local state = CarStateMachine.getCurrentState(i)
      local throttleLimitString = (not (CarManager.cars_throttleLimit[i] == 1)) and string.format('%.2f', CarManager.cars_throttleLimit[i]) or 'none'
      local aiTopSpeedString = (not (CarManager.cars_aiTopSpeed[i] == math.huge)) and string.format('%d', CarManager.cars_aiTopSpeed[i]) or 'none'
      local reason = CarManager.cars_reasonWhyCantYield[i] or ''
      local uiColor = CARSTATES_TO_UICOLOR[state] or ColorManager.RGBM_Colors.White

      -- Row cells
      ui.textColored(string.format("#%02d", i), uiColor); ui.nextColumn()
      ui.textColored(string.format("%.3f", distShown or 0), uiColor); ui.nextColumn()
      ui.textColored(string.format("%d", math.floor(car.speedKmh)), uiColor); ui.nextColumn()
      ui.textColored(string.format("%.3f", CarManager.cars_currentSplineOffset[i] or 0), uiColor); ui.nextColumn()
      ui.textColored(string.format("%.3f", CarManager.cars_targetSplineOffset[i] or 0), uiColor); ui.nextColumn()
      ui.textColored(throttleLimitString, uiColor); ui.nextColumn()
      ui.textColored(tostring(CarManager.cars_aiCaution[i] or 0), uiColor); ui.nextColumn()
      ui.textColored(aiTopSpeedString, uiColor); ui.nextColumn()
      ui.textColored(tostring(CarManager.cars_aiStopCounter[i] or 0), uiColor); ui.nextColumn()
      ui.textColored(tostring(CarManager.cars_gentleStop[i]), uiColor); ui.nextColumn()
      ui.textColored(CarStateMachine.CarStateTypeStrings[state] or tostring(state), uiColor); ui.nextColumn()
      if CarManager.cars_currentlyYielding[i] then
        ui.textColored(string.format("yes (%.1fs)", CarManager.cars_yieldTime[i] or 0), uiColor)
      else
        ui.textColored("no", uiColor)
      end
      ui.nextColumn()
      ui.textColored(reason, uiColor); ui.nextColumn()
    end
  end

  -- reset columns
  ui.columns(1, false)
end

UIManager.indicatorStatusText = function(i)
    local l = CarManager.cars_indLeft[i]
    local r = CarManager.cars_indRight[i]
    local ph = CarManager.cars_indPhase[i]
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
    if CarManager.cars_hasTL[i] == false then indTxt = indTxt .. '(!)' end
    if CarManager.cars_isSideBlocked[i] then
        -- explicitly show that we’re not able to move over yet and are slowing to create space
        indTxt = (indTxt ~= '-' and (indTxt .. ' ') or '') .. '(slowing due to yield lane blocked)'
    end
    return indTxt
end

function UIManager.draw3DOverheadText()
  local storage = StorageManager.getStorage()
  if not storage.debugDraw then return end
  local sim = ac.getSim()
  local depthModeBeforeModification = render.DepthMode
  -- if storage.drawOnTop then
    -- -- draw over everything (no depth testing)
    -- render.setDepthMode(render.DepthMode.Off)
  -- else
    -- -- respect existing depth, don’t write to depth (debug text won’t “punch holes”)
    -- render.setDepthMode(render.DepthMode.ReadOnlyLessEqual)
  -- end

  for i = 1, (sim.carsCount or 0) - 1 do
    CarManager.ensureDefaults(i) -- Ensure defaults are set if this car hasn't been initialized yet
    -- if CarManager.cars_initialized[i] and (math.abs(CarManager.cars_currentSplineOffset_meters[i] or 0) > 0.02 or CarManager.cars_isSideBlocked[i]) then
    local carState = CarStateMachine.getCurrentState(i)
    if CarManager.cars_initialized[i] and carState ~= CarStateMachine.CarStateType.DRIVING_NORMALLY then
      local car = ac.getCar(i)
      if car then
        local txt = string.format(
          "#%02d d=%5.1fm  v=%3dkm/h  offset=%4.3f  targetOffset=%4.3f state=%s",
          i, CarManager.cars_distanceFromPlayerToCar[i], math.floor(car.speedKmh),
          CarManager.cars_currentSplineOffset[i],
          CarManager.cars_targetSplineOffset[i],
          carState
        )
        -- do
        --   local indicatorStatusText = UIManager.indicatorStatusText(i)
        --   txt = txt .. string.format("  ind=%s", indicatorStatusText)
        -- end

        -- render the text slightly above the car
        render.debugText(car.position + vec3(0, 2.0, 0), txt)
      end
    end
  end

  render.setDepthMode(depthModeBeforeModification)
end

function UIManager.renderUIOptionsControls()
    local storage = StorageManager.getStorage()

    if ui.checkbox('Enabled', storage.enabled) then storage.enabled = not storage.enabled end
    if ui.itemHovered() then ui.setTooltip('Master switch for this app.') end

    if ui.checkbox('Debug markers (3D)', storage.debugDraw) then storage.debugDraw = not storage.debugDraw end
    if ui.itemHovered() then ui.setTooltip('Shows floating text above AI cars currently yielding.') end

    -- if ui.checkbox('Draw markers on top (no depth test)', storage.drawOnTop) then storage.drawOnTop = not storage.drawOnTop end
    -- if ui.itemHovered() then ui.setTooltip('If markers are hidden by car bodywork, enable this so text ignores depth testing.') end

    local comboValueChanged
    storage.yieldSide, comboValueChanged = ui.combo('YIELD Side', storage.yieldSide, ui.ComboFlags.NoPreview, RaceTrackManager.TrackSideStrings)
    if ui.itemHovered() then ui.setTooltip('The track side which AI will yield to when you approach from the rear.') end

    if ui.checkbox('Override AI awareness', storage.overrideAiAwareness) then storage.overrideAiAwareness = not storage.overrideAiAwareness end
    if ui.itemHovered() then ui.setTooltip('If enabled, AI will be less aware of the player car and may yield more easily.') end

    if ui.checkbox('Handle accidents', storage.handleAccidents) then storage.handleAccidents = not storage.handleAccidents end
    if ui.itemHovered() then ui.setTooltip('If enabled, AI will stop and remain stopped after an accident until the player car passes.') end

    storage.detectCarBehind_meters =  ui.slider('Detect radius (m)', storage.detectCarBehind_meters, 5, 90)
    if ui.itemHovered() then ui.setTooltip('Start yielding if the player is behind and within this distance') end

    storage.yieldMaxOffset_normalized =  ui.slider('Side offset', storage.yieldMaxOffset_normalized, 0.1, 1.0)
    if ui.itemHovered() then ui.setTooltip('How far to move towards the chosen side when yielding (0.1 barely moving to the side, 1.0 moving as much as possible to the side).') end

    storage.minPlayerSpeed_kmh =  ui.slider('Min player speed (km/h)', storage.minPlayerSpeed_kmh, 0, 160)
    if ui.itemHovered() then ui.setTooltip('Ignore very low-speed approaches (pit exits, traffic jams).') end

    storage.minSpeedDelta_kmh =  ui.slider('Min speed delta (km/h)', storage.minSpeedDelta_kmh, 0, 30)
    if ui.itemHovered() then ui.setTooltip('Require some closing speed before asking AI to yield.') end

    storage.rampSpeed_mps =  ui.slider('Offset ramp (m/s)', storage.rampSpeed_mps, 0.1, 3.0)
    if ui.itemHovered() then ui.setTooltip('Ramp speed of offset change.') end

    storage.rampRelease_mps =  ui.slider('Offset release (m/s)', storage.rampRelease_mps, 0.1, 3.0)
    if ui.itemHovered() then ui.setTooltip('How quickly offset returns to center once you’re past the AI.') end

    storage.minAISpeed_kmh =  ui.slider('Min AI speed (km/h)', storage.minAISpeed_kmh, 0, 120)
    if ui.itemHovered() then ui.setTooltip('Don’t ask AI to yield if its own speed is below this (corners/traffic).') end
end

return UIManager
