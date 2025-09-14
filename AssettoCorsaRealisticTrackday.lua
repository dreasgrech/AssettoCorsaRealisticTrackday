DequeManager = require("DataStructures.DequeManager")
StackManager = require("DataStructures.StackManager")
QueueManager = require("DataStructures.QueueManager")
Constants = require("Constants")
ColorManager = require("ColorManager")
RaceTrackManager = require("RaceTrackManager")
Logger = require("Logger")
StorageManager = require("StorageManager")
MathHelpers = require("MathHelpers")
CarOperations = require("CarOperations")
CarManager = require("CarManager")
CameraManager = require("CameraManager")

CarStateMachine = require("CarStateMachine.CarStateMachine")
CarState_DrivingNormally = require("CarStateMachine.States.CarState_DrivingNormally")
CarState_EasingInYield = require("CarStateMachine.States.CarState_EasingInYield")
CarState_StayingOnYieldingLane = require("CarStateMachine.States.CarState_StayingOnYieldingLane")
CarState_EasingOutYield = require("CarStateMachine.States.CarState_EasingOutYield")
CarState_CollidedWithCar = require("CarStateMachine.States.CarState_CollidedWithCar")
CarState_CollidedWithTrack = require("CarStateMachine.States.CarState_CollidedWithTrack")
CarState_AnotherCarCollidedIntoMe = require("CarStateMachine.States.CarState_AnotherCarCollidedIntoMe")
CarState_EasingInOvertake = require("CarStateMachine.States.CarState_EasingInOvertake")
CarState_StayingOnOvertakingLane = require("CarStateMachine.States.CarState_StayingOnOvertakingLane")
CarState_EasingOutOvertake = require("CarStateMachine.States.CarState_EasingOutOvertake")

AccidentManager = require("AccidentManager")
RaceFlagManager = require("RaceFlagManager")
UIManager = require("UIManager")

---
-- Andreas: I tried making this a self-invoked anonymous function but the interpreter didn’t like it
---
local function awake()
  if (not Constants.CAN_APP_RUN) then
    Logger.log('App can not run.  Online? ' .. tostring(Constants.IS_ONLINE))
    return
  end

  -- Logger.log('Initializing')
  CarManager.ensureDefaults(0) -- ensure defaults on local player car
end
awake()

local function shouldAppRun()
    local storage = StorageManager.getStorage()
    return
        Constants.CAN_APP_RUN
        and storage.enabled
end

-- Monitor car collisions so we can register an accident
ac.onCarCollision(-1, function (carIndex)
    local accidentIndex = AccidentManager.registerCollision(carIndex)

    CarStateMachine.informAboutAccident(accidentIndex)
end)

---
-- Function defined in manifest.ini
-- wiki: function to be called each frame to draw window content
---
function script.MANIFEST__FUNCTION_MAIN(dt)
  local storage = StorageManager.getStorage()
  if (not shouldAppRun()) then
    ui.text(string.format('App not running.  Enabled: %s,  Online? %s', tostring(storage.enabled), tostring(Constants.IS_ONLINE)))
    return
  end

  UIManager.drawMainWindowContent()
end

