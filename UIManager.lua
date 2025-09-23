local UIManager = {}

-- UI Car list table colors
local CARLIST_ROW_BACKGROUND_COLOR_SELECTED = rgbm(1, 0, 0, 0.3)
local CARLIST_ROW_BACKGROUND_COLOR_CLICKED = rgbm(1, 0, 0, 0.3)
local CARLIST_ROW_BACKGROUND_COLOR_HOVERED = rgbm(1, 0, 0, 0.1)
local CARLIST_ROW_TEXT_COLOR_LOCALPLAYER = ColorManager.RGBM_Colors.Violet

local CARSTATES_TO_CARLIST_ROW_TEXT_COLOR_CURRENTSTATE = {
  [CarStateMachine.CarStateType.DRIVING_NORMALLY] = ColorManager.RGBM_Colors.White,
  [CarStateMachine.CarStateType.EASING_IN_YIELD] = ColorManager.RGBM_Colors.LimeGreen,
  [CarStateMachine.CarStateType.STAYING_ON_YIELDING_LANE] = ColorManager.RGBM_Colors.YellowGreen,
  [CarStateMachine.CarStateType.EASING_OUT_YIELD] = ColorManager.RGBM_Colors.Yellow,
  [CarStateMachine.CarStateType.WAITING_AFTER_ACCIDENT] = ColorManager.RGBM_Colors.Red,
  [CarStateMachine.CarStateType.COLLIDED_WITH_TRACK] = ColorManager.RGBM_Colors.DarkRed,
  [CarStateMachine.CarStateType.COLLIDED_WITH_CAR] = ColorManager.RGBM_Colors.Rose,
  [CarStateMachine.CarStateType.ANOTHER_CAR_COLLIDED_INTO_ME] = ColorManager.RGBM_Colors.OrangeRed,
  [CarStateMachine.CarStateType.EASING_IN_OVERTAKE] = ColorManager.RGBM_Colors.DodgerBlue,
  [CarStateMachine.CarStateType.STAYING_ON_OVERTAKING_LANE] = ColorManager.RGBM_Colors.DeepSkyBlue,
  [CarStateMachine.CarStateType.EASING_OUT_OVERTAKE] = ColorManager.RGBM_Colors.Cyan,
}

local carTableColumns_name = { }
local carTableColumns_orderDirection = { }
local carTableColumns_width = { }
local carTableColumns_tooltip = { }

-- this table is only used to set the data to the actual data holders i.e. the tables named carTableColumns_xxx
local carTableColumns_dataBeforeDoD = {
  { name = '#', orderDirection = 0, width = 35, tooltip='Car ID' },
  -- { name = 'Distance (m)', orderDirection = -1, width = 100, tooltip='Distance to player' },
  { name = 'Speed', orderDirection = 0, width = 70, tooltip='Current velocity' },
  { name = 'AverageSpeed', orderDirection = 0, width = 70, tooltip='Average speed' },
  { name = 'RealOffset', orderDirection = 0, width = 75, tooltip='Actual Lateral offset from centerline' },
  { name = 'Offset', orderDirection = 0, width = 60, tooltip='Lateral offset from centerline' },
  { name = 'TargetOffset', orderDirection = 0, width = 90, tooltip='Desired lateral offset' },
  -- { name = 'UT Distance', orderDirection = 0, width = 90, tooltip='Upcoming Turn distance' },
  -- { name = 'UT TurnAngle', orderDirection = 0, width = 90, tooltip='Upcoming Turn turn-angle' },
  { name = 'Pedals (C,B,G)', orderDirection = 0, width = 100, tooltip='Pedal positions' },
  { name = 'ThrottleLimit', orderDirection = 0, width = 90, tooltip='Max throttle limit' },
  { name = 'AITopSpeed', orderDirection = 0, width = 90, tooltip='AI top speed' },
  { name = 'AICaution', orderDirection = 0, width = 80, tooltip='AI caution level' },
  -- { name = 'AIStopCounter', orderDirection = 0, width = 105, tooltip='AI stop counter' },
  -- { name = 'GentleStop', orderDirection = 0, width = 85, tooltip='Gentle stop' },
  { name = 'PreviousState', orderDirection = 0, width = 170, tooltip='Previous state' },
  { name = 'CurrentState', orderDirection = 0, width = 170, tooltip='Current state' },
  { name = 'StateTime', orderDirection = 0, width = 75, tooltip='Time spent in current state' },
  { name = 'Yielding', orderDirection = 0, width = 70, tooltip='Yielding status' },
  { name = 'Overtaking', orderDirection = 0, width = 80, tooltip='Overtaking status' },
  { name = 'PreviousStateExitReason', orderDirection = 0, width = 300, tooltip='Reason for last state exit' },
  { name = "CantYieldReason", orderDirection = 0, width = 300, tooltip="Reason why the car can't yield" },
  { name = "CantOvertakeReason", orderDirection = 0, width = 800, tooltip="Reason why the car can't overtake" },
}

