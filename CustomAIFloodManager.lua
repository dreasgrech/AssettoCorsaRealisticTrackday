local CustomAIFloodManager = {}

--[===[
Andreas: Here I tried to create a custom AI flood manager that cycles AI cars around the main car and the idea is that it's used instead of the built-in CSP AI flood.
         My motivation was because physics.setAITopSpeed() currently does not seem to work on AI cars when on Trackday with AI Flood enabled so I tried to roll my own flood manager.

          But I encountered a major issue with this approach because after the api teleports a car, the car completely stops moving and refuses to budge for an arbitrary amount of time.
          This delay in the AI regaining control of the car seems to match the timer that's used when the AI cars are in the pits in Trackday mode and they wait for some time before joining the track.

          I've tried getting the cars to speed up and regaining control again after teleporting by using various physics api functions like:
            - physics.setGentleStop(carIndex, false)
            - physics.awakeCar(carIndex)
            - physics.setAINoInput(carIndex, false, false)
            - physics.setAICaution(carIndex, 0)
            - physics.setCarFuel(carIndex, 100)
            - physics.engageGear(carIndex, 3)
            - physics.setEngineRPM(carIndex, 5000)

            but the ai cars still refuse to move for a while after being teleported, and because the pedal modulation api doesn't allow me to set absolute pedal values, 
            I can't force the cars the let go of the brake.

            Because of this limitation, I am not able to use this custom flood manager approach
--]===]


--[===[
local distanceBehindPlayerToCycle_meters = 200
local distanceAheadOfPlayerToCycle_meters = 100

local distanceBehindPlayerToCycle_spline = RaceTrackManager.metersToSplineSpan(distanceBehindPlayerToCycle_meters)
local distanceAheadOfPlayerToCycle_spline = RaceTrackManager.metersToSplineSpan(distanceAheadOfPlayerToCycle_meters)

local distanceFromPlayerToSpawnAhead_meters = distanceAheadOfPlayerToCycle_meters * 0.5
local distanceFromPlayerToSpawnAhead_spline = RaceTrackManager.metersToSplineSpan(distanceFromPlayerToSpawnAhead_meters)

local distanceFromPlayerToSpawnBehind_meters = distanceBehindPlayerToCycle_meters * 0.5
local distanceFromPlayerToSpawnBehind_spline = RaceTrackManager.metersToSplineSpan(distanceFromPlayerToSpawnBehind_meters)
--]===]

-- ---https://discord.com/channels/453595061788344330/962668819933982720/1422571156627787806
-- local function GetDirFromSplinePos(splinePosition)
  -- -- local dir = 0.0

  -- -- 1st point on spline
  -- local p1 = ac.trackProgressToWorldCoordinate(splinePosition)

  -- -- add 1 meter for 2nd point to find direction
  -- local spline2 = splinePosition + 1/RaceTrackManager.getTrackLengthMeters()
  -- -- make sure we hit a valid value
  -- if spline2 > 1.0 then spline2 = 0.0 end

  -- -- 2nd point on spline
  -- local p2 = ac.trackProgressToWorldCoordinate(spline2)

  -- -- dir = -math.atan2(p2.z-p1.z, p2.x-p1.x) - math.rad(90)
  -- -- ac.debug("angle in deg:", math.deg(dir) )

  -- -- return dir -- rads
-- end

