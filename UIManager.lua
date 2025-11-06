local UIManager = {}

--bindings
local ac = ac
local ac_getSim = ac.getSim
local ac_getCar = ac.getCar
local ac_setWindowOpen = ac.setWindowOpen
local ac_isWindowOpen = ac.isWindowOpen
local ac_overrideCarControls = ac.overrideCarControls
local ac_getTrackAISplineSides = ac.getTrackAISplineSides
local ui = ui
local ui_itemHovered = ui.itemHovered
local ui_setTooltip = ui.setTooltip
local ui_columns = ui.columns
local ui_setColumnWidth = ui.setColumnWidth
local ui_nextColumn = ui.nextColumn
local ui_newLine = ui.newLine
local ui_text = ui.text
local ui_separator = ui.separator
local ui_textColored = ui.textColored
local ui_pushStyleColor = ui.pushStyleColor
local ui_popStyleColor = ui.popStyleColor
local ui_itemRectMin = ui.itemRectMin
local ui_itemRectMax = ui.itemRectMax
local ui_textLineHeightWithSpacing = ui.textLineHeightWithSpacing
local ui_cursorScreenPos = ui.cursorScreenPos
local ui_setItemAllowOverlap = ui.setItemAllowOverlap
local ui_setCursorScreenPos = ui.setCursorScreenPos
local ui_invisibleButton = ui.invisibleButton
local ui_windowPos = ui.windowPos
local ui_columnSortingHeader = ui.columnSortingHeader
local ui_pushColumnsBackground = ui.pushColumnsBackground
local ui_popColumnsBackground = ui.popColumnsBackground
local ui_pushID = ui.pushID
local ui_popID = ui.popID
local ui_selectable = ui.selectable
local ui_itemClicked = ui.itemClicked
local ui_sameLine = ui.sameLine
local ui_getScrollMaxY = ui.getScrollMaxY
local ui_getScrollX = ui.getScrollX
local ui_getScrollY = ui.getScrollY
local render = render
local render_debugText = render.debugText
local math = math
local math_max = math.max
local math_floor = math.floor
local string = string
local string_format = string.format
local StorageManager = StorageManager
local RaceTrackManager = RaceTrackManager
local RaceTrackManager_getDefaultDrivingSide = RaceTrackManager.getDefaultDrivingSide
local RaceTrackManager_getOvertakingSide = RaceTrackManager.getOvertakingSide
local RaceTrackManager_getYieldingSide = RaceTrackManager.getYieldingSide
local ColorManager = ColorManager
local UILateralOffsetsImageWidget = UILateralOffsetsImageWidget
local UILateralOffsetsImageWidget_draw = UILateralOffsetsImageWidget.draw
local CarStateMachine = CarStateMachine
local CarStateMachine_getCurrentState = CarStateMachine.getCurrentState
local CarStateMachine_getPreviousState = CarStateMachine.getPreviousState
local CarManager = CarManager
local CarManager_getCalculatedTrackLateralOffset = CarManager.getCalculatedTrackLateralOffset
local CarManager_getActualTrackLateralOffset = CarManager.getActualTrackLateralOffset
local CarManager_getClosingSpeed = CarManager.getClosingSpeed
local CameraManager = CameraManager
local CameraManager_getFocusedCarIndex = CameraManager.getFocusedCarIndex
local CameraManager_followCarWithChaseCamera = CameraManager.followCarWithChaseCamera
local MathHelpers = MathHelpers
local MathHelpers_distanceBetweenVec3sSqr = MathHelpers.distanceBetweenVec3sSqr
local StringsManager = StringsManager
local StringsManager_resolveStringValue = StringsManager.resolveStringValue
local Logger = Logger
local Logger_error = Logger.error


-- These are the window IDs as defined in the manifest.ini
local MAIN_WINDOW_ID = 'mainWindow'
local SETTINGS_WINDOW_ID = 'settingsWindow'

-- UI Car list table colors
local CARLIST_ROW_BACKGROUND_COLOR_SELECTED = rgbm(1, 0, 0, 0.3)
local CARLIST_ROW_BACKGROUND_COLOR_CLICKED = rgbm(1, 0, 0, 0.3)
local CARLIST_ROW_BACKGROUND_COLOR_HOVERED = rgbm(1, 0, 0, 0.1)
local CARLIST_ROW_TEXT_COLOR_LOCALPLAYER = ColorManager.RGBM_Colors.Violet

UIManager.VERTICAL_SCROLLBAR_WIDTH = 9 * 2 -- Andreas: the * 2 is to account for the tiny margin that's created next to the vertical scrollbar which seems to be the same size as the scrollbar width

