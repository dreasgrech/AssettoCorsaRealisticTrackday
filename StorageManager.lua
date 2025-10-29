local StorageManager = {}

---@enum StorageManager.Options
StorageManager.Options ={
    Enabled = 1,
    HandleSideChecking = 2,
    -- YieldSide = 3,
    OverrideAiAwareness = 3,
    DefaultAICaution = 4,
    DefaultAIAggression = 5,

    DefaultLateralOffset = 6,
    YieldingLateralOffset = 7,
    OvertakingLateralOffset = 8,
    -- MaxLateralOffset_normalized = 9,

    ClearAhead_meters = 9,

    HandleYielding = 10,
    DetectCarBehind_meters = 11,
    RampSpeed_mps = 12,
    RampRelease_mps = 13,

    HandleOvertaking = 14,
    DetectCarAhead_meters = 15,
    OvertakeRampSpeed_mps = 16,
    OvertakeRampRelease_mps = 17,

    CustomAIFlood_enabled = 18,
    CustomAIFlood_distanceBehindPlayerToCycle_meters = 19,
    CustomAIFlood_distanceAheadOfPlayerToCycle_meters = 20,

    HandleAccidents = 21,
    DistanceFromAccidentToSeeYellowFlag_meters = 22,
    DistanceToStartNavigatingAroundCarInAccident_meters = 23,

    DebugShowCarStateOverheadText = 24,
    DebugCarStateOverheadShowDistance = 25,
    DebugShowRaycastsWhileDrivingLaterally = 26,
    DebugDrawSideOfftrack = 27,
    DrawCarList = 28,
    DebugLogFastStateChanges = 29,
    DebugLogCarYielding = 30,
    DebugLogCarOvertaking = 31,
}

-- local RAMP_SPEEDS_MAX = 10

-- only used to build the actual tables that hold the runtime values
local optionsCollection_beforeDoD = {
    { name = StorageManager.Options.Enabled, default=false, min=nil, max=nil },
    { name = StorageManager.Options.HandleSideChecking, default=true, min=nil, max=nil },
    -- { name = StorageManager.Options.YieldSide, default=RaceTrackManager.TrackSide.RIGHT, min=nil, max=nil },
    { name = StorageManager.Options.OverrideAiAwareness, default=true, min=nil, max=nil },
    { name = StorageManager.Options.DefaultAICaution, default=3, min=3, max=16 },
    { name = StorageManager.Options.DefaultAIAggression, default=.5, min=0, max=0.95 }, -- The max is .95 because it's mentioned in the docs for physics.setAIAggression that the value from the launcher is multiplied by .95 so that's the max

    { name = StorageManager.Options.DefaultLateralOffset, default=0, min=-1, max=1 },
    { name = StorageManager.Options.YieldingLateralOffset, default=0.8, min=-1, max=1 },
    { name = StorageManager.Options.OvertakingLateralOffset, default=-0.8, min=-1, max=1 },
    -- { name = StorageManager.Options.MaxLateralOffset_normalized, default=0.8, min=0.1, max=1.0 },

    { name = StorageManager.Options.ClearAhead_meters, default=10.0, min=4.0, max=20.0 },

    { name = StorageManager.Options.HandleYielding, default=true, min=nil, max=nil },
    { name = StorageManager.Options.DetectCarBehind_meters, default=90, min=10, max=90 },
    { name = StorageManager.Options.RampSpeed_mps, default=0.25, min=0.1, max=1.0 },
    { name = StorageManager.Options.RampRelease_mps, default=0.25, min=0.1, max=1.0 },
    -- { name = StorageManager.Options.RampSpeed_mps, default=0.25, min=0.1, max=RAMP_SPEEDS_MAX },
    -- { name = StorageManager.Options.RampRelease_mps, default=0.1, min=0.1, max=RAMP_SPEEDS_MAX },

    { name = StorageManager.Options.HandleOvertaking, default=true, min=nil, max=nil },
    { name = StorageManager.Options.DetectCarAhead_meters, default=100, min=50, max=500 },
    { name = StorageManager.Options.OvertakeRampSpeed_mps, default=0.5, min=0.1, max=1.0 },
    { name = StorageManager.Options.OvertakeRampRelease_mps, default=0.5, min=0.1, max=1.0 },
    -- { name = StorageManager.Options.OvertakeRampSpeed_mps, default=0.5, min=0.1, max=RAMP_SPEEDS_MAX },
    -- { name = StorageManager.Options.OvertakeRampRelease_mps, default=0.5, min=0.1, max=RAMP_SPEEDS_MAX },

    { name = StorageManager.Options.CustomAIFlood_enabled, default=false, min=nil, max=nil },
    { name = StorageManager.Options.CustomAIFlood_distanceBehindPlayerToCycle_meters, default=200, min=50, max=500 },
    { name = StorageManager.Options.CustomAIFlood_distanceAheadOfPlayerToCycle_meters, default=100, min=20, max=300 },

    { name = StorageManager.Options.HandleAccidents, default=false, min=nil, max=nil },
    { name = StorageManager.Options.DistanceFromAccidentToSeeYellowFlag_meters, default=200.0, min=50.0, max=500.0 },
    { name = StorageManager.Options.DistanceToStartNavigatingAroundCarInAccident_meters, default=30.0, min=10.0, max=100.0 },

    { name = StorageManager.Options.DebugShowCarStateOverheadText, default=false, min=nil, max=nil },
    { name = StorageManager.Options.DebugCarStateOverheadShowDistance, default=125.0, min=10.0, max=500.0 },
    { name = StorageManager.Options.DebugShowRaycastsWhileDrivingLaterally, default=false, min=nil, max=nil },
    { name = StorageManager.Options.DebugDrawSideOfftrack, default=false, min=nil, max=nil },
    { name = StorageManager.Options.DrawCarList, default=true, min=nil, max=nil },
    { name = StorageManager.Options.DebugLogFastStateChanges, default=false, min=nil, max=nil },
    { name = StorageManager.Options.DebugLogCarYielding, default=false, min=nil, max=nil },
    { name = StorageManager.Options.DebugLogCarOvertaking, default=false, min=nil, max=nil },
}

