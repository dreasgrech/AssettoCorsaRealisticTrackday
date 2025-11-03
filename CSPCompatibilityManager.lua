--- Responsible for checking if required CSP elements (functions, fields, enums, etc...) are available in the current CSP version.
--- When making use of a CSP element that was added in a specific CSP version, it is recommended to add it to the list of used elements here
--- so that we can check for its existence at runtime
local CSPCompatibilityManager = {}

local LOG_MISSING_ELEMENTS_WHILE_CHECKING = false
local ADD_NON_EXISTANT_FUNCTIONS_TO_TEST_MISSING = false

---@class TableForUsedElement
---@field elementFn function
---@field name string

--- Creates a table for metadata of a used CSP element
---@param elementFn function
---@param elementName string
---@return TableForUsedElement
local getTableForUsedElement = function(elementFn, elementName)
    return {
        name = elementName,
        elementFn = elementFn
    }
end

---Returns the current version of Custom Shaders Patch
---@return string
CSPCompatibilityManager.getCSPVersion = function()
    if not ac.getPatchVersion then
        return "Unknown"
    end

    local versionStr = ac.getPatchVersion()
    return string.format("v%s", versionStr)
end

--- Checks for missing CSP elements (functions, fields, enums, etc...) used in the app
--- @return table<string> @List of missing element names
CSPCompatibilityManager.checkForMissingCSPElements = function()
    -- bindings
    local ac = ac
    local ui = ui
    local physics = physics

    ---@type table<TableForUsedElement>
    local usedACElements = {
        getTableForUsedElement(function() return ac.log end, "ac.log"),
        getTableForUsedElement(function() return ac.warn end, "ac.warn"),
        getTableForUsedElement(function() return ac.error end, "ac.error"),
        getTableForUsedElement(function() return ac.getSim end, "ac.getSim"),
        getTableForUsedElement(function() return ac.getCar end, "ac.getCar"),
        getTableForUsedElement(function() return ac.onCarJumped end, "ac.onCarJumped"),
        getTableForUsedElement(function() return ac.onCarCollision end, "ac.onCarCollision"),
        getTableForUsedElement(function() return ac.iterateCars end, "ac.iterateCars"),
        getTableForUsedElement(function() return ac.setTargetCar end, "ac.setTargetCar"),
        getTableForUsedElement(function() return ac.setTurningLights end, "ac.setTurningLights"),
        getTableForUsedElement(function() return ac.worldCoordinateToTrack end, "ac.worldCoordinateToTrack"),
        getTableForUsedElement(function() return ac.worldCoordinateToTrackProgress end, "ac.worldCoordinateToTrackProgress"),
        getTableForUsedElement(function() return ac.trackProgressToWorldCoordinate end, "ac.trackProgressToWorldCoordinate"),
        getTableForUsedElement(function() return ac.getTrackUpcomingTurn end, "ac.getTrackUpcomingTurn"),
        getTableForUsedElement(function() return ac.overrideCarControls end, "ac.overrideCarControls"),
        getTableForUsedElement(function() return ac.hasTrackSpline end, "ac.hasTrackSplines"),
        getTableForUsedElement(function() return ac.getTrackFullID end, "ac.getTrackFullID"),
        getTableForUsedElement(function() return ac.storage end, "ac.storage"),
        getTableForUsedElement(function() return ac.focusCar end, "ac.focusCar"),
        getTableForUsedElement(function() return ac.setCurrentCamera end, "ac.setCurrentCamera"),
        getTableForUsedElement(function() return ac.setCurrentDrivableCamera end, "ac.setCurrentDrivableCamera"),
        getTableForUsedElement(function() return ac.getCarMaxSpeedWithGear end, "ac.getCarMaxSpeedWithGear"),
    }

    ---@type table<TableForUsedElement>
    local usedUIElements = {
        getTableForUsedElement(function() return ui.button end, "ui.button"),
        getTableForUsedElement(function() return ui.newLine end, "ui.newLine"),
        getTableForUsedElement(function() return ui.text end, "ui.text"),
        getTableForUsedElement(function() return ui.drawRect end, "ui.drawRect"),
        getTableForUsedElement(function() return ui.drawLine end, "ui.drawLine"),
        getTableForUsedElement(function() return ui.getCursor end, "ui.getCursor"),
        getTableForUsedElement(function() return ui.drawTextClipped end, "ui.drawTextClipped"),
        getTableForUsedElement(function() return ui.dwriteDrawText end, "ui.dwriteDrawText"),
        getTableForUsedElement(function() return ui.invisibleButton end, "ui.invisibleButton"),
        getTableForUsedElement(function() return ui.pushItemWidth end, "ui.pushItemWidth"),
        getTableForUsedElement(function() return ui.popItemWidth end, "ui.popItemWidth"),
        getTableForUsedElement(function() return ui.itemHovered end, "ui.itemHovered"),
        getTableForUsedElement(function() return ui.setTooltip end, "ui.setTooltip"),
        getTableForUsedElement(function() return ui.pushDisabled end, "ui.pushDisabled"),
        getTableForUsedElement(function() return ui.popDisabled end, "ui.popDisabled"),
        getTableForUsedElement(function() return ui.columns end, "ui.columns"),
        getTableForUsedElement(function() return ui.ButtonFlags end, "ui.buttonFlags"),
        getTableForUsedElement(function() return ui.windowSize end, "ui.windowSize"),
        getTableForUsedElement(function() return ui.drawImage end, "ui.drawImage"),
        getTableForUsedElement(function() return ui.pushDWriteFont end, "ui.pushDWriteFont"),
        getTableForUsedElement(function() return ui.pushStyleColor end, "ui.pushStyleColor"),
        getTableForUsedElement(function() return ui.popStyleColor end, "ui.popStyleColor"),
        getTableForUsedElement(function() return ui.textColored end, "ui.textColored"),
        getTableForUsedElement(function() return ui.setColumnWidth end, "ui.setColumnWidth"),
        getTableForUsedElement(function() return ui.popDWriteFont end, "ui.popDWriteFont"),
        getTableForUsedElement(function() return ui.separator end, "ui.separator"),
    }

    ---@type table<TableForUsedElement>
    local usedPhysicsElements = {
        getTableForUsedElement(function() return physics.overrideRacingFlag end, "physics.overrideRacingFlag"),
        getTableForUsedElement(function() return physics.setAIThrottleLimit end, "physics.setAIThrottleLimit"),
        getTableForUsedElement(function() return physics.setAITopSpeed end, "physics.setAITopSpeed"),
        getTableForUsedElement(function() return physics.setAICaution end, "physics.setAICaution"),
        getTableForUsedElement(function() return physics.setAIAggression end, "physics.setAIAggression"),
        getTableForUsedElement(function() return physics.setAIStopCounter end, "physics.setAIStopCounter"),
        getTableForUsedElement(function() return physics.setExtraAIGrip end, "physics.setExtraAIGrip"),
        getTableForUsedElement(function() return physics.disableCarCollisions end, "physics.disableCarCollisions"),
        getTableForUsedElement(function() return physics.setGentleStop end, "physics.setGentleStop"),
        getTableForUsedElement(function() return physics.preventAIFromRetiring end, "physics.preventAIFromRetiring"),
        getTableForUsedElement(function() return physics.setAISplineOffset end, "physics.setAISplineOffset"),
    }

    -- Make sure we have access to the ac.getSim or ac.getSimState functions!
    ---@type table<TableForUsedElement>
    local usedAcStateSimElements
    local simStateFn = ac.getSim or ac.getSimState
    local simStateFnAvailable, sim = pcall(function() return simStateFn() end)
    if simStateFnAvailable then
        usedAcStateSimElements = {
            getTableForUsedElement(function() return sim.trackLengthM end, "ac.getSim().trackLengthM"),
            getTableForUsedElement(function() return sim.raceSessionType end, "ac.getSim().raceSessionType"),
        }
    end

    -- For testing: add some non-existant functions to see if the missing check works
    if ADD_NON_EXISTANT_FUNCTIONS_TO_TEST_MISSING then
        table.insert(usedACElements, getTableForUsedElement(function() return ac.nonExistantFunction end, "ac.nonExistantFunction"))
        table.insert(usedUIElements, getTableForUsedElement(function() return ui.nonExistantFunction end, "ui.nonExistantFunction"))
        table.insert(usedPhysicsElements, getTableForUsedElement(function() return physics.nonExistantFunction end, "physics.nonExistantFunction"))
        if simStateFnAvailable then
            table.insert(usedAcStateSimElements, getTableForUsedElement(function() return sim.nonExistantFunction end, "ac.getSim().nonExistantFunction"))
        end
    end

    ---Goes through the list of used elements and checks if any are not available
    ---@param elements table<TableForUsedElement>
    ---@param missingElementsNames table<string>
    ---@param namespace string
    local checkMissingElements = function(elements, missingElementsNames, namespace)
        for _, usedElement in ipairs(elements) do
            local elementFn = usedElement.elementFn
            -- using pcall here to catch any errors that may occur when calling the function that retrieves the element, which is an indication that the element is missing
            local success, result = pcall(function()
                local elementFnValue = elementFn()
                return elementFnValue ~= nil
            end)

            if
                not success or  -- if success is false, there was an error calling the function, so the element is missing
                result == false -- if result is false, the element is nil, so it's missing
            then
                -- add the missing element name metadata to the list of missing elements
                table.insert(missingElementsNames, usedElement.name)
                if LOG_MISSING_ELEMENTS_WHILE_CHECKING then ac.log(string.format("[CSPCompatibilityManager] %s function '%s' is not available (nil)", namespace, usedElement.name)) end
            end
        end
    end

    ---@type table<string>
    local missingElementsNames = {}

    -- Check for missing elements in ac
    checkMissingElements(usedACElements, missingElementsNames, "ac")

    -- Check for missing elements in ui
    checkMissingElements(usedUIElements, missingElementsNames, "ui")

    -- Check for missing elements in physics
    checkMissingElements(usedPhysicsElements, missingElementsNames, "physics")

    -- Check for missing elements in ac.getSim()
    if simStateFnAvailable then
        checkMissingElements(usedAcStateSimElements, missingElementsNames, "ac.getSim()")
    end

    return missingElementsNames
end

return CSPCompatibilityManager