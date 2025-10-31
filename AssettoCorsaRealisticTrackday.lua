DequeManager = require("DataStructures.DequeManager")
StackManager = require("DataStructures.StackManager")
QueueManager = require("DataStructures.QueueManager")
CompletableIndexCollectionManager = require("DataStructures.CompletableIndexCollectionManager")

Constants = require("Constants")
Logger = require("Logger")
ColorManager = require("ColorManager")
RaceTrackManager = require("RaceTrackManager")
StorageManager = require("StorageManager")
MathHelpers = require("MathHelpers")
CarOperations = require("CarOperations")
CarManager = require("CarManager")
CameraManager = require("CameraManager")

Strings = require("Strings.Strings")
Strings_ReasonWhyCantYield = require("Strings.Strings_ReasonWhyCantYield")
Strings_ReasonWhyCantOvertake = require("Strings.Strings_ReasonWhyCantOvertake")
Strings_StateExitReason = require("Strings.Strings_StateExitReason")
StringsManager = require("StringsManager")
local OnCarEventManager = require("OnCarEventManager")

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
CarState_NavigatingAroundAccident = require("CarStateMachine.States.CarState_NavigatingAroundAccident")
CarState_DrivingInYellowFlagZone = require("CarStateMachine.States.CarState_DrivingInYellowFlagZone")
CarState_AfterCustomAIFloodTeleport = require("CarStateMachine.States.CarState_AfterCustomAIFloodTeleport")

AccidentManager = require("AccidentManager")
RaceFlagManager = require("RaceFlagManager")
UIManager = require("UIManager")
-- CarSpeedLimiter = require("CarSpeedLimiter")
CustomAIFloodManager = require("CustomAIFloodManager")
CollisionAvoidanceManager = require("CollisionAvoidanceManager")
FrenetAvoid = require("FrenetAvoid")

SettingsWindow = require("SettingsWindow")
UILateralOffsetsImageWidget = require("UILateralOffsetsImageWidget")

local WHILE_WORKING_ON_FRENET = false

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

  -- Logger.log(ac.getTrackFullID())
  -- Logger.log(ac.getSim().raceSessionType)

  local globalStorage = StorageManager.getStorage_Global()
  if not globalStorage.appRanFirstTime then
    Logger.log('First time app run detected.  Showing app windows')
    UIManager.openMainWindow()
    UIManager.openSettingsWindow()

    globalStorage.appRanFirstTime = true
  end

  -- Collect some initial data about all the cars
  for i, car in ac.iterateCars() do
    local carIndex = car.index
    local originalCarAIAggression = car.aiAggression
    CarManager.cars_ORIGINAL_AI_AGGRESSION[carIndex] = originalCarAIAggression
    Logger.log(string.format('Car %d AI Aggression: %.3f', i, car.aiAggression))
  end
end
awake()

local function shouldAppRun()
    local storage = StorageManager.getStorage()
    return
        Constants.CAN_APP_RUN
        and storage.enabled
end

---The callback function for when a car collision event occurs
---@param carIndex integer
OnCarEventManager.OnCarEventExecutions[OnCarEventManager.OnCarEventType.Collision] = function (carIndex)
  local storage = StorageManager.getStorage()
  if storage.handleAccidents then
      -- Register an accident for the car collision
      local car = ac.getCar(carIndex)
      if not car then
          Logger.error(string.format('OnCarEventManager: OnCarEventType.Collision called for invalid car index %d', carIndex))
          return
      end

      --[====[
      local accidentIndex = AccidentManager.registerCollision(carIndex, car.collisionPosition, car.collidedWith)
      if not accidentIndex then
          return
      end

      CarStateMachine.informAboutAccident(accidentIndex)
      --]====]
      AccidentManager.registerCollision(carIndex, car.collisionPosition, car.collidedWith)
  end
end

