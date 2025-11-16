local VecPool = {}

local tempVec3 = vec3(0, 0, 0)

---Returns a vec3 that's only be meant to be used temporarily within a single function call.
---Usually only used when functions require a vec3 and you need a throwaway vec3 to pass in.
---@param x number 
---@param y number 
---@param z number 
---@return vec3
VecPool.getTempVec3 = function(x,y,z)
    tempVec3:set(x, y, z)
    return tempVec3
end

return VecPool