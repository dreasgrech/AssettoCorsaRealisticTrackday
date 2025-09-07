local Enum = {}

function Enum.hasFlag(state, flag)
    return (state & flag) ~= 0
end

function Enum.add(state, flag)
    return state | flag
end

function Enum.remove(state, flag)
    return state & (~flag)
end

return Enum