---The callback function for when a car jumped event occurs
---@param carIndex integer
OnCarEventManager.OnCarEventExecutions[OnCarEventManager.OnCarEventType.Jumped] = function (carIndex)
  -- Inform the accident manager about the car reset
  AccidentManager.informAboutCarReset(carIndex)

  -- finally reset all our car data
  if not CarManager.cars_justTeleportedDueToCustomAIFlood[carIndex] then
    CarManager.setInitializedDefaults(carIndex)
  end
end

-- Monitor car collisions so we can register an accident
ac.onCarCollision(-1, function (carIndex)
    if (not shouldAppRun()) then return end
    local car = ac.getCar(carIndex)
    if not car then return end

    OnCarEventManager.enqueueOnCarEvent(OnCarEventManager.OnCarEventType.Collision, carIndex)
end)

-- Monitor flood ai cars cycle event so that we also reset our state
ac.onCarJumped(-1, function(carIndex)
    if (not shouldAppRun()) then return end
    local car = ac.getCar(carIndex)
    if not car then return end

    OnCarEventManager.enqueueOnCarEvent(OnCarEventManager.OnCarEventType.Jumped, carIndex)
end)

---
-- Function defined in manifest.ini
-- wiki: function to be called each frame to draw window content
---
function script.MANIFEST__FUNCTION_MAIN(dt)

  if ui.button('Modify Settings') then
    UIManager.toggleSettingsWindow()
  end

  ui.newLine(1)
  if (not shouldAppRun()) then
    local storage = StorageManager.getStorage()
    ui.text(string.format('App not running.  Enabled: %s,  Online? %s', tostring(storage.enabled), tostring(Constants.IS_ONLINE)))
    return
  end

  UIManager.drawMainWindowContent()
end

