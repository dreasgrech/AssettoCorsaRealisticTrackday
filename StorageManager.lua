local StorageManager = {}

local storageTable = {
    enabled = true,
    debugDraw = false,
    drawOnTop = false,
    yieldToLeft = false,
    overrideAiAwareness = false,
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
    blockSideLateral_meters = 2.2,
    blockSideLongitudinal_meters = 5.5,
    blockSlowdownKmh = 12.0,
    blockThrottleLimit = 0.92,
}

local storage = ac.storage(storageTable)

function StorageManager.getStorage()
    return storage
end

return StorageManager