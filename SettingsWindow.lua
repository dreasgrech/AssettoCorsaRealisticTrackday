local SettingsWindow = {}

-- bindings
local ui = ui
local ui_pushItemWidth = ui.pushItemWidth
local ui_popItemWidth =  ui.popItemWidth
local ui_slider = ui.slider
local ui_itemHovered = ui.itemHovered
local ui_setTooltip = ui.setTooltip
local ui_pushDisabled = ui.pushDisabled
local ui_popDisabled = ui.popDisabled
local ui_columns = ui.columns
local ui_setColumnWidth = ui.setColumnWidth
local ui_nextColumn = ui.nextColumn
local ui_button = ui.button
local ui_newLine = ui.newLine
local ui_text = ui.text
local ui_separator = ui.separator
local ui_textColored = ui.textColored
local ui_pushStyleColor = ui.pushStyleColor
local ui_popStyleColor = ui.popStyleColor
local ui_dwriteText = ui.dwriteText
local ui_checkbox = ui.checkbox
local ui_pushDWriteFont = ui.pushDWriteFont
local ui_popDWriteFont = ui.popDWriteFont
local ui_MouseButton = ui.MouseButton
local ui_mouseClicked = ui.mouseClicked
local ui_StyleColor = ui.StyleColor
local string = string
local string_format = string.format
local RaceTrackManager = RaceTrackManager
local RaceTrackManager_getTrackName = RaceTrackManager.getTrackName
local RaceTrackManager_getSessionTypeName = RaceTrackManager.getSessionTypeName
local RaceTrackManager_getOvertakingSide = RaceTrackManager.getOvertakingSide
local RaceTrackManager_getYieldingSide = RaceTrackManager.getYieldingSide
local AppIconRenderer = AppIconRenderer
local AppIconRenderer_draw = AppIconRenderer.draw
local ColorManager = ColorManager
local UILateralOffsetsImageWidget = UILateralOffsetsImageWidget
local UILateralOffsetsImageWidget_draw = UILateralOffsetsImageWidget.draw
local UIAppNameVersionWidget = UIAppNameVersionWidget
local UIAppNameVersionWidget_drawBottomRight = UIAppNameVersionWidget.drawBottomRight

local StorageManager = StorageManager
local StorageManager_getPerTrackPerModeStorageKey = StorageManager.getPerTrackPerModeStorageKey

local StorageManager_options_default = StorageManager.options_default
local StorageManager_options_min = StorageManager.options_min
local StorageManager_options_max = StorageManager.options_max

local StorageManager_options_Yielding_default = StorageManager.options_Yielding_default
local StorageManager_options_Yielding_min = StorageManager.options_Yielding_min
local StorageManager_options_Yielding_max = StorageManager.options_Yielding_max

local StorageManager_options_Overtaking_default = StorageManager.options_Overtaking_default
local StorageManager_options_Overtaking_min = StorageManager.options_Overtaking_min
local StorageManager_options_Overtaking_max = StorageManager.options_Overtaking_max

local StorageManager_Options = StorageManager.Options
local StorageManager_Options_Debugging = StorageManager.Options_Debugging
local StorageManager_Options_Yielding = StorageManager.Options_Yielding
local StorageManager_Options_Overtaking = StorageManager.Options_Overtaking


local UI_HEADER_TEXT_FONT_SIZE = 15

local DEFAULT_SLIDER_WIDTH = 200
local DEFAULT_SLIDER_FORMAT = '%.2f'

local DEFAULT_SLIDERGRAB_STYLECOLOR = ui.styleColor(ui_StyleColor.SliderGrab, 0)
local AICAUTION_SLIDERGRAB_COLOR_WHEN_SET_TO_ZERO = ColorManager.RGBM_Colors.DarkKhaki

local storage = StorageManager.getStorage()
local storage_Yielding = StorageManager.getStorage_Yielding()
local storage_Overtaking = StorageManager.getStorage_Overtaking()
local storage_Debugging = StorageManager.getStorage_Debugging()

---Renders a slider with a tooltip
---@param label string @Slider label.
---@param tooltip string
---@param value refnumber|number @Current slider value.
---@param minValue number? @Default value: 0.
---@param maxValue number? @Default value: 1.
---@param sliderWidth number
---@param labelFormat string|'%.3f'|nil @C-style format string. Default value: `'%.3f'`.
---@param defaultValue number @The default value to reset to on right-click and is shown in the tooltip.
---@return number @Possibly updated slider value.
local renderSlider = function(label, tooltip, value, minValue, maxValue, sliderWidth, labelFormat, defaultValue)
    -- set the width of the slider
    ui_pushItemWidth(sliderWidth)

    -- render the slider
    local newValue = ui_slider(label, value, minValue, maxValue, labelFormat)

    -- reset the item width
    ui_popItemWidth()

    tooltip = string_format('%s\n\nDefault: %.2f', tooltip, defaultValue)

    if ui_itemHovered() then
        -- render the tooltip
        ui_setTooltip(tooltip)

        -- reset the slider to default value on right-click
        if ui_mouseClicked(ui_MouseButton.Right) then
            -- Logger.log(string.format('Resetting slider "%s" to default value: %.2f', label, defaultValue))
            newValue = defaultValue
        end
    end

    return newValue
