local MathHelpers = {}

-- bindings
local sqrt = math.sqrt

---vsub
---@param a vec3
---@param b vec3
---@return vec3
function MathHelpers.vsub(a,b) return vec3(a.x-b.x, a.y-b.y, a.z-b.z) end

---vlen
---@param v vec3
---@return number
function MathHelpers.vlen(v)
  local x, y, z = v.x, v.y, v.z
  return sqrt(x*x + y*y + z*z)
end

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

---Returns the distance between two vector3s (3D Euclidean).
---Avoids temporary vec3 creation and extra function calls.
---@param vec3a vec3
---@param vec3b vec3
---@return number
function MathHelpers.distanceBetweenVec3s(vec3a, vec3b)
    local dx = vec3a.x - vec3b.x
    local dy = vec3a.y - vec3b.y
    local dz = vec3a.z - vec3b.z
    return sqrt(dx*dx + dy*dy + dz*dz)
end

---Returns squared distance between two vector3s (no sqrt).
---Use this for threshold checks or sorting to avoid sqrt overhead:
---  if MathHelpers.distanceBetweenVec3sSq(a,b) < r*r then ...
---@param vec3a vec3
---@param vec3b vec3
---@return number
function MathHelpers.distanceBetweenVec3sSqr(vec3a, vec3b)
    local dx = vec3a.x - vec3b.x
    local dy = vec3a.y - vec3b.y
    local dz = vec3a.z - vec3b.z
    return dx*dx + dy*dy + dz*dz
end

return MathHelpers