local storage = StorageManager.getStorage()
local storage_Yielding = StorageManager.getStorage_Yielding()
local storage_Overtaking = StorageManager.getStorage_Overtaking()
local storage_Debugging = StorageManager.getStorage_Debugging()

local CARSTATES_TO_CARLIST_ROW_TEXT_COLOR_CURRENTSTATE = {
  [CarStateMachine.CarStateType.DRIVING_NORMALLY] = ColorManager.RGBM_Colors.White,
  [CarStateMachine.CarStateType.EASING_IN_YIELD] = ColorManager.RGBM_Colors.LimeGreen,
  [CarStateMachine.CarStateType.STAYING_ON_YIELDING_LANE] = ColorManager.RGBM_Colors.YellowGreen,
  [CarStateMachine.CarStateType.EASING_OUT_YIELD] = ColorManager.RGBM_Colors.DarkKhaki,
  [CarStateMachine.CarStateType.WAITING_AFTER_ACCIDENT] = ColorManager.RGBM_Colors.Red,
  [CarStateMachine.CarStateType.COLLIDED_WITH_TRACK] = ColorManager.RGBM_Colors.DarkRed,
  [CarStateMachine.CarStateType.COLLIDED_WITH_CAR] = ColorManager.RGBM_Colors.Rose,
  [CarStateMachine.CarStateType.ANOTHER_CAR_COLLIDED_INTO_ME] = ColorManager.RGBM_Colors.OrangeRed,
  [CarStateMachine.CarStateType.EASING_IN_OVERTAKE] = ColorManager.RGBM_Colors.DodgerBlue,
  [CarStateMachine.CarStateType.STAYING_ON_OVERTAKING_LANE] = ColorManager.RGBM_Colors.DeepSkyBlue,
  [CarStateMachine.CarStateType.EASING_OUT_OVERTAKE] = ColorManager.RGBM_Colors.Cyan,
  [CarStateMachine.CarStateType.NAVIGATING_AROUND_ACCIDENT] = ColorManager.RGBM_Colors.MediumPurple,
  [CarStateMachine.CarStateType.DRIVING_IN_YELLOW_FLAG_ZONE] = ColorManager.RGBM_Colors.Yellow,
  -- [CarStateMachine.CarStateType.AFTER_CUSTOMAIFLOOD_TELEPORT] = ColorManager.RGBM_Colors.LightGray,
}

local carTableColumns_name = { }
local carTableColumns_orderDirection = { }
local carTableColumns_width = { }
local carTableColumns_tooltip = { }

-- this table is only used to set the data to the actual data holders i.e. the tables named carTableColumns_xxx
local carTableColumns_dataBeforeDoD = {
  { name = '#', orderDirection = 0, width = 35, tooltip='Car ID' },
  -- { name = 'Distance (m)', orderDirection = -1, width = 100, tooltip='Distance to player' },
  { name = 'SplinePosition', orderDirection = 0, width = 50, tooltip='Spline Position' },
  { name = 'SplineSides', orderDirection = 0, width = 75, tooltip='Spline Sides' },
  -- { name = 'MaxSpeed', orderDirection = 0, width = 70, tooltip='Max Speed' },
  { name = 'Speed', orderDirection = 0, width = 70, tooltip='Current velocity' },
  { name = 'AvgSpeed', orderDirection = 0, width = 75, tooltip='Average speed' },
  { name = 'ActualOffset', orderDirection = 0, width = 88, tooltip='Actual Lateral offset from centerline' },
  { name = 'CalculatedOffset', orderDirection = 0, width = 110, tooltip='Lateral offset from centerline' },
  { name = 'TargetOffset', orderDirection = 0, width = 90, tooltip='Desired lateral offset' },
  -- { name = 'UT Distance', orderDirection = 0, width = 90, tooltip='Upcoming Turn distance' },
  -- { name = 'UT TurnAngle', orderDirection = 0, width = 90, tooltip='Upcoming Turn turn-angle' },
  { name = 'Pedals (C,B,G)', orderDirection = 0, width = 100, tooltip='Pedal positions' },
  { name = 'ThrottlePedalLimit', orderDirection = 0, width = 90, tooltip='Max throttle pedal limit' },
  { name = 'TopSpeedLimit', orderDirection = 0, width = 90, tooltip='AI top speed limit' },
  { name = 'AICaution', orderDirection = 0, width = 75, tooltip='AI caution level' },
  { name = 'AIAggression', orderDirection = 0, width = 75, tooltip='AI aggression level' },
  { name = 'AIDifficultyLevel', orderDirection = 0, width = 75, tooltip='AI difficulty level' },
  { name = 'Grip', orderDirection = 0, width = 40, tooltip='AI grip level' },
  -- { name = 'AIStopCounter', orderDirection = 0, width = 105, tooltip='AI stop counter' },
  -- { name = 'GentleStop', orderDirection = 0, width = 85, tooltip='Gentle stop' },
  { name = 'ClosingSpeed', orderDirection = 0, width = 95, tooltip='Closing speed to car in front' },
  { name = 'TimeToCollide', orderDirection = 0, width = 75, tooltip='Time to collide to car in front' },
  { name = 'FrontCarDistance', orderDirection = 0, width = 75, tooltip='The distance to the car in front' },
  { name = 'PreviousState', orderDirection = 0, width = 160, tooltip='Previous state' },
  { name = 'CurrentState', orderDirection = 0, width = 160, tooltip='Current state' },
  { name = 'TimeInState', orderDirection = 0, width = 90, tooltip='Time spent in current state' },
  { name = 'Yielding', orderDirection = 0, width = 70, tooltip='Yielding status' },
  { name = 'Overtaking', orderDirection = 0, width = 80, tooltip='Overtaking status' },
  -- { name = 'InvolvedInAccident', orderDirection = 0, width = 40, tooltip='Involved in accident status' },
  -- { name = 'NavigatingAccident', orderDirection = 0, width = 40, tooltip='Navigating accident status' },
  { name = 'PreviousStateExitReason', orderDirection = 0, width = 250, tooltip='Reason for last state exit' },
  { name = "CantYieldReason", orderDirection = 0, width = 220, tooltip="Reason why the car can't yield" },
  { name = "CantOvertakeReason", orderDirection = 0, width = 260, tooltip="Reason why the car can't overtake" },
}

