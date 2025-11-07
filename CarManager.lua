local CarManager = {}

-- Andreas: used while still writing the accident system
local DISABLE_ACCIDENTCOLLISION_DETECTION = true

-- local CAR_SPEEDS_BUFFER_SIZE = 600
local CAR_SPEEDS_BUFFER_SIZE = 300

---@type table<integer,boolean>
CarManager.cars_initialized = {}
-- ---@type table<integer,number>
-- CarManager.cars_MAXTOPSPEED = {} -- do not reset this
---@type table<integer,integer>
CarManager.cars_ORIGINAL_AI_AGGRESSION = {} -- do not reset this
---@type table<integer,integer>
CarManager.cars_ORIGINAL_AI_DIFFICULTY_LEVEL = {} -- do not reset this

---@type table<integer,number>
CarManager.cars_currentSplineOffset = {}
---@type table<integer,number>
CarManager.cars_targetSplineOffset = {}

---@type table<integer,number>
CarManager.cars_maxSideMargin = {}
---@type table<integer,number>
CarManager.cars_currentNormalizedTrackProgress = {}
---@type table<integer,integer>
CarManager.cars_reasonWhyCantYield_NAME = {}
---@type table<integer,integer>
CarManager.cars_reasonWhyCantOvertake_NAME = {}
---@type table<integer,table<integer,integer>>
CarManager.cars_statesExitReason_NAME = {}
-- CarManager.cars_currentTurningLights = {}
-- CarManager.cars_indLeft = {}
-- CarManager.cars_indRight = {}
-- CarManager.cars_indPhase = {}
-- CarManager.cars_hasTL = {}
-- CarManager.cars_evacuating = {}

-- CarManager.cars_anchorPoints = {}
---@type table<integer,integer>
CarManager.cars_totalSideBlockRaysData = {} -- {[carIndex] = 1, [carIndex] = 0, ...}
---@type table<integer,table>
CarManager.cars_sideBlockRaysData = {} -- Example: one ray=> {pos,dir,len,hit}. two rays: {pos,dir,len,hit,pos,dir,len,hit}

---@type table<integer,number>
CarManager.cars_throttleLimit = {}
---@type table<integer,integer>
CarManager.cars_aiCaution = {}
---@type table<integer,integer>
CarManager.cars_aiAggression = {}
---@type table<integer,integer>
CarManager.cars_aiDifficultyLevel = {}
---@type table<integer,number>
CarManager.cars_aiTopSpeed = {}
---@type table<integer,number>
CarManager.cars_aiStopCounter = {}
---@type table<integer,boolean>
CarManager.cars_gentleStop = {}
---@type table<integer,integer>
CarManager.cars_currentlyOvertakingCarIndex = {} -- car index of the car we're currently overtaking
---@type table<integer,integer>
CarManager.cars_currentlyYieldingCarToIndex = {} -- car index of the car we're currently yielding to
---@type table<integer,number>
CarManager.cars_timeInCurrentState = {} -- time spent in the current state (seconds)
---@type table<integer,table<integer,number>>
CarManager.cars_speedBuffer = {}
---@type table<integer,integer>
CarManager.cars_speedBufferIndex = {}
---@type table<integer,number>
CarManager.cars_speedBufferTotal = {}
---@type table<integer,number>
CarManager.cars_averageSpeedKmh = {}
---@type table<integer,number>
CarManager.cars_closingSpeed = {}
---@type table<integer,number>
CarManager.cars_timeToCollision = {}

-- CarManager.cars_involvedInAccidents = {}
-- CarManager.cars_totalAccidentsInvolvedIn = {}
-- ---@type table<integer,integer>
-- CarManager.cars_culpritInAccidentIndex = {}
---@type table<integer,integer>
CarManager.cars_navigatingAroundAccidentIndex = {}
---@type table<integer,integer>
CarManager.cars_navigatingAroundCarIndex = {}

---@type table<integer,boolean>
CarManager.cars_justTeleportedDueToCustomAIFlood = {}

---@type table<integer,number>
CarManager.cars_grip = {}