end

local renderSliderWithInnerText = function(sliderID, labelFormat, tooltip, value, min, max, sliderWidth)
    ui_pushItemWidth(sliderWidth)
    local newValue = ui_slider(sliderID, value, min, max, labelFormat)
    ui_popItemWidth()
    if ui_itemHovered() then ui_setTooltip(tooltip) end
    return newValue
end

--- Creates a disabled section in the UI.
---@param createSection boolean @If true, will create a disabled section.
---@param callback function @Function to call to render the contents of the section.
local createDisabledSection = function(createSection, callback)
    if createSection then
        ui_pushDisabled()
    end

    callback()

    if createSection then
        ui_popDisabled()
    end
end


---@param storage_Debugging StorageTable_Debugging
local renderDebuggingSection = function(storage_Debugging)
    -- ui.text('Debugging')
    ui_newLine(1)
    ui_dwriteText('Debugging', UI_HEADER_TEXT_FONT_SIZE)
    ui_newLine(1)

    ui_columns(3, false, "debuggingSection")

    if ui_checkbox('Show UI Car List', storage_Debugging.drawCarList) then storage_Debugging.drawCarList = not storage_Debugging.drawCarList end
    if ui_itemHovered() then ui_setTooltip('Shows a list of all cars in the scene') end

    if ui_checkbox('Show car state overhead text', storage_Debugging.debugShowCarStateOverheadText) then storage_Debugging.debugShowCarStateOverheadText = not storage_Debugging.debugShowCarStateOverheadText end
    if ui_itemHovered() then ui_setTooltip("Shows the car's current state as text over the car") end

    storage_Debugging.debugCarGizmosDrawistance = renderSliderWithInnerText('##debugCarStateOverheadShowDistance', 'Car gizmos draw distance: %.0fm', 'The maximum distance from the camera focused car at which to show the car state overhead text.', storage_Debugging.debugCarGizmosDrawistance, StorageManager_options_min[StorageManager_Options_Debugging.DebugCarGizmosDrawistance], StorageManager_options_max[StorageManager_Options_Debugging.DebugCarGizmosDrawistance], DEFAULT_SLIDER_WIDTH)

    if ui_checkbox('Show raycasts when driving laterally', storage_Debugging.debugShowRaycastsWhileDrivingLaterally) then storage_Debugging.debugShowRaycastsWhileDrivingLaterally = not storage_Debugging.debugShowRaycastsWhileDrivingLaterally end
    if ui_itemHovered() then ui_setTooltip('Shows the raycasts used to check for side clearance when driving checking for cars on the side') end

    if ui_checkbox('Draw tyres side offtrack gizmos', storage_Debugging.debugDrawSideOfftrack) then storage_Debugging.debugDrawSideOfftrack = not storage_Debugging.debugDrawSideOfftrack end
    if ui_itemHovered() then ui_setTooltip('Shows gizmos for the car\'s tyres when offtrack') end

    ui_nextColumn()

    if ui_checkbox('Log fast AI state changes', storage_Debugging.debugLogFastStateChanges) then storage_Debugging.debugLogFastStateChanges = not storage_Debugging.debugLogFastStateChanges end
    if ui_itemHovered() then ui_setTooltip('If enabled, will write to the CSP log if an ai car changes from one state to another very quickly') end

    if ui_checkbox('Log car yielding', storage_Debugging.debugLogCarYielding) then storage_Debugging.debugLogCarYielding = not storage_Debugging.debugLogCarYielding end
    if ui_itemHovered() then ui_setTooltip('If enabled, will write to the CSP log if an ai car is yielding to another car') end

    if ui_checkbox('Log car overtaking', storage_Debugging.debugLogCarOvertaking) then storage_Debugging.debugLogCarOvertaking = not storage_Debugging.debugLogCarOvertaking end
    if ui_itemHovered() then ui_setTooltip('If enabled, will write to the CSP log if an ai car is overtaking another car') end

    ui_nextColumn()

    createDisabledSection(not Constants.ENABLE_ACCIDENT_HANDLING_IN_APP, function()
        if ui_button('Simulate accident', ui.ButtonFlags.None) then
            AccidentManager.simulateAccident()
        end
    end)

    -- reset the column layout
    ui_columns(1, false)

    ui_newLine(1)
    ui_textColored('Warning: Enabling debugging options may impact performance.', ColorManager.RGBM_Colors.Yellow)
end

local getSliderColorForAICautionWhenSetToZero = function(aiCautionValue)
    return aiCautionValue < 1 and AICAUTION_SLIDERGRAB_COLOR_WHEN_SET_TO_ZERO or DEFAULT_SLIDERGRAB_STYLECOLOR
end

