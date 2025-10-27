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
  { name = 'SplinePosition', orderDirection = 0, width = 70, tooltip='Spline Position' },
  { name = 'SplineSides', orderDirection = 0, width = 85, tooltip='Spline Sides' },
  -- { name = 'MaxSpeed', orderDirection = 0, width = 70, tooltip='Max Speed' },
  { name = 'Speed', orderDirection = 0, width = 70, tooltip='Current velocity' },
  { name = 'AverageSpeed', orderDirection = 0, width = 100, tooltip='Average speed' },
  { name = 'ActualOffset', orderDirection = 0, width = 88, tooltip='Actual Lateral offset from centerline' },
  { name = 'CalculatedOffset', orderDirection = 0, width = 110, tooltip='Lateral offset from centerline' },
  { name = 'TargetOffset', orderDirection = 0, width = 90, tooltip='Desired lateral offset' },
  -- { name = 'UT Distance', orderDirection = 0, width = 90, tooltip='Upcoming Turn distance' },
  -- { name = 'UT TurnAngle', orderDirection = 0, width = 90, tooltip='Upcoming Turn turn-angle' },
  { name = 'Pedals (C,B,G)', orderDirection = 0, width = 100, tooltip='Pedal positions' },
  { name = 'ThrottleLimit', orderDirection = 0, width = 90, tooltip='Max throttle limit' },
  { name = 'AITopSpeed', orderDirection = 0, width = 90, tooltip='AI top speed' },
  { name = 'AICaution', orderDirection = 0, width = 75, tooltip='AI caution level' },
  { name = 'Grip', orderDirection = 0, width = 40, tooltip='AI grip level' },
  -- { name = 'AIStopCounter', orderDirection = 0, width = 105, tooltip='AI stop counter' },
  -- { name = 'GentleStop', orderDirection = 0, width = 85, tooltip='Gentle stop' },
  { name = 'ClosingSpeed', orderDirection = 0, width = 95, tooltip='Closing speed to car in front' },
  { name = 'TimeToCollide', orderDirection = 0, width = 95, tooltip='Time to collision to car in front' },
  { name = 'FrontCarDistance', orderDirection = 0, width = 95, tooltip='The distance to the car in front (m)' },
  { name = 'PreviousState', orderDirection = 0, width = 170, tooltip='Previous state' },
  { name = 'CurrentState', orderDirection = 0, width = 170, tooltip='Current state' },
  { name = 'TimeInState', orderDirection = 0, width = 90, tooltip='Time spent in current state' },
  { name = 'Yielding', orderDirection = 0, width = 70, tooltip='Yielding status' },
  { name = 'Overtaking', orderDirection = 0, width = 80, tooltip='Overtaking status' },
  { name = 'InvolvedInAccident', orderDirection = 0, width = 40, tooltip='Involved in accident status' },
  { name = 'NavigatingAccident', orderDirection = 0, width = 40, tooltip='Navigating accident status' },
  { name = 'PreviousStateExitReason', orderDirection = 0, width = 250, tooltip='Reason for last state exit' },
  { name = "CantYieldReason", orderDirection = 0, width = 260, tooltip="Reason why the car can't yield" },
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

local overheadTextHeightAboveCar = vec3(0, 2.0, 0)

