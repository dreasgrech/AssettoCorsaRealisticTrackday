local Logger = {}

-- CSP log file at 'Documents\Assetto Corsa\logs\custom_shaders_patch.log'

---Logs the message to the CSP log
---@param msg string
function Logger.log(msg)
  ac.log('[' .. Constants.APP_NAME .. '] ' .. msg)
end

---Logs the message as a warning to the CSP log
---@param msg string
function Logger.warn(msg)
  ac.warn('[' .. Constants.APP_NAME .. '] ' .. msg)
end

---Logs the message as an error to the CSP log
---@param msg string
function Logger.error(msg)
  ac.error('[' .. Constants.APP_NAME .. '] ' .. msg)
end

return Logger