SettingsWindow.draw = function()
    -- Draw the app icon at the top-right of the settings window
    AppIconRenderer_draw()

    ui_pushDWriteFont('Segoe UI')

    ui_text(string_format('Settings loaded for %s', StorageManager_getPerTrackPerModeStorageKey()))
    ui_newLine(1)

    -- Draw the Enabled checkbox
    local appEnabled = storage.enabled
    local enabledCheckBoxColor = appEnabled and ColorManager.RGBM_Colors.LimeGreen or ColorManager.RGBM_Colors.Red
    ui_pushStyleColor(ui_StyleColor.Text, enabledCheckBoxColor)
    local enabledDisabledText = appEnabled and 'Enabled' or 'Disabled'
    if ui_checkbox(string_format('Realistic Trackday %s for: %s (Mode: %s)', enabledDisabledText, RaceTrackManager_getTrackName(), RaceTrackManager_getSessionTypeName()), appEnabled) then storage.enabled = not storage.enabled end
    ui_popStyleColor(1)
    if ui_itemHovered() then ui_setTooltip('Enable the Realistic Trackday app for this specific track and session mode.\n\nEach track and session mode type use individually saved settings.') end

    ui_newLine(1)

    -- start the global app-enabled disabled section if the app is disabled
    if not appEnabled then
        ui_pushDisabled()
    end

    -- if ui.checkbox('Draw markers on top (no depth test)', storage.drawOnTop) then storage.drawOnTop = not storage.drawOnTop end
    -- if ui.itemHovered() then ui.setTooltip('If markers are hidden by car bodywork, enable this so text ignores depth testing.') end

    -- local comboValueChanged
    -- storage.yieldSide, comboValueChanged = ui.combo('Yielding Side', storage.yieldSide, ui.ComboFlags.NoPreview, RaceTrackManager.TrackSideStrings)
    -- if ui.itemHovered() then ui.setTooltip('The track side which AI will yield to when you approach from the rear.') end

    ui_columns(3, false, "cautionAndAggressionSection")
    ui_setColumnWidth(0, 500)
    ui_setColumnWidth(1, 500)

    ui_newLine(1)
    ui_dwriteText('Caution', UI_HEADER_TEXT_FONT_SIZE)

    ui_text('Caution determines how much space cars keep from each other while driving.\nA higher caution means a larger gap between cars.')
    ui_newLine(1)

    ui_pushStyleColor(ui_StyleColor.SliderGrab, getSliderColorForAICautionWhenSetToZero(storage.defaultAICaution))
    storage.defaultAICaution =  renderSlider('Caution while driving normally', 'The default gap cars keep between each other while driving on the default driving lane.\n\nThe higher this value is, the more cautious the cars will be by keeping a larger gap between each other, which can provide a more relaxed trackday experience.', storage.defaultAICaution, StorageManager_options_min[StorageManager_Options.DefaultAICaution], StorageManager_options_max[StorageManager_Options.DefaultAICaution], DEFAULT_SLIDER_WIDTH, DEFAULT_SLIDER_FORMAT, StorageManager_options_default[StorageManager_Options.DefaultAICaution]) -- do not drop the minimum below 2 because 1 is used while overtaking
    ui_popStyleColor()

    storage.AICaution_OvertakingWithNoObstacleInFront =  renderSlider('Caution while overtaking (No obstacle in front)', 'The caution level used when overtaking another car if there is no obstacle in front of the overtaking car.\n\nThe lower this value is, the more aggressive the cars will be while overtaking when there is no obstacle in front of them.', storage.AICaution_OvertakingWithNoObstacleInFront, StorageManager_options_min[StorageManager_Options.AICaution_OvertakingWithNoObstacleInFront], StorageManager_options_max[StorageManager_Options.AICaution_OvertakingWithNoObstacleInFront], DEFAULT_SLIDER_WIDTH, DEFAULT_SLIDER_FORMAT, StorageManager_options_default[StorageManager_Options.AICaution_OvertakingWithNoObstacleInFront])

    ui_pushStyleColor(ui_StyleColor.SliderGrab, getSliderColorForAICautionWhenSetToZero(storage.AICaution_OvertakingWithObstacleInFront))
    storage.AICaution_OvertakingWithObstacleInFront =  renderSlider('Caution while overtaking (Obstacle in front)', 'The caution level used when overtaking another car if there is an obstacle in front of the overtaking car.\n\nThe higher this value is, the more cautious the cars will be while overtaking when there is an obstacle in front of them.', storage.AICaution_OvertakingWithObstacleInFront, StorageManager_options_min[StorageManager_Options.AICaution_OvertakingWithObstacleInFront], StorageManager_options_max[StorageManager_Options.AICaution_OvertakingWithObstacleInFront], DEFAULT_SLIDER_WIDTH, DEFAULT_SLIDER_FORMAT, StorageManager_options_default[StorageManager_Options.AICaution_OvertakingWithObstacleInFront])
    ui_popStyleColor()

    ui_pushStyleColor(ui_StyleColor.SliderGrab, getSliderColorForAICautionWhenSetToZero(storage.AICaution_OvertakingWhileInCorner))
    storage.AICaution_OvertakingWhileInCorner =  renderSlider('Caution while overtaking in corner', 'The caution level used when overtaking another car while in a corner.\n\nThe higher this value is, the more cautious the cars will be while overtaking in corners.', storage.AICaution_OvertakingWhileInCorner, StorageManager_options_min[StorageManager_Options.AICaution_OvertakingWhileInCorner], StorageManager_options_max[StorageManager_Options.AICaution_OvertakingWhileInCorner], DEFAULT_SLIDER_WIDTH, DEFAULT_SLIDER_FORMAT, StorageManager_options_default[StorageManager_Options.AICaution_OvertakingWhileInCorner])
    ui_popStyleColor()

    ui_pushStyleColor(ui_StyleColor.SliderGrab, getSliderColorForAICautionWhenSetToZero(storage.AICaution_Yielding))
    storage.AICaution_Yielding =  renderSlider('Caution while yielding', 'The caution level used when yielding (giving way to faster cars).\n\nThe higher this value is, the more cautious the cars will be while yielding.', storage.AICaution_Yielding, StorageManager_options_min[StorageManager_Options.AICaution_Yielding], StorageManager_options_max[StorageManager_Options.AICaution_Yielding], DEFAULT_SLIDER_WIDTH, DEFAULT_SLIDER_FORMAT, StorageManager_options_default[StorageManager_Options.AICaution_Yielding])
    ui_popStyleColor()

    ui_nextColumn()

    ui_newLine(1)
    ui_dwriteText('Aggression', UI_HEADER_TEXT_FONT_SIZE)
    ui_newLine(1)

    if ui_checkbox('Override original AI aggression when driving normally', storage.overrideOriginalAIAggression_drivingNormally) then storage.overrideOriginalAIAggression_drivingNormally = not storage.overrideOriginalAIAggression_drivingNormally end
    if ui_itemHovered() then ui_setTooltip('If enabled, will override the original AI aggression value thats is set from the game launcher when the car is driving normally.') end

    local overrideOriginalAIAggression_drivingNormally = storage.overrideOriginalAIAggression_drivingNormally

    createDisabledSection(not overrideOriginalAIAggression_drivingNormally, function()
        storage.defaultAIAggression =  renderSlider('Overridden Base AI Aggression', 'The default aggression level cars exhibit when driving on the default driving lane.\n\nThe higher this value is, the more aggressive the cars will be (although the exact definition of aggression is still a bit unclear at the moment).', storage.defaultAIAggression, StorageManager_options_min[StorageManager_Options.DefaultAIAggression], StorageManager_options_max[StorageManager_Options.DefaultAIAggression], DEFAULT_SLIDER_WIDTH, DEFAULT_SLIDER_FORMAT, StorageManager_options_default[StorageManager_Options.DefaultAIAggression]) -- do not set above 0.95 because 1.0 is reserved for overtaking with no obstacles
    end)

    if ui_checkbox('Override original AI aggression when overtaking', storage.overrideOriginalAIAggression_overtaking) then storage.overrideOriginalAIAggression_overtaking = not storage.overrideOriginalAIAggression_overtaking end
    if ui_itemHovered() then ui_setTooltip('If enabled, will override the original AI aggression value thats is set from the game launcher when the car is overtaking another car.') end

    ui_columns(1, false)

    ui_newLine(1)
    ui_separator()

    ui_newLine(1)
    ui_dwriteText('Lateral Offsets (Driving Lanes)', UI_HEADER_TEXT_FONT_SIZE)
    ui_newLine(1)

    ui_columns(2, false, "lateralsSection")
    ui_setColumnWidth(0, 560)

    local handleYielding = storage_Yielding.handleYielding
    local handleOvertaking = storage_Overtaking.handleOvertaking

    local overtakingSide = RaceTrackManager_getOvertakingSide()
    createDisabledSection(not handleOvertaking, function()
        storage.overtakingLateralOffset =  renderSlider(string_format('Overtaking Lateral Offset [-1..1] -> Overtaking side: %s', RaceTrackManager.TrackSideStrings[overtakingSide]), 'The lateral offset from the centerline that AI cars will drive to when overtaking another car.\n-1 = fully to the left\n0 = center of the track\n1 = fully to the right', storage.overtakingLateralOffset, StorageManager_options_min[StorageManager_Options.OvertakingLateralOffset], StorageManager_options_max[StorageManager_Options.OvertakingLateralOffset], DEFAULT_SLIDER_WIDTH, DEFAULT_SLIDER_FORMAT, StorageManager_options_default[StorageManager_Options.OvertakingLateralOffset])
    end)

    storage.defaultLateralOffset =  renderSlider('Default Lateral Offset [-1..1]', 'The default lateral offset from the centerline that AI cars will try to maintain when not yielding or overtaking.\n-1 = fully to the left\n0 = center of the track (racing line)\n1 = fully to the right', storage.defaultLateralOffset, StorageManager_options_min[StorageManager_Options.DefaultLateralOffset], StorageManager_options_max[StorageManager_Options.DefaultLateralOffset], DEFAULT_SLIDER_WIDTH, DEFAULT_SLIDER_FORMAT, StorageManager_options_default[StorageManager_Options.DefaultLateralOffset])

    local yieldingSide = RaceTrackManager_getYieldingSide()
    createDisabledSection(not handleYielding, function()
        storage.yieldingLateralOffset =  renderSlider(string_format('Yielding Lateral Offset [-1..1] -> Yielding side: %s', RaceTrackManager.TrackSideStrings[yieldingSide]), 'The lateral offset from the centerline that AI cars will drive to when yielding (giving way to faster cars).\n-1 = fully to the left\n0 = center of the track\n1 = fully to the right', storage.yieldingLateralOffset, StorageManager_options_min[StorageManager_Options.YieldingLateralOffset], StorageManager_options_max[StorageManager_Options.YieldingLateralOffset], DEFAULT_SLIDER_WIDTH, DEFAULT_SLIDER_FORMAT, StorageManager_options_default[StorageManager_Options.YieldingLateralOffset])
    end)

    -- ui.newLine(1)

    if yieldingSide == overtakingSide then
      ui_textColored('Warning: Yielding side and overtaking side are the same!', ColorManager.RGBM_Colors.Yellow)
    end

    ui_nextColumn()

    UILateralOffsetsImageWidget_draw(storage)

    ui_columns(1, false)

    -- storage.maxLateralOffset_normalized =  ui.slider('Max Side offset', storage.maxLateralOffset_normalized, StorageManager_options_min[StorageManager_Options.MaxLateralOffset_normalized], StorageManager_options_max[StorageManager_Options.MaxLateralOffset_normalized])
    -- if ui.itemHovered() then ui.setTooltip('How far to move towards the chosen side when yielding/overtaking(0.1 barely moving to the side, 1.0 moving as much as possible to the side).') end

    ui_newLine(1)
    ui_separator()

