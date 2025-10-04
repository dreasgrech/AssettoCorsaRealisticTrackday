local StringsManager = {}

-- StringsManager.setString(
-- 1,
-- Strings.StringCategories.ReasonWhyCantYield,
-- Strings.StringsName[Strings.StringCategories.ReasonWhyCantYield].TargetSideBlocked
-- )

---Sets a string for a car given the string category and string name (no actual strings are used here)
---@param carIndex integer
---@param stringCategory Strings.StringCategories
---@param stringName integer
StringsManager.setString = function(carIndex, stringCategory, stringName)
    local stringSaveFunction = Strings.StringSaveFunctions[stringCategory]
    stringSaveFunction(carIndex, stringName)
end

---Resolves the actual string value from the string category and string name
---@param stringCategory Strings.StringCategories
---@param stringName integer
---@return string
StringsManager.resolveStringValue = function(stringCategory, stringName)
    local stringValues = Strings.StringValues[stringCategory]
    return stringValues[stringName]
end


return StringsManager