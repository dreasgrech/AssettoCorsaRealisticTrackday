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
---@field minPlayerSpeed_kmh number
---@field yieldMaxOffset_normalized number
---@field rampSpeed_mps number
---@field rampRelease_mps number
---@field overtakeRampSpeed_mps number
---@field overtakeRampRelease_mps number
---@field clearAhead_meters number
---@field minAISpeed_kmh number
---@field distanceFromAccidentToSeeYellowFlag_meters number
---@field distanceToStartNavigatingAroundCarInAccident_meters number
-- ---@field customAIFlood_enabled boolean
-- ---@field customAIFlood_distanceBehindPlayerToCycle_meters number
-- ---@field customAIFlood_distanceAheadOfPlayerToCycle_meters number

---@type StorageTable
local storageTable = {
    enabled = true,
    debugDraw = false,
    drawCarList = true,
    handleSideChecking = true,
    yieldSide = RaceTrackManager.TrackSide.RIGHT,
    overrideAiAwareness = false,
    handleAccidents = false,
    handleOvertaking = true,
    detectCarBehind_meters = 70,
    minPlayerSpeed_kmh = 0,
    -- minSpeedDelta_kmh = 0.0,
    yieldMaxOffset_normalized = 0.8,
    rampSpeed_mps = 0.5,
    rampRelease_mps = 0.3,
    overtakeRampSpeed_mps = 0.7,
    overtakeRampRelease_mps = 0.4,
    clearAhead_meters = 6.0,
    minAISpeed_kmh = 35.0,
    distanceFromAccidentToSeeYellowFlag_meters = 200.0,
    distanceToStartNavigatingAroundCarInAccident_meters = 30.0,
    -- customAIFlood_enabled = true,
    -- customAIFlood_distanceBehindPlayerToCycle_meters = 200,
    -- customAIFlood_distanceAheadOfPlayerToCycle_meters = 100,
}

local storage = ac.storage(storageTable)

---comment
---@return StorageTable storage
function StorageManager.getStorage()
    return storage
end

return StorageManager