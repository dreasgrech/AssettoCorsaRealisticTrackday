local StringsManager = {}

-- StringsManager.setString(
-- 1,
-- Strings.StringCategories.ReasonWhyCantYield,
-- Strings.StringsName[Strings.StringCategories.ReasonWhyCantYield].TargetSideBlocked
-- )
StringsManager.setString = function(carIndex, stringCategory, stringName)
    local stringSaveFunction = Strings.StringSaveFunctions[stringCategory]
    stringSaveFunction(carIndex, stringName)
end

---comment
---@param stringCategory any
---@param stringName any
---@return string
StringsManager.resolveStringValue = function(stringCategory, stringName)
    local stringValues = Strings.StringValues[stringCategory]
    return stringValues[stringName]
end


return StringsManager