local uiCarListSelectedIndex = 0

-- add the car table columns data to the actual data holders
for i, col in ipairs(carTableColumns_dataBeforeDoD) do
  carTableColumns_name[i] = col.name
  carTableColumns_orderDirection[i] = col.orderDirection
  carTableColumns_width[i] = col.width
  carTableColumns_tooltip[i] = col.tooltip
end

UIManager.drawMainWindowContent = function()
  local storage = StorageManager.getStorage()
  ui.text(string.format('AI cars yielding to the %s', RaceTrackManager.TrackSideStrings[storage.yieldSide]))

  --[====[
  -- Andreas: testing the indicator lights issue here
  -- Andreas:  It seems to be a car-specific issue for ai driven cars, because for example on an ai car, ac.setTurningLights works fine on the Ferrari GTO 84 but doesn't work on the Alfa Mito, but then the function works with both cars when driven by the local player.
  if ui.button('Left indicator', ui.ButtonFlags.None) then
    CarOperations.toggleTurningLights(3, ac.getCar(1), ac.TurningLights.Left)
  end
  ui.sameLine()
  if ui.button('Right indicator', ui.ButtonFlags.None) then
    CarOperations.toggleTurningLights(0, ac.getCar(1), ac.TurningLights.Right)
  end
  --]====]

  ui.separator()

  -- local sim = ac.getSim()
  -- local yieldingCount = 0
  -- local totalAI = math.max(0, (sim.carsCount or 1) - 1)
  -- for i = 1, totalAI do
    -- if CarManager.cars_currentlyYielding[i] then
      -- yieldingCount = yieldingCount + 1
    -- end
  -- end
  -- ui.text(string.format('Yielding: %d / %d', yieldingCount, totalAI))

  if not storage.drawCarList then
    return
  end

  -- Draw as a table: columns with headings
  -- draw the column headers including setting the width
  local totalColumns = #carTableColumns_name
  ui.columns(totalColumns, true)
  for col = 1, totalColumns do
    ui.columnSortingHeader(carTableColumns_name[col], carTableColumns_orderDirection[col])
    ui.setColumnWidth(col-1, carTableColumns_width[col])
  end

  local sortedCarsList = CarManager.currentSortedCarsList

  for n = 1, #sortedCarsList do
    local car = sortedCarsList[n]
    local carIndex = car.index
    if car and CarManager.cars_initialized[carIndex] then
      -- local distShown = order[n].d or CarManager.cars_distanceFromPlayerToCar[carIndex]
      local state = CarStateMachine.getCurrentState(carIndex)
      local throttleLimitString = (not (CarManager.cars_throttleLimit[carIndex] == 1)) and string.format('%.2f', CarManager.cars_throttleLimit[carIndex]) or 'no limit'
      local aiTopSpeedString = (not (CarManager.cars_aiTopSpeed[carIndex] == math.huge)) and string.format('%d', CarManager.cars_aiTopSpeed[carIndex]) or 'no limit'
      -- local cantYieldReason = CarManager.cars_reasonWhyCantYield[carIndex] or ''
      -- local cantYieldReason = Strings.StringValues[Strings.StringCategories.ReasonWhyCantYield][CarManager.cars_reasonWhyCantYield_NAME[carIndex]] or ''
      -- local cantOvertakeReason = CarManager.cars_reasonWhyCantOvertake[carIndex] or ''
      local cantYieldReason = StringsManager.resolveStringValue(Strings.StringCategories.ReasonWhyCantYield, CarManager.cars_reasonWhyCantYield_NAME[carIndex]) or ''
      local cantOvertakeReason = StringsManager.resolveStringValue(Strings.StringCategories.ReasonWhyCantOvertake, CarManager.cars_reasonWhyCantOvertake_NAME[carIndex]) or ''
      local uiColor = CARSTATES_TO_CARLIST_ROW_TEXT_COLOR_CURRENTSTATE[state] or ColorManager.RGBM_Colors.White
      if car.index == 0 then
        uiColor = CARLIST_ROW_TEXT_COLOR_LOCALPLAYER
      end

      local carInput = ac.overrideCarControls(carIndex)
      local currentlyYieldingCarIndex = CarManager.cars_currentlyYieldingCarToIndex[carIndex]
      local currentlyYielding = currentlyYieldingCarIndex
      local currentlyOvertakingCarIndex = CarManager.cars_currentlyOvertakingCarIndex[carIndex]
      local currentlyOvertaking = currentlyOvertakingCarIndex
      -- local actualTrackLateralOffset = CarManager.getActualTrackLateralOffset(carIndex)
      local actualTrackLateralOffset = CarManager.getActualTrackLateralOffset(car.position)

      -- local previousCarState = CarStateMachine.cars_previousState[carIndex]
      local previousCarState = CarStateMachine.getPreviousState(carIndex)
      -- local lastStateExitReason = CarManager.cars_statesExitReason[carIndex][previousCarState] or ''
      local lastStateExitReason = StringsManager.resolveStringValue(Strings.StringCategories.StateExitReason, CarManager.cars_statesExitReason_NAME[carIndex][previousCarState]) or ''

      -- local trackUpcomingTurn = ac.getTrackUpcomingTurn(carIndex)
      local isMidCorner, distanceToUpcomingTurn = CarManager.isCarMidCorner(carIndex)

      -- TODO: this assert check should move to somewhere else
      if currentlyOvertaking and currentlyYielding then
        Logger.error(string.format('Car #%d (current: %s, previous:%s) is both yielding to car #%d and overtaking car #%d at the same time!', carIndex, CarStateMachine.CarStateTypeStrings[state],CarStateMachine.CarStateTypeStrings[previousCarState], currentlyYieldingCarIndex, currentlyOvertakingCarIndex))
      end

      -- start a new ui id section so that we don't have name collisions
      ui.pushID(carIndex)

      -- cache the top-left screen position of this row so we can draw the full-row background first, then reset the cursor to the same Y before drawing cells.
      local rowTop = ui.cursorScreenPos()  -- current screen-space cursor

      -- send the full-row clickable to the background so the per-cell text/controls render cleanly on top across all columns
      ui.pushColumnsBackground()

      -- push the row colors we'll use for the full-row clickable
      ui.pushStyleColor(ui.StyleColor.Header, CARLIST_ROW_BACKGROUND_COLOR_SELECTED)
      ui.pushStyleColor(ui.StyleColor.HeaderActive, CARLIST_ROW_BACKGROUND_COLOR_CLICKED)
      ui.pushStyleColor(ui.StyleColor.HeaderHovered, CARLIST_ROW_BACKGROUND_COLOR_HOVERED)

      -- create the full-row selectable which will be clickable
      local isRowSelected = carIndex == uiCarListSelectedIndex
      local rowH = ui.textLineHeightWithSpacing()
      -- todo: check about this string concat here: '##row'..carIndex
      ui.selectable('##row'..carIndex, isRowSelected, ui.SelectableFlags.SpanAllColumns, vec2(0, rowH)) -- ui.SelectableFlags.SpanAllColumns used to expand the hitbox across the entire row

      -- grab the itemClicked event of the selectable we just created
      local rowClicked = ui.itemClicked()         -- capture immediately (refers to the selectable)
      -- ui.setItemAllowOverlap()                     -- allow drawing cells over the clickable area

      -- pop the row colors now that the selectable is done
      ui.popStyleColor(3)

      -- pop the columns background so that cells draw normally
      ui.popColumnsBackground()

      -- put cursor back so first cell draws at the right Y
      -- this is because we're drawing the clickable row first and then drawing the cells on top of it
      ui.setCursorScreenPos(rowTop)

      -- Row cells
      ui.textColored(string.format("#%02d", carIndex), uiColor); ui.nextColumn()
      -- if ui.itemHovered() then ui.setTooltip(carTableColumns_tooltip[1]) end
      -- ui.textColored(string.format("%.3f", distShown or 0), uiColor); ui.nextColumn()
      ui.textColored(string.format("%d km/h", math.floor(car.speedKmh)), uiColor); ui.nextColumn()
      ui.textColored(string.format("%d km/h", math.floor(CarManager.cars_averageSpeedKmh[carIndex] or 0)), uiColor); ui.nextColumn()
      ui.textColored(string.format("%.3f", actualTrackLateralOffset), uiColor); ui.nextColumn()
      ui.textColored(string.format("%.3f", CarManager.getCalculatedTrackLateralOffset(carIndex) or 0), uiColor); ui.nextColumn()
      ui.textColored(string.format("%.3f", CarManager.cars_targetSplineOffset[carIndex] or 0), uiColor); ui.nextColumn()
      -- ui.textColored(string.format("%.3f", trackUpcomingTurn.x, uiColor)); ui.nextColumn()
      -- ui.textColored(string.format("%.3f", distanceToUpcomingTurn, uiColor)); ui.nextColumn()
      -- ui.textColored(string.format("%.3f", trackUpcomingTurn.y, uiColor)); ui.nextColumn()
      ui.textColored(string.format("%.1f|%.1f|%.1f", carInput.clutch, carInput.brake, carInput.gas), uiColor); ui.nextColumn()
      ui.textColored(throttleLimitString, uiColor); ui.nextColumn()
      ui.textColored(aiTopSpeedString, uiColor); ui.nextColumn()
      ui.textColored(tostring(CarManager.cars_aiCaution[carIndex] or 0), uiColor); ui.nextColumn()
      -- ui.textColored(tostring(CarManager.cars_aiStopCounter[carIndex] or 0), uiColor); ui.nextColumn()
      -- ui.textColored(tostring(CarManager.cars_gentleStop[carIndex]), uiColor); ui.nextColumn()
      ui.textColored(CarStateMachine.CarStateTypeStrings[previousCarState], uiColor); ui.nextColumn()
      ui.textColored(CarStateMachine.CarStateTypeStrings[state], uiColor); ui.nextColumn()
      ui.textColored(string.format("%.1fs", CarManager.cars_timeInCurrentState[carIndex]), uiColor); ui.nextColumn()
      -- if CarManager.cars_currentlyYielding[carIndex] then
      if currentlyYielding then
        -- ui.textColored(string.format("yes (%.1fs)", CarManager.cars_yieldTime[carIndex] or 0), uiColor)
        ui.textColored(string.format("yes #%d", currentlyYieldingCarIndex), uiColor)
      else
        ui.textColored("no", uiColor)
      end
      ui.nextColumn()
      if currentlyOvertaking then
        -- ui.textColored(string.format("yes (%.1fs)", CarManager.cars_yieldTime[i] or 0), uiColor)
        -- ui.textColored(string.format("yes"), uiColor)
        ui.textColored(string.format("yes #%d", currentlyOvertakingCarIndex), uiColor)
      else
        ui.textColored("no", uiColor)
      end
      ui.nextColumn()
      ui.textColored(lastStateExitReason, uiColor); ui.nextColumn()
      ui.textColored(cantYieldReason, uiColor); ui.nextColumn()
      ui.textColored(cantOvertakeReason, uiColor); ui.nextColumn()

      -- end the ui id section
      ui.popID()

      if rowClicked then
          -- Logger.log(string.format('UIManager: Car row %d clicked', carIndex))
          uiCarListSelectedIndex = carIndex
          CameraManager.followCarWithChaseCamera(carIndex)
      end

    end
  end

  -- reset columns
  ui.columns(1, false)
