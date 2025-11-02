local SettingsWindow = {}

-- bindings
local ui = ui

local UI_HEADER_TEXT_FONT_SIZE = 15

-- Values for drawing the app icon in the settings window
local APP_ICON_PATH = Constants.APP_ICON_PATH
local APP_ICON_SIZE = Constants.APP_ICON_SIZE
local settingsWindowIconPosition = vec2(0,10) -- the x value is updated dynamically depending on the window size since we want to always draw the image at the top-right corner of the window
local settingsWindowIconPositionBottomLeft = vec2(0,0) -- this is needed for the ui.drawImage function and is also calculated dynamically

local DEFAULT_SLIDER_WIDTH = 200
local DEFAULT_SLIDER_FORMAT = '%.2f'

---Renders a slider with a tooltip
---@param label string @Slider label.
---@param tooltip string
---@param value refnumber|number @Current slider value.
---@param min number? @Default value: 0.
---@param max number? @Default value: 1.
---@param sliderWidth number
---@param labelFormat string|'%.3f'|nil @C-style format string. Default value: `'%.3f'`.
---@return number @Possibly updated slider value.
local renderSlider = function(label, tooltip, value, min, max, sliderWidth, labelFormat)
    ui.pushItemWidth(sliderWidth)
    local newValue = ui.slider(label, value, min, max, labelFormat)
    ui.popItemWidth()
    if ui.itemHovered() then ui.setTooltip(tooltip) end
    return newValue
end

local renderSliderWithInnerText = function(sliderID, labelFormat, tooltip, value, min, max, sliderWidth)
    ui.pushItemWidth(sliderWidth)
    local newValue = ui.slider(sliderID, value, min, max, labelFormat)
    ui.popItemWidth()
    if ui.itemHovered() then ui.setTooltip(tooltip) end
    return newValue
end

--- Creates a disabled section in the UI.
---@param createSection boolean @If true, will create a disabled section.
---@param callback function @Function to call to render the contents of the section.
local createDisabledSection = function(createSection, callback)
    if createSection then
        ui.pushDisabled()
    end

    callback()

    if createSection then
        ui.popDisabled()
    end
end

