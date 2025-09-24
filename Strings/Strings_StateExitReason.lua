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
    [stringNames.None] = "No reason",
    [stringNames.YieldingToCar] = "Yielding to car behind",
    [stringNames.OvertakingCar] = "Overtaking car in front",
    [stringNames.OvertakingCarNoLongerExists] = "Overtaking car no longer exists",
    [stringNames.ArrivedAtOvertakingLane] = "Arrived at overtaking lane",
    [stringNames.OvertakingCarIsClearlyAhead] = "Overtaking car is clearly ahead",
    [stringNames.ArrivedAtYieldingLane] = "Arrived at yielding lane",
    [stringNames.ArrivedToNormal] = "Arrived to normal driving lane",
    [stringNames.ContinuingOvertakingNextCar] = "Continuing overtaking next car",
    [stringNames.ClearlyAheadOfYieldingCar] = "Clearly ahead of yielding car",
    [stringNames.OvertakingCarIsClearlyBehind] = "Overtaking car is clearly behind",
    [stringNames.YieldingCarIsFasterThenOvertakingCar] = "Yielding car is faster than overtaking car",
    [stringNames.OvertakingCarNotOnOvertakingSide] = "Overtaking car not on overtaking side",
    [stringNames.NavigatingAroundAccident] = "Navigating around accident",
}

local stringSaveFunction = function (carIndex, stringName)
    local state = CarStateMachine.getCurrentState(carIndex)
    CarManager.cars_statesExitReason_NAME[carIndex][state] = stringName
end

Strings.StringNames[STRING_CATEGORY] = stringNames
Strings.StringValues[STRING_CATEGORY] = stringValues
Strings.StringSaveFunctions[STRING_CATEGORY] = stringSaveFunction