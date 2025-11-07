Constants = require("Constants")
Logger = require("Logger")
CSPCompatibilityManager = require("CSPCompatibilityManager")

local cspVersion = CSPCompatibilityManager.getCSPVersion()
Logger.log(string.format("Launching Realistic Trackday v%s.  Custom Shaders Patch: %s", Constants.APP_VERSION, cspVersion))

local showMissingCSPElementsErrorModalDialog = function(message)
  local neededFunctionsForModalDialogAvailable =
    ui.modalDialog ~= nil or
    ui.textWrapped ~= nil or
    ui.newLine ~= nil or
    ui.button ~= nil or
    ac.setClipboardText ~= nil or
    ui.sameLine ~= nil

    if not neededFunctionsForModalDialogAvailable then
      Logger.error(string.format("Cannot show error dialog because some required CSP elements are missing.\nError text: %s", message))
      return
    end

  ui.modalDialog('[Error] Missing CSP elements needed to run Realistic Trackday app', function()
    ui.textColored(message, rgbm(1, 0, 0, 1))
    ui.newLine()
    if ui.modernButton('Copy', vec2(110, 40)) then
      ac.setClipboardText(message) 
    end
    ui.sameLine()
    if ui.modernButton('Close', vec2(120, 40)) then
      return true
    end

    return false
  end, true)
end

