local MathHelpers = {}

---vsub
---@param a vec3
---@param b vec3
---@return vec3
function MathHelpers.vsub(a,b) return vec3(a.x-b.x, a.y-b.y, a.z-b.z) end

---vlen
---@param v vec3
---@return number
function MathHelpers.vlen(v) return math.sqrt(v.x*v.x + v.y*v.y + v.z*v.z) end

---dot
---@param a vec3
---@param b vec3
---@return number
function MathHelpers.dot(a,b) return a.x*b.x + a.y*b.y + a.z*b.z end

---approach
---@param curr number
---@param target number
---@param step number
---@return number
function MathHelpers.approach(curr, target, step)
    if math.abs(target - curr) <= step then return target end
    return curr + (target > curr and step or -step)
end

---Returns the distance between two vector3s
---@param vec3a vec3
---@param vec3b vec3
---@return number
function MathHelpers.distanceBetweenVec3s(vec3a, vec3b)
    -- TODO: this can definitely be optimized
    return MathHelpers.vlen(MathHelpers.vsub(vec3a, vec3b))
end

return MathHelpers