StorageManager.options_default = {}
StorageManager.options_min = {}
StorageManager.options_max = {}

for i, option in ipairs(optionsCollection_beforeDoD) do
    local optionName = option.name
    StorageManager.options_default[optionName] = option.default
    StorageManager.options_min[optionName] = option.min
    StorageManager.options_max[optionName] = option.max
end

optionsCollection_beforeDoD = nil  -- free memory

---@class StorageTable
---@field enabled boolean
---@field handleSideChecking boolean
-- ---@field yieldSide RaceTrackManager.TrackSide
---@field overrideAiAwareness boolean
---@field defaultAICaution integer
---@field defaultAIAggression integer
---@field defaultLateralOffset number
---@field yieldingLateralOffset number
---@field overtakingLateralOffset number
-- ---@field maxLateralOffset_normalized number
---@field handleYielding boolean
---@field detectCarBehind_meters number
---@field rampSpeed_mps number
---@field rampRelease_mps number
---@field handleOvertaking boolean
---@field detectCarAhead_meters number
---@field clearAhead_meters number
---@field overtakeRampSpeed_mps number
---@field overtakeRampRelease_mps number
---@field customAIFlood_enabled boolean
---@field customAIFlood_distanceBehindPlayerToCycle_meters number
---@field customAIFlood_distanceAheadOfPlayerToCycle_meters number
---@field handleAccidents boolean
---@field distanceFromAccidentToSeeYellowFlag_meters number
---@field distanceToStartNavigatingAroundCarInAccident_meters number
---@field debugShowCarStateOverheadText boolean
---@field debugCarStateOverheadShowDistance number
---@field debugShowRaycastsWhileDrivingLaterally boolean
---@field debugDrawSideOfftrack boolean
---@field drawCarList boolean
---@field debugLogFastStateChanges boolean
---@field debugLogCarYielding boolean
---@field debugLogCarOvertaking boolean

