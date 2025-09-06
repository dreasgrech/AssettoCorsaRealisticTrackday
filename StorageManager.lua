local StorageManager = {}

--[=====[ 
StorageManager.enabled = true
StorageManager.debugDraw = false
StorageManager.drawOnTop = false

StorageManager.detectInner_meters = 66
StorageManager.detectHysteresis_meters = 60.0
StorageManager.minPlayerSpeed_kmh = 0.0
StorageManager.minSpeedDelta_kmh = 5.0
StorageManager.yieldOffset_meters = 2.5
StorageManager.rampSpeed_mps = 2.0
StorageManager.rampRelease_mps = 1.6  -- slower return to center to avoid “snap back” once player is clearly ahead
StorageManager.clearAhead_meters = 6.0
StorageManager.rightMargin_meters = 0.6
StorageManager.listRadiusFilter_meters = 400.0
StorageManager.minAISpeed_kmh = 35.0
StorageManager.yieldToLeft = false
--]=====]

--[=====[ 
local storage = ac.storage{
    enabled = true,
    debugDraw = false,
    drawOnTop = false,
    detectInner_meters = 66,
    detectHysteresis_meters = 60.0,
    minPlayerSpeed_kmh = 0,
    minSpeedDelta_kmh = 5.0,
    yieldOffset_meters = 2.5,
    rampSpeed_mps = 2.0,
    rampRelease_mps = 1.6,  -- slower return to center to avoid “snap back” once player is clearly ahead
    clearAhead_meters = 6.0,
    rightMargin_meters = 0.6,
    listRadiusFilter_meters = 400.0,
    minAISpeed_kmh = 35.0,
    yieldToLeft = false,
}
--]=====]

--[=====[ 
local storageTable = {
    enabled = StorageManager.enabled,
    debugDraw = StorageManager.debugDraw,
    drawOnTop = StorageManager.drawOnTop,
    detectInner_meters = StorageManager.detectInner_meters,
    detectHysteresis_meters = StorageManager.detectHysteresis_meters,
    minPlayerSpeed_kmh = StorageManager.minPlayerSpeed_kmh,
    minSpeedDelta_kmh = StorageManager.minSpeedDelta_kmh,
    yieldOffset_meters = StorageManager.yieldOffset_meters,
    rampSpeed_mps = StorageManager.rampSpeed_mps,
    rampRelease_mps = StorageManager.rampRelease_mps,
    clearAhead_meters = StorageManager.clearAhead_meters,
    rightMargin_meters = StorageManager.rightMargin_meters,
    listRadiusFilter_meters = StorageManager.listRadiusFilter_meters,
    minAISpeed_kmh = StorageManager.minAISpeed_kmh,
    yieldToLeft = StorageManager.yieldToLeft,
}
--]=====]

local storageTable = {
    enabled = true,
    debugDraw = false,
    drawOnTop = false,
    detectInner_meters = 66,
    detectHysteresis_meters = 60.0,
    minPlayerSpeed_kmh = 0,
    minSpeedDelta_kmh = 5.0,
    yieldOffset_meters = 2.5,
    rampSpeed_mps = 2.0,
    rampRelease_mps = 1.6,
    clearAhead_meters = 6.0,
    rightMargin_meters = 0.6,
    listRadiusFilter_meters = 400.0,
    minAISpeed_kmh = 35.0,
    yieldToLeft = false,
}

local storage = ac.storage(storageTable)

-- storage['enabled'] = true

function StorageManager.getStorage()
    return storage
end

return StorageManager