-- Forward direction of the track at a normalized spline position.
-- Returns a normalized vec3 (or nil if spline is unavailable).
-- Optional stepMeters lets you change the finite-difference step (default 1 m).
local function GetDirFromSplinePos(splinePosition, stepMeters)
  local trackLen = RaceTrackManager.getTrackLengthMeters()

  -- finite-difference step in normalized progress
  local dp = (stepMeters or 1.0) / trackLen

  -- wrap progress safely into [0, 1)
  local p1 = (splinePosition or 0) % 1.0
  local p2 = (p1 + dp) % 1.0

  -- fetch two nearby world points on the spline without extra allocations
  local w1, w2 = vec3(), vec3()
  ac.trackProgressToWorldCoordinateTo(p1, w1)  -- same as ...ToWorldCoordinate but writes into 'w1'
  ac.trackProgressToWorldCoordinateTo(p2, w2)

  -- build tangent and normalize (guard against degenerate length)
  -- local dir = vec3(w2.x - w1.x, w2.y - w1.y, w2.z - w1.z)
  local dir = vec3(w1.x - w2.x, w1.y - w2.y, w1.z - w2.z)
  local len = dir:length()
  if len < 1e-6 then return vec3(0, 0, 0) end
  return dir / len
end

---
---@param car ac.StateCar
---@param newSplinePosition number
CustomAIFloodManager.teleportCar = function(car, newSplinePosition)
    local carIndex = car.index

      local carVelocity = car.velocity

      local worldPosition = ac.trackProgressToWorldCoordinate(newSplinePosition, false)
      -- local direction = car.look -- todo: get correct direction
      local direction = GetDirFromSplinePos(newSplinePosition, 1)
      -- Logger.log(string.format("[CustomAIFloodManager] Moving #%d from spline position %.6f to %.6f behind main car #%d at %.3f.  car splineDistanceAhead: %.3f", carIndex, carSplinePosition, newSplinePosition, mainCar.index, mainCarSplinePosition, splineDistanceAhead))
      -- physics.setCarPosition(car.index, worldPosition, direction)
      CarManager.cars_doNoResetAfterNextCarJump[carIndex] = true
      -- physics.setAICarPosition(carIndex, worldPosition, direction)
      physics.setEngineStallEnabled(carIndex, false)
      physics.setCarPosition(carIndex, worldPosition, direction)
      -- physics.setCarVelocity(carIndex, carVelocity)
      physics.setCarVelocity(carIndex, -(direction * carVelocity:length()))
      CarStateMachine.queueStateTransition(carIndex, CarStateMachine.CarStateType.AFTER_CUSTOMAIFLOOD_TELEPORT)
end

