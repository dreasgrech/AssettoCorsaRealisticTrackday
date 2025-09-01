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

-- evacuate state so we don’t re-trigger while a car is already evacuating
local evacuating = {}

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

  evacuating[carIndex] = false
end

function CarManager.ensureDefaults(carIndex)
  if CarManager.cars_initialized[carIndex] then
    return
  end

  setInitializedDefaults(carIndex)
end

function CarManager.isCarEvacuating(carIndex)
    return evacuating[carIndex]
end

-- Monitor flood ai cars cycle event so that we also reset our state
ac.onCarJumped(-1, function(carIndex)
  local car = ac.getCar(carIndex)
  if not car then
    return
  end

  -- ac.log(("Car #%d (%s) jumped/reset at spline=%.3f"):format(carIndex, car.name, car.splinePosition))
  setInitializedDefaults(carIndex) -- reset state on jump/reset
end)

-- Monitor collisions
ac.onCarCollision(-1, function (carIndex)
  -- ignore for local player car
  -- if carIndex == 0 then return end

  local car = ac.getCar(carIndex)
  if not car or evacuating[carIndex] then return end

  -- Lights on
  ac.setTargetCar(carIndex)
  if car.hasTurningLights then
    ac.setTurningLights(ac.TurningLights.Hazards)
  end

  -- Figure which side to go to (prefer nearest safe edge)
  local tcoords = ac.worldCoordinateToTrack(car.position)               -- X∈[-1..1], Z∈[0..1]
  local prog    = tcoords.z
  local sides   = ac.getTrackAISplineSides(prog)                        -- vec2(leftDist, rightDist)

  -- Choose the closer boundary to clear the racing line quicker:
  -- if you prefer always-right, replace this with: local goRight = true
  local goRight = (sides.y <= sides.x)

  -- Target lateral offset relative to spline:
  --   +1 = full right, -1 = full left. Aim a bit inside the boundary (±0.85)
  local targetOffset = goRight and 0.85 or -0.85

  -- Phase 1: brief full stop, then roll to the side slowly
  evacuating[carIndex] = true
  physics.setGentleStop(carIndex, true)
  physics.setAIStopCounter(carIndex, 0.7)                               -- quick “collect yourself” pause

  setTimeout(function()
    -- Let it crawl at low speed while sliding to the chosen side
    physics.setAIStopCounter(carIndex, 0)
    physics.setAITopSpeed(carIndex, 20)                                 -- ~20 km/h crawl
    physics.setAIThrottleLimit(carIndex, 0.35)                          -- soft cap

    -- Ask AI to hold to the side; override awareness so it doesn’t get “shy”
    physics.setAISplineOffset(carIndex, targetOffset, true)

    ac.log(("Car #%d (%s) evacuating %s side at spline=%.3f")
      :format(carIndex, car.name, goRight and "RIGHT" or "LEFT", car.splinePosition))
  end, 0.8)                                                              -- run after the brief stop
end)

return CarManager