---@type StorageTable
local storageTable = {
    enabled = StorageManager.options_default[StorageManager.Options.Enabled],
    handleSideChecking = StorageManager.options_default[StorageManager.Options.HandleSideChecking],
    -- yieldSide = StorageManager.options_default[StorageManager.Options.YieldSide],
    overrideAiAwareness = StorageManager.options_default[StorageManager.Options.OverrideAiAwareness],
    defaultAICaution = StorageManager.options_default[StorageManager.Options.DefaultAICaution],
    defaultAIAggression = StorageManager.options_default[StorageManager.Options.DefaultAIAggression],

    defaultLateralOffset = StorageManager.options_default[StorageManager.Options.DefaultLateralOffset],
    yieldingLateralOffset = StorageManager.options_default[StorageManager.Options.YieldingLateralOffset],
    overtakingLateralOffset = StorageManager.options_default[StorageManager.Options.OvertakingLateralOffset],
    -- maxLateralOffset_normalized = StorageManager.options_default[StorageManager.Options.MaxLateralOffset_normalized],

    handleYielding = StorageManager.options_default[StorageManager.Options.HandleYielding],
    detectCarBehind_meters = StorageManager.options_default[StorageManager.Options.DetectCarBehind_meters],
    rampSpeed_mps = StorageManager.options_default[StorageManager.Options.RampSpeed_mps],
    rampRelease_mps = StorageManager.options_default[StorageManager.Options.RampRelease_mps],

    handleOvertaking = StorageManager.options_default[StorageManager.Options.HandleOvertaking],
    detectCarAhead_meters = StorageManager.options_default[StorageManager.Options.DetectCarAhead_meters],
    clearAhead_meters = StorageManager.options_default[StorageManager.Options.ClearAhead_meters],
    overtakeRampSpeed_mps = StorageManager.options_default[StorageManager.Options.OvertakeRampSpeed_mps],
    overtakeRampRelease_mps = StorageManager.options_default[StorageManager.Options.OvertakeRampRelease_mps],

    customAIFlood_enabled = StorageManager.options_default[StorageManager.Options.CustomAIFlood_enabled],
    customAIFlood_distanceBehindPlayerToCycle_meters = StorageManager.options_default[StorageManager.Options.CustomAIFlood_distanceBehindPlayerToCycle_meters],
    customAIFlood_distanceAheadOfPlayerToCycle_meters = StorageManager.options_default[StorageManager.Options.CustomAIFlood_distanceAheadOfPlayerToCycle_meters],

    handleAccidents = StorageManager.options_default[StorageManager.Options.HandleAccidents],
    distanceFromAccidentToSeeYellowFlag_meters = StorageManager.options_default[StorageManager.Options.DistanceFromAccidentToSeeYellowFlag_meters],
    distanceToStartNavigatingAroundCarInAccident_meters = StorageManager.options_default[StorageManager.Options.DistanceToStartNavigatingAroundCarInAccident_meters],

    debugShowCarStateOverheadText = StorageManager.options_default[StorageManager.Options.DebugShowCarStateOverheadText],
    debugCarStateOverheadShowDistance = StorageManager.options_default[StorageManager.Options.DebugCarStateOverheadShowDistance],
    debugShowRaycastsWhileDrivingLaterally = StorageManager.options_default[StorageManager.Options.DebugShowRaycastsWhileDrivingLaterally],
    debugDrawSideOfftrack = StorageManager.options_default[StorageManager.Options.DebugDrawSideOfftrack],
    drawCarList = StorageManager.options_default[StorageManager.Options.DrawCarList],
    debugLogFastStateChanges = StorageManager.options_default[StorageManager.Options.DebugLogFastStateChanges],
    debugLogCarYielding = StorageManager.options_default[StorageManager.Options.DebugLogCarYielding],
    debugLogCarOvertaking = StorageManager.options_default[StorageManager.Options.DebugLogCarOvertaking],
}

local sim = ac.getSim()
local raceSessionType = sim.raceSessionType

local fullTrackID = ac.getTrackFullID("_")

local perTrackPerModeStorageKey = string.format("%s_%s", fullTrackID, raceSessionType)
local perTrackPerModeStorage = ac.storage(storageTable, perTrackPerModeStorageKey)

---@class GlobalStorageTable
---@field appRanFirstTime boolean

---@type GlobalStorageTable

local globalStorageTable = {
    appRanFirstTime = false,
}

local globalStorage = ac.storage(globalStorageTable, "global")

---@return StorageTable storage
function StorageManager.getStorage()
    return perTrackPerModeStorage
end

---@return GlobalStorageTable globalStorage
function StorageManager.getGlobalStorage()
    return globalStorage
end

function StorageManager.getStorageKey()
    return perTrackPerModeStorageKey
end

return StorageManager