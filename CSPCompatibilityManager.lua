--- Responsible for checking if required CSP elements (functions, fields, enums, etc...) are available in the current CSP version.
--- When making use of a CSP element that was added in a specific CSP version, it is recommended to add it to the list of used elements here
--- so that we can check for its existence at runtime
local CSPCompatibilityManager = {}

-- bindings
local ac = ac
local ui = ui
local physics = physics

local LOG_MISSING_ELEMENTS_WHILE_CHECKING = false
local ADD_NON_EXISTANT_FUNCTIONS_TO_TEST_MISSING = false

---@class TableForUsedElement
---@field element any|nil
---@field name string

---comment
---@param element any
---@param elementName string
---@return TableForUsedElement
local getTableForUsedElement = function(element, elementName)
    return {
        name = elementName,
        element = element
    }
end

local usedACElements = {
    getTableForUsedElement(ac.log, "ac.log"),
    getTableForUsedElement(ac.warn, "ac.warn"),
    getTableForUsedElement(ac.error, "ac.error"),
    getTableForUsedElement(ac.getSim, "ac.getSim"),
    getTableForUsedElement(ac.getCar, "ac.getCar"),
    getTableForUsedElement(ac.onCarJumped, "ac.onCarJumped"),
    getTableForUsedElement(ac.onCarCollision, "ac.onCarCollision"),
    getTableForUsedElement(ac.iterateCars, "ac.iterateCars"),
    getTableForUsedElement(ac.setTargetCar, "ac.setTargetCar"),
    getTableForUsedElement(ac.setTurningLights, "ac.setTurningLights"),
    getTableForUsedElement(ac.worldCoordinateToTrack, "ac.worldCoordinateToTrack"),
    getTableForUsedElement(ac.worldCoordinateToTrackProgress, "ac.worldCoordinateToTrackProgress"),
    getTableForUsedElement(ac.trackProgressToWorldCoordinate, "ac.trackProgressToWorldCoordinate"),
    getTableForUsedElement(ac.getTrackUpcomingTurn, "ac.getTrackUpcomingTurn"),
    getTableForUsedElement(ac.overrideCarControls, "ac.overrideCarControls"),
    getTableForUsedElement(ac.hasTrackSpline, "ac.hasTrackSplines"),
    getTableForUsedElement(ac.getTrackFullID, "ac.getTrackFullID"),
    getTableForUsedElement(ac.storage, "ac.storage"),
    getTableForUsedElement(ac.focusCar, "ac.focusCar"),
    getTableForUsedElement(ac.setCurrentCamera, "ac.setCurrentCamera"),
    getTableForUsedElement(ac.setCurrentDrivableCamera, "ac.setCurrentDrivableCamera"),
    getTableForUsedElement(ac.getCarMaxSpeedWithGear, "ac.getCarMaxSpeedWithGear"),
}

local usedUIElements = {
    getTableForUsedElement(ui.button, "ui.button"),
    getTableForUsedElement(ui.newLine, "ui.newLine"),
    getTableForUsedElement(ui.text, "ui.text"),
    getTableForUsedElement(ui.drawRect, "ui.drawRect"),
    getTableForUsedElement(ui.drawLine, "ui.drawLine"),
    getTableForUsedElement(ui.getCursor, "ui.getCursor"),
    getTableForUsedElement(ui.drawTextClipped, "ui.drawTextClipped"),
    getTableForUsedElement(ui.dwriteDrawText, "ui.dwriteDrawText"),
    getTableForUsedElement(ui.invisibleButton, "ui.invisibleButton"),
    getTableForUsedElement(ui.pushItemWidth, "ui.pushItemWidth"),
    getTableForUsedElement(ui.popItemWidth, "ui.popItemWidth"),
    getTableForUsedElement(ui.itemHovered, "ui.itemHovered"),
    getTableForUsedElement(ui.setTooltip, "ui.setTooltip"),
    getTableForUsedElement(ui.pushDisabled, "ui.pushDisabled"),
    getTableForUsedElement(ui.popDisabled, "ui.popDisabled"),
    getTableForUsedElement(ui.columns, "ui.columns"),
    getTableForUsedElement(ui.ButtonFlags, "ui.buttonFlags"),
    getTableForUsedElement(ui.windowSize, "ui.windowSize"),
    getTableForUsedElement(ui.drawImage, "ui.drawImage"),
    getTableForUsedElement(ui.pushDWriteFont, "ui.pushDWriteFont"),
    getTableForUsedElement(ui.pushStyleColor, "ui.pushStyleColor"),
    getTableForUsedElement(ui.popStyleColor, "ui.popStyleColor"),
    getTableForUsedElement(ui.textColored, "ui.textColored"),
    getTableForUsedElement(ui.setColumnWidth, "ui.setColumnWidth"),
    getTableForUsedElement(ui.popDWriteFont, "ui.popDWriteFont"),
    getTableForUsedElement(ui.separator, "ui.separator"),
}

