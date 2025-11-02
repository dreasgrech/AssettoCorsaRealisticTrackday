local StorageManager = {}

local fillInDoDTables = function(collection_beforeDoD, options_default, options_min, options_max)
    options_default = {}
    options_min = {}
    options_max = {}

    for i, option in ipairs(collection_beforeDoD) do
        local optionName = option.name
        options_default[optionName] = option.default
        options_min[optionName] = option.min
        options_max[optionName] = option.max
    end

    return options_default, options_min, options_max
end

---@param storageID string|nil
---@param trackID string
---@param sessionType string
---@return string
local getStorageKeyForTrackAndMode = function(storageID, trackID, sessionType)
    -- TODO: this if-check here is done for backwards compatibility, remove later
    if storageID == nil then
        return string.format("%s_%s", trackID, sessionType)
    end

    return string.format("%s_%s_%s", storageID, trackID, sessionType)
end

---@enum StorageManager.Options
StorageManager.Options ={
    Enabled = 1,
    HandleSideCheckingWhenYielding = 2,
    HandleSideCheckingWhenOvertaking = 3,
    -- YieldSide = 3,
    OverrideAiAwareness = 4,
    DefaultAICaution = 5,
    OverrideOriginalAIAggression_DrivingNormally = 6,
    OverrideOriginalAIAggression_Overtaking = 7,
    DefaultAIAggression = 8,

    DefaultLateralOffset = 9,
    YieldingLateralOffset = 10,
    OvertakingLateralOffset = 11,
    -- MaxLateralOffset_normalized = 10,

    ClearAhead_meters = 12,

    -- HandleYielding = 13,
    -- DetectCarBehind_meters = 14,
    -- RampSpeed_mps = 15,
    -- RampRelease_mps = 16,
    -- DistanceToOvertakingCarToLimitSpeed = 17,
    -- SpeedLimitValueToOvertakingCar = 18,
    -- MinimumSpeedLimitKmhToLimitToOvertakingCar = 19,
    -- RequireOvertakingCarToBeOnOvertakingLaneToYield = 20,

    HandleOvertaking = 13,
    DetectCarAhead_meters = 14,
    OvertakeRampSpeed_mps = 15,
    OvertakeRampRelease_mps = 16,
    RequireYieldingCarToBeOnYieldingLaneToOvertake = 17,

    CustomAIFlood_enabled = 18,
    CustomAIFlood_distanceBehindPlayerToCycle_meters = 19,
    CustomAIFlood_distanceAheadOfPlayerToCycle_meters = 20,

    HandleAccidents = 21,
    DistanceFromAccidentToSeeYellowFlag_meters = 22,
    DistanceToStartNavigatingAroundCarInAccident_meters = 23,
}

---@enum StorageManager.Options_Debugging
StorageManager.Options_Debugging = {
    DebugShowCarStateOverheadText = 1,
    DebugCarGizmosDrawistance = 2,
    DebugShowRaycastsWhileDrivingLaterally = 3,
    DebugDrawSideOfftrack = 4,
    DrawCarList = 5,
    DebugLogFastStateChanges = 6,
    DebugLogCarYielding = 7,
    DebugLogCarOvertaking = 8,
}

---@enum StorageManager.Options_Yielding
StorageManager.Options_Yielding = {
    HandleYielding = 1,
    DetectCarBehind_meters = 2,
    RampSpeed_mps = 3,
    RampRelease_mps = 4,
    DistanceToOvertakingCarToLimitSpeed = 5,
    SpeedLimitValueToOvertakingCar = 6,
    MinimumSpeedLimitKmhToLimitToOvertakingCar = 7,
    RequireOvertakingCarToBeOnOvertakingLaneToYield = 8,
}