-- ui.pushDWriteFont('Segoe UI')     -- or a custom TTF; see docs comment
-- ui.dwriteText('Yielding', 12)       -- 24 px size here
-- ui.popDWriteFont()

    ui_columns(2, true, "yieldingOvertakingSection")
    ui_setColumnWidth(0, 560)
    --ui.setColumnWidth(1, 260)


    ui_newLine(1)
    ui_dwriteText('Yielding', UI_HEADER_TEXT_FONT_SIZE)
    ui_newLine(1)

    local handleYieldingCheckboxColor = handleYielding and ColorManager.RGBM_Colors.LimeGreen or ColorManager.RGBM_Colors.Red
    ui_pushStyleColor(ui_StyleColor.Text, handleYieldingCheckboxColor)
    if ui_checkbox('Handle Yielding', storage_Yielding.handleYielding) then storage_Yielding.handleYielding = not storage_Yielding.handleYielding end
    ui_popStyleColor(1)
    if ui_itemHovered() then ui_setTooltip('If enabled, AI cars will attempt to yield to the specified Yielding Lateral Offset side of the track') end

    createDisabledSection(not handleYielding, function()
        if ui_checkbox('Check sides while yielding', storage_Yielding.handleSideCheckingWhenYielding) then storage_Yielding.handleSideCheckingWhenYielding = not storage_Yielding.handleSideCheckingWhenYielding end
        if ui_itemHovered() then ui_setTooltip("If enabled, cars will check for other cars on the side when yielding so they don't crash into them.") end

        if ui_checkbox('Require overtaking car to be on overtaking lane to yield', storage_Yielding.requireOvertakingCarToBeOnOvertakingLane) then storage_Yielding.requireOvertakingCarToBeOnOvertakingLane = not storage_Yielding.requireOvertakingCarToBeOnOvertakingLane end
        if ui_itemHovered() then ui_setTooltip("If enabled, the yielding car will only yield if the overtaking car is actually driving on the overtaking lane.") end

        ui_newLine(1)

        if ui_checkbox('Use indicator lights when easing in yield', storage_Yielding.UseIndicatorLightsWhenEasingInYield) then storage_Yielding.UseIndicatorLightsWhenEasingInYield = not storage_Yielding.UseIndicatorLightsWhenEasingInYield end
        if ui_itemHovered() then ui_setTooltip("If enabled, cars will use their indicator lights while driving to the reach the yielding lane.") end

        if ui_checkbox('Use indicator lights when easing out of yield', storage_Yielding.UseIndicatorLightsWhenEasingOutYield) then storage_Yielding.UseIndicatorLightsWhenEasingOutYield = not storage_Yielding.UseIndicatorLightsWhenEasingOutYield end
        if ui_itemHovered() then ui_setTooltip("If enabled, cars will use their indicator lights while driving from the yielding lane back to the default driving lane.") end

        if ui_checkbox('Use indicator lights when driving on yielding lane', storage_Yielding.UseIndicatorLightsWhenDrivingOnYieldingLane) then storage_Yielding.UseIndicatorLightsWhenDrivingOnYieldingLane = not storage_Yielding.UseIndicatorLightsWhenDrivingOnYieldingLane end
        if ui_itemHovered() then ui_setTooltip("If enabled, cars will keep their indicator lights on while driving on the yielding lane.") end

        ui_newLine(1)

        storage_Yielding.detectCarBehind_meters =  renderSlider('Detect car behind distance', 'Start yielding if the car behind is within this distance', storage_Yielding.detectCarBehind_meters, StorageManager_options_Yielding_min[StorageManager_Options_Yielding.DetectCarBehind_meters], StorageManager_options_Yielding_max[StorageManager_Options_Yielding.DetectCarBehind_meters], DEFAULT_SLIDER_WIDTH, '%.2f m', StorageManager_options_Yielding_default[StorageManager_Options_Yielding.DetectCarBehind_meters])

        storage_Yielding.rampSpeed_mps =  renderSlider('Yielding Lateral Offset increment step', 'How quickly the lateral offset ramps up when yielding to an overtaking car.\nThe higher it is, the more quickly cars will change lanes when moving to the yielding side.', storage_Yielding.rampSpeed_mps, StorageManager_options_Yielding_min[StorageManager_Options_Yielding.RampSpeed_mps], StorageManager_options_Yielding_max[StorageManager_Options_Yielding.RampSpeed_mps], DEFAULT_SLIDER_WIDTH, '%.2f m/s', StorageManager_options_Yielding_default[StorageManager_Options_Yielding.RampSpeed_mps])

        storage_Yielding.rampRelease_mps =  renderSlider('Yielding Lateral Offset decrement step', 'How quickly the lateral offset returns to normal once an overtaking car has fully driven past the yielding car.\nThe higher it is, the more quickly cars will change lanes moving back to the default lateral offset after finishing yielding.', storage_Yielding.rampRelease_mps, StorageManager_options_Yielding_min[StorageManager_Options_Yielding.RampRelease_mps], StorageManager_options_Yielding_max[StorageManager_Options_Yielding.RampRelease_mps], DEFAULT_SLIDER_WIDTH, '%.2f m/s', StorageManager_options_Yielding_default[StorageManager_Options_Yielding.RampRelease_mps])

        ui_newLine(1)

        storage_Yielding.speedLimitValueToOvertakingCar = renderSlider('Top speed limit value to overtaking car [0..1]', "When yielding, the yielding car's top speed will be limited to this fraction of the overtaking car's current speed to let it pass more easily.\n1.0 = no top speed limiting\n0.5 = limit top speed to half the current speed of the overtaking car.\n0.0 = make the car grind to a halt", storage_Yielding.speedLimitValueToOvertakingCar, StorageManager_options_Yielding_min[StorageManager_Options_Yielding.SpeedLimitValueToOvertakingCar], StorageManager_options_Yielding_max[StorageManager_Options_Yielding.SpeedLimitValueToOvertakingCar], DEFAULT_SLIDER_WIDTH, DEFAULT_SLIDER_FORMAT, StorageManager_options_Yielding_default[StorageManager_Options_Yielding.SpeedLimitValueToOvertakingCar])
        local speedLimitValueToOvertakingCar  = storage_Yielding.speedLimitValueToOvertakingCar
        createDisabledSection(speedLimitValueToOvertakingCar >= 1.0, function()
            storage_Yielding.minimumSpeedLimitKmhToLimitToOvertakingCar = renderSlider('Minimum top speed to limit to overtaking car', "When yielding, the yielding car's top speed will not be limited below this speed even if the overtaking car is very slow.\n0.0 = no minimum top speed limit while yielding", storage_Yielding.minimumSpeedLimitKmhToLimitToOvertakingCar, StorageManager_options_Yielding_min[StorageManager_options_Yielding_min.MinimumSpeedLimitKmhToLimitToOvertakingCar], StorageManager_options_Yielding_max[StorageManager_Options_Yielding.MinimumSpeedLimitKmhToLimitToOvertakingCar], DEFAULT_SLIDER_WIDTH, '%.2f km/h', StorageManager_options_Yielding_default[StorageManager_Options_Yielding.MinimumSpeedLimitKmhToLimitToOvertakingCar])

        end)

        storage_Yielding.throttlePedalLimitWhenYieldingToOvertakingCar = renderSlider('Throttle pedal limit when yielding to overtaking car [0..1]', "When yielding, the yielding car's throttle pedal input will be limited to this fraction to let the overtaking car pass more easily.\n1.0 = no throttle pedal limiting\n0.5 = limit throttle pedal input to half\n0.0 = completely let go of the throttle pedal", storage_Yielding.throttlePedalLimitWhenYieldingToOvertakingCar, StorageManager_options_Yielding_min[StorageManager_Options_Yielding.ThrottlePedalLimitWhenYieldingToOvertakingCar], StorageManager_options_Yielding_max[StorageManager_Options_Yielding.ThrottlePedalLimitWhenYieldingToOvertakingCar], DEFAULT_SLIDER_WIDTH, DEFAULT_SLIDER_FORMAT, StorageManager_options_Yielding_default[StorageManager_Options_Yielding.ThrottlePedalLimitWhenYieldingToOvertakingCar])

        local anySpeedLimitingWhileYieldingApplied = 
            speedLimitValueToOvertakingCar < 1.0 or 
            storage_Yielding.throttlePedalLimitWhenYieldingToOvertakingCar < 1.0

        createDisabledSection(not anySpeedLimitingWhileYieldingApplied, function()
            storage_Yielding.distanceToOvertakingCarToLimitSpeed = renderSlider('Distance to overtaking car to apply speed limiting', 'When yielding, if an overtaking car is within this distance behind us, we will limit our speed to let it pass more easily.', storage_Yielding.distanceToOvertakingCarToLimitSpeed, StorageManager_options_Yielding_min[StorageManager_Options_Yielding.DistanceToOvertakingCarToLimitSpeed], StorageManager_options_Yielding_max[StorageManager_Options_Yielding.DistanceToOvertakingCarToLimitSpeed], DEFAULT_SLIDER_WIDTH, '%.2f m', StorageManager_options_Yielding_default[StorageManager_Options_Yielding.DistanceToOvertakingCarToLimitSpeed])
        end)
    end)

    --ui.separator()

    ui_nextColumn()

    ui_newLine(1)
    ui_dwriteText('Overtaking', UI_HEADER_TEXT_FONT_SIZE)
    ui_newLine(1)

    local handleOvertakingCheckboxColor = handleOvertaking and ColorManager.RGBM_Colors.LimeGreen or ColorManager.RGBM_Colors.Red
    ui_pushStyleColor(ui_StyleColor.Text, handleOvertakingCheckboxColor)
    if ui_checkbox('Handle Overtaking', storage_Overtaking.handleOvertaking) then storage_Overtaking.handleOvertaking = not storage_Overtaking.handleOvertaking end
    ui_popStyleColor(1)
    if ui_itemHovered() then ui_setTooltip('If enabled, AI cars will attempt to overtake to the specified Overtaking Lateral Offset side of the track') end
    
    createDisabledSection(not handleOvertaking, function()
        if ui_checkbox('Check sides while overtaking', storage_Overtaking.handleSideCheckingWhenOvertaking) then storage_Overtaking.handleSideCheckingWhenOvertaking = not storage_Overtaking.handleSideCheckingWhenOvertaking end
        if ui_itemHovered() then ui_setTooltip("If enabled, cars will check for other cars on the side when overtaking so they don't crash into them.") end

        if ui_checkbox('Require yielding car to be on yielding lane to overtake', storage_Overtaking.requireYieldingCarToBeOnYieldingLane) then storage_Overtaking.requireYieldingCarToBeOnYieldingLane = not storage_Overtaking.requireYieldingCarToBeOnYieldingLane end
        if ui_itemHovered() then ui_setTooltip("If enabled, the overtaking car will only overtake if the yielding car is actually driving on the yielding lane.") end

        ui_newLine(1)

        if ui_checkbox('Use indicator lights when easing in to overtake', storage_Overtaking.UseIndicatorLightsWhenEasingInOvertaking) then storage_Overtaking.UseIndicatorLightsWhenEasingInOvertaking = not storage_Overtaking.UseIndicatorLightsWhenEasingInOvertaking end
        if ui_itemHovered() then ui_setTooltip("If enabled, cars will use their indicator lights when driving to the overtaking lane.") end

        if ui_checkbox('Use indicator lights when easing out of overtaking', storage_Overtaking.UseIndicatorLightsWhenEasingOutOvertaking) then storage_Overtaking.UseIndicatorLightsWhenEasingOutOvertaking = not storage_Overtaking.UseIndicatorLightsWhenEasingOutOvertaking end
        if ui_itemHovered() then ui_setTooltip("If enabled, cars will use their indicator lights when driving from the overtaking lane back to the default driving lane.") end

        if ui_checkbox('Use indicator lights when driving on overtaking lane', storage_Overtaking.UseIndicatorLightsWhenDrivingOnOvertakingLane) then storage_Overtaking.UseIndicatorLightsWhenDrivingOnOvertakingLane = not storage_Overtaking.UseIndicatorLightsWhenDrivingOnOvertakingLane end
        if ui_itemHovered() then ui_setTooltip("If enabled, cars will keep their indicator lights on while driving on the overtaking lane.") end

        ui_newLine(1)

        storage_Overtaking.detectCarAhead_meters =  renderSlider('Detect car ahead distance', 'Start overtaking if the car in front is within this distance', storage_Overtaking.detectCarAhead_meters, StorageManager_options_Overtaking_min[StorageManager_Options_Overtaking.DetectCarAhead_meters], StorageManager_options_Overtaking_max[StorageManager_Options_Overtaking.DetectCarAhead_meters], DEFAULT_SLIDER_WIDTH, '%.2f m', StorageManager_options_Overtaking_default[StorageManager_Options_Overtaking.DetectCarAhead_meters])

        storage_Overtaking.overtakeRampSpeed_mps =  renderSlider('Overtaking Lateral Offset increment step', 'How quickly the lateral offset ramps up when overtaking another car.\nThe higher it is, the more quickly cars will change lanes when moving to the overtaking side', storage_Overtaking.overtakeRampSpeed_mps, StorageManager_options_Overtaking_min[StorageManager_Options_Overtaking.OvertakeRampSpeed_mps], StorageManager_options_Overtaking_max[StorageManager_Options_Overtaking.OvertakeRampSpeed_mps], DEFAULT_SLIDER_WIDTH, '%.3f m/s', StorageManager_options_Overtaking_default[StorageManager_Options_Overtaking.OvertakeRampSpeed_mps])

        storage_Overtaking.overtakeRampRelease_mps =  renderSlider('Overtaking Lateral Offset decrement step', 'How quickly the lateral offset returns to normal once an overtaking car has fully driven past the overtaken car.\nThe higher it is, the more quickly cars will change lanes moving back to the default lateral offset after finishing overtaking.', storage_Overtaking.overtakeRampRelease_mps, StorageManager_options_Overtaking_min[StorageManager_Options_Overtaking.OvertakeRampRelease_mps], StorageManager_options_Overtaking_max[StorageManager_Options_Overtaking.OvertakeRampRelease_mps], DEFAULT_SLIDER_WIDTH, '%.3f m/s', StorageManager_options_Overtaking_default[StorageManager_Options_Overtaking.OvertakeRampRelease_mps])
    end)

    -- finish two columns
    ui_columns(1, false)

    ui_newLine(1)
    ui_separator()

    createDisabledSection(not Constants.ENABLE_ACCIDENT_HANDLING_IN_APP, function()
        ui_newLine(1)
        ui_dwriteText('Accidents', UI_HEADER_TEXT_FONT_SIZE)
        ui_newLine(1)

        if ui_checkbox('Handle accidents (WORK IN PROGRESS - BEST NOT USED FOR NOW)', storage.handleAccidents) then storage.handleAccidents = not storage.handleAccidents end
        if ui_itemHovered() then ui_setTooltip('If enabled, AI will stop and remain stopped after an accident until the other cars pass.') end

        local handleAccidents = storage.handleAccidents
        createDisabledSection(not handleAccidents, function()
            storage.distanceFromAccidentToSeeYellowFlag_meters =  renderSlider('Distance from accident to see yellow flag (m)', 'Distance from accident at which AI will see the yellow flag and start slowing down.', storage.distanceFromAccidentToSeeYellowFlag_meters, 50, 500, DEFAULT_SLIDER_WIDTH, '%.2f m', StorageManager_options_default[StorageManager_Options.DistanceFromAccidentToSeeYellowFlag_meters])

            storage.distanceToStartNavigatingAroundCarInAccident_meters =  renderSlider('Distance to start navigating around car in accident (m)', 'Distance from accident at which AI will start navigating around the car in accident.', storage.distanceToStartNavigatingAroundCarInAccident_meters, 5, 100, DEFAULT_SLIDER_WIDTH, '%.2f m', StorageManager_options_default[StorageManager_Options.DistanceToStartNavigatingAroundCarInAccident_meters])
        end)
    end)


    ui_newLine(1)
    ui_separator()

    ui_newLine(1)
    ui_dwriteText('Other', UI_HEADER_TEXT_FONT_SIZE)
    ui_newLine(1)

    storage.globalTopSpeedLimitKmh = renderSlider('Global top speed limit', 'A global top speed limit applied to all AI cars.\n0  = no global top speed limit.', storage.globalTopSpeedLimitKmh, StorageManager_options_min[StorageManager_Options.GlobalTopSpeedLimitKmh], StorageManager_options_max[StorageManager_Options.GlobalTopSpeedLimitKmh], DEFAULT_SLIDER_WIDTH, '%.2f km/h', StorageManager_options_default[StorageManager_Options.GlobalTopSpeedLimitKmh])

    if ui_checkbox('Override AI awareness', storage.overrideAiAwareness) then storage.overrideAiAwareness = not storage.overrideAiAwareness end
    if ui_itemHovered() then ui_setTooltip('If enabled, our computed lateral offset will override the value from Kunos, otherwise our computed lateral offset adds to it. (EXPERIMENTAL)') end

    storage.clearAhead_meters = renderSlider('The distance which determines whether a car is far enough ahead of another car', 'When checking if a car is clear ahead of another car, this is the distance used to determine if it is clear.', storage.clearAhead_meters, StorageManager_options_min[StorageManager_Options.ClearAhead_meters], StorageManager_options_max[StorageManager_Options.ClearAhead_meters], DEFAULT_SLIDER_WIDTH, '%.2f m', StorageManager_options_default[StorageManager_Options.ClearAhead_meters])

    ui_separator()

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

    -- Draw the app name and version at the bottom-right of the settings window
    UIAppNameVersionWidget_drawBottomRight(15)

    ui_popDWriteFont()

    -- Close the global app-enabled disabled section if the app is disabled
    if not appEnabled then
        ui_popDisabled()
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