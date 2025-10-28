local Logger = {}

-- CSP log file at 'Documents\Assetto Corsa\logs\custom_shaders_patch.log'

local APP_NAME_STRING = string.format("[%s]", Constants.APP_NAME)

local getTimestampString = function()
  -- return os.date("%Y-%m-%d %H:%M:%S")
  return string.format("[%s]", os.date("%H:%M:%S"))
end

local getFullMessage = function(msg)
  return string.format("%s %s %s", getTimestampString(), APP_NAME_STRING, msg)
end

---Logs the message to the CSP log
---@param msg string
function Logger.log(msg)
  ac.log(getFullMessage(msg))
end

---Logs the message as a warning to the CSP log
---@param msg string
function Logger.warn(msg)
  ac.warn(getFullMessage(msg))
end

---Logs the message as an error to the CSP log
---@param msg string
function Logger.error(msg)
  ac.error(getFullMessage(msg))
end

return Logger