local optionsCollection_Debugging_beforeDoD = {
    { name = StorageManager.Options_Debugging.DebugShowCarStateOverheadText, default=false, min=nil, max=nil },
    { name = StorageManager.Options_Debugging.DebugCarGizmosDrawistance, default=125.0, min=10.0, max=500.0 },
    { name = StorageManager.Options_Debugging.DebugShowRaycastsWhileDrivingLaterally, default=false, min=nil, max=nil },
    { name = StorageManager.Options_Debugging.DebugDrawSideOfftrack, default=false, min=nil, max=nil },
    { name = StorageManager.Options_Debugging.DrawCarList, default=true, min=nil, max=nil },
    { name = StorageManager.Options_Debugging.DebugLogFastStateChanges, default=false, min=nil, max=nil },
    { name = StorageManager.Options_Debugging.DebugLogCarYielding, default=false, min=nil, max=nil },
    { name = StorageManager.Options_Debugging.DebugLogCarOvertaking, default=false, min=nil, max=nil },
}

local optionsCollection_Yielding_beforeDoD = {
    { name = StorageManager.Options_Yielding.HandleYielding, default=true, min=nil, max=nil },
    { name = StorageManager.Options_Yielding.DetectCarBehind_meters, default=90, min=10, max=500 },
    { name = StorageManager.Options_Yielding.RampSpeed_mps, default=0.25, min=0.1, max=1.0 },
    { name = StorageManager.Options_Yielding.RampRelease_mps, default=0.25, min=0.1, max=1.0 },
    { name = StorageManager.Options_Yielding.DistanceToOvertakingCarToLimitSpeed, default=10.0, min=1.0, max=100.0 },
    { name = StorageManager.Options_Yielding.SpeedLimitValueToOvertakingCar, default=0.7, min=0.0, max=1.0 },
    { name = StorageManager.Options_Yielding.MinimumSpeedLimitKmhToLimitToOvertakingCar, default=60.0, min=0.0, max=300.0 },
    { name = StorageManager.Options_Yielding.RequireOvertakingCarToBeOnOvertakingLaneToYield, default=true, min=nil, max=nil },
    -- { name = StorageManager.Options_Yielding.RampSpeed_mps, default=0.25, min=0.1, max=RAMP_SPEEDS_MAX },
    -- { name = StorageManager.Options_Yielding.RampRelease_mps, default=0.1, min=0.1, max=RAMP_SPEEDS_MAX },
}

-- local RAMP_SPEEDS_MAX = 10