---@type table<integer,vec3>
CarManager.cars_AABBSIZE = {}
---@type table<integer,vec3>
CarManager.cars_HALF_AABSIZE = {}

---@type table<integer,ac.StateCar>
CarManager.currentSortedCarsList = {}
---@type table<number,number>
CarManager.sortedCarList_carIndexToSortedIndex = {} -- [carIndex] = sortedListIndex

-- -- evacuate state so we don’t re-trigger while a car is already evacuating
-- local evacuating = {}

--TODO: don't leave this here, put it in awake()
-- -- calculate the max top speeds of each car
-- for i, car in ac.iterateCars() do
  -- local carIndex = car.index
  -- CarManager.cars_MAXTOPSPEED[carIndex] = CarOperations.calculateMaxTopSpeed(carIndex)
-- end

---@enum CarManager.AICautionValues
---Holds the different AI Caution levels used in different situations
CarManager.AICautionValues = {
  -- OVERTAKING_WITH_NO_OBSTACLE_INFRONT = 0,
  -- OVERTAKING_WITH_OBSTACLE_INFRONT = 1,
  -- OVERTAKING_WHILE_INCORNER = 2,
  -- YIELDING = 4,
  AFTER_ACCIDENT = 16
}

---@enum CarManager.AIAggressionValues
---Holds the different AI Aggression levels used in different situations
CarManager.AIAggressionValues = {
  -- OVERTAKING_WITH_NO_OBSTACLE_INFRONT = 1,
  -- OVERTAKING_WITH_OBSTACLE_INFRONT = .95,
  -- OVERTAKING_WHILE_INCORNER = .95,
  -- YIELDING = .5,
  AFTER_ACCIDENT = .1
}

---@enum CarManager.GripValues
CarManager.GripValues = {
  NORMAL = 1, -- todo: physics.setExtraAIGrip says that the default value is 1 but also says that AI cars have 120% grip
  DRIVING_TO_THE_SIDE = 1.3
}