---@param storage_Debugging StorageTable_Debugging
local renderDebuggingSection = function(storage_Debugging)
    -- ui.text('Debugging')
    ui.newLine(1)
    ui.dwriteText('Debugging', UI_HEADER_TEXT_FONT_SIZE)
    ui.newLine(1)

    ui.columns(3, false, "debuggingSection")

    if ui.checkbox('Show car state overhead text', storage_Debugging.debugShowCarStateOverheadText) then storage_Debugging.debugShowCarStateOverheadText = not storage_Debugging.debugShowCarStateOverheadText end
    if ui.itemHovered() then ui.setTooltip("Shows the car's current state as text over the car") end

    -- storage.debugCarStateOverheadShowDistance = renderSlider('Car state overhead show distance (m)', 'The maximum distance from the camera focused car at which to show the car state overhead text.', storage.debugCarStateOverheadShowDistance, StorageManager.options_min[StorageManager.Options.DebugCarStateOverheadShowDistance], StorageManager.options_max[StorageManager.Options.DebugCarStateOverheadShowDistance], DEFAULT_SLIDER_WIDTH)
    storage_Debugging.debugCarGizmosDrawistance = renderSliderWithInnerText('##debugCarStateOverheadShowDistance', 'Car gizmos draw distance: %.0fm', 'The maximum distance from the camera focused car at which to show the car state overhead text.', storage_Debugging.debugCarGizmosDrawistance, StorageManager.options_min[StorageManager.Options_Debugging.DebugCarGizmosDrawistance], StorageManager.options_max[StorageManager.Options_Debugging.DebugCarGizmosDrawistance], DEFAULT_SLIDER_WIDTH)

    if ui.checkbox('Show raycasts when driving laterally', storage_Debugging.debugShowRaycastsWhileDrivingLaterally) then storage_Debugging.debugShowRaycastsWhileDrivingLaterally = not storage_Debugging.debugShowRaycastsWhileDrivingLaterally end
    if ui.itemHovered() then ui.setTooltip('Shows the raycasts used to check for side clearance when driving checking for cars on the side') end

    if ui.checkbox('Draw tyres side offtrack gizmos', storage_Debugging.debugDrawSideOfftrack) then storage_Debugging.debugDrawSideOfftrack = not storage_Debugging.debugDrawSideOfftrack end
    if ui.itemHovered() then ui.setTooltip('Shows gizmos for the car\'s tyres when offtrack') end

    if ui.checkbox('Draw Car List', storage_Debugging.drawCarList) then storage_Debugging.drawCarList = not storage_Debugging.drawCarList end
    if ui.itemHovered() then ui.setTooltip('Shows a list of all cars in the scene') end

    ui.nextColumn()

    if ui.checkbox('Log fast AI state changes', storage_Debugging.debugLogFastStateChanges) then storage_Debugging.debugLogFastStateChanges = not storage_Debugging.debugLogFastStateChanges end
    if ui.itemHovered() then ui.setTooltip('If enabled, will write to the CSP log if an ai car changes from one state to another very quickly') end

    if ui.checkbox('Log car yielding', storage_Debugging.debugLogCarYielding) then storage_Debugging.debugLogCarYielding = not storage_Debugging.debugLogCarYielding end
    if ui.itemHovered() then ui.setTooltip('If enabled, will write to the CSP log if an ai car is yielding to another car') end

    if ui.checkbox('Log car overtaking', storage_Debugging.debugLogCarOvertaking) then storage_Debugging.debugLogCarOvertaking = not storage_Debugging.debugLogCarOvertaking end
    if ui.itemHovered() then ui.setTooltip('If enabled, will write to the CSP log if an ai car is overtaking another car') end

    ui.nextColumn()

    createDisabledSection(not Constants.ENABLE_ACCIDENT_HANDLING_IN_APP, function()
        if ui.button('Simulate accident', ui.ButtonFlags.None) then
            AccidentManager.simulateAccident()
        end
    end)

    -- reset the column layout
    ui.columns(1, false)
end