-- Check if any CSP elements used by the app are missing
local missingCSPElements = CSPCompatibilityManager.checkForMissingCSPElements()
local anyMissingCSPElements = (#missingCSPElements > 0)
local missingCSPElementsErrorMessage

-- Show an error modal dialog if any CSP elements are missing
if anyMissingCSPElements then
  -- Build the CSP missing elements error message
  missingCSPElementsErrorMessage = "Realistic Trackday may not run as expected because some required Custom Shaders Patch elements are missing."
  missingCSPElementsErrorMessage = missingCSPElementsErrorMessage .. "\n\nThe following CSP elements are needed by the app:\n"
  for _, elementName in ipairs(missingCSPElements) do
      missingCSPElementsErrorMessage = missingCSPElementsErrorMessage .. " - " .. elementName .. "\n"
  end
  missingCSPElementsErrorMessage = missingCSPElementsErrorMessage .. "\nSee the CSP log in \"\\Documents\\Assetto Corsa\\logs\\custom_shaders_patch.log\" for more details."
  missingCSPElementsErrorMessage = missingCSPElementsErrorMessage .. "\n\nTo fix the issue, please make sure you're on the latest version of Custom Shaders Patch (https://www.patreon.com/c/x4fab/posts)"
  missingCSPElementsErrorMessage = missingCSPElementsErrorMessage .. string.format("\n\nYour CSP version is %s", cspVersion)

  -- Log the error to the CSP log as well
  Logger.error(missingCSPElementsErrorMessage)

  -- Show the error modal dialog
  showMissingCSPElementsErrorModalDialog(missingCSPElementsErrorMessage)
end

DequeManager = require("DataStructures.DequeManager")
StackManager = require("DataStructures.StackManager")
QueueManager = require("DataStructures.QueueManager")
CompletableIndexCollectionManager = require("DataStructures.CompletableIndexCollectionManager")

AppIconRenderer = require("AppIconRenderer")
ColorManager = require("ColorManager")
RaceTrackManager = require("RaceTrackManager")
StorageManager = require("StorageManager")
MathHelpers = require("MathHelpers")
CarManager = require("CarManager")
CarOperations = require("CarOperations")
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
UILateralOffsetsImageWidget = require("UILateralOffsetsImageWidget")
UIAppNameVersionWidget = require("UIAppNameVersionWidget")
UIManager = require("UIManager")
SessionDetails = require("SessionDetails")
-- CarSpeedLimiter = require("CarSpeedLimiter")
-- CustomAIFloodManager = require("CustomAIFloodManager")
-- CollisionAvoidanceManager = require("CollisionAvoidanceManager")
FrenetAvoid = require("FrenetAvoid")

SettingsWindow = require("SettingsWindow")

-- bindings
local ac = ac
local ac_getCar = ac.getCar
local ac_getSim = ac.getSim
local ac_iterateCars = ac.iterateCars
local ui = ui
local ui_textColored = ui.textColored
local ui_newLine = ui.newLine
local ui_separator = ui.separator
local ui_button = ui.button
local math = math
local math_min = math.min
local Constants = Constants
local Logger = Logger
local Logger_error = Logger.error
local string = string
local string_format = string.format
local RaceTrackManager = RaceTrackManager
local RaceTrackManager_isSplinePositionInYellowZone = RaceTrackManager.isSplinePositionInYellowZone
local RaceTrackManager_updateYellowFlagZones = RaceTrackManager.updateYellowFlagZones
local AccidentManager = AccidentManager
local AccidentManager_registerCollision = AccidentManager.registerCollision
local AccidentManager_informAboutCarReset = AccidentManager.informAboutCarReset
local AppIconRenderer = AppIconRenderer
local AppIconRenderer_draw = AppIconRenderer.draw
local CameraManager = CameraManager
local CameraManager_getFocusedCarIndex = CameraManager.getFocusedCarIndex
local CarManager = CarManager
local CarManager_ensureDefaults = CarManager.ensureDefaults
local CarManager_saveCarSpeed = CarManager.saveCarSpeed
local CarManager_sortCarListByTrackPosition = CarManager.sortCarListByTrackPosition
local CarOperations = CarOperations
local CarOperations_setAITopSpeed = CarOperations.setAITopSpeed
local CarStateMachine = CarStateMachine
local CarStateMachine_setReasonWhyCantOvertake = CarStateMachine.setReasonWhyCantOvertake
local CarStateMachine_setReasonWhyCantYield = CarStateMachine.setReasonWhyCantYield
local CarStateMachine_updateCar = CarStateMachine.updateCar
local CarStateMachine_handleQueuedAccidents = CarStateMachine.handleQueuedAccidents
local UIManager = UIManager
local UIManager_toggleSettingsWindow = UIManager.toggleSettingsWindow
local UIManager_drawMainWindowLateralOffsetsSection = UIManager.drawMainWindowLateralOffsetsSection
local UIManager_drawUICarList = UIManager.drawUICarList
local UIManager_drawCarStateOverheadText = UIManager.drawCarStateOverheadText
local RaceFlagManager = RaceFlagManager
local RaceFlagManager_setRaceFlag = RaceFlagManager.setRaceFlag
local RaceFlagManager_removeRaceFlag = RaceFlagManager.removeRaceFlag
local SettingsWindow = SettingsWindow
local SettingsWindow_draw = SettingsWindow.draw




-- local ENABLE_CUSTOM_AI_FLOOD_MANAGER = false

local FRENET_DEBUGGING = false
local FRENET_DEBUGGING_CAR_INDEX = 0

local CAN_APP_RUN = Constants.CAN_APP_RUN


local storage = StorageManager.getStorage()
local storage_Debugging = StorageManager.getStorage_Debugging()

local math_huge = math.huge

---
-- Andreas: I tried making this a self-invoked anonymous function but the interpreter didn’t like it
---
local function awake()
  if (not CAN_APP_RUN) then
    Logger.log('App can not run.  Online? ' .. tostring(Constants.IS_ONLINE))
    return
  end

  -- Logger.log('Initializing')
  CarManager_ensureDefaults(0) -- ensure defaults on local player car

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
  for i, car in ac_iterateCars() do
    local carIndex = car.index
    local originalCarAIAggression = car.aiAggression
    local originalCarAILevel = car.aiLevel

    CarManager.cars_ORIGINAL_AI_AGGRESSION[carIndex] = originalCarAIAggression
    -- Logger.log(string.format('Original #%d AI Aggression: %.3f', i, car.aiAggression))

    CarManager.cars_ORIGINAL_AI_DIFFICULTY_LEVEL[carIndex] = originalCarAILevel
    -- Logger.log(string.format('Original #%d AI Difficulty Level: %.3f', i, originalCarAILevel))
  end
end
awake()

local function shouldAppRun()
    -- local storage = StorageManager.getStorage()
    return
        CAN_APP_RUN
        -- and storage.enabled
        and storage.enabled
end

---The callback function for when a car collision event occurs
---@param carIndex integer
OnCarEventManager.OnCarEventExecutions[OnCarEventManager.OnCarEventType.Collision] = function (carIndex)
  -- local storage = StorageManager.getStorage()
  if storage.handleAccidents then
      -- Register an accident for the car collision
      local car = ac_getCar(carIndex)
      if not car then
          Logger_error(string_format('OnCarEventManager: OnCarEventType.Collision called for invalid car index %d', carIndex))
          return
      end

      --[====[
      local accidentIndex = AccidentManager.registerCollision(carIndex, car.collisionPosition, car.collidedWith)
      if not accidentIndex then
          return
      end

      CarStateMachine.informAboutAccident(accidentIndex)
      --]====]
      AccidentManager_registerCollision(carIndex, car.collisionPosition, car.collidedWith)
  end
end

---The callback function for when a car jumped event occurs
---@param carIndex integer
OnCarEventManager.OnCarEventExecutions[OnCarEventManager.OnCarEventType.Jumped] = function (carIndex)
  -- Inform the accident manager about the car reset
  AccidentManager_informAboutCarReset(carIndex)

  -- finally reset all our car data
  if not CarManager.cars_justTeleportedDueToCustomAIFlood[carIndex] then
    CarManager.setInitializedDefaults(carIndex)
  end
end

-- Monitor car collisions so we can register an accident
ac.onCarCollision(-1, function (carIndex)
    if (not shouldAppRun()) then return end
    local car = ac_getCar(carIndex)
    if not car then return end

    OnCarEventManager.enqueueOnCarEvent(OnCarEventManager.OnCarEventType.Collision, carIndex)
end)

-- Monitor flood ai cars cycle event so that we also reset our state
ac.onCarJumped(-1, function(carIndex)
    if (not shouldAppRun()) then return end
    local car = ac_getCar(carIndex)
    if not car then return end

    OnCarEventManager.enqueueOnCarEvent(OnCarEventManager.OnCarEventType.Jumped, carIndex)
end)

---
-- Function defined in manifest.ini
-- wiki: function to be called each frame to draw window content
---
function script.MANIFEST__FUNCTION_MAIN(dt)
  ui_textColored("Realistic Trackday allows you to alter the AI cars' behavior to act more like humans driving during a track day event by yielding to faster cars and overtaking slower cars.", ColorManager.RGBM_Colors.WhiteSmoke)
  ui_newLine(1)

  -- Show the missing CSP elements error message if needed
  if anyMissingCSPElements then
    ui_textColored(missingCSPElementsErrorMessage, rgbm(1, 0, 0, 1))
    ui_newLine(1)
    ui_separator()
    ui_newLine(1)
  end

  AppIconRenderer_draw()

  if ui_button('Modify Settings', vec2(120, 40)) then
    UIManager_toggleSettingsWindow()
  end
  ui_newLine(1)

  -- If the app is not running, show a message and stop drawing further UI
  if (not shouldAppRun()) then
    UIManager.drawAppNotRunningMessageInMainWindow()
    return
  end

  -- ui.text(string.format('AI cars yielding to the %s', RaceTrackManager.TrackSideStrings[RaceTrackManager.getYieldingSide()]))
  -- ui.newLine(1)

  UIManager_drawMainWindowLateralOffsetsSection()

  ui_newLine(1)

  UIManager_drawUICarList()
end

local frenetOffsets = {}

---
-- wiki: called after a whole simulation update
---
function script.MANIFEST__UPDATE(dt)
  if (not shouldAppRun()) then return end

  local sim = ac_getSim()
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

  -- local storage = StorageManager.getStorage()
  -- local playerCar = ac_getCar(0)

  SessionDetails.update(dt)

  -- check if the player is coming up to an accident so we can set a caution flag
  -- local isPlayerComingUpToAccidentIndex = AccidentManager.isCarComingUpToAccident(playerCar, storage.distanceFromAccidentToSeeYellowFlag_meters)
  -- if isPlayerComingUpToAccidentIndex then
  local cameraFocusedCarIndex = CameraManager_getFocusedCarIndex()
  -- Logger.log(string.format("Camera focused car index is %d", cameraFocusedCarIndex or -1))
  local cameraFocusedCar = ac_getCar(cameraFocusedCarIndex)
  if cameraFocusedCar then
    local cameraFocusedCarSplinePosition = cameraFocusedCar.splinePosition
    local isFocusedCarInYellowFlagZone = RaceTrackManager_isSplinePositionInYellowZone(cameraFocusedCarSplinePosition)
    if isFocusedCarInYellowFlagZone then
      RaceFlagManager_setRaceFlag(ac.FlagType.Caution)
    else
      RaceFlagManager_removeRaceFlag()
    end
  end
  -- local playerCarSplinePosition = playerCar.splinePosition
  -- local isPlayerInYellowFlagZone = RaceTrackManager_isSplinePositionInYellowZone(playerCarSplinePosition)
  -- if isPlayerInYellowFlagZone then
    -- RaceFlagManager.setRaceFlag(ac.FlagType.Caution)
  -- else
    -- RaceFlagManager.removeRaceFlag()
  -- end

  -- build the sorted car list and do any per-car operations that doesn't require the sorted list
  ---@type table<integer,ac.StateCar>
  local carList = {}
  for i, car in ac_iterateCars() do
    carList[i] = car

    local carIndex = car.index
    CarManager_ensureDefaults(carIndex) -- Ensure defaults are set if this car hasn't been initialized yet

    CarManager_saveCarSpeed(car)

    -- clear the reason why we can't yield/overtake for this car, we'll re-set it below if needed
    CarStateMachine_setReasonWhyCantYield(carIndex, Strings.StringNames[Strings.StringCategories.ReasonWhyCantYield].None)
    CarStateMachine_setReasonWhyCantOvertake(carIndex, Strings.StringNames[Strings.StringCategories.ReasonWhyCantOvertake].None)

    -- local isCarComingUpToAccident = AccidentManager.isCarComingUpToAccident(car)
    -- if isCarComingUpToAccident then
    -- end
  end
  local sortedCars = CarManager_sortCarListByTrackPosition(carList)

  -- save a reference to the current sorted cars list for other parts of the app to use
  CarManager.currentSortedCarsList = sortedCars

  -- handle any queued accidents before updating the car state machines
  OnCarEventManager.processQueuedEvents()
  CarStateMachine_handleQueuedAccidents() -- todo: check if this can be integrated with the processQueuedEvents() above

  local globalTopSpeedLimitKmh = storage.globalTopSpeedLimitKmh
  if globalTopSpeedLimitKmh == 0 then
    globalTopSpeedLimitKmh = math_huge
  end

  local totalCars = #sortedCars
  for i = 1, totalCars do
    local car = sortedCars[i]
    local carIndex = car.index
    CarManager.sortedCarList_carIndexToSortedIndex[carIndex] = i -- save the mapping of carIndex to sorted list index
    if car.isAIControlled then -- including the player car if it's AI controlled
      -- execute the state machine for this car
      CarStateMachine_updateCar(carIndex, dt, sortedCars, i)--, storage)

      -- local carState = CarStateMachine.getCurrentState(carIndex)
      -- local aiCarCurrentlyYielding = (carState == CarStateMachine.CarStateType.EASING_IN_YIELD) or (carState == CarStateMachine.CarStateType.STAYING_ON_YIELDING_LANE)
      -- CarManager.cars_currentlyYielding[carIndex] = aiCarCurrentlyYielding

      -- Apply the global top speed limit to this car
      local requestedCarTopSpeedLimitKmh = CarManager.cars_aiTopSpeed[carIndex]
      local appliedCarTopSpeedLimitKmh = math_min(requestedCarTopSpeedLimitKmh, globalTopSpeedLimitKmh)
      CarOperations_setAITopSpeed(carIndex, appliedCarTopSpeedLimitKmh)
    end
  end

  -- custom ai flood handling
  -- if ENABLE_CUSTOM_AI_FLOOD_MANAGER then
    -- local localPlayerSortedCarListIndex = CarManager.sortedCarList_carIndexToSortedIndex[0]
    -- CustomAIFloodManager.handleFlood(sortedCars, localPlayerSortedCarListIndex)
  -- end

  RaceTrackManager_updateYellowFlagZones()

  if FRENET_DEBUGGING then
    frenetOffsets = FrenetAvoid.computeOffsetsForAll(sortedCars, dt, frenetOffsets)

    local playerCar = ac_getCar(FRENET_DEBUGGING_CAR_INDEX)
    if playerCar then -- if-block only to satisfty the linter because player 0 car always exists
      --local offset = FrenetAvoid.computeOffset(sortedCars, playerCar, dt)
      local offset = frenetOffsets[FRENET_DEBUGGING_CAR_INDEX+1]
      Logger.log(string_format("Setting player car frenet offset to %.2f", offset))
      CarOperations.driveSafelyToSide(FRENET_DEBUGGING_CAR_INDEX, dt, playerCar, offset, 500, true, false, false)  -- empty storage since we don't need to save anything for the player car
      Logger.log(string_format("Player car frenet offset set to %.2f", offset))
    end
  end

  -- local sessionType = sim.raceSessionType
  -- if sessionType == ac.SessionType.Race then
    -- local isSessionStarted = sim.isSessionStarted
    -- Logger.log(string_format("Race session started: %s", tostring(isSessionStarted)))
  -- end
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
  -- local storage_Debugging = StorageManager.getStorage_Debugging()

  if storage_Debugging.debugDrawSideOfftrack then
    for i, car in ac_iterateCars() do
      local carIndex = car.index
      CarOperations.renderCarSideOffTrack(carIndex)
    end
  end
  UIManager_drawCarStateOverheadText()

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
    local debugCarStateOverheadShowDistance = storage_Debugging.debugCarGizmosDrawistance
    local debugCarStateOverheadShowDistanceSqr = debugCarStateOverheadShowDistance * debugCarStateOverheadShowDistance
    local cameraFocusedCarIndex = CameraManager_getFocusedCarIndex()
    local cameraFocusedCar = ac_getCar(cameraFocusedCarIndex)
    if cameraFocusedCar then
      local cameraFocusedCarPosition = cameraFocusedCar.position
      for i, car in ac_iterateCars() do
        local carIndex = car.index
        local distanceFromCameraFocusedCarToThisCarSqr = MathHelpers.distanceBetweenVec3sSqr(car.position, cameraFocusedCarPosition)
        local isThisCarCloseToCameraFocusedCar = distanceFromCameraFocusedCarToThisCarSqr < debugCarStateOverheadShowDistanceSqr
        if isThisCarCloseToCameraFocusedCar then
          CarOperations.renderCarBlockCheckRays_NEWDoDAPPROACH(carIndex)
        end
      end
    end
  end

  if FRENET_DEBUGGING then
    FrenetAvoid.debugDraw(FRENET_DEBUGGING_CAR_INDEX)
  end


  -- render.setDepthMode(render.DepthMode.Normal)
end

---
-- wiki: function to be called to draw content of corresponding settings window (only with “SETTINGS” flag)
---
function script.MANIFEST__FUNCTION_SETTINGS()
  if (not CAN_APP_RUN) then return end

  SettingsWindow_draw()
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