local uiCarListSelectedIndex = 0

-- add the car table columns data to the actual data holders
for i, col in ipairs(carTableColumns_dataBeforeDoD) do
  carTableColumns_name[i] = col.name
  carTableColumns_orderDirection[i] = col.orderDirection
  carTableColumns_width[i] = col.width
  carTableColumns_tooltip[i] = col.tooltip
end

carTableColumns_dataBeforeDoD = nil  -- free memory

local OVERHEAD_TEXT_HEIGHT_ABOVE_CAR = vec3(0, 2.0, 0)

local uiCarListSetDefaultColumnWidths = false

local addTooltipOverLastItem_scrollPosition = vec2(0,0)
local addTooltipOverLastItem_invisibleButtonPosition = vec2(0,0)
local addTooltipOverLastItem_invisibleButtonSize = vec2(0,0)

-- Andreas: This function is needed because ImGui doesn't have built-in support for tooltips on column headers in tables i.e. ui.itemHovered() after a call to ui.columnSortingHeader() doesn't work.
-- Minimal overlay for column-header tooltips.
-- Uses the header’s own rect AFTER it’s drawn, so IDs/widths match.
local function addTooltipOnTableColumnHeader(text, idSuffix)
  -- Header rect is returned in window space:
  local itemRectMin = ui_itemRectMin()
  local itemRectMax = ui_itemRectMax()
  local w = math_max(itemRectMax.x - itemRectMin.x, 1)
  local h = math_max(itemRectMax.y - itemRectMin.y, ui_textLineHeightWithSpacing())
  addTooltipOverLastItem_invisibleButtonSize:set(w, h)

  -- capture the current cursor screen position to restore it later, since we're going to move it to draw an invisible button which will capture the hover state
  local previousCursorScreenPosition = ui_cursorScreenPos()

  -- allow the invisible button to be drawn outside the normal item rect so that it can cover the entire column header area
  ui_setItemAllowOverlap()

  -- determine the position of where to place the invisible button which will capture the hover for the tooltip
  local scrollX = ui_getScrollX()
  local scrollY = ui_getScrollY()
  local windowPosition = ui_windowPos()
  addTooltipOverLastItem_scrollPosition:set(scrollX, scrollY)
  addTooltipOverLastItem_invisibleButtonPosition:set(windowPosition):sub(addTooltipOverLastItem_scrollPosition):add(itemRectMin)
  ui_setCursorScreenPos(addTooltipOverLastItem_invisibleButtonPosition)

  -- draw the invisible button over the column header
  ui_invisibleButton('##carListTableHeaderTip'..idSuffix, addTooltipOverLastItem_invisibleButtonSize)

  -- show the tooltip if hovered over the invisible button
  if ui_itemHovered() then
    ui_setTooltip(text)
  end

  -- restore previous cursor screen position before we added the invisible button
  ui_setCursorScreenPos(previousCursorScreenPosition)