---
-- wiki: called after a whole simulation update
---
function script.MANIFEST__UPDATE(dt)
  if (not shouldAppRun()) then return end

  local sim = ac.getSim()
  if sim.isPaused then return end

  -------------------
  -- physics.setAITopSpeed(6,30)
    -- CarSpeedLimiter.limitTopSpeed(6, 30, dt)
  --[====[
  if true then
    --CarSpeedLimiter.limitTopSpeed(0, 30, dt)
    CarOperations.setPedalPosition(0, CarOperations.CarPedals.Gas, 0.1)
    CarOperations.setPedalPosition(0, CarOperations.CarPedals.Brake, 0.01)
    -- CarOperations.setPedalPosition(0, CarOperations.CarPedals.Clutch, 0.5)
     -- physics.setAIBrakeHint(0, 1)
    return
  end
  --]====]
  -------------------

  local storage = StorageManager.getStorage()
  local playerCar = ac.getCar(0)

  -- check if the player is coming up to an accident so we can set a caution flag
  -- local isPlayerComingUpToAccidentIndex = AccidentManager.isCarComingUpToAccident(playerCar, storage.distanceFromAccidentToSeeYellowFlag_meters)
  -- if isPlayerComingUpToAccidentIndex then
  local cameraFocusedCarIndex = CameraManager.getFocusedCarIndex()
  -- Logger.log(string.format("Camera focused car index is %d", cameraFocusedCarIndex or -1))
  local cameraFocusedCar = ac.getCar(cameraFocusedCarIndex)
  if cameraFocusedCar then
    local cameraFocusedCarSplinePosition = cameraFocusedCar.splinePosition
    local isFocusedCarInYellowFlagZone = RaceTrackManager.isSplinePositionInYellowZone(cameraFocusedCarSplinePosition)
    if isFocusedCarInYellowFlagZone then
      RaceFlagManager.setRaceFlag(ac.FlagType.Caution)
    else
      RaceFlagManager.removeRaceFlag()
    end
  end
  -- local playerCarSplinePosition = playerCar.splinePosition
  -- local isPlayerInYellowFlagZone = RaceTrackManager.isSplinePositionInYellowZone(playerCarSplinePosition)
  -- if isPlayerInYellowFlagZone then
    -- RaceFlagManager.setRaceFlag(ac.FlagType.Caution)
  -- else
    -- RaceFlagManager.removeRaceFlag()
  -- end

  -- build the sorted car list and do any per-car operations that doesn't require the sorted list
  ---@type table<integer,ac.StateCar>
  local carList = {}
  for i, car in ac.iterateCars() do
    carList[i] = car

    local carIndex = car.index
    CarManager.ensureDefaults(carIndex) -- Ensure defaults are set if this car hasn't been initialized yet

    CarManager.saveCarSpeed(car)

    -- clear the reason why we can't yield/overtake for this car, we'll re-set it below if needed
    CarStateMachine.setReasonWhyCantYield(carIndex, Strings.StringNames[Strings.StringCategories.ReasonWhyCantYield].None)
    CarStateMachine.setReasonWhyCantOvertake(carIndex, Strings.StringNames[Strings.StringCategories.ReasonWhyCantOvertake].None)

    -- local isCarComingUpToAccident = AccidentManager.isCarComingUpToAccident(car)
    -- if isCarComingUpToAccident then
    -- end
  end
  local sortedCars = CarManager.sortCarListByTrackPosition(carList)

  -- save a reference to the current sorted cars list for other parts of the app to use
  CarManager.currentSortedCarsList = sortedCars

  -- handle any queued accidents before updating the car state machines
  OnCarEventManager.processQueuedEvents()
  CarStateMachine.handleQueuedAccidents() -- todo: check if this can be integrated with the processQueuedEvents() above

  local totalCars = #sortedCars
  for i = 1, totalCars do
    local car = sortedCars[i]
    local carIndex = car.index
    CarManager.sortedCarList_carIndexToSortedIndex[carIndex] = i -- save the mapping of carIndex to sorted list index
    if car.isAIControlled then -- including the player car if it's AI controlled
      -- execute the state machine for this car
      CarStateMachine.updateCar(carIndex, dt, sortedCars, i, storage)

      -- local carState = CarStateMachine.getCurrentState(carIndex)
      -- local aiCarCurrentlyYielding = (carState == CarStateMachine.CarStateType.EASING_IN_YIELD) or (carState == CarStateMachine.CarStateType.STAYING_ON_YIELDING_LANE)
      -- CarManager.cars_currentlyYielding[carIndex] = aiCarCurrentlyYielding
    end
  end

  -- custom ai flood handling
  local localPlayerSortedCarListIndex = CarManager.sortedCarList_carIndexToSortedIndex[0]
  CustomAIFloodManager.handleFlood(sortedCars, localPlayerSortedCarListIndex)

  RaceTrackManager.updateYellowFlagZones()

  if WHILE_WORKING_ON_FRENET then
    local offset = FrenetAvoid.computeOffset(sortedCars, ac.getCar(0), dt)
    -- physics.setAISplineOffset(0, offset, true)
    CarOperations.driveSafelyToSide(0, dt, ac.getCar(0), offset, 500, true, false)  -- empty storage since we don't need to save anything for the player car
    Logger.log(string.format("Player car frenet offset set to %.2f", offset))
  end
end

--[====[
--Andreas: experimenting with drawing a 3D overhead text label above the player car that respects geometry occlusion
-- a small canvas we’ll draw the string into
local nameplate = ui.ExtraCanvas(256, 64)

-- draw/update the text (do this once now; call again whenever text changes)
local function setNameplate(text, color)
  nameplate:update(function()
    ui.beginTransparentWindow("np", vec2(0,0), vec2(256,64), true, false)
      ui.drawRectFilled(vec2(0,0), vec2(256,64), rgbm(0,0,0,0))     -- fully transparent
      ui.setCursor(vec2(10,10))
      ui.textColored(text, color or rgbm(1,1,1,1))
    ui.endTransparentWindow()
  end)
end

setNameplate("AI #12", rgbm(1,1,1,1))   -- example label; re-call when you want a new string

-- minimal shadered quad descriptor (camera-facing billboard)
local plate = {
  textures = { tx = nameplate },
  shader   = [[ float4 main(PS_IN pin){ return pin.ApplyFog(tx.Sample(samAnisotropic, pin.Tex)); } ]]
}
-- draw after opaque geometry so the depth buffer is ready
render.on('main.root.transparent', function()
  -- Logger.log("Drawing nameplate")
  -- depth: read-only (respect geometry), blend: regular alpha
  render.setDepthMode(render.DepthMode.ReadOnlyLessEqual)
  render.setBlendMode(render.BlendMode.AlphaBlend)

  -- position a little above the car roof; size in meters
  local car = ac.getCar(0)                           -- pick your car index
  local pos = car.position + vec3(0, 1.8, 0)
  plate.pos    = pos
  plate.width  = 0.7                                 -- world width (m)
  plate.height = 0.18                                -- world height (m)
  plate.up     = vec3(0,1,0)                         -- keep upright

  render.shaderedQuad(plate)
end)
--]====]

