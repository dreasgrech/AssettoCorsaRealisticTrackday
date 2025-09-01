local CarManager = {}

CarManager.ai = {} -- [i] = { offset, yielding, dist, desired, maxRight, prog, reason, yieldTime, blink }

CarManager.cars_initialized = {}
CarManager.cars_offset = {}

function CarManager.ensureDefaults(carIndex)
  if CarManager.cars_initialized[carIndex] then
    return
  end

  CarManager.cars_initialized[carIndex] = true
  CarManager.cars_offset[carIndex] = 0
end


return CarManager