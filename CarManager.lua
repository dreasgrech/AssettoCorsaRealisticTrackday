local CarManager = {}

-- Andreas: used while still writing the accident system
local DISABLE_ACCIDENTCOLLISION_DETECTION = true

CarManager.cars_initialized = {}
CarManager.cars_currentlyYielding = {}

CarManager.cars_currentSplineOffset_meters = {} -- used in old system which used meters instead of normalized
CarManager.cars_targetSplineOffset_meters = {} -- used in old system which used meters instead of normalized

CarManager.cars_currentSplineOffset = {}
CarManager.cars_targetSplineOffset = {}

CarManager.cars_distanceFromPlayerToCar = {}
CarManager.cars_maxSideMargin = {}
CarManager.cars_currentNormalizedTrackProgress = {}
CarManager.cars_reasonWhyCantYield = {}
CarManager.cars_yieldTime = {}
CarManager.cars_currentTurningLights = {}
CarManager.cars_isSideBlocked = {}
CarManager.cars_sideBlockedCarIndex = {}
CarManager.cars_indLeft = {}
CarManager.cars_indRight = {}
CarManager.cars_indPhase = {}
CarManager.cars_hasTL = {}
CarManager.cars_evacuating = {}

CarManager.cars_AABBSIZE = {}
CarManager.cars_HALF_AABSIZE = {}

-- -- evacuate state so we don’t re-trigger while a car is already evacuating
-- local evacuating = {}

local function setInitializedDefaults(carIndex)
  CarManager.cars_initialized[carIndex] = true
  CarManager.cars_currentlyYielding[carIndex] = false

  CarManager.cars_currentSplineOffset_meters[carIndex] = 0
  CarManager.cars_targetSplineOffset_meters[carIndex] = 0

  CarManager.cars_currentSplineOffset[carIndex] = 0
  CarManager.cars_targetSplineOffset[carIndex] = 0

  CarManager.cars_distanceFromPlayerToCar[carIndex] = 0
  CarManager.cars_maxSideMargin[carIndex] = 0
  CarManager.cars_currentNormalizedTrackProgress[carIndex] = -1
  CarManager.cars_reasonWhyCantYield[carIndex] = ''
  CarManager.cars_yieldTime[carIndex] = 0
  CarManager.cars_currentTurningLights[carIndex] = nil
  CarManager.cars_isSideBlocked[carIndex] = false
  CarManager.cars_sideBlockedCarIndex[carIndex] = nil
  CarManager.cars_indLeft[carIndex] = false
  CarManager.cars_indRight[carIndex] = false
  CarManager.cars_indPhase[carIndex] = false
  CarManager.cars_hasTL[carIndex] = false
  CarManager.cars_evacuating[carIndex] = false
  CarStateMachine.changeState(carIndex, CarStateMachine.CarStateType.DRIVING_NORMALLY)

  -- remove speed limitations which could have occured during an accident
  physics.setAIThrottleLimit(carIndex, 1)
  physics.setAITopSpeed(carIndex, math.huge)
  physics.setAIStopCounter(carIndex, 0)
  physics.setGentleStop(carIndex, false)
  physics.setAICaution(carIndex, 1)

  local car = ac.getCar(carIndex)
  if car then
    CarManager.cars_AABBSIZE[carIndex] = car.aabbSize
    CarManager.cars_HALF_AABSIZE[carIndex] = car.aabbSize * 0.5

    -- Turn off any turning lights
    ac.setTargetCar(carIndex)
    ac.setTurningLights(ac.TurningLights.None)
  end
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
  if not car then
    return
  end

  -- ac.log(("Car #%d (%s) jumped/reset at spline=%.3f"):format(carIndex, car.name, car.splinePosition))
  setInitializedDefaults(carIndex) -- reset state on jump/reset
end)

-- -- Utility: compute world right-vector at a given progress on the AI spline
-- local function trackRightAt(progress)
  -- -- sample two points along the spline to get forward dir
  -- local p0 = ac.trackProgressToWorldCoordinate(progress)
  -- local p1 = ac.trackProgressToWorldCoordinate((progress + 0.0008) % 1.0)
  -- local fwd = (p1 - p0):normalize()
  -- -- Y-up world, so right = up × fwd
  -- local up  = vec3(0,1,0)
  -- local right = up:cross(fwd):normalize()
  -- return right
-- end

