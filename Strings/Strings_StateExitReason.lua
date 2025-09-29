local STRING_CATEGORY = Strings.StringCategories.StateExitReason

local stringNames = {
    None = 0,
    YieldingToCar = 1,
    OvertakingCar = 2,
    OvertakingCarNoLongerExists = 3,
    ArrivedAtOvertakingLane = 4,
    OvertakingCarIsClearlyAhead = 5,
    ArrivedAtYieldingLane = 6,
    ArrivedToNormal = 7,
    ContinuingOvertakingNextCar = 8,
    ClearlyAheadOfYieldingCar = 9,
    OvertakingCarIsClearlyBehind = 10,
    YieldingCarIsFasterThenOvertakingCar = 11,
    OvertakingCarNotOnOvertakingSide = 12,
    NavigatingAroundAccident = 13,
    NoAccidentIndexToNavigateAround = 14,
    FoundCloserAccidentToNavigateAround = 15,
    AccidentIsFarBehindUs = 16,
}

local stringValues = {
    [stringNames.None] = const("No reason"),
    [stringNames.YieldingToCar] = const("Yielding to car behind"),
    [stringNames.OvertakingCar] = const("Overtaking car in front"),
    [stringNames.OvertakingCarNoLongerExists] = const("Overtaking car no longer exists"),
    [stringNames.ArrivedAtOvertakingLane] = const("Arrived at overtaking lane"),
    [stringNames.OvertakingCarIsClearlyAhead] = const("Overtaking car is clearly ahead"),
    [stringNames.ArrivedAtYieldingLane] = const("Arrived at yielding lane"),
    [stringNames.ArrivedToNormal] = const("Arrived to normal driving lane"),
    [stringNames.ContinuingOvertakingNextCar] = const("Continuing overtaking next car"),
    [stringNames.ClearlyAheadOfYieldingCar] = const("Clearly ahead of yielding car"),
    [stringNames.OvertakingCarIsClearlyBehind] = const("Overtaking car is clearly behind"),
    [stringNames.YieldingCarIsFasterThenOvertakingCar] = const("Yielding car is faster than overtaking car"),
    [stringNames.OvertakingCarNotOnOvertakingSide] = const("Overtaking car not on overtaking side"),
    [stringNames.NavigatingAroundAccident] = const("Navigating around accident"),
}

local stringSaveFunction = function (carIndex, stringName)
    local state = CarStateMachine.getCurrentState(carIndex)
    CarManager.cars_statesExitReason_NAME[carIndex][state] = stringName
end

Strings.StringNames[STRING_CATEGORY] = stringNames
Strings.StringValues[STRING_CATEGORY] = stringValues
Strings.StringSaveFunctions[STRING_CATEGORY] = stringSaveFunction