---Sets all the default values for a car
---@param carIndex number
CarManager.setInitializedDefaults = function(carIndex)
  CarManager.cars_initialized[carIndex] = true

  CarManager.setCalculatedTrackLateralOffset(carIndex, 0)
  CarManager.cars_targetSplineOffset[carIndex] = 0

  CarManager.cars_maxSideMargin[carIndex] = 0
  CarManager.cars_currentNormalizedTrackProgress[carIndex] = -1
  CarManager.cars_reasonWhyCantYield_NAME[carIndex] = Strings.StringNames[Strings.StringCategories.ReasonWhyCantYield].None
  CarManager.cars_reasonWhyCantOvertake_NAME[carIndex] = Strings.StringNames[Strings.StringCategories.ReasonWhyCantOvertake].None
  -- CarManager.cars_currentTurningLights[carIndex] = nil
  -- CarManager.cars_indLeft[carIndex] = false
  -- CarManager.cars_indRight[carIndex] = false
  -- CarManager.cars_indPhase[carIndex] = false
  -- CarManager.cars_hasTL[carIndex] = false
  -- CarManager.cars_evacuating[carIndex] = false
  -- CarManager.cars_anchorPoints[carIndex] = nil
  CarManager.cars_totalSideBlockRaysData[carIndex] = 0
  CarManager.cars_sideBlockRaysData[carIndex] = {} -- since this is used as a list, initialize to empty list
  CarManager.cars_currentlyOvertakingCarIndex[carIndex] = nil
  CarManager.cars_currentlyYieldingCarToIndex[carIndex] = nil
  CarManager.cars_timeInCurrentState[carIndex] = 0
  CarManager.cars_statesExitReason_NAME[carIndex] = {}
  CarManager.cars_speedBuffer[carIndex] = {}
  CarManager.cars_speedBufferIndex[carIndex] = 0
  CarManager.cars_speedBufferTotal[carIndex] = 0
  CarManager.cars_averageSpeedKmh[carIndex] = 0
  CarManager.cars_closingSpeed[carIndex] = 0
  CarManager.cars_timeToCollision[carIndex] = math.huge
  -- CarManager.cars_involvedInAccidents[carIndex] = {}
  -- CarManager.cars_culpritInAccidentIndex[carIndex] = 0
  -- CarManager.cars_navigatingAroundAccidentIndex[carIndex] = nil
  -- CarManager.cars_navigatingAroundCarIndex[carIndex] = nil
  CarManager.sortedCarList_carIndexToSortedIndex[carIndex] = nil
  CarManager.cars_justTeleportedDueToCustomAIFlood[carIndex] = false
  AccidentManager.setCarNavigatingAroundAccident(carIndex, nil, nil)
  CarStateMachine.initializeCarInStateMachine(carIndex)

  -- remove speed limitations which could have occured during an accident
  CarOperations.resetAIThrottleLimit(carIndex)
  CarOperations.removeAITopSpeed(carIndex)
  CarOperations.setAIStopCounter(carIndex, 0)
  CarOperations.setGentleStop(carIndex, false)
  CarOperations.removeAICaution(carIndex)
  CarOperations.setDefaultAIAggression(carIndex)
  CarOperations.setDefaultAIDifficultyLevel(carIndex)
  CarOperations.setDefaultAIGrip(carIndex)

  -- reset any pedal positions we may have set
  CarOperations.resetPedalPosition(carIndex, CarOperations.CarPedals.Brake)
  CarOperations.resetPedalPosition(carIndex, CarOperations.CarPedals.Gas)
  CarOperations.resetPedalPosition(carIndex, CarOperations.CarPedals.Clutch )

  CarOperations.toggleCarCollisions(carIndex, true) -- TODO: make sure this doesn't interfere with CSP's disabling of car collisions when an ai flood car cycles to a new position
  -- CarOperations.toggleCarCollisions(carIndex, false) -- TODO: SETTING TO FALSE TO SEE IF IT ACTUALLY WORKS

  local car = ac.getCar(carIndex)
  if car then
    CarManager.cars_AABBSIZE[carIndex] = car.aabbSize
    CarManager.cars_HALF_AABSIZE[carIndex] = car.aabbSize * 0.5

    -- Turn off any turning lights
    ac.setTargetCar(carIndex)
    ac.setTurningLights(ac.TurningLights.None)
  end
end

---If the car hasn't been initialized yet, initializes it to default values
---@param carIndex number
function CarManager.ensureDefaults(carIndex)
  if CarManager.cars_initialized[carIndex] then
    return
  end

  CarManager.setInitializedDefaults(carIndex)
end

--- returns the calculated spline offset of the car, which is the one we use when easing driving to the side
---@param carIndex integer
---@return number
function CarManager.getCalculatedTrackLateralOffset(carIndex)
  return CarManager.cars_currentSplineOffset[carIndex]
end

---Sets the calculated track lateral offset
---@param carIndex integer
---@param calculatedLateralOffset number
function CarManager.setCalculatedTrackLateralOffset(carIndex, calculatedLateralOffset)
  CarManager.cars_currentSplineOffset[carIndex] = calculatedLateralOffset
end

-- function CarManager.getActualTrackLateralOffset(carIndex)
  -- local car = ac.getCar(carIndex)
  -- if not car then
    -- return 0
  -- end
--- returns the actual spline offset of the car, which may be different from the one set via physics.setAISplineOffset due to physics corrections
---@param carPosition vec3
---@return number
function CarManager.getActualTrackLateralOffset(carPosition)
  local carTrackCoordinates = ac.worldCoordinateToTrack(carPosition)
  return carTrackCoordinates.x
end

CarManager.getDefaultAIAggression = function(carIndex)
  local storage_aiCarValues = StorageManager.getStorage_AICarValues()
  return 
    -- if we're not overriding the original aggression, restore revert back to the original aggression
    storage_aiCarValues.overrideOriginalAIAggression_drivingNormally and storage_aiCarValues.defaultAIAggression
    or CarManager.cars_ORIGINAL_AI_AGGRESSION[carIndex]
end

