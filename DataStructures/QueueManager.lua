local QueueManager = {}

local lastCreatedQueueIndex = 0

local queues = {}

---Creates a new queue and returns the index to it.
---@return integer
function QueueManager.createQueue()
    lastCreatedQueueIndex = lastCreatedQueueIndex + 1
    queues[lastCreatedQueueIndex] = DequeManager.createDeque()
    return lastCreatedQueueIndex
end

---Enqueues a value to the given queue
---@param queueIndex integer
---@param value any
function QueueManager.enqueue(queueIndex, value)
    local dequeIndex = queues[queueIndex]
    DequeManager.pushRight(dequeIndex, value)
end

---Dequeues a value from the given queue
---@param queueIndex integer
---@return any
function QueueManager.dequeue(queueIndex)
    local dequeIndex = queues[queueIndex]
    return DequeManager.popLeft(dequeIndex)
end

---Returns the total number of items currently in the given queue
---@param queueIndex integer
---@return integer
function QueueManager.queueLength(queueIndex)
    local dequeIndex = queues[queueIndex]
    return DequeManager.dequeLength(dequeIndex)
end

return QueueManager