-- only used to build the actual tables that hold the runtime values
local optionsCollection_beforeDoD = {
    { name = StorageManager.Options.Enabled, default=false, min=nil, max=nil },
    { name = StorageManager.Options.HandleSideCheckingWhenYielding, default=true, min=nil, max=nil },
    { name = StorageManager.Options.HandleSideCheckingWhenOvertaking, default=true, min=nil, max=nil },
    -- { name = StorageManager.Options.YieldSide, default=RaceTrackManager.TrackSide.RIGHT, min=nil, max=nil },
    { name = StorageManager.Options.OverrideAiAwareness, default=true, min=nil, max=nil },
    { name = StorageManager.Options.DefaultAICaution, default=3, min=3, max=16 },
    { name = StorageManager.Options.OverrideOriginalAIAggression_DrivingNormally, default=true, min=nil, max=false },
    { name = StorageManager.Options.OverrideOriginalAIAggression_Overtaking, default=true, min=nil, max=false },
    { name = StorageManager.Options.DefaultAIAggression, default=.5, min=0, max=0.95 }, -- The max is .95 because it's mentioned in the docs for physics.setAIAggression that the value from the launcher is multiplied by .95 so that's the max

    { name = StorageManager.Options.DefaultLateralOffset, default=0, min=-1, max=1 },
    { name = StorageManager.Options.YieldingLateralOffset, default=0.8, min=-1, max=1 },
    { name = StorageManager.Options.OvertakingLateralOffset, default=-0.8, min=-1, max=1 },
    -- { name = StorageManager.Options.MaxLateralOffset_normalized, default=0.8, min=0.1, max=1.0 },

    { name = StorageManager.Options.ClearAhead_meters, default=10.0, min=4.0, max=20.0 },

    -- { name = StorageManager.Options.HandleYielding, default=true, min=nil, max=nil },
    -- { name = StorageManager.Options.DetectCarBehind_meters, default=90, min=10, max=500 },
    -- { name = StorageManager.Options.RampSpeed_mps, default=0.25, min=0.1, max=1.0 },
    -- { name = StorageManager.Options.RampRelease_mps, default=0.25, min=0.1, max=1.0 },
    -- { name = StorageManager.Options.DistanceToOvertakingCarToLimitSpeed, default=10.0, min=1.0, max=100.0 },
    -- { name = StorageManager.Options.SpeedLimitValueToOvertakingCar, default=0.7, min=0.0, max=1.0 },
    -- { name = StorageManager.Options.MinimumSpeedLimitKmhToLimitToOvertakingCar, default=60.0, min=0.0, max=300.0 },
    -- { name = StorageManager.Options.RequireOvertakingCarToBeOnOvertakingLaneToYield, default=true, min=nil, max=nil },
    -- -- { name = StorageManager.Options.RampSpeed_mps, default=0.25, min=0.1, max=RAMP_SPEEDS_MAX },
    -- -- { name = StorageManager.Options.RampRelease_mps, default=0.1, min=0.1, max=RAMP_SPEEDS_MAX },

    { name = StorageManager.Options.HandleOvertaking, default=true, min=nil, max=nil },
    { name = StorageManager.Options.DetectCarAhead_meters, default=100, min=50, max=500 },
    { name = StorageManager.Options.OvertakeRampSpeed_mps, default=0.5, min=0.1, max=1.0 },
    { name = StorageManager.Options.OvertakeRampRelease_mps, default=0.5, min=0.1, max=1.0 },
    { name = StorageManager.Options.RequireYieldingCarToBeOnYieldingLaneToOvertake, default=true, min=nil, max=nil },
    -- { name = StorageManager.Options.OvertakeRampSpeed_mps, default=0.5, min=0.1, max=RAMP_SPEEDS_MAX },
    -- { name = StorageManager.Options.OvertakeRampRelease_mps, default=0.5, min=0.1, max=RAMP_SPEEDS_MAX },

    { name = StorageManager.Options.CustomAIFlood_enabled, default=false, min=nil, max=nil },
    { name = StorageManager.Options.CustomAIFlood_distanceBehindPlayerToCycle_meters, default=200, min=50, max=500 },
    { name = StorageManager.Options.CustomAIFlood_distanceAheadOfPlayerToCycle_meters, default=100, min=20, max=300 },

    { name = StorageManager.Options.HandleAccidents, default=false, min=nil, max=nil },
    { name = StorageManager.Options.DistanceFromAccidentToSeeYellowFlag_meters, default=200.0, min=50.0, max=500.0 },
    { name = StorageManager.Options.DistanceToStartNavigatingAroundCarInAccident_meters, default=30.0, min=10.0, max=100.0 },

    -- { name = StorageManager.Options.DebugShowCarStateOverheadText, default=false, min=nil, max=nil },
    -- { name = StorageManager.Options.DebugCarStateOverheadShowDistance, default=125.0, min=10.0, max=500.0 },
    -- { name = StorageManager.Options.DebugShowRaycastsWhileDrivingLaterally, default=false, min=nil, max=nil },
    -- { name = StorageManager.Options.DebugDrawSideOfftrack, default=false, min=nil, max=nil },
    -- { name = StorageManager.Options.DrawCarList, default=true, min=nil, max=nil },
    -- { name = StorageManager.Options.DebugLogFastStateChanges, default=false, min=nil, max=nil },
    -- { name = StorageManager.Options.DebugLogCarYielding, default=false, min=nil, max=nil },
    -- { name = StorageManager.Options.DebugLogCarOvertaking, default=false, min=nil, max=nil },
}

--[====[
StorageManager.options_default = {}
StorageManager.options_min = {}
StorageManager.options_max = {}

for i, option in ipairs(optionsCollection_beforeDoD) do
    local optionName = option.name
    StorageManager.options_default[optionName] = option.default
    StorageManager.options_min[optionName] = option.min
    StorageManager.options_max[optionName] = option.max
end
--]====]