CarManager.getDefaultAIDifficultyLevel = function(carIndex)
  local storage_aiCarValues = StorageManager.getStorage_AICarValues()
  return 
    -- if we're not overriding the original difficulty level, restore revert back to the original difficulty level
    storage_aiCarValues.overrideOriginalAIDifficultyLevel_drivingNormally and storage_aiCarValues.defaultAIDifficultyLevel
    or CarManager.cars_ORIGINAL_AI_DIFFICULTY_LEVEL[carIndex]
end

-- local SIDE_DETERMINATION_THRESHOLD = 0.1
-- local SIDE_DETERMINATION_THRESHOLD = 0.3
local SIDE_DETERMINATION_THRESHOLD = 0

--- returns a boolean value indicating whether the car is on the overtaking lane
---@param carIndex number
---@param trackSide RaceTrackManager.TrackSide
---@return boolean
function CarManager.isCarDrivingOnSide(carIndex, trackSide)
  local car = ac.getCar(carIndex)
  if not car then
    return false
  end

  local carPosition = car.position
  local actualLateralOffset = CarManager.getActualTrackLateralOffset(carPosition)

  if trackSide == RaceTrackManager.TrackSide.LEFT then
    return actualLateralOffset <= -SIDE_DETERMINATION_THRESHOLD
  end

  return actualLateralOffset >= SIDE_DETERMINATION_THRESHOLD

  -- return (trackSide == RaceTrackManager.TrackSide.LEFT and carTrackCoordinatesX <= -0.1) and true or false
end

---used in sorting
---@param carA ac.StateCar
---@param carB ac.StateCar
---@return boolean
local function isFirstCarSplinePositionGreater(carA, carB)
  return carA.splinePosition > carB.splinePosition
end