SettingsWindow.draw = function()
    local storage = StorageManager.getStorage()
    local storage_Yielding = StorageManager.getStorage_Yielding()
    local storage_Overtaking = StorageManager.getStorage_Overtaking()

    -- Draw the app icon at the top-right of the settings window
    local settingsWindowSize = ui.windowSize()
    settingsWindowIconPosition.x = settingsWindowSize.x - (APP_ICON_SIZE.x + 10)
    settingsWindowIconPositionBottomLeft.x = settingsWindowIconPosition.x + APP_ICON_SIZE.x
    settingsWindowIconPositionBottomLeft.y = settingsWindowIconPosition.y + APP_ICON_SIZE.y
    ui.drawImage(APP_ICON_PATH, settingsWindowIconPosition, settingsWindowIconPositionBottomLeft, ui.ImageFit.Fit)

    ui.pushDWriteFont('Segoe UI')

    ui.text(string.format('Settings loaded for %s', StorageManager.getPerTrackPerModeStorageKey()))
    ui.newLine(1)

    -- Draw the Enabled checkbox
    local appEnabled = storage.enabled
    local enabledCheckBoxColor = appEnabled and ColorManager.RGBM_Colors.LimeGreen or ColorManager.RGBM_Colors.Red
    ui.pushStyleColor(ui.StyleColor.Text, enabledCheckBoxColor)
    local enabledDisabledText = appEnabled and 'Enabled' or 'Disabled'
    if ui.checkbox(string.format('Realistic Trackday %s for: %s (Mode: %s)', enabledDisabledText, RaceTrackManager.getTrackName(), RaceTrackManager.getSessionTypeName()), appEnabled) then storage.enabled = not storage.enabled end
    ui.popStyleColor(1)
    if ui.itemHovered() then ui.setTooltip('Master switch for this app.\n\nEach track and session mode type use different settings.') end

    ui.newLine(1)

    -- start the global app-enabled disabled section if the app is disabled
    if not appEnabled then
        ui.pushDisabled()
    end

    -- if ui.checkbox('Draw markers on top (no depth test)', storage.drawOnTop) then storage.drawOnTop = not storage.drawOnTop end
    -- if ui.itemHovered() then ui.setTooltip('If markers are hidden by car bodywork, enable this so text ignores depth testing.') end

    -- local comboValueChanged
    -- storage.yieldSide, comboValueChanged = ui.combo('Yielding Side', storage.yieldSide, ui.ComboFlags.NoPreview, RaceTrackManager.TrackSideStrings)
    -- if ui.itemHovered() then ui.setTooltip('The track side which AI will yield to when you approach from the rear.') end

    ui.columns(3, false, "cautionAndAggressionSection")
    ui.setColumnWidth(0, 380)
    ui.setColumnWidth(1, 500)

    ui.newLine(1)
    ui.dwriteText('AI Caution', UI_HEADER_TEXT_FONT_SIZE)
    ui.newLine(1)

    storage.defaultAICaution =  renderSlider('Default AI Caution', 'Base AI caution level (higher = more cautious, slower but less accident prone).', storage.defaultAICaution, StorageManager.options_min[StorageManager.Options.DefaultAICaution], StorageManager.options_max[StorageManager.Options.DefaultAICaution], DEFAULT_SLIDER_WIDTH, DEFAULT_SLIDER_FORMAT) -- do not drop the minimum below 2 because 1 is used while overtaking

    ui.nextColumn()

    ui.newLine(1)
    ui.dwriteText('AI Aggression', UI_HEADER_TEXT_FONT_SIZE)
    ui.newLine(1)

    if ui.checkbox('Override original AI aggression when driving normally', storage.overrideOriginalAIAggression_drivingNormally) then storage.overrideOriginalAIAggression_drivingNormally = not storage.overrideOriginalAIAggression_drivingNormally end
    if ui.itemHovered() then ui.setTooltip('If enabled, will override the original AI aggression value thats is set from the game launcher when the car is driving normally.') end

    local overrideOriginalAIAggression_drivingNormally = storage.overrideOriginalAIAggression_drivingNormally

    createDisabledSection(not overrideOriginalAIAggression_drivingNormally, function()
        storage.defaultAIAggression =  renderSlider('Overridden AI Aggression when driving normally', 'Base AI aggression level (higher = more aggressive, faster but more accident prone).', storage.defaultAIAggression, StorageManager.options_min[StorageManager.Options.DefaultAIAggression], StorageManager.options_max[StorageManager.Options.DefaultAIAggression], DEFAULT_SLIDER_WIDTH, DEFAULT_SLIDER_FORMAT) -- do not set above 0.95 because 1.0 is reserved for overtaking with no obstacles
    end)

    if ui.checkbox('Override original AI aggression when overtaking', storage.overrideOriginalAIAggression_overtaking) then storage.overrideOriginalAIAggression_overtaking = not storage.overrideOriginalAIAggression_overtaking end
    if ui.itemHovered() then ui.setTooltip('If enabled, will override the original AI aggression value thats is set from the game launcher when the car is overtaking another car.') end

    ui.columns(1, false)

    ui.newLine(1)
    ui.separator()

    ui.newLine(1)
    ui.dwriteText('Driving Lanes', UI_HEADER_TEXT_FONT_SIZE)
    ui.newLine(1)

    ui.columns(2, false, "lateralsSection")
    ui.setColumnWidth(0, 560)

    storage.defaultLateralOffset =  renderSlider('Default Lateral Offset [-1..1]', 'The default lateral offset from the centerline that AI cars will try to maintain when not yielding or overtaking.\n-1 = fully to the left\n0 = center of the track (racing line)\n1 = fully to the right', storage.defaultLateralOffset, StorageManager.options_min[StorageManager.Options.DefaultLateralOffset], StorageManager.options_max[StorageManager.Options.DefaultLateralOffset], DEFAULT_SLIDER_WIDTH, DEFAULT_SLIDER_FORMAT)

    -- currentValue = ui.slider('##someSliderID', currentValue, 0, 100, 'Quantity: %.0f')

    local handleYielding = storage_Yielding.handleYielding
    local handleOvertaking = storage_Overtaking.handleOvertaking

    local yieldingSide = RaceTrackManager.getYieldingSide()
    createDisabledSection(not handleYielding, function()
        storage.yieldingLateralOffset =  renderSlider(string.format('Yielding Lateral Offset [-1..1] -> Yielding side: %s', RaceTrackManager.TrackSideStrings[yieldingSide]), 'The lateral offset from the centerline that AI cars will drive to when yielding (giving way to faster cars).\n-1 = fully to the left\n0 = center of the track\n1 = fully to the right', storage.yieldingLateralOffset, StorageManager.options_min[StorageManager.Options.YieldingLateralOffset], StorageManager.options_max[StorageManager.Options.YieldingLateralOffset], DEFAULT_SLIDER_WIDTH, DEFAULT_SLIDER_FORMAT)
    end)

    local overtakingSide = RaceTrackManager.getOvertakingSide()
    createDisabledSection(not handleOvertaking, function()
        storage.overtakingLateralOffset =  renderSlider(string.format('Overtaking Lateral Offset [-1..1] -> Overtaking side: %s', RaceTrackManager.TrackSideStrings[overtakingSide]), 'The lateral offset from the centerline that AI cars will drive to when overtaking another car.\n-1 = fully to the left\n0 = center of the track\n1 = fully to the right', storage.overtakingLateralOffset, StorageManager.options_min[StorageManager.Options.OvertakingLateralOffset], StorageManager.options_max[StorageManager.Options.OvertakingLateralOffset], DEFAULT_SLIDER_WIDTH, DEFAULT_SLIDER_FORMAT)
    end)

    -- ui.newLine(1)

    if yieldingSide == overtakingSide then
      ui.textColored('Warning: Yielding side and overtaking side are the same!', ColorManager.RGBM_Colors.Yellow)
    end

    ui.nextColumn()

    UILateralOffsetsImageWidget.draw(storage)

    ui.columns(1, false)

    -- storage.maxLateralOffset_normalized =  ui.slider('Max Side offset', storage.maxLateralOffset_normalized, StorageManager.options_min[StorageManager.Options.MaxLateralOffset_normalized], StorageManager.options_max[StorageManager.Options.MaxLateralOffset_normalized])
    -- if ui.itemHovered() then ui.setTooltip('How far to move towards the chosen side when yielding/overtaking(0.1 barely moving to the side, 1.0 moving as much as possible to the side).') end

    ui.newLine(1)
    ui.separator()

