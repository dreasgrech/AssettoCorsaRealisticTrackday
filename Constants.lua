local Constants = {}

local sim = ac.getSim()

Constants.APP_NAME = "RealisticTrackday"
Constants.APP_VERSION = "0.9.5"
Constants.APP_ICON_PATH = 'AssettoCorsaRealisticTrackday_Icon.png'
Constants.APP_ICON_SIZE = vec2(128, 128)
Constants.IS_ONLINE = sim.isOnlineRace
Constants.CAN_APP_RUN = (not Constants.IS_ONLINE)

return Constants