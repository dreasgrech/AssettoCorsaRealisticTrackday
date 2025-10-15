local STRING_CATEGORY = Strings.StringCategories.ReasonWhyCantOvertake

---@class Strings.ReasonWhyCantOvertake
---@field None integer
---@field YieldingCarInPits integer
---@field YieldingCarTooFarAhead integer
---@field YieldingCarIsFaster integer
---@field YieldingCarIsNotOnYieldingSide integer
---@field AnotherCarBehindTooClose integer

---@type Strings.ReasonWhyCantOvertake
local stringNames = {
    None = 0,
    YieldingCarInPits = 1,
    YieldingCarTooFarAhead = 2,
    YieldingCarIsFaster = 3,
    YieldingCarIsNotOnYieldingSide = 4,
    AnotherCarBehindTooClose = 5,
}

local stringValues = {
    [stringNames.None] = const('No reason'),
    [stringNames.YieldingCarInPits] = const('Car in front is in pits'),
    [stringNames.YieldingCarTooFarAhead] = const('Car too front ahead'),
    [stringNames.YieldingCarIsFaster] = const('Car in front is faster'),
    [stringNames.YieldingCarIsNotOnYieldingSide] = const('Car in front not on overtaking lane'),
    [stringNames.AnotherCarBehindTooClose] = const('Another car behind us too close'),
}

local stringSaveFunction = function (carIndex, stringName)
    CarManager.cars_reasonWhyCantOvertake_NAME[carIndex] = stringName
end

Strings.StringNames[STRING_CATEGORY] = stringNames
Strings.StringValues[STRING_CATEGORY] = stringValues
Strings.StringSaveFunctions[STRING_CATEGORY] = stringSaveFunction
