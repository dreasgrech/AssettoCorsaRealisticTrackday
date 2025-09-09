local StorageManager = {}

local storageTable = {
    enabled = true,
    debugDraw = false,
    drawOnTop = false,
    yieldToLeft = false,
    overrideAiAwareness = false,
    handleAccidents = false,
    detectInner_meters = 20,
    minPlayerSpeed_kmh = 0,
    minSpeedDelta_kmh = 5.0,
    yieldMaxOffset_normalized = 0.8,
    rampSpeed_mps = 2.0,
    rampRelease_mps = 1.6,
    clearAhead_meters = 6.0,
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