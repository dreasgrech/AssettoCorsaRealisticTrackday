local CompletableIndexCollectionManager = {}

local collections_lastIndexCreated = {}
local collections_firstNonResolvedIndex = {}
local collections_resolved = {}

local lastCreatedCollectionIndex = 0

CompletableIndexCollectionManager.createNewIndex = function()
    lastCreatedCollectionIndex = lastCreatedCollectionIndex + 1

    collections_lastIndexCreated[lastCreatedCollectionIndex] = 0
    collections_firstNonResolvedIndex[lastCreatedCollectionIndex] = 1
    collections_resolved[lastCreatedCollectionIndex] = false

    return lastCreatedCollectionIndex
end

CompletableIndexCollectionManager.getLastIndexCreated = function(collectionIndex)
    return collections_lastIndexCreated[collectionIndex]
end

CompletableIndexCollectionManager.getFirstNonResolvedIndex = function(collectionIndex)
    return collections_firstNonResolvedIndex[collectionIndex]
end

-- CompletableIndexCollectionManager.updateFirstNonResolvedIndex = function(collectionIndex)
CompletableIndexCollectionManager.setAsResolved = function(collectionIndex)
    collections_resolved[collectionIndex] = true

    -- check the existing collections and update the first non-resolved collection index so that loops iterating over the indexes can skip resolved ones
    local firstNonResolvedIndex = collections_firstNonResolvedIndex[collectionIndex]
    local lastIndexCreated = collections_lastIndexCreated[collectionIndex]
    for i = firstNonResolvedIndex, lastIndexCreated do
        if collections_resolved[i] == false then
            Logger.log(string.format("[CompletableIndexCollectionManager] #%d Setting first non-resolved index to %d", collectionIndex, i))
            collections_firstNonResolvedIndex[collectionIndex] = i
            break
        end
    end
end

CompletableIndexCollectionManager.incrementLastIndexCreated = function(collectionIndex)
    local lastIndexCreated = collections_lastIndexCreated[collectionIndex] + 1
    collections_lastIndexCreated[collectionIndex] = lastIndexCreated

    return lastIndexCreated
end

return CompletableIndexCollectionManager