-- ui.pushDWriteFont('Segoe UI')     -- or a custom TTF; see docs comment
-- ui.dwriteText('Yielding', 12)       -- 24 px size here
-- ui.popDWriteFont()

    ui.columns(2, true, "yieldingOvertakingSection")
    ui.setColumnWidth(0, 470)
    --ui.setColumnWidth(1, 260)


    ui.newLine(1)
    ui.dwriteText('Yielding', UI_HEADER_TEXT_FONT_SIZE)
    ui.newLine(1)

    local handleYieldingCheckboxColor = handleYielding and ColorManager.RGBM_Colors.LimeGreen or ColorManager.RGBM_Colors.Red
    ui.pushStyleColor(ui.StyleColor.Text, handleYieldingCheckboxColor)
    if ui.checkbox('Handle Yielding', storage_Yielding.handleYielding) then storage_Yielding.handleYielding = not storage_Yielding.handleYielding end
    ui.popStyleColor(1)
    if ui.itemHovered() then ui.setTooltip('If enabled, AI cars will attempt to yield to the specified Yielding Lateral Offset side of the track') end

    createDisabledSection(not handleYielding, function()
        if ui.checkbox('Check sides while yielding', storage_Yielding.handleSideCheckingWhenYielding) then storage_Yielding.handleSideCheckingWhenYielding = not storage_Yielding.handleSideCheckingWhenYielding end
        if ui.itemHovered() then ui.setTooltip("If enabled, cars will check for other cars on the side when yielding so they don't crash into them.") end

        if ui.checkbox('Require overtaking car to be on overtaking lane to yield', storage_Yielding.requireOvertakingCarToBeOnOvertakingLane) then storage_Yielding.requireOvertakingCarToBeOnOvertakingLane = not storage_Yielding.requireOvertakingCarToBeOnOvertakingLane end
        if ui.itemHovered() then ui.setTooltip("If enabled, the yielding car will only yield if the overtaking car is actually driving on the overtaking lane.") end

        storage_Yielding.detectCarBehind_meters =  renderSlider('Detect car behind distance', 'Start yielding if the player is behind and within this distance', storage_Yielding.detectCarBehind_meters, StorageManager.options_Yielding_min[StorageManager.Options_Yielding.DetectCarBehind_meters], StorageManager.options_Yielding_max[StorageManager.Options_Yielding.DetectCarBehind_meters], DEFAULT_SLIDER_WIDTH, '%.2f m')

        storage_Yielding.rampSpeed_mps =  renderSlider('Yielding Lateral Offset increment step', 'How quickly the lateral offset ramps up when yielding to an overtaking car.\nThe higher it is, the more quickly cars will change lanes when moving to the yielding side.', storage_Yielding.rampSpeed_mps, StorageManager.options_Yielding_min[StorageManager.Options_Yielding.RampSpeed_mps], StorageManager.options_Yielding_max[StorageManager.Options_Yielding.RampSpeed_mps], DEFAULT_SLIDER_WIDTH, '%.2f m/s')

        storage_Yielding.rampRelease_mps =  renderSlider('Yielding Lateral Offset decrement step', 'How quickly the lateral offset returns to normal once an overtaking car has fully driven past the yielding car.\nThe higher it is, the more quickly cars will change lanes moving back to the default lateral offset after finishing yielding.', storage_Yielding.rampRelease_mps, StorageManager.options_Yielding_min[StorageManager.Options_Yielding.RampRelease_mps], StorageManager.options_Yielding_max[StorageManager.Options_Yielding.RampRelease_mps], DEFAULT_SLIDER_WIDTH, '%.2f m/s')

        ui.newLine(1)

        storage_Yielding.speedLimitValueToOvertakingCar = renderSlider('Speed limit value to overtaking car [0..1]', 'When yielding, the yielding car speed will be limited to this fraction of the overtaking car speed to let it pass more easily.\n1.0 = same speed as overtaking car so no speed limiting\n0.5 = limit to half the speed of the overtaking car.', storage_Yielding.speedLimitValueToOvertakingCar, StorageManager.options_Yielding_min[StorageManager.Options_Yielding.SpeedLimitValueToOvertakingCar], StorageManager.options_Yielding_max[StorageManager.Options_Yielding.SpeedLimitValueToOvertakingCar], DEFAULT_SLIDER_WIDTH, DEFAULT_SLIDER_FORMAT)
        local speedLimitValueToOvertakingCar  = storage_Yielding.speedLimitValueToOvertakingCar
        createDisabledSection(speedLimitValueToOvertakingCar >= 1.0, function()
            storage_Yielding.distanceToOvertakingCarToLimitSpeed = renderSlider('Distance to overtaking car to limit speed', 'When yielding, if an overtaking car is within this distance behind us, we will limit our speed to let it pass more easily.', storage_Yielding.distanceToOvertakingCarToLimitSpeed, StorageManager.options_Yielding_min[StorageManager.Options_Yielding.DistanceToOvertakingCarToLimitSpeed], StorageManager.options_Yielding_max[StorageManager.Options_Yielding.DistanceToOvertakingCarToLimitSpeed], DEFAULT_SLIDER_WIDTH, '%.2f m')

            storage_Yielding.minimumSpeedLimitKmhToLimitToOvertakingCar = renderSlider('Minimum speed to limit to overtaking car', 'When yielding, the yielding car speed will not be limited below this speed even if the overtaking car is very slow.\n0.0 = no minimum speed limit', storage_Yielding.minimumSpeedLimitKmhToLimitToOvertakingCar, StorageManager.options_Yielding_min[StorageManager.options_Yielding_min.MinimumSpeedLimitKmhToLimitToOvertakingCar], StorageManager.options_Yielding_max[StorageManager.Options_Yielding.MinimumSpeedLimitKmhToLimitToOvertakingCar], DEFAULT_SLIDER_WIDTH, '%.2f km/h')
        end)
    end)

    --ui.separator()

    ui.nextColumn()

    ui.newLine(1)
    ui.dwriteText('Overtaking', UI_HEADER_TEXT_FONT_SIZE)
    ui.newLine(1)

    local handleOvertakingCheckboxColor = handleOvertaking and ColorManager.RGBM_Colors.LimeGreen or ColorManager.RGBM_Colors.Red
    ui.pushStyleColor(ui.StyleColor.Text, handleOvertakingCheckboxColor)
    if ui.checkbox('Handle Overtaking', storage_Overtaking.handleOvertaking) then storage_Overtaking.handleOvertaking = not storage_Overtaking.handleOvertaking end
    ui.popStyleColor(1)
    if ui.itemHovered() then ui.setTooltip('If enabled, AI cars will attempt to overtake to the specified Overtaking Lateral Offset side of the track') end
    
    createDisabledSection(not handleOvertaking, function()
        if ui.checkbox('Check sides while overtaking', storage.handleSideCheckingWhenOvertaking) then storage.handleSideCheckingWhenOvertaking = not storage.handleSideCheckingWhenOvertaking end
        if ui.itemHovered() then ui.setTooltip("If enabled, cars will check for other cars on the side when overtaking so they don't crash into them.") end

        if ui.checkbox('Require yielding car to be on yielding lane to overtake', storage_Overtaking.requireYieldingCarToBeOnYieldingLane) then storage_Overtaking.requireYieldingCarToBeOnYieldingLane = not storage_Overtaking.requireYieldingCarToBeOnYieldingLane end
        if ui.itemHovered() then ui.setTooltip("If enabled, the overtaking car will only overtake if the yielding car is actually driving on the yielding lane.") end

        storage_Overtaking.detectCarAhead_meters =  renderSlider('Detect car ahead distance', 'Start overtaking if the car in front is within this distance', storage_Overtaking.detectCarAhead_meters, StorageManager.options_Overtaking_min[StorageManager.Options_Overtaking.DetectCarAhead_meters], StorageManager.options_Overtaking_max[StorageManager.Options_Overtaking.DetectCarAhead_meters], DEFAULT_SLIDER_WIDTH, '%.2f m')

        storage_Overtaking.overtakeRampSpeed_mps =  renderSlider('Overtaking Lateral Offset increment step', 'How quickly the lateral offset ramps up when overtaking another car.\nThe higher it is, the more quickly cars will change lanes when moving to the overtaking side', storage_Overtaking.overtakeRampSpeed_mps, StorageManager.options_Overtaking_min[StorageManager.Options_Overtaking.OvertakeRampSpeed_mps], StorageManager.options_Overtaking_max[StorageManager.Options_Overtaking.OvertakeRampSpeed_mps], DEFAULT_SLIDER_WIDTH, '%.3f m/s')

        storage_Overtaking.overtakeRampRelease_mps =  renderSlider('Overtaking Lateral Offset decrement step', 'How quickly the lateral offset returns to normal once an overtaking car has fully driven past the overtaken car.\nThe higher it is, the more quickly cars will change lanes moving back to the default lateral offset after finishing overtaking.', storage_Overtaking.overtakeRampRelease_mps, StorageManager.options_Overtaking_min[StorageManager.Options_Overtaking.OvertakeRampRelease_mps], StorageManager.options_Overtaking_max[StorageManager.Options_Overtaking.OvertakeRampRelease_mps], DEFAULT_SLIDER_WIDTH, '%.3f m/s')
    end)

    -- finish two columns
    ui.columns(1, false)

    ui.newLine(1)
    ui.separator()

    createDisabledSection(not Constants.ENABLE_ACCIDENT_HANDLING_IN_APP, function()
        ui.newLine(1)
        ui.dwriteText('Accidents', UI_HEADER_TEXT_FONT_SIZE)
        ui.newLine(1)

        if ui.checkbox('Handle accidents (WORK IN PROGRESS - BEST NOT USED FOR NOW)', storage.handleAccidents) then storage.handleAccidents = not storage.handleAccidents end
        if ui.itemHovered() then ui.setTooltip('If enabled, AI will stop and remain stopped after an accident until the player car passes.') end

        local handleAccidents = storage.handleAccidents
        createDisabledSection(not handleAccidents, function()
            storage.distanceFromAccidentToSeeYellowFlag_meters =  renderSlider('Distance from accident to see yellow flag (m)', 'Distance from accident at which AI will see the yellow flag and start slowing down.', storage.distanceFromAccidentToSeeYellowFlag_meters, 50, 500, DEFAULT_SLIDER_WIDTH, '%.2f m')

            storage.distanceToStartNavigatingAroundCarInAccident_meters =  renderSlider('Distance to start navigating around car in accident (m)', 'Distance from accident at which AI will start navigating around the car in accident.', storage.distanceToStartNavigatingAroundCarInAccident_meters, 5, 100, DEFAULT_SLIDER_WIDTH, '%.2f m')
        end)
    end)


    ui.newLine(1)
    ui.separator()

    ui.newLine(1)
    ui.dwriteText('Other', UI_HEADER_TEXT_FONT_SIZE)
    ui.newLine(1)

    if ui.checkbox('Override AI awareness', storage.overrideAiAwareness) then storage.overrideAiAwareness = not storage.overrideAiAwareness end
    if ui.itemHovered() then ui.setTooltip('If enabled, our computed lateral offset will override the value from Kunos, otherwise our computed lateral offset adds to it. (EXPERIMENTAL)') end

    storage.clearAhead_meters = renderSlider('The distance (m) which determines whether a car is far enough ahead of another car', 'When checking if a car is clear ahead of another car, this is the distance used to determine if it is clear.', storage.clearAhead_meters, StorageManager.options_min[StorageManager.Options.ClearAhead_meters], StorageManager.options_max[StorageManager.Options.ClearAhead_meters], DEFAULT_SLIDER_WIDTH, '%.2f m')

    ui.separator()

    local storage_Debugging = StorageManager.getStorage_Debugging()
    renderDebuggingSection(storage_Debugging)

