local Constants = {}

local sim = ac.getSim()

Constants.APP_NAME = "AC_AICarsOvertake"
Constants.IS_ONLINE = sim.isOnlineRace
Constants.CAN_APP_RUN = (not Constants.IS_ONLINE)

return Constants