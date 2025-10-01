local CompletableIndexCollectionManager = {}

---@type table<integer, integer>
local collections_lastIndexCreated = {}
---@type table<integer, integer>
local collections_firstNonResolvedIndex = {}

local lastCreatedCollectionIndex = 0

--- Creates a new Index and returns its index
---@return integer indexIndex
CompletableIndexCollectionManager.createNewIndex = function()
    lastCreatedCollectionIndex = lastCreatedCollectionIndex + 1

    collections_lastIndexCreated[lastCreatedCollectionIndex] = 0
    collections_firstNonResolvedIndex[lastCreatedCollectionIndex] = 1

    return lastCreatedCollectionIndex
end

---Returns the last index created for the given index
---@param indexIndex number
---@return integer lastIndexCreated
CompletableIndexCollectionManager.getLastIndexCreated = function(indexIndex)
    return collections_lastIndexCreated[indexIndex]
end

---Returns the first non-resolved index for the given index
---@param indexIndex number
---@return integer firstNonResolvedIndex
CompletableIndexCollectionManager.getFirstNonResolvedIndex = function(indexIndex)
    return collections_firstNonResolvedIndex[indexIndex]
end

---
---@param indexIndex number
---@param resolvedCollection table<integer, boolean>
CompletableIndexCollectionManager.updateFirstNonResolvedIndex = function(indexIndex, resolvedCollection)
    -- check the resolvedCollection and update the first non-resolved collection index so that loops iterating over the indexes can skip resolved ones
    local firstNonResolvedIndex = collections_firstNonResolvedIndex[indexIndex]
    local lastIndexCreated = collections_lastIndexCreated[indexIndex]
    for i = firstNonResolvedIndex, lastIndexCreated do
        if resolvedCollection[i] == false then
            Logger.log(string.format("[CompletableIndexCollectionManager] #%d Setting first non-resolved index to %d", indexIndex, i))
            collections_firstNonResolvedIndex[indexIndex] = i
            break
        end
    end
end

---
---@param indexIndex number
---@return number lastIndexCreated
CompletableIndexCollectionManager.incrementLastIndexCreated = function(indexIndex)
    local lastIndexCreated = collections_lastIndexCreated[indexIndex] + 1
    collections_lastIndexCreated[indexIndex] = lastIndexCreated

    return lastIndexCreated
end

return CompletableIndexCollectionManager