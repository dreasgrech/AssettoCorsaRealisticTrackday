local StringsManager = {}

-- Strings.resolve

-- StringsManager.setString(
-- 1,
-- Strings.StringCategories.ReasonWhyCantYield,
-- Strings.StringsName[Strings.StringCategories.ReasonWhyCantYield].TargetSideBlocked
-- )
StringsManager.setString = function(carIndex, stringCategory, stringName)
    local stringSaveFunction = Strings.StringSaveFunctions[stringCategory]
    stringSaveFunction(carIndex, stringName)
end


return StringsManager