local StorageManager = {}

---@enum StorageManager.Options
StorageManager.Options ={
    Enabled = 1,
    HandleSideChecking = 2,
    YieldSide = 3,
    OverrideAiAwareness = 4,
    DefaultAICaution = 5,
    MaxLateralOffset_normalized = 6,
    ClearAhead_meters = 7,

    DetectCarBehind_meters = 8,
    RampSpeed_mps = 9,
    RampRelease_mps = 10,

    HandleOvertaking = 11,
    DetectCarAhead_meters = 12,
    OvertakeRampSpeed_mps = 13,
    OvertakeRampRelease_mps = 14,

    CustomAIFlood_enabled = 15,
    CustomAIFlood_distanceBehindPlayerToCycle_meters = 16,
    CustomAIFlood_distanceAheadOfPlayerToCycle_meters = 17,

    HandleAccidents = 18,
    DistanceFromAccidentToSeeYellowFlag_meters = 19,
    DistanceToStartNavigatingAroundCarInAccident_meters = 20,

    DebugDraw = 21,
    DebugDrawSideOfftrack = 22,
    DrawCarList = 23,
    DebugLogFastStateChanges = 24,
}

-- only used to build the actual tables that hold the runtime values
local optionsCollection_beforeDoD = {
    { name = StorageManager.Options.Enabled, default=true, min=nil, max=nil },
    { name = StorageManager.Options.HandleSideChecking, default=true, min=nil, max=nil },
    { name = StorageManager.Options.YieldSide, default=RaceTrackManager.TrackSide.RIGHT, min=nil, max=nil },
    { name = StorageManager.Options.OverrideAiAwareness, default=false, min=nil, max=nil },
    { name = StorageManager.Options.DefaultAICaution, default=3, min=3, max=16 },
    { name = StorageManager.Options.MaxLateralOffset_normalized, default=0.8, min=0.1, max=1.0 },
    { name = StorageManager.Options.ClearAhead_meters, default=10.0, min=4.0, max=20.0 },

    { name = StorageManager.Options.DetectCarBehind_meters, default=90, min=10, max=90 },
    { name = StorageManager.Options.RampSpeed_mps, default=0.25, min=0.1, max=2.0 },
    { name = StorageManager.Options.RampRelease_mps, default=0.1, min=0.1, max=2.0 },

    { name = StorageManager.Options.HandleOvertaking, default=true, min=nil, max=nil },
    { name = StorageManager.Options.DetectCarAhead_meters, default=100, min=50, max=500 },
    { name = StorageManager.Options.OvertakeRampSpeed_mps, default=0.5, min=0.1, max=2.0 },
    { name = StorageManager.Options.OvertakeRampRelease_mps, default=0.5, min=0.1, max=2.0 },

    { name = StorageManager.Options.CustomAIFlood_enabled, default=false, min=nil, max=nil },
    { name = StorageManager.Options.CustomAIFlood_distanceBehindPlayerToCycle_meters, default=200, min=50, max=500 },
    { name = StorageManager.Options.CustomAIFlood_distanceAheadOfPlayerToCycle_meters, default=100, min=20, max=300 },

    { name = StorageManager.Options.HandleAccidents, default=false, min=nil, max=nil },
    { name = StorageManager.Options.DistanceFromAccidentToSeeYellowFlag_meters, default=200.0, min=50.0, max=500.0 },
    { name = StorageManager.Options.DistanceToStartNavigatingAroundCarInAccident_meters, default=30.0, min=10.0, max=100.0 },

    { name = StorageManager.Options.DebugDraw, default=false, min=nil, max=nil },
    { name = StorageManager.Options.DebugDrawSideOfftrack, default=false, min=nil, max=nil },
    { name = StorageManager.Options.DrawCarList, default=true, min=nil, max=nil },
    { name = StorageManager.Options.DebugLogFastStateChanges, default=false, min=nil, max=nil },
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
---@field yieldSide RaceTrackManager.TrackSide
---@field overrideAiAwareness boolean
---@field defaultAICaution integer
---@field maxLateralOffset_normalized number
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
---@field debugDraw boolean
---@field debugDrawSideOfftrack boolean
---@field drawCarList boolean
---@field debugLogFastStateChanges boolean

---@type StorageTable
local storageTable = {
    enabled = StorageManager.options_default[StorageManager.Options.Enabled],
    handleSideChecking = StorageManager.options_default[StorageManager.Options.HandleSideChecking],
    yieldSide = StorageManager.options_default[StorageManager.Options.YieldSide],
    overrideAiAwareness = StorageManager.options_default[StorageManager.Options.OverrideAiAwareness],
    defaultAICaution = StorageManager.options_default[StorageManager.Options.DefaultAICaution],
    maxLateralOffset_normalized = StorageManager.options_default[StorageManager.Options.MaxLateralOffset_normalized],

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

    debugDraw = StorageManager.options_default[StorageManager.Options.DebugDraw],
    debugDrawSideOfftrack = StorageManager.options_default[StorageManager.Options.DebugDrawSideOfftrack],
    drawCarList = StorageManager.options_default[StorageManager.Options.DrawCarList],
    debugLogFastStateChanges = StorageManager.options_default[StorageManager.Options.DebugLogFastStateChanges],
}

local storage = ac.storage(storageTable)

---comment
---@return StorageTable storage
function StorageManager.getStorage()
    return storage
end

return StorageManager