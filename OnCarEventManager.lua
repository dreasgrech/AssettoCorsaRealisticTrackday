local OnCarEventManager = {}

local OnCarEventType = {
    None = 0,
    Collision = 1,
    Jumped = 2,
}

local onCarEventExecutions = {
    [OnCarEventType.Collision] = function (carIndex)
      -- Register an accident for the car collision
      local accidentIndex = AccidentManager.registerCollision(carIndex)
      if not accidentIndex then
          return
      end

      CarStateMachine.informAboutAccident(accidentIndex)
    end,
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