StorageManager.options_default,
StorageManager.options_min,
StorageManager.options_max = fillInDoDTables(
    optionsCollection_beforeDoD,
    StorageManager.options_default,
    StorageManager.options_min,
    StorageManager.options_max
)
optionsCollection_beforeDoD = nil  -- free memory

StorageManager.options_Debugging_default,
StorageManager.options_Debugging_min,
StorageManager.options_Debugging_max = fillInDoDTables(
    optionsCollection_Debugging_beforeDoD,
    StorageManager.options_Debugging_default,
    StorageManager.options_Debugging_min,
    StorageManager.options_Debugging_max
)
optionsCollection_Debugging_beforeDoD = nil  -- free memory

StorageManager.options_Yielding_default,
StorageManager.options_Yielding_min,
StorageManager.options_Yielding_max = fillInDoDTables(
    optionsCollection_Yielding_beforeDoD,
    StorageManager.options_Yielding_default,
    StorageManager.options_Yielding_min,
    StorageManager.options_Yielding_max
)
optionsCollection_Yielding_beforeDoD = nil  -- free memory

---@class StorageTable
---@field enabled boolean
---@field handleSideCheckingWhenYielding boolean
---@field handleSideCheckingWhenOvertaking boolean
-- ---@field yieldSide RaceTrackManager.TrackSide
---@field overrideAiAwareness boolean
---@field defaultAICaution integer
---@field overrideOriginalAIAggression_drivingNormally boolean
---@field overrideOriginalAIAggression_overtaking boolean
---@field defaultAIAggression integer
---@field defaultLateralOffset number
---@field yieldingLateralOffset number
---@field overtakingLateralOffset number
-- ---@field maxLateralOffset_normalized number
-----@field handleYielding boolean
-- ---@field detectCarBehind_meters number
-- ---@field rampSpeed_mps number
-- ---@field rampRelease_mps number
-- ---@field distanceToOvertakingCarToLimitSpeed number
-- ---@field speedLimitValueToOvertakingCar number
-- ---@field minimumSpeedLimitKmhToLimitToOvertakingCar number
-- ---@field requireOvertakingCarToBeOnOvertakingLane boolean
---@field handleOvertaking boolean
---@field detectCarAhead_meters number
---@field clearAhead_meters number
---@field overtakeRampSpeed_mps number
---@field overtakeRampRelease_mps number
---@field requireYieldingCarToBeOnYieldingLane boolean
---@field customAIFlood_enabled boolean
---@field customAIFlood_distanceBehindPlayerToCycle_meters number
---@field customAIFlood_distanceAheadOfPlayerToCycle_meters number
---@field handleAccidents boolean
---@field distanceFromAccidentToSeeYellowFlag_meters number
---@field distanceToStartNavigatingAroundCarInAccident_meters number