---Cycle the cars around the main car
---@param sortedCarList table<number,ac.StateCar>
---@param sortedCarListMainCarIndex number
CustomAIFloodManager.handleFlood = function(sortedCarList, sortedCarListMainCarIndex)
  local storage = StorageManager.getStorage()
  -- TODO: Andreas: Disabling the custom flood manager for now because of the issues mentioned in the comment at the top of this file
  -- if not storage.customAIFlood_enabled then
  if true then
    return
  end

  local mainCar = sortedCarList[sortedCarListMainCarIndex]
  local mainCarSplinePosition = mainCar.splinePosition

  local totalCars = #sortedCarList
  -- local totalCarsBehindMainCar = sortedCarListMainCarIndex - 1
  -- local totalCarsAheadOfMainCar = totalCars - sortedCarListMainCarIndex
  local totalCarsAheadOfMainCar = sortedCarListMainCarIndex - 1
  local totalCarsBehindMainCar = totalCars - sortedCarListMainCarIndex

  local distanceBehindPlayerToCycle_meters = storage.customAIFlood_distanceBehindPlayerToCycle_meters
  local distanceAheadOfPlayerToCycle_meters = storage.customAIFlood_distanceAheadOfPlayerToCycle_meters

  local distanceBehindPlayerToCycle_spline = RaceTrackManager.metersToSplineSpan(distanceBehindPlayerToCycle_meters)
  local distanceAheadOfPlayerToCycle_spline = RaceTrackManager.metersToSplineSpan(distanceAheadOfPlayerToCycle_meters)

  local distanceFromPlayerToSpawnAhead_meters = distanceAheadOfPlayerToCycle_meters * 0.5
  local distanceFromPlayerToSpawnAhead_spline = RaceTrackManager.metersToSplineSpan(distanceFromPlayerToSpawnAhead_meters)

  local distanceFromPlayerToSpawnBehind_meters = distanceBehindPlayerToCycle_meters * 0.5
  local distanceFromPlayerToSpawnBehind_spline = RaceTrackManager.metersToSplineSpan(distanceFromPlayerToSpawnBehind_meters)

  -- Logger.log(string.format("sortedCarListMainCarIndex: %d, #sortedCarList: %d", sortedCarListMainCarIndex, totalCars))

  -- Logger.log(string.format("[CustomAIFloodManager] Main car #%d at spline position %.6f has %d cars behind and %d cars ahead", mainCar.index, mainCarSplinePosition, totalCarsBehindMainCar, totalCarsAheadOfMainCar))
  -- Logger.log(string.format("sortedCarListMainCarIndex: %d, totalCars: %d, totalCarsBehindMainCar: %d, totalCarsAheadOfMainCar: %d", sortedCarListMainCarIndex, totalCars, totalCarsBehindMainCar, totalCarsAheadOfMainCar))
  -- cars ahead of main car
  -- for i = sortedCarListMainCarIndex+1, totalCars do
  -- for i = 1, sortedCarListMainCarIndex do
  for i = 1, totalCarsAheadOfMainCar do
    local car = sortedCarList[i]
    local carSplinePosition = car.splinePosition
    local splineDistanceAhead = carSplinePosition - mainCarSplinePosition
    -- if splineDistanceAhead < 0 then
      -- splineDistanceAhead = splineDistanceAhead + 1.0
    -- end
    local carIndex = car.index
    -- Logger.log(string.format("[CustomAIFloodManager] Car #%d spline position %.6f is %.6f ahead of main car #%d at %.6f", carIndex, carSplinePosition, splineDistanceAhead, mainCar.index, mainCarSplinePosition))
    if splineDistanceAhead > distanceAheadOfPlayerToCycle_spline then
      -- move this car behind the main car
      local newSplinePosition = mainCarSplinePosition - distanceFromPlayerToSpawnBehind_spline
      -- if newSplinePosition < 0 then
        -- newSplinePosition = newSplinePosition + 1.0
      -- end
      CustomAIFloodManager.teleportCar(car, newSplinePosition)
    end
  end

  --[====[
  -- for i = 1, totalCarsBehindMainCar do
  -- for i = 1, sortedCarListMainCarIndex do 
  for i = sortedCarListMainCarIndex+1, totalCars do
    local car = sortedCarList[i]
    local carSplinePosition = car.splinePosition
    local splineDistanceBehind = mainCarSplinePosition - carSplinePosition
    -- if splineDistanceBehind < 0 then
      -- splineDistanceBehind = splineDistanceBehind + 1.0
    -- end
    Logger.log(string.format("[CustomAIFloodManager] Car #%d spline position %.6f is %.3f behind main car #%d at %.3f", car.index, carSplinePosition, splineDistanceBehind, mainCar.index, mainCarSplinePosition))
    if splineDistanceBehind > distanceBehindPlayerToCycle_spline then
      -- move this car ahead of the main car
      local newSplinePosition = mainCarSplinePosition + distanceFromPlayerToSpawnAhead_spline
      -- if newSplinePosition > 1.0 then
        -- newSplinePosition = newSplinePosition - 1.0
      -- end

      local worldPosition = ac.trackProgressToWorldCoordinate(newSplinePosition, false)
      -- local direction = car.look -- todo: get correct direction
      local direction = GetDirFromSplinePos(newSplinePosition, 1)
      Logger.log(string.format("[CustomAIFloodManager] Moving #%d from spline position %.6f to %.6f ahead of main car #%d at %.3f.  car splineDistanceBehind: %.3f", car.index, carSplinePosition, newSplinePosition, mainCar.index, mainCarSplinePosition, splineDistanceBehind))
      -- physics.setCarPosition(car.index, worldPosition, direction)
      physics.setAICarPosition(car.index, worldPosition, direction)
    end
  end
  --]====]

end

return CustomAIFloodManager