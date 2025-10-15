local STRING_CATEGORY = Strings.StringCategories.ReasonWhyCantYield

---@class Strings.ReasonWhyCantYield
---@field None integer
---@field TargetSideBlocked integer
---@field CarInBlindSpot integer
---@field OvertakingCarInPits integer
---@field OvertakingCarTooFarBehind integer
---@field OvertakingCarNotBehind integer
---@field OvertakingCarBelowMinimumSpeed integer
---@field YieldingCarBelowMinimumSpeed integer
---@field WeAreFasterThanOvertakingCar integer
---@field OvertakingCarNotOnOvertakingSide integer

-- ---@enum Strings.ReasonWhyCantYield
---@type Strings.ReasonWhyCantYield
local stringNames = {
    None = 0,
    TargetSideBlocked = 1,
    CarInBlindSpot = 2,
    OvertakingCarInPits = 3,
    OvertakingCarTooFarBehind = 4,
    OvertakingCarNotBehind = 5,
    OvertakingCarBelowMinimumSpeed = 6,
    YieldingCarBelowMinimumSpeed = 7,
    WeAreFasterThanOvertakingCar = 8,
    OvertakingCarNotOnOvertakingSide = 9,
}

local stringValues = {
    -- [Strings.ReasonWhyCantYield.None] = "No reason",
    -- [stringNames.TargetSideBlocked] = "Target side blocked by another car (%s) so not driving to the side: gap=%.2f m",
    -- [stringNames.CarInBlindSpot] = 'Car in blind spot so not driving to the side: L=%.2f m  R=%.2f m',
    [stringNames.TargetSideBlocked] = const("Target side blocked by another car (%s) so not driving to the side"),
    [stringNames.CarInBlindSpot] = const('Car in blind spot so not driving to the side'),
    [stringNames.OvertakingCarInPits] = const('Car behind is in pits'),
    [stringNames.OvertakingCarTooFarBehind] = const('Overtaking car too far behind'),
    [stringNames.OvertakingCarNotBehind] = const('Overtaking car not behind (clear)'),
    [stringNames.OvertakingCarBelowMinimumSpeed] = const('Overtaking car below minimum speed'),
    [stringNames.YieldingCarBelowMinimumSpeed] = const('Yielding car speed too low (corner/traffic)'),
    [stringNames.WeAreFasterThanOvertakingCar] = const('We are faster than the car behind'),
    [stringNames.OvertakingCarNotOnOvertakingSide] = const('Overtaking car not on overtaking lane'),
}

local stringSaveFunction = function (carIndex, stringName)
    CarManager.cars_reasonWhyCantYield_NAME[carIndex] = stringName
end

Strings.StringNames[STRING_CATEGORY] = stringNames
Strings.StringValues[STRING_CATEGORY] = stringValues
Strings.StringSaveFunctions[STRING_CATEGORY] = stringSaveFunction