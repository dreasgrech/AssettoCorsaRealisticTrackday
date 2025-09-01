local CarManager = {}

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

local function setInitializedDefaults(carIndex)
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

  -- remove speed limitations which could have occured during an accident
  physics.setAIThrottleLimit(carIndex, 1)
  physics.setAITopSpeed(carIndex, math.huge)
  physics.setAIStopCounter(carIndex, 0)
  physics.setGentleStop(carIndex, false)
end

function CarManager.ensureDefaults(carIndex)
  if CarManager.cars_initialized[carIndex] then
    return
  end

  setInitializedDefaults(carIndex)
end

-- Monitor flood ai cars cycle event so that we also reset our state
ac.onCarJumped(-1, function(carIndex)
  local car = ac.getCar(carIndex)
  if car then
    ac.log(("Car #%d (%s) jumped/reset at spline=%.3f"):format(carIndex, car.name, car.splinePosition))
    setInitializedDefaults(carIndex) -- reset state on jump/reset
  else
    ac.log(("Car #%d jumped/reset"):format(carIndex))
  end
end)

-- Monitor collisions
ac.onCarCollision(-1, function (carIndex)
    -- ignore for local player car
  if carIndex == 0 then return end

  local car = ac.getCar(carIndex)
  if not car then return end

  -- 1) Switch hazards on (if car has turn signals)
  -- (setTargetCar lets light control hit non-user cars)
  ac.setTargetCar(carIndex)                                   -- may no-op for some cars, but usually fine
  if car.hasTurningLights then
    ac.setTurningLights(ac.TurningLights.Hazards)             -- hazards = both blinkers
  end

  -- 2) Make the AI stop completely
  --    • setAIStopCounter tells AI to brake for N seconds (use >0 if you want timed stop)
  --    • throttle limit 0 blocks gas
  --    • top speed ~0 km/h prevents creeping
  --    • gentle stop engages a smooth stop (leave on until you want to release)
  physics.setAIThrottleLimit(carIndex, 0)
  physics.setAITopSpeed(carIndex, 1)                          -- 1 km/h ≈ hard stop
  physics.setAIStopCounter(carIndex, 5)                       -- brakes for 5 s; set 0 to cancel later
  physics.setGentleStop(carIndex, true)

  -- Optional: drop gearbox to neutral to emulate a human securing the car:
  ac.switchToNeutralGear()

  ac.log(("Car #%d (%s) collided: hazards on, stopping at spline=%.3f") :format(carIndex, car.name, car.splinePosition))
end)

return CarManager