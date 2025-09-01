local CarManager = {}

CarManager.ai = {} -- [i] = { offset, yielding, dist, desired, maxRight, prog, reason, yieldTime, blink }

CarManager.cars_initialized = {}
CarManager.cars_offset = {}
CarManager.cars_yielding = {}
CarManager.cars_dist = {}
CarManager.cars_desired = {}
CarManager.cars_maxRight = {}
CarManager.cars_prog = {}
CarManager.cars_reason = {}
CarManager.cars_yieldTime = {}
CarManager.cars_blink = {}
CarManager.cars_blocked = {}
CarManager.cars_blocker = {}
CarManager.cars_indLeft = {}
CarManager.cars_indRight = {}
CarManager.cars_indPhase = {}
CarManager.cars_hasTL = {}

function CarManager.ensureDefaults(carIndex)
  if CarManager.cars_initialized[carIndex] then
    return
  end

  CarManager.cars_initialized[carIndex] = true
  CarManager.cars_offset[carIndex] = 0
  CarManager.cars_yielding[carIndex] = false
  CarManager.cars_dist[carIndex] = 0
  CarManager.cars_desired[carIndex] = 0
  CarManager.cars_maxRight[carIndex] = 0
  CarManager.cars_prog[carIndex] = -1
  CarManager.cars_reason[carIndex] = '-'
  CarManager.cars_yieldTime[carIndex] = 0
  CarManager.cars_blink[carIndex] = nil
  CarManager.cars_blocked[carIndex] = false
  CarManager.cars_blocker[carIndex] = nil
  CarManager.cars_indLeft[carIndex] = false
  CarManager.cars_indRight[carIndex] = false
  CarManager.cars_indPhase[carIndex] = false
  CarManager.cars_hasTL[carIndex] = false
end

return CarManager