-- function CarManager.getCarListSortedByTrackPosition()
  -- local sortedCarsList = {}
  -- for i, car in ac.iterateCars() do
    -- sortedCarsList[#sortedCarsList + 1] = car
  -- end

  -- -- table.sort(sortedCarsList, function (carA, carB)
    -- -- return carA.splinePosition > carB.splinePosition
  -- -- end)
  -- table.sort(sortedCarsList, isFirstCarSplinePositionGreater)

  -- return sortedCarsList
-- end

---Sorts the given car list by track position, with the car furthest ahead first
---@param carList table<integer,ac.StateCar>
---@return table<integer,ac.StateCar> carList 
function CarManager.sortCarListByTrackPosition(carList)
  table.sort(carList, isFirstCarSplinePositionGreater)
  return carList
end

---Returns a boolean value indicating whether the car is mid-corner and the distance to the upcoming turn (0 if mid-corner)
---@param carIndex number
---@return boolean
---@return number
function CarManager.isCarMidCorner(carIndex)
  local trackUpcomingTurn = ac.getTrackUpcomingTurn(carIndex)
  local distanceToUpcomingTurn = trackUpcomingTurn.x
  -- local turnAngle = trackUpcomingTurn.y

  local isMidCorner = distanceToUpcomingTurn == 0
  return isMidCorner, distanceToUpcomingTurn
end

-- ---Returns a boolean value indicating whether the car is off track (more than 1.5 lanes away from center)
-- ---@param carIndex number
-- ---@return boolean
-- function CarManager.isCarOffTrack(carIndex)
  -- local car = ac.getCar(carIndex)
  -- if not car then
    -- return false
  -- end

  -- local carActualTrackLateralOffset = CarManager.getActualTrackLateralOffset(car.position)
  -- return math.abs(carActualTrackLateralOffset) > 1.5
-- end

---The indices of the car wheels as used in car.wheels[]
---Andreas: I found these indexes by drawing a debugBox at each wheel position with different colors
---@enum CarManager.CAR_WHEELS_INDEX
CarManager.CAR_WHEELS_INDEX = {
  FRONT_LEFT = 0,
  FRONT_RIGHT = 1,
  REAR_LEFT = 2,
  REAR_RIGHT = 3
}

---Returns a boolean value indicating whether the car is off track depending on the given side (if any wheel on that side is off track)
---@param car ac.StateCar
---@param side RaceTrackManager.TrackSide
---@return boolean
function CarManager.isCarOffTrack(car, side)
  if not car then
    return false
  end

  local carWheels = car.wheels

  -- Andreas: the following loop assumes that the wheel indices are always 0,1,2,3 for FL,FR,RL,RR
  -- First I determine which index to start the loop from (FRONT_LEFT or FRONT_RIGHT)
  -- then the loop iterates over both wheels on the given side by incrementing by 2 to skip the tyre in between
  local loopStart
  if side == RaceTrackManager.TrackSide.LEFT then
    loopStart = CarManager.CAR_WHEELS_INDEX.FRONT_LEFT
  else
    loopStart = CarManager.CAR_WHEELS_INDEX.FRONT_RIGHT
  end

  -- this loop won't run more than twice since there are only two wheels on each side
  local loopEnd = loopStart + 2
  for i = loopStart, loopEnd, 2 do
    local wheel = carWheels[i]
    if wheel then -- Andreas: is this wheel check neccessary? can there be vehicles with less than 4 wheels?
      local wheelOffTrack = not wheel.surfaceValidTrack
      if wheelOffTrack then
        -- todo: should we check both wheels on the side or just one?
        return true
      end
    end
  end

  return false

  -- for i = 0, 1 do
    -- local wheelIndex
    -- if side == RaceTrackManager.TrackSide.LEFT then
      -- wheelIndex = i * 2 -- 0,2
    -- else
      -- wheelIndex = i * 2 + 1 -- 1,3
    -- end

    -- local wheel = carWheels[wheelIndex]
  -- end
end

---comment
---@param car ac.StateCar
function CarManager.saveCarSpeed(car)
  local carIndex = car.index
  local currentSpeedKmh = car.speedKmh

  -- don't record the speed if the car is barely moving or stopped
  local carStopped = currentSpeedKmh < 1
  if carStopped then
    return
  end

  local currentSpeedBufferIndex = CarManager.cars_speedBufferIndex[carIndex]
  local speedThatWillBeReplaced = CarManager.cars_speedBuffer[carIndex][currentSpeedBufferIndex] or 0
  local speedBufferTotal = CarManager.cars_speedBufferTotal[carIndex]
  speedBufferTotal = speedBufferTotal - speedThatWillBeReplaced + currentSpeedKmh

  CarManager.cars_speedBufferTotal[carIndex] = speedBufferTotal
  CarManager.cars_speedBuffer[carIndex][currentSpeedBufferIndex] = currentSpeedKmh
  CarManager.cars_speedBufferIndex[carIndex] = (currentSpeedBufferIndex + 1) % CAR_SPEEDS_BUFFER_SIZE
  CarManager.cars_averageSpeedKmh[carIndex] = speedBufferTotal / CAR_SPEEDS_BUFFER_SIZE

  -- log the entire speed buffer
  -- Logger.log(string.format("Car %d speed buffer: %s, average: %.2f", carIndex, table.concat(CarManager.cars_speedBuffer[carIndex], ", "), CarManager.cars_averageSpeedKmh[carIndex] or 0))
end

---Returns the closing speed (m/s) and time to collision (s) between two cars
---If the closing speed is negative, then the cars are moving apart (not closing)
---@param car ac.StateCar
---@param carFront ac.StateCar
---@return number closingSpeed_ms
---@return number timeToCollision
---@return number distanceBetweenCars
CarManager.getClosingSpeed = function(car, carFront)
  if not car or not carFront then return -1,-1,-1 end

  -- positions
  local deltaPositions = carFront.position - car.position
  local distanceBetweenPositions = deltaPositions:length()
  if distanceBetweenPositions < 1e-3 then return -1, -1, -1 end
  local rhat = deltaPositions / distanceBetweenPositions

  -- closing speed in m/s (positive = closing, negative = opening)
  local deltaVelocities = carFront.velocity - car.velocity
  local closingSpeed_ms = -math.dot(deltaVelocities, rhat)

  -- -- (optional) smooth a bit to reduce noise
  -- local previousClosingSpeed = CarManager.cars_closingSpeed[car.index] or 0
  -- local alpha = const(0.2)
  -- closing_ms = previousClosingSpeed and (previousClosingSpeed*(1-alpha) + closing_ms*alpha) or closing_ms

  -- time-to-collision if still closing and paths roughly align
  local timeToCollision = (closingSpeed_ms > 0.1) and (distanceBetweenPositions / closingSpeed_ms) or math.huge

  -- local carBehindIndex = car.index
  -- CarManager.cars_closingSpeed[carBehindIndex] = closing_ms
  -- CarManager.cars_timeToCollision[carBehindIndex] = timeToCollision

  return closingSpeed_ms, timeToCollision, distanceBetweenPositions
end

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
  -- physics.disableCarCollisions(carIndex, true)            -- re-enable later  

  -- -- cap pace while evacuating
  -- physics.setAITopSpeed(carIndex, 15)                     -- 15 km/h crawl   
  -- CarOperations.setAIThrottleLimit(carIndex, 0.25)

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
  -- ]], { idx = carIndex, sign = (towardsRight and 1 or -1), forceN = strengthN }, function(err) end)
      -- -- CarManager.cars_reason[carIndex] = "applying lateral shove to evacuate in loop"

  -- -- stop the shove and restore things later
  -- setTimeout(function()
    -- CarManager.cars_reason[carIndex] = "Stopping shove to restore things later"
    -- physics.disableCarCollisions(carIndex, false)         -- restore collisions
    -- physics.setAITopSpeed(carIndex, math.huge)
    -- CarOperations.setAIThrottleLimit(carIndex, 1)
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
  --- local tcoords = ac.worldCoordinateToTrack(car.position)                       -- X∈[-1..1], Z∈[0..1]  
  --- local prog    = tcoords.z
  --- local sides   = ac.getTrackAISplineSides(prog)                                -- vec2(leftDistM, rightDistM)  
  --- local goRight = (sides.y <= sides.x)
  --- local edgeOffsetNorm = goRight and 0.98 or -0.98                              -- hug the boundary
  --- physics.setAISplineOffset(carIndex, edgeOffsetNorm, true)                     -- override AI awareness       

  --- -- brief settle, then push onto grass if still near racing line
  --- CarManager.cars_evacuating[carIndex] = true
  --- physics.setAIStopCounter(carIndex, 0.4)                                       -- momentary pause              
  --- physics.setGentleStop(carIndex, true)                                         -- smooth decel                 

  --- CarManager.cars_reason[carIndex] = ("Just collided.  Evacuating %s side at spline=%.3f") 
                                --- :format(goRight and "RIGHT" or "LEFT", car.splinePosition)

  --- CarManager.cars_currentlyYielding[carIndex] = false

  --- setTimeout(function()
    --- physics.setAIStopCounter(carIndex, 0)
    --- physics.setGentleStop(carIndex, false)

    --- CarManager.cars_reason[carIndex] = "Starting to shove car off track to the " .. (goRight and "RIGHT" or "LEFT")

    --- -- crawl and steer bias remain; now physically nudge off the tarmac
    --- shoveCarSideways(carIndex, goRight, 9000, 1.2)                              -- ~9 kN lateral shove ~1.2 s   

    --- -- if you want them to then head to pits once clear:
    --- -- physics.setAIPitStopRequest(carIndex, true)                                 -- optional                     

    --- Logger.log(("Car #%d (%s) evacuating %s side at spline=%.3f") :format(carIndex, car.name, goRight and "RIGHT" or "LEFT", car.splinePosition))

--- --[=====[ 
    --- -- after a few seconds, clear state & lights so AI can recover
    --- setTimeout(function()
      --- physics.setAISplineOffset(carIndex, 0, true)
      --- physics.setAITopSpeed(carIndex, math.huge)
      --- CarOperations.setAIThrottleLimit(carIndex, 1)
      --- if car.hasTurningLights then ac.setTurningLights(ac.TurningLights.None) end
      --- CarManager.cars_evacuating[carIndex] = nil
    --- end, 6.0)
--- --]=====]
  --- end, 0.6)

--- end)

return CarManager