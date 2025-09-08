-- Reference from https://www.lua.org/pil/11.4.html

local DequeManager = {}

local lastCreatedDequeIndex = 0

local deques = {}

--- Wikipedia: A double-ended queue (deque) is an abstract data type that generalizes a queue, for which elements can be added to or removed from either the front (head) or back (tail).
---@return integer
function DequeManager.createDeque()
    lastCreatedDequeIndex = lastCreatedDequeIndex + 1
    deques[lastCreatedDequeIndex] = {first = 0, last = -1}
    return lastCreatedDequeIndex
end

function DequeManager.pushLeft(dequeIndex, value)
    local deque = deques[dequeIndex]
    local first = deque.first - 1
    deque.first = first
    deque[first] = value
end

function DequeManager.pushRight(dequeIndex, value)
    local deque = deques[dequeIndex]
    local last = deque.last + 1
    deque.last = last
    deque[last] = value
end

function DequeManager.popLeft(dequeIndex)
    local deque = deques[dequeIndex]
    local first = deque.first
    if first > deque.last then error("deque is empty") end
    local value = deque[first]
    deque[first] = nil        -- to allow garbage collection
    deque.first = first + 1
    return value
end

function DequeManager.popRight(dequeIndex)
    local deque = deques[dequeIndex]
    local last = deque.last
    if deque.first > last then error("deque is empty") end
    local value = deque[last]
    deque[last] = nil         -- to allow garbage collection
    deque.last = last - 1
    return value
end

-- todo: I wrote this so check it it thouroughly!
function DequeManager.dequeLength(dequeIndex)
    local deque = deques[dequeIndex]
    return deque.last - deque.first + 1
end

return DequeManager