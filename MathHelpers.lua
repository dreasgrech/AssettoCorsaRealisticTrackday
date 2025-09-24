local MathHelpers = {}

function MathHelpers.vsub(a,b) return vec3(a.x-b.x, a.y-b.y, a.z-b.z) end
function MathHelpers.vlen(v) return math.sqrt(v.x*v.x + v.y*v.y + v.z*v.z) end
function MathHelpers.dot(a,b) return a.x*b.x + a.y*b.y + a.z*b.z end
function MathHelpers.approach(curr, target, step)
    if math.abs(target - curr) <= step then return target end
    return curr + (target > curr and step or -step)
end
function MathHelpers.distanceBetweenVec3s(vec3a, vec3b)
    return MathHelpers.vlen(MathHelpers.vsub(vec3a, vec3b))
end

return MathHelpers