end

UIManager.isVerticalScrollVisible = function()
  local scrollMaxY = ui_getScrollMaxY()
  return scrollMaxY > 0
end

UIManager.drawUICarList = function()

  --[====[
  if ui.button('Teleport', ui.ButtonFlags.None) then
    local carIndex = 1
    local car = ac.getCar(carIndex)
    -- local splinePosition = 0.1
    -- local worldPosition = ac.trackProgressToWorldCoordinate(splinePosition, false)
    -- -- local direction = car.look
    -- local direction = car.look
    -- physics.setCarPosition(carIndex, worldPosition, direction)

    -- CustomAIFloodManager.teleportCar(car, .1)
  end
  --]====]

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

  ui_separator()

  -- local sim = ac.getSim()
  -- local yieldingCount = 0
  -- local totalAI = math.max(0, (sim.carsCount or 1) - 1)
  -- for i = 1, totalAI do
    -- if CarManager.cars_currentlyYielding[i] then
      -- yieldingCount = yieldingCount + 1
    -- end
  -- end
  -- ui.text(string_format('Yielding: %d / %d', yieldingCount, totalAI))

  if not storage_Debugging.drawCarList then
    ui_newLine(1)
    ui_textColored('To understand exactly what each AI car is doing, enable the "Show the UI Car List" option in the Debugging settings.', ColorManager.RGBM_Colors.Aquamarine)
    ui_textColored('A table of all the cars will then be displayed here showing all kinds of data about the cars and the kinds of decisions they are taking.', ColorManager.RGBM_Colors.Aquamarine)
    return
  end

  -- Draw as a table: columns with headings
  -- draw the column headers including setting the width
  local totalColumns = #carTableColumns_name
  ui_columns(totalColumns, true)
  for col = 1, totalColumns do
    if not uiCarListSetDefaultColumnWidths then
      ui_setColumnWidth(col-1, carTableColumns_width[col])
    end
    -- ui.getColumnWidth
    addTooltipOnTableColumnHeader(carTableColumns_tooltip[col], col)
    ui_columnSortingHeader(carTableColumns_name[col], carTableColumns_orderDirection[col])
  end

  uiCarListSetDefaultColumnWidths = true  -- only set the default column widths once

  local sortedCarsList = CarManager.currentSortedCarsList

  for n = 1, #sortedCarsList do
    local car = sortedCarsList[n]
    local carIndex = car.index
    if car and CarManager.cars_initialized[carIndex] then
      -- local distShown = order[n].d or CarManager.cars_distanceFromPlayerToCar[carIndex]
      local state = CarStateMachine_getCurrentState(carIndex)
      local throttleLimitString = (not (CarManager.cars_throttleLimit[carIndex] == 1)) and string_format('%.2f', CarManager.cars_throttleLimit[carIndex]) or 'no limit'
      local aiTopSpeedString = (not (CarManager.cars_aiTopSpeed[carIndex] == math.huge)) and string_format('%d km/h', CarManager.cars_aiTopSpeed[carIndex]) or 'no limit'
      -- local cantYieldReason = CarManager.cars_reasonWhyCantYield[carIndex] or ''
      -- local cantYieldReason = Strings.StringValues[Strings.StringCategories.ReasonWhyCantYield][CarManager.cars_reasonWhyCantYield_NAME[carIndex]] or ''
      -- local cantOvertakeReason = CarManager.cars_reasonWhyCantOvertake[carIndex] or ''
      local cantYieldReason = StringsManager_resolveStringValue(Strings.StringCategories.ReasonWhyCantYield, CarManager.cars_reasonWhyCantYield_NAME[carIndex]) or ''
      local cantOvertakeReason = StringsManager_resolveStringValue(Strings.StringCategories.ReasonWhyCantOvertake, CarManager.cars_reasonWhyCantOvertake_NAME[carIndex]) or ''
      local uiColor = CARSTATES_TO_CARLIST_ROW_TEXT_COLOR_CURRENTSTATE[state] or ColorManager.RGBM_Colors.White
      if car.index == 0 then
        uiColor = CARLIST_ROW_TEXT_COLOR_LOCALPLAYER
      end

      local carInput = ac_overrideCarControls(carIndex)
      local carInputClutch = -1
      local carInputGas = -1
      local carInputBrake = -1
      if carInput then
        carInputClutch = carInput.clutch
        carInputGas = carInput.gas
        carInputBrake = carInput.brake
      end

      local currentlyYieldingCarIndex = CarManager.cars_currentlyYieldingCarToIndex[carIndex]
      local currentlyYielding = currentlyYieldingCarIndex
      local currentlyOvertakingCarIndex = CarManager.cars_currentlyOvertakingCarIndex[carIndex]
      local currentlyOvertaking = currentlyOvertakingCarIndex
      -- local actualTrackLateralOffset = CarManager.getActualTrackLateralOffset(carIndex)
      local actualTrackLateralOffset = CarManager_getActualTrackLateralOffset(car.position)

      local culpritInAccidentIndex = AccidentManager.cars_culpritInAccidentIndex[carIndex]
      local victimInAccidentIndex = AccidentManager.cars_victimInAccidentIndex[carIndex]
      local involvedInAccidentIndex = culpritInAccidentIndex or victimInAccidentIndex
      local currentlyNavigatingAroundAccidentIndex = CarManager.cars_navigatingAroundAccidentIndex[carIndex]

      -- local previousCarState = CarStateMachine.cars_previousState[carIndex]
      local previousCarState = CarStateMachine_getPreviousState(carIndex)
      -- local lastStateExitReason = CarManager.cars_statesExitReason[carIndex][previousCarState] or ''
      local lastStateExitReason = StringsManager_resolveStringValue(Strings.StringCategories.StateExitReason, CarManager.cars_statesExitReason_NAME[carIndex][previousCarState]) or ''

      -- local isMidCorner, distanceToUpcomingTurn = CarManager.isCarMidCorner(carIndex)

      local carSplinePosition = car.splinePosition
      local trackAISplineSides = ac_getTrackAISplineSides(carSplinePosition)

      local carFront = sortedCarsList[n-1]
      local closingSpeed, timeToCollision, distanceToFrontCar = CarManager_getClosingSpeed(car, carFront)

      local aiCaution = CarManager.cars_aiCaution[carIndex]
      -- local aiAggression = CarManager.cars_aiAggression[carIndex]
      local aiAggression = car.aiAggression
      local aiDifficultyLevel = car.aiLevel

      -- TODO: this assert check should move to somewhere else
      if currentlyOvertaking and currentlyYielding then
        Logger_error(string_format('Car #%d (current: %s, previous:%s) is both yielding to car #%d and overtaking car #%d at the same time!', carIndex, CarStateMachine.CarStateTypeStrings[state],CarStateMachine.CarStateTypeStrings[previousCarState], currentlyYieldingCarIndex, currentlyOvertakingCarIndex))
      end

      -- start a new ui id section so that we don't have name collisions
      ui_pushID(carIndex)

      -- cache the top-left screen position of this row so we can draw the full-row background first, then reset the cursor to the same Y before drawing cells.
      local rowTop = ui_cursorScreenPos()  -- current screen-space cursor

      -- send the full-row clickable to the background so the per-cell text/controls render cleanly on top across all columns
      ui_pushColumnsBackground()

      -- push the row colors we'll use for the full-row clickable
      ui_pushStyleColor(ui.StyleColor.Header, CARLIST_ROW_BACKGROUND_COLOR_SELECTED)
      ui_pushStyleColor(ui.StyleColor.HeaderActive, CARLIST_ROW_BACKGROUND_COLOR_CLICKED)
      ui_pushStyleColor(ui.StyleColor.HeaderHovered, CARLIST_ROW_BACKGROUND_COLOR_HOVERED)

      -- create the full-row selectable which will be clickable
      local isRowSelected = carIndex == uiCarListSelectedIndex
      local rowH = ui_textLineHeightWithSpacing()
      -- todo: check about this string concat here: '##row'..carIndex
      ui_selectable('##row'..carIndex, isRowSelected, ui.SelectableFlags.SpanAllColumns, vec2(0, rowH)) -- ui.SelectableFlags.SpanAllColumns used to expand the hitbox across the entire row

      -- grab the itemClicked event of the selectable we just created
      local rowClicked = ui_itemClicked()         -- capture immediately (refers to the selectable)
      -- ui.setItemAllowOverlap()                     -- allow drawing cells over the clickable area

      -- pop the row colors now that the selectable is done
      ui_popStyleColor(3)

      -- pop the columns background so that cells draw normally
      ui_popColumnsBackground()

      -- put cursor back so first cell draws at the right Y
      -- this is because we're drawing the clickable row first and then drawing the cells on top of it
      ui_setCursorScreenPos(rowTop)

      -- Row cells
      ui_textColored(string_format("#%02d", carIndex), uiColor); ui_nextColumn()
      -- if ui.itemHovered() then ui.setTooltip(carTableColumns_tooltip[1]) end
      -- ui.textColored(string_format("%.3f", distShown or 0), uiColor); ui.nextColumn()
      ui_textColored(string_format("%.3f", carSplinePosition), uiColor); ui_nextColumn()
      ui_textColored(string_format("%.2f|%.2f", trackAISplineSides.x, trackAISplineSides.y), uiColor); ui_nextColumn()
      -- ui.textColored(string_format("%d km/h", CarManager.cars_MAXTOPSPEED[carIndex]), uiColor); ui.nextColumn()
      ui_textColored(string_format("%d km/h", math_floor(car.speedKmh)), uiColor); ui_nextColumn()
      ui_textColored(string_format("%d km/h", math_floor(CarManager.cars_averageSpeedKmh[carIndex] or 0)), uiColor); ui_nextColumn()
      ui_textColored(string_format("%.3f", actualTrackLateralOffset), uiColor); ui_nextColumn()
      ui_textColored(string_format("%.3f", CarManager_getCalculatedTrackLateralOffset(carIndex) or 0), uiColor); ui_nextColumn()
      ui_textColored(string_format("%.3f", CarManager.cars_targetSplineOffset[carIndex] or 0), uiColor); ui_nextColumn()
      -- ui.textColored(string_format("%.3f", trackUpcomingTurn.x, uiColor)); ui.nextColumn()
      -- ui.textColored(string_format("%.3f", distanceToUpcomingTurn, uiColor)); ui.nextColumn()
      -- ui.textColored(string_format("%.3f", trackUpcomingTurn.y, uiColor)); ui.nextColumn()
      ui_textColored(string_format("%.1f|%.1f|%.1f", carInputClutch, carInputBrake, carInputGas), uiColor); ui_nextColumn()
      ui_textColored(throttleLimitString, uiColor); ui_nextColumn()
      ui_textColored(aiTopSpeedString, uiColor); ui_nextColumn()
      ui_textColored(string_format("%.2f", aiCaution), uiColor); ui_nextColumn()
      ui_textColored(string_format("%.2f", aiAggression), uiColor); ui_nextColumn()
      ui_textColored(string_format("%.2f", aiDifficultyLevel), uiColor); ui_nextColumn()
      ui_textColored(string_format("%.2f", CarManager.cars_grip[carIndex] or 0), uiColor); ui_nextColumn()
      ui_textColored(string_format("%.2f km/h", closingSpeed), uiColor); ui_nextColumn()
      ui_textColored(string_format("%.2fs", timeToCollision), uiColor); ui_nextColumn()
      ui_textColored(string_format("%.2f m", distanceToFrontCar), uiColor); ui_nextColumn()
      -- ui.textColored(tostring(CarManager.cars_aiStopCounter[carIndex] or 0), uiColor); ui.nextColumn()
      -- ui.textColored(tostring(CarManager.cars_gentleStop[carIndex]), uiColor); ui.nextColumn()
      ui_textColored(CarStateMachine.CarStateTypeStrings[previousCarState], uiColor); ui_nextColumn()
      ui_textColored(CarStateMachine.CarStateTypeStrings[state], uiColor); ui_nextColumn()
      ui_textColored(string_format("%.1fs", CarManager.cars_timeInCurrentState[carIndex]), uiColor); ui_nextColumn()
      -- if CarManager.cars_currentlyYielding[carIndex] then
      if currentlyYielding then
        -- ui.textColored(string_format("yes (%.1fs)", CarManager.cars_yieldTime[carIndex] or 0), uiColor)
        ui_textColored(string_format("yes #%d", currentlyYieldingCarIndex), uiColor)
      else
        ui_textColored("no", uiColor)
      end
      ui_nextColumn()
      if currentlyOvertaking then
        -- ui.textColored(string_format("yes (%.1fs)", CarManager.cars_yieldTime[i] or 0), uiColor)
        -- ui.textColored(string_format("yes"), uiColor)
        ui_textColored(string_format("yes #%d", currentlyOvertakingCarIndex), uiColor)
      else
        ui_textColored("no", uiColor)
      end
      ui_nextColumn()

      -- if involvedInAccidentIndex then
        -- local culpritOrVictim = culpritInAccidentIndex and "Culprit" or "Victim"
        -- ui.textColored(string_format("Accident:#%d %s", involvedInAccidentIndex, culpritOrVictim), uiColor)
      -- else
        -- ui.textColored("no", uiColor)
      -- end
      -- ui.nextColumn()

      -- if currentlyNavigatingAroundAccidentIndex and currentlyNavigatingAroundAccidentIndex > 0 then
        -- ui.textColored(string_format("yes #%d (car: #%d)", currentlyNavigatingAroundAccidentIndex, CarManager.cars_navigatingAroundCarIndex[carIndex]), uiColor)
      -- else
        -- ui.textColored("no", uiColor)
      -- end
      -- ui.nextColumn()

      ui_textColored(lastStateExitReason, uiColor); ui_nextColumn()
      ui_textColored(cantYieldReason, uiColor); ui_nextColumn()
      ui_textColored(cantOvertakeReason, uiColor); ui_nextColumn()

      -- end the ui id section
      ui_popID()

      if rowClicked then
          -- Logger.log(string_format('UIManager: Car row %d clicked', carIndex))
          uiCarListSelectedIndex = carIndex
          CameraManager_followCarWithChaseCamera(carIndex)
      end

    end
  end

  -- reset columns
  ui_columns(1, false)
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

