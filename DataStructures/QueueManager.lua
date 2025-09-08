local QueueManager = {}

local lastCreatedQueueIndex = 0

local queues = {}

function QueueManager.createQueue()
    lastCreatedQueueIndex = lastCreatedQueueIndex + 1
    queues[lastCreatedQueueIndex] = DequeManager.createDeque()
    return lastCreatedQueueIndex
end

function QueueManager.enqueue(queueIndex, value)
    local dequeIndex = queues[queueIndex]
    DequeManager.pushRight(dequeIndex, value)
end

function QueueManager.dequeue(queueIndex)
    local dequeIndex = queues[queueIndex]
    return DequeManager.popLeft(dequeIndex)
end

function QueueManager.queueLength(queueIndex)
    local dequeIndex = queues[queueIndex]
    return DequeManager.dequeLength(dequeIndex)
end

return QueueManager