-- -- Physics shove for ~1.2 s (applied at physics rate) to push the car onto grass
-- local function shoveCarSideways(carIndex, towardsRight, strengthN, seconds)
  -- CarManager.cars_reason[carIndex] = "starting to shove car sideways to evacuate"

  -- -- optional safety bubble: disable car-car collisions during the shove
  -- physics.disableCarCollisions(carIndex, true)            -- re-enable later  :contentReference[oaicite:0]{index=0}

  -- -- cap pace while evacuating
  -- physics.setAITopSpeed(carIndex, 15)                     -- 15 km/h crawl   :contentReference[oaicite:1]{index=1}
  -- physics.setAIThrottleLimit(carIndex, 0.25)

  -- -- Let tyres-out be OK globally in modes; prevents penalties while off track (optional)
  -- physics.setAllowedTyresOut(-1)

  -- -- launch short physics worker to add lateral force each physics tick
  -- local startedAt = os.clock()
  -- physics.startPhysicsWorker([[
    -- local idx, dirSign, forceN = __input.idx, __input.sign, __input.forceN
    -- function script.update(dt)
      -- -- grab current progress and compute world right
      -- local car = ac.getCar(idx)
      -- if not car then return end
      -- local prog = math.max(0, math.min(1, ac.worldCoordinateToTrack(car.position).z))
      -- local p0   = ac.trackProgressToWorldCoordinate(prog)
      -- local p1   = ac.trackProgressToWorldCoordinate((prog + 0.001) % 1.0)
      -- local fwd  = (p1 - p0):normalize()
      -- local right= vec3(0,1,0):cross(fwd):normalize()
      -- local sideways = right * dirSign

      -- -- apply a gentle, ground-level push near CG (world coords)
      -- local applyPos = car.position + vec3(0, 0.2, 0)
      -- physics.addForce(idx, applyPos, false, sideways * forceN * dt, false, -1)
      -- ac.log("lateral log")
    -- end
  -- ]], { idx = carIndex, sign = (towardsRight and 1 or -1), forceN = strengthN }, function(err) end)   -- :contentReference[oaicite:4]{index=4} :contentReference[oaicite:5]{index=5} :contentReference[oaicite:6]{index=6}
      -- -- CarManager.cars_reason[carIndex] = "applying lateral shove to evacuate in loop"

  -- -- stop the shove and restore things later
  -- setTimeout(function()
    -- CarManager.cars_reason[carIndex] = "Stopping shove to restore things later"
    -- physics.disableCarCollisions(carIndex, false)         -- restore collisions
    -- physics.setAITopSpeed(carIndex, math.huge)
    -- physics.setAIThrottleLimit(carIndex, 1)
  -- end, seconds or 1.2)
-- end

--- -- Monitor collisions
--- ac.onCarCollision(-1, function (carIndex)
  --- if DISABLE_ACCIDENTCOLLISION_DETECTION then return end

  --- local car = ac.getCar(carIndex)
  --- if not car or CarManager.cars_evacuating[carIndex] then return end

  --- -- hazard lights
  --- ac.setTargetCar(carIndex)
  --- if car.hasTurningLights then
    --- ac.setTurningLights(ac.TurningLights.Hazards)
  --- end

  --- -- pick nearer side and immediately bias AI to that edge (cheap hint)
  --- local tcoords = ac.worldCoordinateToTrack(car.position)                       -- X∈[-1..1], Z∈[0..1]  :contentReference[oaicite:8]{index=8}
  --- local prog    = tcoords.z
  --- local sides   = ac.getTrackAISplineSides(prog)                                -- vec2(leftDistM, rightDistM)  :contentReference[oaicite:9]{index=9}
  --- local goRight = (sides.y <= sides.x)
  --- local edgeOffsetNorm = goRight and 0.98 or -0.98                              -- hug the boundary
  --- physics.setAISplineOffset(carIndex, edgeOffsetNorm, true)                     -- override AI awareness       :contentReference[oaicite:10]{index=10}

  --- -- brief settle, then push onto grass if still near racing line
  --- CarManager.cars_evacuating[carIndex] = true
  --- physics.setAIStopCounter(carIndex, 0.4)                                       -- momentary pause              :contentReference[oaicite:11]{index=11}
  --- physics.setGentleStop(carIndex, true)                                         -- smooth decel                 :contentReference[oaicite:12]{index=12}

  --- CarManager.cars_reason[carIndex] = ("Just collided.  Evacuating %s side at spline=%.3f") 
                                --- :format(goRight and "RIGHT" or "LEFT", car.splinePosition)

  --- CarManager.cars_currentlyYielding[carIndex] = false

  --- setTimeout(function()
    --- physics.setAIStopCounter(carIndex, 0)
    --- physics.setGentleStop(carIndex, false)

    --- CarManager.cars_reason[carIndex] = "Starting to shove car off track to the " .. (goRight and "RIGHT" or "LEFT")

    --- -- crawl and steer bias remain; now physically nudge off the tarmac
    --- shoveCarSideways(carIndex, goRight, 9000, 1.2)                              -- ~9 kN lateral shove ~1.2 s   :contentReference[oaicite:13]{index=13}

    --- -- if you want them to then head to pits once clear:
    --- -- physics.setAIPitStopRequest(carIndex, true)                                 -- optional                     :contentReference[oaicite:14]{index=14}

    --- Logger.log(("Car #%d (%s) evacuating %s side at spline=%.3f") :format(carIndex, car.name, goRight and "RIGHT" or "LEFT", car.splinePosition))

--- --[=====[ 
    --- -- after a few seconds, clear state & lights so AI can recover
    --- setTimeout(function()
      --- physics.setAISplineOffset(carIndex, 0, true)
      --- physics.setAITopSpeed(carIndex, math.huge)
      --- physics.setAIThrottleLimit(carIndex, 1)
      --- if car.hasTurningLights then ac.setTurningLights(ac.TurningLights.None) end
      --- CarManager.cars_evacuating[carIndex] = nil
    --- end, 6.0)
--- --]=====]
  --- end, 0.6)

--- end)

return CarManager