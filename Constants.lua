local Constants = {}

Constants.APP_NAME = "AC_AICarsOvertake"

local sim = ac.getSim()
Constants.IS_ONLINE = sim.isOnlineRace
Constants.CAN_APP_RUN = (not Constants.IS_ONLINE)

return Constants