--[===[
    ui.separator()

    ui.text('Custom AI Flood')

    if ui.checkbox('Custom AI Flood Enabled', storage.customAIFlood_enabled) then storage.customAIFlood_enabled = not storage.customAIFlood_enabled end
    if ui.itemHovered() then ui.setTooltip('Master switch for the custom AI flood feature.') end

    storage.customAIFlood_distanceBehindPlayerToCycle_meters = ui.slider('Distance behind player to cycle (m)', storage.customAIFlood_distanceBehindPlayerToCycle_meters, 0, 500)
    if ui.itemHovered() then ui.setTooltip('Distance behind the player car at which AI cars will start to cycle.') end

    storage.customAIFlood_distanceAheadOfPlayerToCycle_meters = ui.slider('Distance ahead of player to cycle (m)', storage.customAIFlood_distanceAheadOfPlayerToCycle_meters, 0, 500)
    if ui.itemHovered() then ui.setTooltip('Distance ahead of the player car at which AI cars will start to cycle.') end

    -- storage.distanceToFrontCarToOvertake =  ui.slider('Min distance to front car to overtake (m)', storage.distanceToFrontCarToOvertake, 1.0, 20.0)
    -- if ui.itemHovered() then ui.setTooltip('Minimum distance to the car in front before an AI car will consider overtaking it.') end
--]===]
  ui.popDWriteFont()

-- Close the global app-enabled disabled section if the app is disabled
if not appEnabled then
    ui.popDisabled()
end
end

--[===[
local settingsWindow = ui.addSettings({
  icon = ui.Icons.Settings,
  name = 'Realistic Trackday Settings',
  id = 'rt_settings',                                    -- your stable ID
  size = {
    default = vec2(800, 620),                            -- initial size
    min     = vec2(600, 420),                            -- smallest allowed
    max     = vec2(2000, 1400),                          -- largest allowed
    automatic = false                                    -- don’t autosize content
  },
  category = 'settings'
}, function()
  SettingsWindow.draw()
end)
settingsWindow('open') 
-- ]===]

-- ac.setWindowOpen('mainWindow', true) 
-- ac.setWindowOpen('settingsWindow', true)

return SettingsWindow