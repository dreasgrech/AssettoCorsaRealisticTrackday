local StorageManager = {}

---@class StorageTable
---@field enabled boolean
---@field debugDraw boolean
---@field drawCarList boolean
---@field handleSideChecking boolean
---@field yieldSide RaceTrackManager.TrackSide
---@field overrideAiAwareness boolean
---@field handleAccidents boolean
---@field handleOvertaking boolean
---@field detectCarBehind_meters number
---@field maxLateralOffset_normalized number
---@field rampSpeed_mps number
---@field rampRelease_mps number
---@field overtakeRampSpeed_mps number
---@field overtakeRampRelease_mps number
---@field clearAhead_meters number
---@field defaultAICaution integer
---@field distanceFromAccidentToSeeYellowFlag_meters number
---@field distanceToStartNavigatingAroundCarInAccident_meters number
---@field customAIFlood_enabled boolean
---@field customAIFlood_distanceBehindPlayerToCycle_meters number
---@field customAIFlood_distanceAheadOfPlayerToCycle_meters number

---@type StorageTable
local storageTable = {
    enabled = true,
    handleSideChecking = true,
    yieldSide = RaceTrackManager.TrackSide.RIGHT,
    overrideAiAwareness = false,
    -- minSpeedDelta_kmh = 0.0,
    defaultAICaution = 3,
    maxLateralOffset_normalized = 0.8,

    detectCarBehind_meters = 70,
    rampSpeed_mps = 0.5,
    rampRelease_mps = 0.3,

    handleOvertaking = true,
    clearAhead_meters = 6.0,
    overtakeRampSpeed_mps = 0.7,
    overtakeRampRelease_mps = 0.4,

    customAIFlood_enabled = false,
    customAIFlood_distanceBehindPlayerToCycle_meters = 200,
    customAIFlood_distanceAheadOfPlayerToCycle_meters = 100,

    handleAccidents = false,
    distanceFromAccidentToSeeYellowFlag_meters = 200.0,
    distanceToStartNavigatingAroundCarInAccident_meters = 30.0,

    debugDraw = false,
    drawCarList = true,
}

local storage = ac.storage(storageTable)

---comment
---@return StorageTable storage
function StorageManager.getStorage()
    return storage
end

return StorageManager