---@type StorageTable
local storageTable = {
    enabled = StorageManager.options_default[StorageManager.Options.Enabled],
    handleSideCheckingWhenYielding = StorageManager.options_default[StorageManager.Options.HandleSideCheckingWhenYielding],
    handleSideCheckingWhenOvertaking = StorageManager.options_default[StorageManager.Options.HandleSideCheckingWhenOvertaking],
    -- yieldSide = StorageManager.options_default[StorageManager.Options.YieldSide],
    overrideAiAwareness = StorageManager.options_default[StorageManager.Options.OverrideAiAwareness],
    defaultAICaution = StorageManager.options_default[StorageManager.Options.DefaultAICaution],
    overrideOriginalAIAggression_drivingNormally = StorageManager.options_default[StorageManager.Options.OverrideOriginalAIAggression_DrivingNormally],
    overrideOriginalAIAggression_overtaking = StorageManager.options_default[StorageManager.Options.OverrideOriginalAIAggression_Overtaking],
    defaultAIAggression = StorageManager.options_default[StorageManager.Options.DefaultAIAggression],

    defaultLateralOffset = StorageManager.options_default[StorageManager.Options.DefaultLateralOffset],
    yieldingLateralOffset = StorageManager.options_default[StorageManager.Options.YieldingLateralOffset],
    overtakingLateralOffset = StorageManager.options_default[StorageManager.Options.OvertakingLateralOffset],
    -- maxLateralOffset_normalized = StorageManager.options_default[StorageManager.Options.MaxLateralOffset_normalized],

    --handleYielding = StorageManager.options_default[StorageManager.Options.HandleYielding],
    -- detectCarBehind_meters = StorageManager.options_default[StorageManager.Options.DetectCarBehind_meters],
    -- rampSpeed_mps = StorageManager.options_default[StorageManager.Options.RampSpeed_mps],
    -- rampRelease_mps = StorageManager.options_default[StorageManager.Options.RampRelease_mps],
    -- distanceToOvertakingCarToLimitSpeed = StorageManager.options_default[StorageManager.Options.DistanceToOvertakingCarToLimitSpeed],
    -- speedLimitValueToOvertakingCar = StorageManager.options_default[StorageManager.Options.SpeedLimitValueToOvertakingCar],
    -- minimumSpeedLimitKmhToLimitToOvertakingCar = StorageManager.options_default[StorageManager.Options.MinimumSpeedLimitKmhToLimitToOvertakingCar],
    -- requireOvertakingCarToBeOnOvertakingLane = StorageManager.options_default[StorageManager.Options.RequireOvertakingCarToBeOnOvertakingLaneToYield],

    handleOvertaking = StorageManager.options_default[StorageManager.Options.HandleOvertaking],
    detectCarAhead_meters = StorageManager.options_default[StorageManager.Options.DetectCarAhead_meters],
    clearAhead_meters = StorageManager.options_default[StorageManager.Options.ClearAhead_meters],
    overtakeRampSpeed_mps = StorageManager.options_default[StorageManager.Options.OvertakeRampSpeed_mps],
    overtakeRampRelease_mps = StorageManager.options_default[StorageManager.Options.OvertakeRampRelease_mps],
    requireYieldingCarToBeOnYieldingLane = StorageManager.options_default[StorageManager.Options.RequireYieldingCarToBeOnYieldingLaneToOvertake],

    customAIFlood_enabled = StorageManager.options_default[StorageManager.Options.CustomAIFlood_enabled],
    customAIFlood_distanceBehindPlayerToCycle_meters = StorageManager.options_default[StorageManager.Options.CustomAIFlood_distanceBehindPlayerToCycle_meters],
    customAIFlood_distanceAheadOfPlayerToCycle_meters = StorageManager.options_default[StorageManager.Options.CustomAIFlood_distanceAheadOfPlayerToCycle_meters],

    handleAccidents = StorageManager.options_default[StorageManager.Options.HandleAccidents],
    distanceFromAccidentToSeeYellowFlag_meters = StorageManager.options_default[StorageManager.Options.DistanceFromAccidentToSeeYellowFlag_meters],
    distanceToStartNavigatingAroundCarInAccident_meters = StorageManager.options_default[StorageManager.Options.DistanceToStartNavigatingAroundCarInAccident_meters],
}

---@class StorageTable_Debugging
---@field debugShowCarStateOverheadText boolean
---@field debugCarGizmosDrawistance number
---@field debugShowRaycastsWhileDrivingLaterally boolean
---@field debugDrawSideOfftrack boolean
---@field drawCarList boolean
---@field debugLogFastStateChanges boolean
---@field debugLogCarYielding boolean
---@field debugLogCarOvertaking boolean

---@type StorageTable_Debugging
local storageTable_Debugging = {
    debugShowCarStateOverheadText = StorageManager.options_Debugging_default[StorageManager.Options_Debugging.DebugShowCarStateOverheadText],
    debugCarGizmosDrawistance = StorageManager.options_Debugging_default[StorageManager.Options_Debugging.DebugCarGizmosDrawistance],
    debugShowRaycastsWhileDrivingLaterally = StorageManager.options_Debugging_default[StorageManager.Options_Debugging.DebugShowRaycastsWhileDrivingLaterally],
    debugDrawSideOfftrack = StorageManager.options_Debugging_default[StorageManager.Options_Debugging.DebugDrawSideOfftrack],
    drawCarList = StorageManager.options_Debugging_default[StorageManager.Options_Debugging.DrawCarList],
    debugLogFastStateChanges = StorageManager.options_Debugging_default[StorageManager.Options_Debugging.DebugLogFastStateChanges],
    debugLogCarYielding = StorageManager.options_Debugging_default[StorageManager.Options_Debugging.DebugLogCarYielding],
    debugLogCarOvertaking = StorageManager.options_Debugging_default[StorageManager.Options_Debugging.DebugLogCarOvertaking],
}

