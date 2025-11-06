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

    OverrideAiAwareness = 2,


    DefaultAICaution = 3,
    AICaution_OvertakingWithNoObstacleInFront = 4,
    AICaution_OvertakingWithObstacleInFront = 5,
    AICaution_OvertakingWhileInCorner = 6,
    AICaution_Yielding = 7,

    DefaultAIAggression = 8,
    OverrideOriginalAIAggression_DrivingNormally = 9,
    OverrideOriginalAIAggression_Overtaking = 10,
    OverrideOriginalAIAggression_Yielding = 11,
    AIAggression_OvertakingWithNoObstacleInFront = 12,
    AIAggression_OvertakingWithObstacleInFront = 13,
    AIAggression_WhileInCorner = 14,
    AIAggression_Yielding = 15,

    DefaultAIDifficultyLevel = 16,
    OverrideOriginalAIDifficultyLevel_DrivingNormally = 17,
    OverrideOriginalAIDifficultyLevel_Overtaking = 18,
    OverrideOriginalAIDifficultyLevel_Yielding = 19,
    AIDifficultyLevel_OvertakingWithNoObstacleInFront = 20,
    AIDifficultyLevel_OvertakingWithObstacleInFront = 21,
    AIDifficultyLevel_WhileInCorner = 22,
    AIDifficultyLevel_Yielding = 23,

    GlobalTopSpeedLimitKmh = 24,
    DeferTimeAfterSessionStart = 25,

    DefaultLateralOffset = 26,
    YieldingLateralOffset = 27,
    OvertakingLateralOffset = 28,

    ClearAhead_meters = 29,

    CustomAIFlood_enabled = 30,
    CustomAIFlood_distanceBehindPlayerToCycle_meters = 31,
    CustomAIFlood_distanceAheadOfPlayerToCycle_meters = 32,

    HandleAccidents = 33,
    DistanceFromAccidentToSeeYellowFlag_meters = 34,
    DistanceToStartNavigatingAroundCarInAccident_meters = 35,
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
    HandleSideCheckingWhenYielding = 2,
    DetectCarBehind_meters = 3,
    RampSpeed_mps = 4,
    RampRelease_mps = 5,
    DistanceToOvertakingCarToLimitSpeed = 6,
    SpeedLimitValueToOvertakingCar = 7,
    MinimumSpeedLimitKmhToLimitToOvertakingCar = 8, -- TODO: rename to MinimumTopSpeedLimitKmhToLimitToOvertakingCar
    ThrottlePedalLimitWhenYieldingToOvertakingCar = 9,
    RequireOvertakingCarToBeOnOvertakingLaneToYield = 10,
    UseIndicatorLightsWhenEasingInYield = 11,
    UseIndicatorLightsWhenEasingOutYield = 12,
    UseIndicatorLightsWhenDrivingOnYieldingLane = 13,
}

---@enum StorageManager.Options_Overtaking
StorageManager.Options_Overtaking = {
    HandleOvertaking = 1,
    HandleSideCheckingWhenOvertaking = 2,
    DetectCarAhead_meters = 3,
    OvertakeRampSpeed_mps = 4,
    OvertakeRampRelease_mps = 5,
    RequireYieldingCarToBeOnYieldingLaneToOvertake = 6,
    UseIndicatorLightsWhenEasingInOvertaking = 7,
    UseIndicatorLightsWhenEasingOutOvertaking = 8,
    UseIndicatorLightsWhenDrivingOnOvertakingLane = 9,
}

