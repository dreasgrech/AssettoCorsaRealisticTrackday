local OnCarEventManager = {}

---@enum OnCarEventManager.OnCarEventType 
local OnCarEventType = {
    None = 0,
    Collision = 1,
    Jumped = 2,
}

-- TODO: Get the actual implementation of these functions out of this file
local onCarEventExecutions = {
    ---The callback function for when a car collision event occurs
    ---@param carIndex integer
    [OnCarEventType.Collision] = function (carIndex)
        local storage = StorageManager.getStorage()
        if storage.handleAccidents then
            -- Register an accident for the car collision
            local accidentIndex = AccidentManager.registerCollision(carIndex)
            if not accidentIndex then
                return
            end

            CarStateMachine.informAboutAccident(accidentIndex)
        end
    end,
    ---The callback function for when a car jumped event occurs
    ---@param carIndex integer
    [OnCarEventType.Jumped] = function (carIndex)
      -- Inform the accident manager about the car reset
      AccidentManager.informAboutCarReset(carIndex)

      -- finally reset all our car data
      if not CarManager.cars_justTeleportedDueToCustomAIFlood[carIndex] then
        CarManager.setInitializedDefaults(carIndex)
      end
    end,
}

local onCarEvents_eventTypeQueue = QueueManager.createQueue()
local onCarEvents_carIndexQueue = QueueManager.createQueue()

OnCarEventManager.OnCarEventType = OnCarEventType
OnCarEventManager.enqueueOnCarEvent = function(eventType, carIndex)
    QueueManager.enqueue(onCarEvents_eventTypeQueue, eventType)
    QueueManager.enqueue(onCarEvents_carIndexQueue, carIndex)
end
OnCarEventManager.processQueuedEvents = function()
    while QueueManager.queueLength(onCarEvents_eventTypeQueue) > 0 do
        local eventType = QueueManager.dequeue(onCarEvents_eventTypeQueue)
        local carIndex = QueueManager.dequeue(onCarEvents_carIndexQueue)
        onCarEventExecutions[eventType](carIndex)
    end
end

return OnCarEventManager