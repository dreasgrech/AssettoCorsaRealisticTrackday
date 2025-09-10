local StorageManager = {}

local storageTable = {
    enabled = true,
    debugDraw = false,
    drawOnTop = false,
    yieldToLeft = false,
    overrideAiAwareness = false,
    handleAccidents = false,
    detectInner_meters = 70,
    minPlayerSpeed_kmh = 0,
    minSpeedDelta_kmh = 0.0,
    yieldMaxOffset_normalized = 0.8,
    rampSpeed_mps = 0.5,
    rampRelease_mps = 0.3,
    clearAhead_meters = 6.0,
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