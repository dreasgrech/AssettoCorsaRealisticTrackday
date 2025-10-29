local MathHelpers = {}

-- bindings
local sqrt = math.sqrt
local abs = math.abs
local vec3 = vec3

---vsub
---@param v3a vec3
---@param v3b vec3
---@return vec3
function MathHelpers.vsub(v3a, v3b)
    return vec3(v3a.x-v3b.x, v3a.y-v3b.y, v3a.z-v3b.z)
end

---vlen
---@param v3 vec3
---@return number
function MathHelpers.vlen(v3)
  local x, y, z = v3.x, v3.y, v3.z
  return sqrt(x*x + y*y + z*z)
end

---dot
---@param v3a vec3
---@param v3b vec3
---@return number
function MathHelpers.dot(v3a, v3b)
    return v3a.x*v3b.x + v3a.y*v3b.y + v3a.z*v3b.z
end

---approach
---@param current number
---@param target number
---@param step number
---@return number
function MathHelpers.approach(current, target, step)
    if abs(target - current) <= step then return target end
    return current + (target > current and step or -step)
end

---Returns the distance between two vector3s (3D Euclidean).
---Avoids temporary vec3 creation and extra function calls.
---@param v3a vec3
---@param v3b vec3
---@return number
function MathHelpers.distanceBetweenVec3s(v3a, v3b)
    local dx = v3a.x - v3b.x
    local dy = v3a.y - v3b.y
    local dz = v3a.z - v3b.z
    return sqrt(dx*dx + dy*dy + dz*dz)
end

---Returns squared distance between two vector3s (no sqrt).
---Use this for threshold checks or sorting to avoid sqrt overhead:
---  if MathHelpers.distanceBetweenVec3sSq(a,b) < r*r then ...
---@param v3a vec3
---@param v3b vec3
---@return number
function MathHelpers.distanceBetweenVec3sSqr(v3a, v3b)
    local dx = v3a.x - v3b.x
    local dy = v3a.y - v3b.y
    local dz = v3a.z - v3b.z
    return dx*dx + dy*dy + dz*dz
end

return MathHelpers
