local StackManager = {}

local lastCreatedStackIndex = 0

local stacks = {}

---Creates a new stack and returns the index to it.
---@return integer
function StackManager.createStack()
    lastCreatedStackIndex = lastCreatedStackIndex + 1
    stacks[lastCreatedStackIndex] = DequeManager.createDeque()
    return lastCreatedStackIndex
end

---Pushes a value onto the stack
---@param stackIndex integer
---@param value any
function StackManager.push(stackIndex, value)
    local dequeIndex = stacks[stackIndex]
    DequeManager.pushRight(dequeIndex, value)
end

---Pops a value from the top of the stack
---@param stackIndex integer
---@return any
function StackManager.pop(stackIndex)
    local dequeIndex = stacks[stackIndex]
    return DequeManager.popRight(dequeIndex)
end

---Returns the total number of items currently in the given stack
---@param stackIndex integer
---@return integer
function StackManager.stackLength(stackIndex)
    local dequeIndex = stacks[stackIndex]
    return DequeManager.dequeLength(dequeIndex)
end

return StackManager