---
-- wiki: called when transparent objects are finished rendering
---
function script.MANIFEST__TRANSPARENT(dt)
  if (not shouldAppRun()) then return end
  local storage_Debugging = StorageManager.getStorage_Debugging()

  if storage_Debugging.debugDrawSideOfftrack then
    for i, car in ac.iterateCars() do
      local carIndex = car.index
      CarOperations.renderCarSideOffTrack(carIndex)
    end
  end
  UIManager.drawCarStateOverheadText()

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

--[=====[
  local car = ac.getCar(0)
  local carIndex = car.index
  local carPosition = car.position
  local carForward  = car.look
  local carLeft     = car.side
  local carUp       = car.up
  local halfAABBSize = CarManager.cars_HALF_AABSIZE[carIndex]
  local p = CarOperations.getSideAnchorPoints(carPosition, carForward, carLeft, carUp, halfAABBSize)  -- returns left/right dirs too
  local pLeftDirection = p.leftDirection
  local pRightDirection = p.rightDirection
  local pRearLeft  = p.rearLeft
  local pRearRight = p.rearRight
  local sideGap = 1.0
  local leftOffset  = pLeftDirection  * sideGap
  local rightOffset = pRightDirection * sideGap
  local ray1_pos  = pRearLeft + leftOffset
  local ray1_dir  = carForward
  local ray1_len  = (halfAABBSize.z * 2)-- + 3
  local ray2_pos  = pRearRight + rightOffset
  --local ray2_dir  = p.frontRight + rightOffset
  local ray2_dir  = carForward
  local ray2_len  = halfAABBSize.z*2
  CarManager.cars_totalSideBlockRaysData[0] = 2
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

  -- CarOperations.renderCarBlockCheckRays_PARALLELLINES(0)
  CarOperations.renderCarBlockCheckRays_NEWDoDAPPROACH(0)
--]=====]
-- CarOperations.checkIfCarIsBlockedByAnotherCarAndSaveSideBlockRays(0, RaceTrackManager.TrackSide.LEFT)
  -- ----------------------------------------------------------------
  

  if storage_Debugging.debugShowRaycastsWhileDrivingLaterally then
    for i, car in ac.iterateCars() do
      local carIndex = car.index
        CarOperations.renderCarBlockCheckRays_NEWDoDAPPROACH(carIndex)
    end
  end

  if WHILE_WORKING_ON_FRENET then
    FrenetAvoid.debugDraw(0)
  end


  -- render.setDepthMode(render.DepthMode.Normal)
end

---
-- wiki: function to be called to draw content of corresponding settings window (only with “SETTINGS” flag)
---
function script.MANIFEST__FUNCTION_SETTINGS()
  if (not Constants.CAN_APP_RUN) then return end

  SettingsWindow.draw()
end

--[=====[ 
---
-- wiki: Called each frame after world matrix traversal ends for each app, even if none of its windows are active. 
-- wiki: Please make sure to not do anything too computationally expensive there (unless app needs it for some reason).
---
function script.update(dt)
  if (not shouldAppRun()) then return end

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