function UIManager.drawCarStateOverheadText()
  if not storage_Debugging.debugShowCarStateOverheadText then return end
  local sim = ac_getSim()
  -- local depthModeBeforeModification = render.DepthMode
  -- if storage.drawOnTop then
    -- -- draw over everything (no depth testing)
    -- render.setDepthMode(render.DepthMode.Off)
  -- else
    -- -- respect existing depth, don’t write to depth (debug text won’t “punch holes”)
    -- render.setDepthMode(render.DepthMode.ReadOnlyLessEqual)
  -- end

    -- render.setDepthMode(render.DepthMode.WriteOnly)
    -- render.setCullMode(render.CullMode.Wireframe)

    -- render.CullMode

  -- local prevDepth = render.DepthMode
  -- local prevBlend = render.BlendMode

--render.setDepthMode(render.DepthMode.WriteOnly)   -- test against scene, don’t write
  --render.setBlendMode(render.BlendMode.BlendPremultiplied)        -- act like opaque even in transparent pass  (SDK: OpaqueForced)

  -- for i = 1, sim.carsCount - 1 do

  local debugCarStateOverheadShowDistance = storage_Debugging.debugCarGizmosDrawistance
  local debugCarStateOverheadShowDistanceSqr = debugCarStateOverheadShowDistance * debugCarStateOverheadShowDistance
  local cameraFocusedCarIndex = CameraManager_getFocusedCarIndex()
  local cameraFocusedCar = ac_getCar(cameraFocusedCarIndex)
  local carsCount = sim.carsCount
  if cameraFocusedCar then
    local cameraFocusedCarPosition = cameraFocusedCar.position
    for i = 0, carsCount do
    -- for i, car in ac.iterateCars() do
      -- CarManager.ensureDefaults(i) -- Ensure defaults are set if this car hasn't been initialized yet
      -- if CarManager.cars_initialized[i] and (math.abs(CarManager.cars_currentSplineOffset_meters[i] or 0) > 0.02 or CarManager.cars_isSideBlocked[i]) then
      local carState = CarStateMachine_getCurrentState(i)
      local showText = CarManager.cars_initialized[i] and carState ~= CarStateMachine.CarStateType.DRIVING_NORMALLY
      if showText then
        local car = ac_getCar(i)
        if car then
          local distanceFromCameraFocusedCarToThisCarSqr = MathHelpers_distanceBetweenVec3sSqr(car.position, cameraFocusedCarPosition)
          local isThisCarCloseToCameraFocusedCar = distanceFromCameraFocusedCarToThisCarSqr < debugCarStateOverheadShowDistanceSqr
          if isThisCarCloseToCameraFocusedCar then
            local text = string_format("#%d %s", car.index, CarStateMachine.CarStateTypeStrings[carState])
            render_debugText(car.position + OVERHEAD_TEXT_HEIGHT_ABOVE_CAR, text, CARSTATES_TO_CARLIST_ROW_TEXT_COLOR_CURRENTSTATE[carState], 1, render.FontAlign.Center)--, render.FontAlign.Center)
          end
          -- local txt = string_format(
            -- "#%02d d=%5.1fm  v=%3dkm/h  offset=%4.3f  targetOffset=%4.3f state=%s",
            -- i, CarManager.cars_distanceFromPlayerToCar[i], math.floor(car.speedKmh),
            -- CarManager.cars_currentSplineOffset[i],
            -- CarManager.cars_targetSplineOffset[i],
            -- carState
          -- )
          -- -- do
          -- --   local indicatorStatusText = UIManager.indicatorStatusText(i)
          -- --   txt = txt .. string_format("  ind=%s", indicatorStatusText)
          -- -- end

          -- -- render the text slightly above the car
          -- render.debugText(car.position + vec3(0, 2.0, 0), txt)
        end
      end
    end
  end

  -- render.setBlendMode(prevBlend)
  -- render.setDepthMode(prevDepth)

  -- render.setDepthMode(depthModeBeforeModification)
