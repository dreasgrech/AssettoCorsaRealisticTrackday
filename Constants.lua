local Constants = {}

local sim = ac.getSim()

Constants.APP_NAME = "RealisticTrackday"
Constants.APP_VERSION = "0.9.8"
Constants.APP_AUTHOR = "dreasgrech"
Constants.APP_ICON_PATH = 'AssettoCorsaRealisticTrackday_Icon.png'
Constants.APP_ICON_SIZE = vec2(128, 128)
Constants.IS_ONLINE = sim.isOnlineRace
Constants.CAN_APP_RUN = (not Constants.IS_ONLINE)
Constants.ENABLE_ACCIDENT_HANDLING_IN_APP = false -- disable accident handling for now since it's still WIP

return Constants