local optionsCollection_Debugging_beforeDoD = {
    { name = StorageManager.Options_Debugging.DebugShowCarStateOverheadText, default=false, min=nil, max=nil },
    { name = StorageManager.Options_Debugging.DebugCarGizmosDrawistance, default=125.0, min=10.0, max=500.0 },
    { name = StorageManager.Options_Debugging.DebugShowRaycastsWhileDrivingLaterally, default=false, min=nil, max=nil },
    { name = StorageManager.Options_Debugging.DebugDrawSideOfftrack, default=false, min=nil, max=nil },
    { name = StorageManager.Options_Debugging.DrawCarList, default=false, min=nil, max=nil },
    { name = StorageManager.Options_Debugging.DebugLogFastStateChanges, default=false, min=nil, max=nil },
    { name = StorageManager.Options_Debugging.DebugLogCarYielding, default=false, min=nil, max=nil },
    { name = StorageManager.Options_Debugging.DebugLogCarOvertaking, default=false, min=nil, max=nil },
}

local optionsCollection_Yielding_beforeDoD = {
    { name = StorageManager.Options_Yielding.HandleYielding, default=true, min=nil, max=nil },
    { name = StorageManager.Options_Yielding.HandleSideCheckingWhenYielding, default=true, min=nil, max=nil },
    { name = StorageManager.Options_Yielding.DetectCarBehind_meters, default=50, min=5, max=200 },
    { name = StorageManager.Options_Yielding.RampSpeed_mps, default=0.25, min=0.1, max=1.0 },
    { name = StorageManager.Options_Yielding.RampRelease_mps, default=0.25, min=0.1, max=1.0 },
    { name = StorageManager.Options_Yielding.DistanceToOvertakingCarToLimitSpeed, default=10.0, min=1.0, max=100.0 },
    { name = StorageManager.Options_Yielding.SpeedLimitValueToOvertakingCar, default=0.7, min=0.0, max=1.0 },
    { name = StorageManager.Options_Yielding.MinimumSpeedLimitKmhToLimitToOvertakingCar, default=60.0, min=0.0, max=300.0 },
    { name = StorageManager.Options_Yielding.ThrottlePedalLimitWhenYieldingToOvertakingCar, default=0.9, min=0.0, max=1.0 },
    { name = StorageManager.Options_Yielding.RequireOvertakingCarToBeOnOvertakingLaneToYield, default=true, min=nil, max=nil },
    { name = StorageManager.Options_Yielding.UseIndicatorLightsWhenEasingInYield, default=true, min=nil, max=nil },
    { name = StorageManager.Options_Yielding.UseIndicatorLightsWhenEasingOutYield, default=true, min=nil, max=nil },
    { name = StorageManager.Options_Yielding.UseIndicatorLightsWhenDrivingOnYieldingLane, default=true, min=nil, max=nil },
    -- { name = StorageManager.Options_Yielding.RampSpeed_mps, default=0.25, min=0.1, max=RAMP_SPEEDS_MAX },
    -- { name = StorageManager.Options_Yielding.RampRelease_mps, default=0.1, min=0.1, max=RAMP_SPEEDS_MAX },
}

local optionsCollection_Overtaking_beforeDoD = {
    { name = StorageManager.Options_Overtaking.HandleOvertaking, default=true, min=nil, max=nil },
    { name = StorageManager.Options_Overtaking.HandleSideCheckingWhenOvertaking, default=true, min=nil, max=nil },
    { name = StorageManager.Options_Overtaking.DetectCarAhead_meters, default=50, min=5, max=200 },
    { name = StorageManager.Options_Overtaking.OvertakeRampSpeed_mps, default=0.5, min=0.1, max=1.0 },
    { name = StorageManager.Options_Overtaking.OvertakeRampRelease_mps, default=0.5, min=0.1, max=1.0 },
    { name = StorageManager.Options_Overtaking.RequireYieldingCarToBeOnYieldingLaneToOvertake, default=true, min=nil, max=nil },
    { name = StorageManager.Options_Overtaking.UseIndicatorLightsWhenEasingInOvertaking, default=true, min=nil, max=nil },
    { name = StorageManager.Options_Overtaking.UseIndicatorLightsWhenEasingOutOvertaking, default=true, min=nil, max=nil },
    { name = StorageManager.Options_Overtaking.UseIndicatorLightsWhenDrivingOnOvertakingLane, default=true, min=nil, max=nil },
    -- { name = StorageManager.Options_Overtaking.OvertakeRampSpeed_mps, default=0.5, min=0.1, max=RAMP_SPEEDS_MAX },
    -- { name = StorageManager.Options_Overtaking.OvertakeRampRelease_mps, default=0.5, min=0.1, max=RAMP_SPEEDS_MAX },
}

