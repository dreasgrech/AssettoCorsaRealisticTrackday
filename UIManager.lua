local UIManager = {}

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
  if storage.drawOnTop then
    -- draw over everything (no depth testing)
    render.setDepthMode(render.DepthMode.Off)
  else
    -- respect existing depth, don’t write to depth (debug text won’t “punch holes”)
    render.setDepthMode(render.DepthMode.ReadOnlyLessEqual)
  end

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
end

function UIManager.renderUIOptionsControls()
    local storage = StorageManager.getStorage()

    if ui.checkbox('Enabled', storage.enabled) then storage.enabled = not storage.enabled end
    if ui.itemHovered() then ui.setTooltip('Master switch for this app.') end

    if ui.checkbox('Debug markers (3D)', storage.debugDraw) then storage.debugDraw = not storage.debugDraw end
    if ui.itemHovered() then ui.setTooltip('Shows floating text above AI cars currently yielding.') end

    if ui.checkbox('Draw markers on top (no depth test)', storage.drawOnTop) then storage.drawOnTop = not storage.drawOnTop end
    if ui.itemHovered() then ui.setTooltip('If markers are hidden by car bodywork, enable this so text ignores depth testing.') end

    if ui.checkbox('Yield to LEFT (instead of RIGHT)', storage.yieldToLeft) then storage.yieldToLeft = not storage.yieldToLeft end
    if ui.itemHovered() then ui.setTooltip('If enabled, AI moves left to let you pass on the right. Otherwise AI moves right so you pass on the left.') end

    if ui.checkbox('Override AI awareness', storage.overrideAiAwareness) then storage.overrideAiAwareness = not storage.overrideAiAwareness end
    if ui.itemHovered() then ui.setTooltip('If enabled, AI will be less aware of the player car and may yield more easily.') end

    storage.detectInner_meters =  ui.slider('Detect radius (m)', storage.detectInner_meters, 5, 90)
    if ui.itemHovered() then ui.setTooltip('Start yielding if the player is within this distance AND behind the AI car.') end

    storage.detectHysteresis_meters =  ui.slider('Hysteresis (m)', storage.detectHysteresis_meters, 20, 120)
    if ui.itemHovered() then ui.setTooltip('Extra distance while yielding so AI doesn’t flicker on/off near threshold.') end

    storage.yieldOffset_meters =  ui.slider('Side offset (m)', storage.yieldOffset_meters, 0.5, 4.0)
    if ui.itemHovered() then ui.setTooltip('How far to move towards the chosen side when yielding.') end

    storage.rightMargin_meters =  ui.slider('Edge margin (m)', storage.rightMargin_meters, 0.3, 1.2)
    if ui.itemHovered() then ui.setTooltip('Safety gap from the outer edge on the chosen side.') end

    storage.minPlayerSpeed_kmh =  ui.slider('Min player speed (km/h)', storage.minPlayerSpeed_kmh, 0, 160)
    if ui.itemHovered() then ui.setTooltip('Ignore very low-speed approaches (pit exits, traffic jams).') end

    storage.minSpeedDelta_kmh =  ui.slider('Min speed delta (km/h)', storage.minSpeedDelta_kmh, 0, 30)
    if ui.itemHovered() then ui.setTooltip('Require some closing speed before asking AI to yield.') end

    -- storage.rampSpeed_mps =  ui.slider('Offset ramp (m/s)', storage.rampSpeed_mps, 1.0, 10.0)
    storage.rampSpeed_mps =  ui.slider('Offset ramp (m/s)', storage.rampSpeed_mps, 0.1, 10.0)
    if ui.itemHovered() then ui.setTooltip('Ramp speed of offset change.') end

    -- storage.rampRelease_mps =  ui.slider('Offset release (m/s)', storage.rampRelease_mps, 0.2, 6.0)
    storage.rampRelease_mps =  ui.slider('Offset release (m/s)', storage.rampRelease_mps, 0.1, 10.0)
    if ui.itemHovered() then ui.setTooltip('How quickly offset returns to center once you’re past the AI.') end

    storage.listRadiusFilter_meters =  ui.slider('List radius filter (m)', storage.listRadiusFilter_meters, 0, 1000)
    if ui.itemHovered() then ui.setTooltip('Only show cars within this distance in the list (0 = show all).') end

    storage.minAISpeed_kmh =  ui.slider('Min AI speed (km/h)', storage.minAISpeed_kmh, 0, 120)
    if ui.itemHovered() then ui.setTooltip('Don’t ask AI to yield if its own speed is below this (corners/traffic).') end
end

return UIManager