end

UIManager.drawMainWindowLateralOffsetsSection = function()
    -- ui.dwriteText('Driving Lanes', 15)
    -- ui.newLine(1)

    ui_columns(2, false, "mainWindow_lateralsSection")
    ui_setColumnWidth(0, 260)

    local handleYielding = storage_Yielding.handleYielding
    local handleOvertaking = storage_Overtaking.handleOvertaking

    local yieldingSide = RaceTrackManager_getYieldingSide()
    local overtakingSide = RaceTrackManager_getOvertakingSide()
    local defaultDrivingSide = RaceTrackManager_getDefaultDrivingSide()
    local yieldingSideString = RaceTrackManager.TrackSideStrings[yieldingSide]
    local overtakingSideString = RaceTrackManager.TrackSideStrings[overtakingSide]
    local defaultDrivingSideString = RaceTrackManager.TrackSideStrings[defaultDrivingSide]

    ui_newLine(1)
    if handleOvertaking then
      ui_text(string_format('Overtaking Lateral Offset: %.3f (%s)', storage.overtakingLateralOffset, overtakingSideString))
      ui_newLine(1)
    end
    ui_text(string_format('Default Lateral Offset: %.3f (%s)', storage.defaultLateralOffset, defaultDrivingSideString))
    if handleYielding then
      ui_newLine(1)
      ui_text(string_format('Yielding Lateral Offset: %.3f (%s)', storage.yieldingLateralOffset, yieldingSideString))
    end

    ui_nextColumn()

    UILateralOffsetsImageWidget_draw(storage)
    --ui.textColored(string_format('Yielding side: %s, Overtaking side: %s', yieldingSideString, overtakingSideString), ColorManager.RGBM_Colors.LightSeaGreen)

    if yieldingSide == overtakingSide then
      ui_textColored('Yielding side and overtaking side are the same!', ColorManager.RGBM_Colors.Yellow)
    end

    -- end the table
    ui_columns(1, false)
    ui_newLine(1)
    ui_textColored(
      "These lateral offsets for the AI cars dictate the side of the track they should drive on depending on what they are currently doing (modifyable from the Settings).", 
      ColorManager.RGBM_Colors.DarkGray)