end

-- UIManager.indicatorStatusText = function(i)
    -- local l = CarManager.cars_indLeft[i]
    -- local r = CarManager.cars_indRight[i]
    -- local ph = CarManager.cars_indPhase[i]
    -- local indTxt = '-'
    -- if l or r then
        -- if l and r then
            -- indTxt = ph and 'H*' or 'H'
        -- elseif l then
            -- indTxt = ph and 'L*' or 'L'
        -- else
            -- indTxt = ph and 'R*' or 'R'
        -- end
    -- end
    -- if CarManager.cars_hasTL[i] == false then indTxt = indTxt .. '(!)' end
    -- return indTxt
-- end

local overheadTextHeightAboveCar = vec3(0, 2.0, 0)

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

  -- for i = 1, sim.carsCount - 1 do
  for i = 0, sim.carsCount do
  -- for i, car in ac.iterateCars() do
    CarManager.ensureDefaults(i) -- Ensure defaults are set if this car hasn't been initialized yet
    -- if CarManager.cars_initialized[i] and (math.abs(CarManager.cars_currentSplineOffset_meters[i] or 0) > 0.02 or CarManager.cars_isSideBlocked[i]) then
    local carState = CarStateMachine.getCurrentState(i)
    if CarManager.cars_initialized[i] and carState ~= CarStateMachine.CarStateType.DRIVING_NORMALLY then
      local car = ac.getCar(i)
      if car then
        -- local txt = string.format(
          -- "#%02d d=%5.1fm  v=%3dkm/h  offset=%4.3f  targetOffset=%4.3f state=%s",
          -- i, CarManager.cars_distanceFromPlayerToCar[i], math.floor(car.speedKmh),
          -- CarManager.cars_currentSplineOffset[i],
          -- CarManager.cars_targetSplineOffset[i],
          -- carState
        -- )
        -- -- do
        -- --   local indicatorStatusText = UIManager.indicatorStatusText(i)
        -- --   txt = txt .. string.format("  ind=%s", indicatorStatusText)
        -- -- end

        -- -- render the text slightly above the car
        -- render.debugText(car.position + vec3(0, 2.0, 0), txt)

        local text = string.format("#%d %s", car.index, CarStateMachine.CarStateTypeStrings[carState])
        render.debugText(car.position + overheadTextHeightAboveCar, text, CARSTATES_TO_CARLIST_ROW_TEXT_COLOR_CURRENTSTATE[carState])
      end
    end
  end

  render.setDepthMode(depthModeBeforeModification)