---@class StorageTable_Yielding
---@field handleYielding boolean
---@field detectCarBehind_meters number
---@field rampSpeed_mps number
---@field rampRelease_mps number
---@field distanceToOvertakingCarToLimitSpeed number
---@field speedLimitValueToOvertakingCar number
---@field minimumSpeedLimitKmhToLimitToOvertakingCar number
---@field requireOvertakingCarToBeOnOvertakingLane boolean

---@type StorageTable_Yielding
local storageTable_Yielding = {
    handleYielding = StorageManager.options_Yielding_default[StorageManager.Options_Yielding.HandleYielding],
    detectCarBehind_meters = StorageManager.options_Yielding_default[StorageManager.Options_Yielding.DetectCarBehind_meters],
    rampSpeed_mps = StorageManager.options_Yielding_default[StorageManager.Options_Yielding.RampSpeed_mps],
    rampRelease_mps = StorageManager.options_Yielding_default[StorageManager.Options_Yielding.RampRelease_mps],
    distanceToOvertakingCarToLimitSpeed = StorageManager.options_Yielding_default[StorageManager.Options_Yielding.DistanceToOvertakingCarToLimitSpeed],
    speedLimitValueToOvertakingCar = StorageManager.options_Yielding_default[StorageManager.Options_Yielding.SpeedLimitValueToOvertakingCar],
    minimumSpeedLimitKmhToLimitToOvertakingCar = StorageManager.options_Yielding_default[StorageManager.Options_Yielding.MinimumSpeedLimitKmhToLimitToOvertakingCar],
    requireOvertakingCarToBeOnOvertakingLane = StorageManager.options_Yielding_default[StorageManager.Options_Yielding.RequireOvertakingCarToBeOnOvertakingLaneToYield],
}

---@class StorageTable_Global
---@field appRanFirstTime boolean

---@type StorageTable_Global
local storageTable_Global = {
    appRanFirstTime = false,
}

local sim = ac.getSim()
local raceSessionType = sim.raceSessionType
local fullTrackID = ac.getTrackFullID("_")

local perTrackPerModeStorageKey = getStorageKeyForTrackAndMode(nil, fullTrackID, raceSessionType)

local storage_PerTrackPerMode = ac.storage(storageTable, perTrackPerModeStorageKey)
local storage_Global = ac.storage(storageTable_Global, "global")
local storage_Debugging = ac.storage(storageTable_Debugging, getStorageKeyForTrackAndMode("debugging", fullTrackID, raceSessionType))
local storage_Yielding = ac.storage(storageTable_Yielding, getStorageKeyForTrackAndMode("yielding", fullTrackID, raceSessionType))

-- DISABLING ACCIDENTS FOR NOW SINCE IT'S STILL WIP
storage_PerTrackPerMode.handleAccidents = Constants.ENABLE_ACCIDENT_HANDLING_IN_APP -- got this setting here for now since accidents are still wip

---@return StorageTable storage_PerTrackPerMode
function StorageManager.getStorage()
    return storage_PerTrackPerMode
end

---@return StorageTable_Global storage_Global
function StorageManager.getStorage_Global()
    return storage_Global
end

---@return StorageTable_Debugging storage_Debugging
function StorageManager.getStorage_Debugging()
    return storage_Debugging
end

---@return StorageTable_Yielding storage_Yielding
function StorageManager.getStorage_Yielding()
    return storage_Yielding
end

function StorageManager.getPerTrackPerModeStorageKey()
    return perTrackPerModeStorageKey
end

return StorageManager