UIManager.drawMainWindowContent = function()
  local storage = StorageManager.getStorage()
  -- ui.text(string.format('AI cars yielding to the %s', RaceTrackManager.TrackSideStrings[storage.yieldSide]))
  ui.text(string.format('AI cars yielding to the %s', RaceTrackManager.TrackSideStrings[RaceTrackManager.getYieldingSide()]))

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
      local aiTopSpeedString = (not (CarManager.cars_aiTopSpeed[carIndex] == math.huge)) and string.format('%d km/h', CarManager.cars_aiTopSpeed[carIndex]) or 'no limit'
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
      local actualTrackLateralOffset = CarManager.getActualTrackLateralOffset(car.position)

      local culpritInAccidentIndex = AccidentManager.cars_culpritInAccidentIndex[carIndex]
      local victimInAccidentIndex = AccidentManager.cars_victimInAccidentIndex[carIndex]
      local involvedInAccidentIndex = culpritInAccidentIndex or victimInAccidentIndex
      local currentlyNavigatingAroundAccidentIndex = CarManager.cars_navigatingAroundAccidentIndex[carIndex]

      -- local previousCarState = CarStateMachine.cars_previousState[carIndex]
      local previousCarState = CarStateMachine.getPreviousState(carIndex)
      -- local lastStateExitReason = CarManager.cars_statesExitReason[carIndex][previousCarState] or ''
      local lastStateExitReason = StringsManager.resolveStringValue(Strings.StringCategories.StateExitReason, CarManager.cars_statesExitReason_NAME[carIndex][previousCarState]) or ''

      -- local isMidCorner, distanceToUpcomingTurn = CarManager.isCarMidCorner(carIndex)

      local carSplinePosition = car.splinePosition
      local trackAISplineSides = ac.getTrackAISplineSides(carSplinePosition)

      local carFront = sortedCarsList[n-1]
      local closingSpeed, timeToCollision, distanceToFrontCar = CarManager.getClosingSpeed(car, carFront)


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
      ui.textColored(string.format("%.3f", carSplinePosition), uiColor); ui.nextColumn()
      ui.textColored(string.format("%.2f|%.2f", trackAISplineSides.x, trackAISplineSides.y), uiColor); ui.nextColumn()
      -- ui.textColored(string.format("%d km/h", CarManager.cars_MAXTOPSPEED[carIndex]), uiColor); ui.nextColumn()
      ui.textColored(string.format("%d km/h", math.floor(car.speedKmh)), uiColor); ui.nextColumn()
      ui.textColored(string.format("%d km/h", math.floor(CarManager.cars_averageSpeedKmh[carIndex] or 0)), uiColor); ui.nextColumn()
      ui.textColored(string.format("%.3f", actualTrackLateralOffset), uiColor); ui.nextColumn()
      ui.textColored(string.format("%.3f", CarManager.getCalculatedTrackLateralOffset(carIndex) or 0), uiColor); ui.nextColumn()
      ui.textColored(string.format("%.3f", CarManager.cars_targetSplineOffset[carIndex] or 0), uiColor); ui.nextColumn()
      -- ui.textColored(string.format("%.3f", trackUpcomingTurn.x, uiColor)); ui.nextColumn()
      -- ui.textColored(string.format("%.3f", distanceToUpcomingTurn, uiColor)); ui.nextColumn()
      -- ui.textColored(string.format("%.3f", trackUpcomingTurn.y, uiColor)); ui.nextColumn()
      ui.textColored(string.format("%.1f|%.1f|%.1f", carInputClutch, carInputBrake, carInputGas), uiColor); ui.nextColumn()
      ui.textColored(throttleLimitString, uiColor); ui.nextColumn()
      ui.textColored(aiTopSpeedString, uiColor); ui.nextColumn()
      ui.textColored(tostring(CarManager.cars_aiCaution[carIndex] or 0), uiColor); ui.nextColumn()
      ui.textColored(string.format("%.2f", CarManager.cars_grip[carIndex] or 0), uiColor); ui.nextColumn()
      ui.textColored(string.format("%.2f km/h", closingSpeed), uiColor); ui.nextColumn()
      ui.textColored(string.format("%.2fs", timeToCollision), uiColor); ui.nextColumn()
      ui.textColored(string.format("%.2f m", distanceToFrontCar), uiColor); ui.nextColumn()
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
      
      if involvedInAccidentIndex then
        local culpritOrVictim = culpritInAccidentIndex and "Culprit" or "Victim"
        ui.textColored(string.format("Accident:#%d %s", involvedInAccidentIndex, culpritOrVictim), uiColor)
      else
        ui.textColored("no", uiColor)
      end
      ui.nextColumn()

      if currentlyNavigatingAroundAccidentIndex and currentlyNavigatingAroundAccidentIndex > 0 then
        ui.textColored(string.format("yes #%d (car: #%d)", currentlyNavigatingAroundAccidentIndex, CarManager.cars_navigatingAroundCarIndex[carIndex]), uiColor)
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

function UIManager.drawCarStateOverheadText()
  local storage = StorageManager.getStorage()
  if not storage.debugShowCarStateOverheadText then return end
  local sim = ac.getSim()
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
  local carsCount = sim.carsCount
  for i = 0, carsCount do
  -- for i, car in ac.iterateCars() do
    -- CarManager.ensureDefaults(i) -- Ensure defaults are set if this car hasn't been initialized yet
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
        render.debugText(car.position + overheadTextHeightAboveCar, text, CARSTATES_TO_CARLIST_ROW_TEXT_COLOR_CURRENTSTATE[carState], 1, render.FontAlign.Center)--, render.FontAlign.Center)
      end
    end
  end

  -- render.setBlendMode(prevBlend)
  -- render.setDepthMode(prevDepth)

  -- render.setDepthMode(depthModeBeforeModification)
end

return UIManager
