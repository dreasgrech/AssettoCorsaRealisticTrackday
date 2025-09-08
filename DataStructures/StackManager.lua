local StackManager = {}

local lastCreatedStackIndex = 0

local stacks = {}

function StackManager.createStack()
    lastCreatedStackIndex = lastCreatedStackIndex + 1
    stacks[lastCreatedStackIndex] = DequeManager.createDeque()
    return lastCreatedStackIndex
end

function StackManager.push(stackIndex, value)
    local dequeIndex = stacks[stackIndex]
    DequeManager.pushRight(dequeIndex, value)
end

function StackManager.pop(stackIndex)
    local dequeIndex = stacks[stackIndex]
    return DequeManager.popRight(dequeIndex)
end

function StackManager.stackLength(stackIndex)
    local dequeIndex = stacks[stackIndex]
    return DequeManager.dequeLength(dequeIndex)
end

return StackManager