end

UIManager.drawAppNotRunningMessageInMainWindow = function()
    local isOnline = Constants.IS_ONLINE

    ui_textColored(string_format('Realistic Trackday not running.', tostring(storage.enabled), tostring(Constants.IS_ONLINE)), ColorManager.RGBM_Colors.Red)
    if not isOnline then
      -- ui_textColored('You can enable the app from the Settings', ColorManager.RGBM_Colors.Red)
      ui_text('You can enable the app from the Settings.')
    end
    ui_newLine(1)

    local appEnabled = storage.enabled
    ui_text('App Enabled: ')
    ui_sameLine()
    local appEnabledColor = appEnabled and ColorManager.RGBM_Colors.Green or ColorManager.RGBM_Colors.Red
    ui_textColored(string_format('%s', appEnabled and "yes" or "no"), appEnabledColor)

    ui_text('Playing Online: ')
    ui_sameLine()
    local isOnlineColor = isOnline and ColorManager.RGBM_Colors.Red or ColorManager.RGBM_Colors.Green
    ui_textColored(string_format('%s', isOnline and "yes" or "no"), isOnlineColor)
end

---Opens or closes the specified window.
---@param windowID string
---@param open boolean @true to open, false to close
local openWindow = function(windowID, open)
  ac_setWindowOpen(windowID, open)
end

---Opens the specified window if closed, or closes it if opened.
---@param windowID string
local toggleWindow = function(windowID)
  local windowOpen = ac_isWindowOpen(windowID)
  openWindow(windowID, not windowOpen)
end

UIManager.openMainWindow = function()
  openWindow(MAIN_WINDOW_ID, true)
end

UIManager.openSettingsWindow = function()
  openWindow(SETTINGS_WINDOW_ID, true)
end

UIManager.toggleSettingsWindow = function()
  toggleWindow(SETTINGS_WINDOW_ID)
end

return UIManager
