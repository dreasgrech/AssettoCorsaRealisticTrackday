local Logger = {}

function Logger.log(msg)
  ac.log('[' .. Constants.APP_NAME .. '] ' .. msg)
end

function Logger.warn(msg)
  ac.warn('[' .. Constants.APP_NAME .. '] ' .. msg)
end

function Logger.error(msg)
  ac.error('[' .. Constants.APP_NAME .. '] ' .. msg)
end

return Logger