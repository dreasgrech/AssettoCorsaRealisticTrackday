local OnCarEventManager = {}

---@enum OnCarEventManager.OnCarEventType 
OnCarEventManager.OnCarEventType = {
    None = 0,
    Collision = 1,
    Jumped = 2,
}

--This is filled with actual implementations from somewhere else
---@type table<OnCarEventManager.OnCarEventType,function>
OnCarEventManager.OnCarEventExecutions = { }

local onCarEvents_eventTypeQueue = QueueManager.createQueue()
local onCarEvents_carIndexQueue = QueueManager.createQueue()

OnCarEventManager.enqueueOnCarEvent = function(eventType, carIndex)
    QueueManager.enqueue(onCarEvents_eventTypeQueue, eventType)
    QueueManager.enqueue(onCarEvents_carIndexQueue, carIndex)
end

OnCarEventManager.processQueuedEvents = function()
    while QueueManager.queueLength(onCarEvents_eventTypeQueue) > 0 do
        local eventType = QueueManager.dequeue(onCarEvents_eventTypeQueue)
        local carIndex = QueueManager.dequeue(onCarEvents_carIndexQueue)
        OnCarEventManager.OnCarEventExecutions[eventType](carIndex)
    end
end

return OnCarEventManager