end

function UIManager.renderUIOptionsControls()
    local storage = StorageManager.getStorage()

    if ui.checkbox('Enabled', storage.enabled) then storage.enabled = not storage.enabled end
    if ui.itemHovered() then ui.setTooltip('Master switch for this app.') end

    -- if ui.checkbox('Draw markers on top (no depth test)', storage.drawOnTop) then storage.drawOnTop = not storage.drawOnTop end
    -- if ui.itemHovered() then ui.setTooltip('If markers are hidden by car bodywork, enable this so text ignores depth testing.') end

    local comboValueChanged
    storage.yieldSide, comboValueChanged = ui.combo('YIELD Side', storage.yieldSide, ui.ComboFlags.NoPreview, RaceTrackManager.TrackSideStrings)
    if ui.itemHovered() then ui.setTooltip('The track side which AI will yield to when you approach from the rear.') end

    if ui.checkbox('Override AI awareness', storage.overrideAiAwareness) then storage.overrideAiAwareness = not storage.overrideAiAwareness end
    if ui.itemHovered() then ui.setTooltip('If enabled, AI will be less aware of the player car and may yield more easily. (EXPERIMENTAL)') end

    if ui.checkbox('Handle overtaking', storage.handleOvertaking) then storage.handleOvertaking = not storage.handleOvertaking end
    if ui.itemHovered() then ui.setTooltip('If enabled, AI cars will attempt to overtake on the correct lane') end

    if ui.checkbox('Handle side checking while yielding/overtaking', storage.handleSideChecking) then storage.handleSideChecking = not storage.handleSideChecking end
    if ui.itemHovered() then ui.setTooltip('If enabled, cars will check for other cars on the side when yielding.') end

    if ui.checkbox('Handle accidents', storage.handleAccidents) then storage.handleAccidents = not storage.handleAccidents end
    if ui.itemHovered() then ui.setTooltip('If enabled, AI will stop and remain stopped after an accident until the player car passes.') end

    if ui.checkbox('Draw Debug Gizmos', storage.debugDraw) then storage.debugDraw = not storage.debugDraw end
    if ui.itemHovered() then ui.setTooltip('Shows 3D debug information about the cars') end

    if ui.checkbox('Draw Car List', storage.drawCarList) then storage.drawCarList = not storage.drawCarList end
    if ui.itemHovered() then ui.setTooltip('Shows a list of all cars in the scene') end

    storage.detectCarBehind_meters =  ui.slider('Detect radius (m)', storage.detectCarBehind_meters, 5, 90)
    if ui.itemHovered() then ui.setTooltip('Start yielding if the player is behind and within this distance') end

    storage.yieldMaxOffset_normalized =  ui.slider('Side offset', storage.yieldMaxOffset_normalized, 0.1, 1.0)
    if ui.itemHovered() then ui.setTooltip('How far to move towards the chosen side when yielding (0.1 barely moving to the side, 1.0 moving as much as possible to the side).') end

    storage.minPlayerSpeed_kmh =  ui.slider('Min player speed (km/h)', storage.minPlayerSpeed_kmh, 0, 160)
    if ui.itemHovered() then ui.setTooltip('Ignore very low-speed approaches (pit exits, traffic jams).') end

    -- storage.minSpeedDelta_kmh =  ui.slider('Min speed delta (km/h)', storage.minSpeedDelta_kmh, 0, 30)
    -- if ui.itemHovered() then ui.setTooltip('Require some closing speed before asking AI to yield.') end

    storage.rampSpeed_mps =  ui.slider('Yield Offset ramp (m/s)', storage.rampSpeed_mps, 0.1, 3.0)
    if ui.itemHovered() then ui.setTooltip('How quickly the side offset ramps up when yielding.') end

    storage.rampRelease_mps =  ui.slider('Offset release (m/s)', storage.rampRelease_mps, 0.1, 3.0)
    if ui.itemHovered() then ui.setTooltip('How quickly the side offset returns to normal once an overtaking car has fully driven past the yielding car.') end

    storage.overtakeRampSpeed_mps =  ui.slider('Overtake offset ramp (m/s)', storage.overtakeRampSpeed_mps, 0.1, 3.0)
    if ui.itemHovered() then ui.setTooltip('How quickly the side offset ramps up when overtaking another car.') end

    storage.overtakeRampRelease_mps =  ui.slider('Overtake offset release (m/s)', storage.overtakeRampRelease_mps, 0.1, 3.0)
    if ui.itemHovered() then ui.setTooltip('How quickly the side offset returns to normal once an overtaking car has fully driven past the overtaken car.') end

    storage.minAISpeed_kmh =  ui.slider('Min AI speed (km/h)', storage.minAISpeed_kmh, 0, 120)
    if ui.itemHovered() then ui.setTooltip('Don’t ask AI to yield if its own speed is below this (corners/traffic).') end

    -- storage.distanceToFrontCarToOvertake =  ui.slider('Min distance to front car to overtake (m)', storage.distanceToFrontCarToOvertake, 1.0, 20.0)
    -- if ui.itemHovered() then ui.setTooltip('Minimum distance to the car in front before an AI car will consider overtaking it.') end
end

return UIManager
