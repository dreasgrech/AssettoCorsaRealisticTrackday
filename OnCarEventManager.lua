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

---Enqueues an on car event to be processed in the next tick
---@param eventType OnCarEventManager.OnCarEventType
---@param carIndex integer
OnCarEventManager.enqueueOnCarEvent = function(eventType, carIndex)
    QueueManager.enqueue(onCarEvents_eventTypeQueue, eventType)
    QueueManager.enqueue(onCarEvents_carIndexQueue, carIndex)
end

---Should be called from an update loop to process any queued events
OnCarEventManager.processQueuedEvents = function()
    while QueueManager.queueLength(onCarEvents_eventTypeQueue) > 0 do
        local eventType = QueueManager.dequeue(onCarEvents_eventTypeQueue)
        local carIndex = QueueManager.dequeue(onCarEvents_carIndexQueue)
        OnCarEventManager.OnCarEventExecutions[eventType](carIndex)
    end
end

return OnCarEventManager