local usedPhysicsElements = {
    getTableForUsedElement(physics.overrideRacingFlag, "physics.overrideRacingFlag"),
    getTableForUsedElement(physics.setAIThrottleLimit, "physics.setAIThrottleLimit"),
    getTableForUsedElement(physics.setAITopSpeed, "physics.setAITopSpeed"),
    getTableForUsedElement(physics.setAICaution, "physics.setAICaution"),
    getTableForUsedElement(physics.setAIAggression, "physics.setAIAggression"),
    getTableForUsedElement(physics.setAIStopCounter, "physics.setAIStopCounter"),
    getTableForUsedElement(physics.setExtraAIGrip, "physics.setExtraAIGrip"),
    getTableForUsedElement(physics.disableCarCollisions, "physics.disableCarCollisions"),
    getTableForUsedElement(physics.setGentleStop, "physics.setGentleStop"),
    getTableForUsedElement(physics.preventAIFromRetiring, "physics.preventAIFromRetiring"),
    getTableForUsedElement(physics.setAISplineOffset, "physics.setAISplineOffset"),
}

if ADD_NON_EXISTANT_FUNCTIONS_TO_TEST_MISSING then
    table.insert(usedACElements, getTableForUsedElement(ac.nonExistantFunction, "ac.nonExistantFunction"))
    table.insert(usedUIElements, getTableForUsedElement(ui.nonExistantFunction, "ui.nonExistantFunction"))
    table.insert(usedPhysicsElements, getTableForUsedElement(physics.nonExistantFunction, "physics.nonExistantFunction"))
end

--- Checks for missing CSP elements (functions, fields, enums, etc...) used in the app
--- @return table<string> @List of missing element names
CSPCompatibilityManager.checkForMissingCSPElements = function()
    ---@type table<string>
    local missingElementsNames = {}

    -- Check for missing elements in ac
    for _, usedElement in ipairs(usedACElements) do
        if usedElement.element == nil then
            table.insert(missingElementsNames, usedElement.name)
            if LOG_MISSING_ELEMENTS_WHILE_CHECKING then Logger.log(string.format("[CSPCompatibilityManager] ac function '%s' is not available (nil)", usedElement.name)) end
        end
    end

    -- Check for missing elements in ui
    for _, usedElement in ipairs(usedUIElements) do
        if usedElement.element == nil then
            table.insert(missingElementsNames, usedElement.name)
            if LOG_MISSING_ELEMENTS_WHILE_CHECKING then Logger.log(string.format("[CSPCompatibilityManager] ui function '%s' is not available (nil)", usedElement.name)) end
        end
    end

    -- Check for missing elements in physics
    for _, usedElement in ipairs(usedPhysicsElements) do
        if usedElement.element == nil then
            table.insert(missingElementsNames, usedElement.name)
            if LOG_MISSING_ELEMENTS_WHILE_CHECKING then Logger.log(string.format("[CSPCompatibilityManager] physics function '%s' is not available (nil)", usedElement.name)) end
        end
    end

    return missingElementsNames
end

--- Clears the cached memory of the CSP elements metadata we hold to check for missing elements
CSPCompatibilityManager.clearElementsMetadataMemory = function()
    usedACElements = nil
    usedUIElements = nil
    usedPhysicsElements = nil
end

return CSPCompatibilityManager