-- Returns car indices sorted by car.splinePosition (ascending)
local function getCarIndicesSortedBySpline()
  local ids = {}
  for carIndex, car in ac.iterateCars() do
    ids[#ids + 1] = carIndex
  end
  table.sort(ids, function(a, b)
    local carA = ac.getCar(a)
    local carB = ac.getCar(b)
    if not carA then
      return true
    elseif not carB then
      return false
    end

    return carA.splinePosition < carB.splinePosition
  end)
  return ids
end

---
-- wiki: called after a whole simulation update
---
function script.MANIFEST__UPDATE(dt)
  if (not shouldAppRun()) then return end

  ----------------------------------------------------------------
  -- local isBlocked, direction, distance = CarOperations.isTargetSideBlocked(0)
  -- if isBlocked then
    -- -- ui.textColored(string.format("Player car side is BLOCKED on %s (distance %.2f m)", tostring(direction), distance or -1), rgbm(1.0, 0.2, 0.2, 1.0))
    -- Logger.log(string.format("Car %d left side is BLOCKED (hit at %s, distance %.2f m)", 0, CarOperations.CarDirectionsStrings[direction], distance or -1))
  -- else
    -- -- ui.textColored("Player car side is clear", rgbm(0.2, 1.0, 0.2, 1.0))
  -- end
  ----------------------------------------------------------------

  local sim = ac.getSim()
  if sim.isPaused then return end

  local storage = StorageManager.getStorage()
  local playerCar = ac.getCar(0)

  -- check if the player is coming up to an accident so we can set a caution flag
  local isPlayerComingUpToAccident = AccidentManager.isCarComingUpToAccident(playerCar)
  if isPlayerComingUpToAccident then
    RaceFlagManager.setRaceFlag(ac.FlagType.Caution)
  else
    RaceFlagManager.removeRaceFlag()
  end

  local sortedCars = CarManager.getCarListSortedByTrackPosition()
  -- save a reference to the current sorted cars list for other parts of the app to use
  CarManager.currentSortedCarsList = sortedCars

  -- local orderedCarsString = ""
  -- for i = 1, #sortedCars do
    -- local car = sortedCars[i]
    -- if not car then break end
    -- orderedCarsString = orderedCarsString .. string.format("%d. #%d, ", i, car.index)
  -- end
  -- Logger.log(string.format("Ordered: %s", orderedCarsString))

  -- for carIndex, car in ac.iterateCars() do
  -- for carIndex = 1, sim.carsCount - 1 do
  -- for i = 1, sim.carsCount - 1 do
  for i = 1, #sortedCars do
    local car = sortedCars[i]
    local carIndex = car.index
    -- if carIndex ~= 0  -- skip the player car since it doesn't need to run the yielding logic
    -- if carIndex ~= -1  -- TODO: NOT SKIPPING PLAYER CAR FOR TESTING PURPOSES
    if car.isAIControlled -- including the player car if it's AI controlled
    then
      CarManager.ensureDefaults(carIndex) -- Ensure defaults are set if this car hasn't been initialized yet

      -- execute the state machine for this car
      CarStateMachine.update(carIndex, dt, sortedCars, i, storage)

      local carState = CarStateMachine.getCurrentState(carIndex)

      local aiCarCurrentlyYielding = (carState == CarStateMachine.CarStateType.EASING_IN_YIELD) or (carState == CarStateMachine.CarStateType.STAYING_ON_YIELDING_LANE)
      CarManager.cars_currentlyYielding[carIndex] = aiCarCurrentlyYielding

      -- local carBehind = sortedCars[i + 1]
      -- if carBehind then
        -- local distanceFromOvertakingCarToYieldingCar = MathHelpers.vlen(MathHelpers.vsub(carBehind.position, car.position))
        local distanceFromOvertakingCarToYieldingCar = MathHelpers.vlen(MathHelpers.vsub(playerCar.position, car.position))
        CarManager.cars_distanceFromPlayerToCar[carIndex] = distanceFromOvertakingCarToYieldingCar
      -- else
        -- CarManager.cars_distanceFromPlayerToCar[carIndex] = 0
      -- end
    end
  end
end

---
-- wiki: called when transparent objects are finished rendering
---
function script.MANIFEST__TRANSPARENT(dt)
  if (not shouldAppRun()) then return end
  local storage = StorageManager.getStorage()
  UIManager.draw3DOverheadText()

  -- render.debugSphere(playerCarPosition, 1, rgbm(1, 0, 0, 1))
  -- render.debugBox(playerCarPosition + vec3(0, 1, 0), vec3(1, 1, 1), rgbm(0, 1, 0, 1))
  -- render.debugCross(playerCarPosition + vec3(0, 2, 0), 1.0, rgbm(0, 0, 1, 1))
  -- render.debugArrow(playerCarPosition + vec3(0, 3, 0), playerCarPosition + vec3(0, 3, 5), 0.7, rgbm(0.2, 0.2, 1.0, 1))
  -- render.debugLine(playerCarPosition + vec3(0, 1, 0), playerCarPosition + vec3(0, 1, 5), rgbm(1.0, 0.2, 0.2, 1))
  -- render.debugLine(playerCarPosition + vec3(0, 0, 0), playerCarPosition + (playerCarSide * 2), rgbm(1.0, 0.2, 0.2, 1))


  -- ----------------------------------------------------------------
  -- -- Draw car block check rays for player car for debugging purposes
  -- CarOperations.drawSideAnchorPoints(0)
  -- local carBlocked, carOnSideDirection, carOnSideDistance = CarOperations.checkIfCarIsBlockedByAnotherCarAndSaveAnchorPoints(0)
  -- if carBlocked then
    -- -- ui.textColored(string.format("Player car side is BLOCKED on %s (distance %.2f m)", tostring(carOnSideDirection), carOnSideDistance or -1), rgbm(1.0, 0.2, 0.2, 1.0))
    -- Logger.log(string.format("Player Car left side is BLOCKED (hit at %s, distance %.2f m)", CarOperations.CarDirectionsStrings[carOnSideDirection], carOnSideDistance or -1))
  -- end
  local car = ac.getCar(0)
  local carIndex = car.index
  local carPosition = car.position
  local carForward  = car.look
  local carLeft     = car.side
  local carUp       = car.up
  local halfAABBSize = CarManager.cars_HALF_AABSIZE[carIndex]
  local p = CarOperations.getSideAnchorPoints(carPosition, carForward, carLeft, carUp, halfAABBSize)  -- returns left/right dirs too
  local sideGap = 1.0
  local leftOffset  = p.leftDirection  * sideGap
  local rightOffset = p.rightDirection * sideGap
  local ray1_pos  = p.rearLeft + leftOffset
  local ray1_dir  = carForward
  local ray1_len  = 6
  local ray2_pos  = p.rearRight + rightOffset
  --local ray2_dir  = p.frontRight + rightOffset
  local ray2_dir  = carForward
  local ray2_len  = 3
  local ray3_pos  = p.frontRight + rightOffset
  local ray3_dir  = p.rearLeft + leftOffset
  local ray3_len  = 5
  CarManager.cars_totalSideBlockRaysData[0] = 3
  -- CarManager.cars_sideBlockRaysData[0] = {
    -- ray1_pos, ray1_dir, ray1_len,
    -- ray2_pos, ray2_dir, ray2_len
  -- }
  CarManager.cars_sideBlockRaysData[0] = {}
  CarManager.cars_sideBlockRaysData[0][0] = ray1_pos
  CarManager.cars_sideBlockRaysData[0][1] = ray1_dir
  CarManager.cars_sideBlockRaysData[0][2] = ray1_len
  CarManager.cars_sideBlockRaysData[0][3] = ray2_pos
  CarManager.cars_sideBlockRaysData[0][4] = ray2_dir
  CarManager.cars_sideBlockRaysData[0][5] = ray2_len
  CarManager.cars_sideBlockRaysData[0][6] = ray3_pos
  CarManager.cars_sideBlockRaysData[0][7] = ray3_dir
  CarManager.cars_sideBlockRaysData[0][8] = ray3_len

  -- CarOperations.renderCarBlockCheckRays_PARALLELLINES(0)
  CarOperations.renderCarBlockCheckRays_NEWDoDAPPROACH(0)
  -- ----------------------------------------------------------------
  


  if storage.debugDraw then
    local sim = ac.getSim()
    -- for carIndex = 1, sim.carsCount - 1 do
    for carIndex, car in ac.iterateCars() do
      -- local carAnchorPoints = CarManager.cars_anchorPoints[carIndex]
      -- if carAnchorPoints then
        -- CarOperations.drawSideAnchorPoints(carIndex)
        CarOperations.renderCarBlockCheckRays(carIndex)
      -- end
    end
  end

  -- render.setDepthMode(render.DepthMode.Normal)
end

---
-- wiki: function to be called to draw content of corresponding settings window (only with “SETTINGS” flag)
---
function script.MANIFEST__FUNCTION_SETTINGS()
  if (not Constants.CAN_APP_RUN) then return end

  UIManager.renderUIOptionsControls()
end

--[=====[ 
---
-- wiki: Called each frame after world matrix traversal ends for each app, even if none of its windows are active. 
-- wiki: Please make sure to not do anything too computationally expensive there (unless app needs it for some reason).
---
function script.update(dt)
  if (not shouldAppRun()) then return end

  -- TODO: We probably don't need these settings checks in here
end
--]=====]

--[=====[ 
---
-- Save when window is closed/hidden as a last resort
-- wiki: function to be called once when window closes
---
function script.MANIFEST__FUNCTION_ON_HIDE()
  if (not shouldAppRun()) then return end
end
--]=====]
