local CarManager = {}

CarManager.ai = {} -- [i] = { offset, yielding, dist, desired, maxRight, prog, reason, yieldTime, blink }

CarManager.cars_initialized = {}
CarManager.cars_offset = {}
CarManager.cars_yielding = {}
CarManager.cars_dist = {}
CarManager.cars_desired = {}

function CarManager.ensureDefaults(carIndex)
  if CarManager.cars_initialized[carIndex] then
    return
  end

  CarManager.cars_initialized[carIndex] = true
  CarManager.cars_offset[carIndex] = 0
  CarManager.cars_yielding[carIndex] = false
  CarManager.cars_dist[carIndex] = 0
  CarManager.cars_desired[carIndex] = 0
end

return CarManager