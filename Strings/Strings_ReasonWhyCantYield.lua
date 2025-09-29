local STRING_CATEGORY = Strings.StringCategories.ReasonWhyCantYield

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
    [stringNames.OvertakingCarInPits] = const('Car behind is in pits so not yielding'),
    [stringNames.OvertakingCarTooFarBehind] = const('Overtaking car too far behind'),
    [stringNames.OvertakingCarNotBehind] = const('Overtaking car not behind (clear) so not yielding'),
    [stringNames.OvertakingCarBelowMinimumSpeed] = const('Overtaking car below minimum speed so not yielding'),
    [stringNames.YieldingCarBelowMinimumSpeed] = const('Yielding car speed too low (corner/traffic) so not yielding'),
    [stringNames.WeAreFasterThanOvertakingCar] = const('We are faster than the car behind so not yielding'),
    [stringNames.OvertakingCarNotOnOvertakingSide] = const('Overtaking car not on overtaking lane so not yielding'),
}

local stringSaveFunction = function (carIndex, stringName)
    -- CarManager.cars_reasonWhyCantYield[carIndex] = stringName
    CarManager.cars_reasonWhyCantYield_NAME[carIndex] = stringName
end

Strings.StringNames[STRING_CATEGORY] = stringNames
Strings.StringValues[STRING_CATEGORY] = stringValues
Strings.StringSaveFunctions[STRING_CATEGORY] = stringSaveFunction