-- local RAMP_SPEEDS_MAX = 10

-- local MIN_AI_CAUTION_VALUE = 3
local MIN_AI_CAUTION_VALUE = 0
local MAX_AI_CAUTION_VALUE = 16 -- as per physics.setAICaution function doc

local MIN_AI_AGGRESSION_VALUE = 0
-- local MAX_AI_AGGRESSION_VALUE = 0.95
local MAX_AI_AGGRESSION_VALUE = 1.0 -- as per physics.setAIAggression function doc

local MIN_AI_DIFFICULTY_LEVEL = 0
local MAX_AI_DIFFICULTY_LEVEL = 2 -- as per physics.setAILevel function doc

-- only used to build the actual tables that hold the runtime values
local optionsCollection_beforeDoD = {
    { name = StorageManager.Options.Enabled, default=false, min=nil, max=nil },
    -- { name = StorageManager.Options.HandleSideCheckingWhenYielding, default=true, min=nil, max=nil },
    -- { name = StorageManager.Options.HandleSideCheckingWhenOvertaking, default=true, min=nil, max=nil },
    { name = StorageManager.Options.OverrideAiAwareness, default=true, min=nil, max=nil },

    { name = StorageManager.Options.DefaultAICaution, default=3, min=MIN_AI_CAUTION_VALUE, max=MAX_AI_CAUTION_VALUE },
    { name = StorageManager.Options.AICaution_OvertakingWithNoObstacleInFront, default=0, min=MIN_AI_CAUTION_VALUE, max=MAX_AI_CAUTION_VALUE },
    { name = StorageManager.Options.AICaution_OvertakingWithObstacleInFront, default=1, min=MIN_AI_CAUTION_VALUE, max=MAX_AI_CAUTION_VALUE },
    { name = StorageManager.Options.AICaution_OvertakingWhileInCorner, default=2, min=MIN_AI_CAUTION_VALUE, max=MAX_AI_CAUTION_VALUE },
    { name = StorageManager.Options.AICaution_Yielding, default=4, min=MIN_AI_CAUTION_VALUE, max=MAX_AI_CAUTION_VALUE },

    { name = StorageManager.Options.OverrideOriginalAIAggression_DrivingNormally, default=true, min=nil, max=nil },
    { name = StorageManager.Options.OverrideOriginalAIAggression_Overtaking, default=true, min=nil, max=nil },
    { name = StorageManager.Options.OverrideOriginalAIAggression_Yielding, default=true, min=nil, max=nil },
    { name = StorageManager.Options.DefaultAIAggression, default=.5, min=MIN_AI_AGGRESSION_VALUE, max=MAX_AI_AGGRESSION_VALUE }, -- The max is .95 because it's mentioned in the docs for physics.setAIAggression that the value from the launcher is multiplied by .95 so that's the max
    { name = StorageManager.Options.AIAggression_OvertakingWithNoObstacleInFront, default=1, min=MIN_AI_AGGRESSION_VALUE, max=MAX_AI_AGGRESSION_VALUE },
    { name = StorageManager.Options.AIAggression_OvertakingWithObstacleInFront, default=.95, min=MIN_AI_AGGRESSION_VALUE, max=MAX_AI_AGGRESSION_VALUE },
    { name = StorageManager.Options.AIAggression_WhileInCorner, default=.95, min=MIN_AI_AGGRESSION_VALUE, max=MAX_AI_AGGRESSION_VALUE },
    { name = StorageManager.Options.AIAggression_Yielding, default=.5, min=MIN_AI_AGGRESSION_VALUE, max=MAX_AI_AGGRESSION_VALUE },

    { name = StorageManager.Options.DefaultAIDifficultyLevel, default=.8, min=MIN_AI_DIFFICULTY_LEVEL, max=MAX_AI_DIFFICULTY_LEVEL },
    { name = StorageManager.Options.OverrideOriginalAIDifficultyLevel_DrivingNormally, default=true, min=nil, max=nil },
    { name = StorageManager.Options.OverrideOriginalAIDifficultyLevel_Overtaking, default=true, min=nil, max=nil },
    { name = StorageManager.Options.OverrideOriginalAIDifficultyLevel_Yielding, default=true, min=nil, max=nil },
    { name = StorageManager.Options.AIDifficultyLevel_OvertakingWithNoObstacleInFront, default=2, min=MIN_AI_DIFFICULTY_LEVEL, max=MAX_AI_DIFFICULTY_LEVEL },
    { name = StorageManager.Options.AIDifficultyLevel_OvertakingWithObstacleInFront, default=1.5, min=MIN_AI_DIFFICULTY_LEVEL, max=MAX_AI_DIFFICULTY_LEVEL },
    { name = StorageManager.Options.AIDifficultyLevel_WhileInCorner, default=.7, min=MIN_AI_DIFFICULTY_LEVEL, max=MAX_AI_DIFFICULTY_LEVEL },
    { name = StorageManager.Options.AIDifficultyLevel_Yielding, default=.6, min=MIN_AI_DIFFICULTY_LEVEL, max=MAX_AI_DIFFICULTY_LEVEL },

    { name = StorageManager.Options.GlobalTopSpeedLimitKmh, default=0, min=0, max=500 },
    { name = StorageManager.Options.DeferTimeAfterSessionStart, default=0, min=0, max=300 },

    { name = StorageManager.Options.DefaultLateralOffset, default=0, min=-1, max=1 },
    { name = StorageManager.Options.YieldingLateralOffset, default=0.8, min=-1, max=1 },
    { name = StorageManager.Options.OvertakingLateralOffset, default=-0.8, min=-1, max=1 },

    { name = StorageManager.Options.ClearAhead_meters, default=10.0, min=4.0, max=20.0 },

    { name = StorageManager.Options.CustomAIFlood_enabled, default=false, min=nil, max=nil },
    { name = StorageManager.Options.CustomAIFlood_distanceBehindPlayerToCycle_meters, default=200, min=50, max=500 },
    { name = StorageManager.Options.CustomAIFlood_distanceAheadOfPlayerToCycle_meters, default=100, min=20, max=300 },

    { name = StorageManager.Options.HandleAccidents, default=false, min=nil, max=nil },
    { name = StorageManager.Options.DistanceFromAccidentToSeeYellowFlag_meters, default=200.0, min=50.0, max=500.0 },
    { name = StorageManager.Options.DistanceToStartNavigatingAroundCarInAccident_meters, default=30.0, min=10.0, max=100.0 },
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

StorageManager.options_Overtaking_default,
StorageManager.options_Overtaking_min,
StorageManager.options_Overtaking_max = fillInDoDTables(
    optionsCollection_Overtaking_beforeDoD,
    StorageManager.options_Overtaking_default,
    StorageManager.options_Overtaking_min,
    StorageManager.options_Overtaking_max
)
optionsCollection_Overtaking_beforeDoD = nil  -- free memory


---@class StorageTable
---@field enabled boolean
-- ---@field handleSideCheckingWhenYielding boolean
-- ---@field handleSideCheckingWhenOvertaking boolean
-- ---@field yieldSide RaceTrackManager.TrackSide
---@field overrideAiAwareness boolean
---@field defaultAICaution integer
---@field AICaution_OvertakingWithNoObstacleInFront integer
---@field AICaution_OvertakingWithObstacleInFront integer
---@field AICaution_OvertakingWhileInCorner integer
---@field AICaution_Yielding integer
---@field overrideOriginalAIAggression_drivingNormally boolean
---@field overrideOriginalAIAggression_overtaking boolean
---@field overrideOriginalAIAggression_yielding boolean
---@field defaultAIAggression integer
---@field AIAggression_OvertakingWithNoObstacleInFront number
---@field AIAggression_OvertakingWithObstacleInFront number
---@field AIAggression_WhileInCorner number
---@field AIAggression_Yielding number
---@field defaultAIDifficultyLevel number
---@field overrideOriginalAIDifficultyLevel_drivingNormally boolean
---@field overrideOriginalAIDifficultyLevel_overtaking boolean
---@field overrideOriginalAIDifficultyLevel_yielding boolean
---@field AIDifficultyLevel_OvertakingWithNoObstacleInFront number
---@field AIDifficultyLevel_OvertakingWithObstacleInFront number
---@field AIDifficultyLevel_WhileInCorner number
---@field AIDifficultyLevel_Yielding number
---@field globalTopSpeedLimitKmh number
---@field deferTimeAfterSessionStart number
---@field defaultLateralOffset number
---@field yieldingLateralOffset number
---@field overtakingLateralOffset number
---@field clearAhead_meters number
---@field customAIFlood_enabled boolean
---@field customAIFlood_distanceBehindPlayerToCycle_meters number
---@field customAIFlood_distanceAheadOfPlayerToCycle_meters number
---@field handleAccidents boolean
---@field distanceFromAccidentToSeeYellowFlag_meters number
---@field distanceToStartNavigatingAroundCarInAccident_meters number

---@type StorageTable
local storageTable = {
    enabled = StorageManager.options_default[StorageManager.Options.Enabled],
    -- handleSideCheckingWhenYielding = StorageManager.options_default[StorageManager.Options.HandleSideCheckingWhenYielding],
    -- handleSideCheckingWhenOvertaking = StorageManager.options_default[StorageManager.Options.HandleSideCheckingWhenOvertaking],
    overrideAiAwareness = StorageManager.options_default[StorageManager.Options.OverrideAiAwareness],

    defaultAICaution = StorageManager.options_default[StorageManager.Options.DefaultAICaution],
    AICaution_OvertakingWithNoObstacleInFront = StorageManager.options_default[StorageManager.Options.AICaution_OvertakingWithNoObstacleInFront],
    AICaution_OvertakingWithObstacleInFront = StorageManager.options_default[StorageManager.Options.AICaution_OvertakingWithObstacleInFront],
    AICaution_OvertakingWhileInCorner = StorageManager.options_default[StorageManager.Options.AICaution_OvertakingWhileInCorner],
    AICaution_Yielding = StorageManager.options_default[StorageManager.Options.AICaution_Yielding],

    overrideOriginalAIAggression_drivingNormally = StorageManager.options_default[StorageManager.Options.OverrideOriginalAIAggression_DrivingNormally],
    overrideOriginalAIAggression_overtaking = StorageManager.options_default[StorageManager.Options.OverrideOriginalAIAggression_Overtaking],
    overrideOriginalAIAggression_yielding = StorageManager.options_default[StorageManager.Options.OverrideOriginalAIAggression_Yielding],
    defaultAIAggression = StorageManager.options_default[StorageManager.Options.DefaultAIAggression],
    AIAggression_OvertakingWithNoObstacleInFront = StorageManager.options_default[StorageManager.Options.AIAggression_OvertakingWithNoObstacleInFront],
    AIAggression_OvertakingWithObstacleInFront = StorageManager.options_default[StorageManager.Options.AIAggression_OvertakingWithObstacleInFront],
    AIAggression_WhileInCorner = StorageManager.options_default[StorageManager.Options.AIAggression_WhileInCorner],
    AIAggression_Yielding = StorageManager.options_default[StorageManager.Options.AIAggression_Yielding],

    defaultAIDifficultyLevel = StorageManager.options_default[StorageManager.Options.DefaultAIDifficultyLevel],
    overrideOriginalAIDifficultyLevel_drivingNormally = StorageManager.options_default[StorageManager.Options.OverrideOriginalAIDifficultyLevel_DrivingNormally],
    overrideOriginalAIDifficultyLevel_overtaking = StorageManager.options_default[StorageManager.Options.OverrideOriginalAIDifficultyLevel_Overtaking],
    overrideOriginalAIDifficultyLevel_yielding = StorageManager.options_default[StorageManager.Options.OverrideOriginalAIDifficultyLevel_Yielding],
    AIDifficultyLevel_OvertakingWithNoObstacleInFront = StorageManager.options_default[StorageManager.Options.AIDifficultyLevel_OvertakingWithNoObstacleInFront],
    AIDifficultyLevel_OvertakingWithObstacleInFront = StorageManager.options_default[StorageManager.Options.AIDifficultyLevel_OvertakingWithObstacleInFront],
    AIDifficultyLevel_WhileInCorner = StorageManager.options_default[StorageManager.Options.AIDifficultyLevel_WhileInCorner],
    AIDifficultyLevel_Yielding = StorageManager.options_default[StorageManager.Options.AIDifficultyLevel_Yielding],

    globalTopSpeedLimitKmh = StorageManager.options_default[StorageManager.Options.GlobalTopSpeedLimitKmh],
    deferTimeAfterSessionStart = StorageManager.options_default[StorageManager.Options.DeferTimeAfterSessionStart],

    defaultLateralOffset = StorageManager.options_default[StorageManager.Options.DefaultLateralOffset],
    yieldingLateralOffset = StorageManager.options_default[StorageManager.Options.YieldingLateralOffset],
    overtakingLateralOffset = StorageManager.options_default[StorageManager.Options.OvertakingLateralOffset],

    clearAhead_meters = StorageManager.options_default[StorageManager.Options.ClearAhead_meters],

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
---@field handleSideCheckingWhenYielding boolean
---@field detectCarBehind_meters number
---@field rampSpeed_mps number
---@field rampRelease_mps number
---@field distanceToOvertakingCarToLimitSpeed number
---@field speedLimitValueToOvertakingCar number
---@field minimumSpeedLimitKmhToLimitToOvertakingCar number
---@field throttlePedalLimitWhenYieldingToOvertakingCar number @0.0 to 1.0 value representing throttle pedal limit when yielding to overtaking cars
---@field requireOvertakingCarToBeOnOvertakingLane boolean
---@field UseIndicatorLightsWhenEasingInYield boolean
---@field UseIndicatorLightsWhenEasingOutYield boolean
---@field UseIndicatorLightsWhenDrivingOnYieldingLane boolean

---@type StorageTable_Yielding
local storageTable_Yielding = {
    handleYielding = StorageManager.options_Yielding_default[StorageManager.Options_Yielding.HandleYielding],
    handleSideCheckingWhenYielding = StorageManager.options_Yielding_default[StorageManager.Options_Yielding.HandleSideCheckingWhenYielding],
    detectCarBehind_meters = StorageManager.options_Yielding_default[StorageManager.Options_Yielding.DetectCarBehind_meters],
    rampSpeed_mps = StorageManager.options_Yielding_default[StorageManager.Options_Yielding.RampSpeed_mps],
    rampRelease_mps = StorageManager.options_Yielding_default[StorageManager.Options_Yielding.RampRelease_mps],
    distanceToOvertakingCarToLimitSpeed = StorageManager.options_Yielding_default[StorageManager.Options_Yielding.DistanceToOvertakingCarToLimitSpeed],
    speedLimitValueToOvertakingCar = StorageManager.options_Yielding_default[StorageManager.Options_Yielding.SpeedLimitValueToOvertakingCar],
    minimumSpeedLimitKmhToLimitToOvertakingCar = StorageManager.options_Yielding_default[StorageManager.Options_Yielding.MinimumSpeedLimitKmhToLimitToOvertakingCar],
    throttlePedalLimitWhenYieldingToOvertakingCar = StorageManager.options_Yielding_default[StorageManager.Options_Yielding.ThrottlePedalLimitWhenYieldingToOvertakingCar],
    requireOvertakingCarToBeOnOvertakingLane = StorageManager.options_Yielding_default[StorageManager.Options_Yielding.RequireOvertakingCarToBeOnOvertakingLaneToYield],
    UseIndicatorLightsWhenEasingInYield = StorageManager.options_Yielding_default[StorageManager.Options_Yielding.UseIndicatorLightsWhenEasingInYield],
    UseIndicatorLightsWhenEasingOutYield = StorageManager.options_Yielding_default[StorageManager.Options_Yielding.UseIndicatorLightsWhenEasingOutYield],
    UseIndicatorLightsWhenDrivingOnYieldingLane = StorageManager.options_Yielding_default[StorageManager.Options_Yielding.UseIndicatorLightsWhenDrivingOnYieldingLane],
}

---@class StorageTable_Overtaking
---@field handleOvertaking boolean
---@field handleSideCheckingWhenOvertaking boolean
---@field detectCarAhead_meters number
---@field overtakeRampSpeed_mps number
---@field overtakeRampRelease_mps number
---@field requireYieldingCarToBeOnYieldingLane boolean
---@field UseIndicatorLightsWhenEasingInOvertaking boolean
---@field UseIndicatorLightsWhenEasingOutOvertaking boolean
---@field UseIndicatorLightsWhenDrivingOnOvertakingLane boolean

---@type StorageTable_Overtaking
local storageTable_Overtaking = {
    handleOvertaking = StorageManager.options_Overtaking_default[StorageManager.Options_Overtaking.HandleOvertaking],
    handleSideCheckingWhenOvertaking = StorageManager.options_Overtaking_default[StorageManager.Options_Overtaking.HandleSideCheckingWhenOvertaking],
    detectCarAhead_meters = StorageManager.options_Overtaking_default[StorageManager.Options_Overtaking.DetectCarAhead_meters],
    overtakeRampSpeed_mps = StorageManager.options_Overtaking_default[StorageManager.Options_Overtaking.OvertakeRampSpeed_mps],
    overtakeRampRelease_mps = StorageManager.options_Overtaking_default[StorageManager.Options_Overtaking.OvertakeRampRelease_mps],
    requireYieldingCarToBeOnYieldingLane = StorageManager.options_Overtaking_default[StorageManager.Options_Overtaking.RequireYieldingCarToBeOnYieldingLaneToOvertake],
    UseIndicatorLightsWhenEasingInOvertaking = StorageManager.options_Overtaking_default[StorageManager.Options_Overtaking.UseIndicatorLightsWhenEasingInOvertaking],
    UseIndicatorLightsWhenEasingOutOvertaking = StorageManager.options_Overtaking_default[StorageManager.Options_Overtaking.UseIndicatorLightsWhenEasingOutOvertaking],
    UseIndicatorLightsWhenDrivingOnOvertakingLane = StorageManager.options_Overtaking_default[StorageManager.Options_Overtaking.UseIndicatorLightsWhenDrivingOnOvertakingLane],
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
local storage_Overtaking = ac.storage(storageTable_Overtaking, getStorageKeyForTrackAndMode("overtaking", fullTrackID, raceSessionType))

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

---@return StorageTable_Overtaking storage_Overtaking
function StorageManager.getStorage_Overtaking()
    return storage_Overtaking
end

function StorageManager.getPerTrackPerModeStorageKey()
    return perTrackPerModeStorageKey
end

return StorageManager