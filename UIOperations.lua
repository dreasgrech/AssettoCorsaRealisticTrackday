local UIOperations = {}

local ui = ui
local ui_pushItemWidth = ui.pushItemWidth
local ui_popItemWidth =  ui.popItemWidth
local ui_slider = ui.slider
local ui_itemHovered = ui.itemHovered
local ui_setTooltip = ui.setTooltip
local ui_mouseClicked = ui.mouseClicked
local ui_pushDisabled = ui.pushDisabled
local ui_popDisabled = ui.popDisabled
local ui_getScrollMaxY = ui.getScrollMaxY
local ui_itemRectMin = ui.itemRectMin
local ui_itemRectMax = ui.itemRectMax
local ui_getScrollX = ui.getScrollX
local ui_getScrollY = ui.getScrollY
local ui_windowPos = ui.windowPos
local ui_cursorScreenPos = ui.cursorScreenPos
local ui_setItemAllowOverlap = ui.setItemAllowOverlap
local ui_setCursorScreenPos = ui.setCursorScreenPos
local ui_invisibleButton = ui.invisibleButton
local ui_textLineHeightWithSpacing = ui.textLineHeightWithSpacing
local ui_MouseButton = ui.MouseButton
local string = string
local string_format = string.format
local math = math
local math_max = math.max

---Renders a slider with a tooltip
---@param label string @Slider label.
---@param tooltip string
---@param value refnumber|number @Current slider value.
---@param minValue number? @Default value: 0.
---@param maxValue number? @Default value: 1.
---@param sliderWidth number
---@param labelFormat string|'%.3f'|nil @C-style format string. Default value: `'%.3f'`.
---@param defaultValue number @The default value to reset to on right-click and is shown in the tooltip.
---@return number @Possibly updated slider value.
UIOperations.renderSlider = function(label, tooltip, value, minValue, maxValue, sliderWidth, labelFormat, defaultValue)
    -- set the width of the slider
    ui_pushItemWidth(sliderWidth)

    -- render the slider
    local newValue = ui_slider(label, value, minValue, maxValue, labelFormat)

    -- reset the item width
    ui_popItemWidth()

    tooltip = string_format('%s\n\nDefault: %.2f', tooltip, defaultValue)

    if ui_itemHovered() then
        -- render the tooltip
        ui_setTooltip(tooltip)

        -- reset the slider to default value on right-click
        if ui_mouseClicked(ui_MouseButton.Right) then
            -- Logger.log(string.format('Resetting slider "%s" to default value: %.2f', label, defaultValue))
            newValue = defaultValue
        end
    end

    return newValue
end

--- Creates a disabled section in the UI.
---@param createSection boolean @If true, will create a disabled section.
---@param callback function @Function to call to render the contents of the section.
UIOperations.createDisabledSection = function(createSection, callback)
    if createSection then
        ui_pushDisabled()
    end

    callback()

    if createSection then
        ui_popDisabled()
    end
end

UIOperations.isVerticalScrollVisible = function()
  local scrollMaxY = ui_getScrollMaxY()
  return scrollMaxY > 0
end

-- variables used by addTooltipOnTableColumnHeader to prevent allocations on each call
local addTooltipOverLastItem_scrollPosition = vec2(0,0)
local addTooltipOverLastItem_invisibleButtonPosition = vec2(0,0)
local addTooltipOverLastItem_invisibleButtonSize = vec2(0,0)

-- Andreas: This function is needed because ImGui doesn't have built-in support for tooltips on column headers in tables i.e. ui.itemHovered() after a call to ui.columnSortingHeader() doesn't work.
-- Minimal overlay for column-header tooltips.
-- Uses the header’s own rect AFTER it’s drawn, so IDs/widths match.
---@param text string
---@param idPrefix string
---@param idSuffix integer
UIOperations.addTooltipOnTableColumnHeader =  function (text, idPrefix, idSuffix)
  -- Header rect is returned in window space:
  local itemRectMin = ui_itemRectMin()
  local itemRectMax = ui_itemRectMax()
  local w = math_max(itemRectMax.x - itemRectMin.x, 1)
  local h = math_max(itemRectMax.y - itemRectMin.y, ui_textLineHeightWithSpacing())
  addTooltipOverLastItem_invisibleButtonSize:set(w, h)

  -- capture the current cursor screen position to restore it later, since we're going to move it to draw an invisible button which will capture the hover state
  local previousCursorScreenPosition = ui_cursorScreenPos()

  -- allow the invisible button to be drawn outside the normal item rect so that it can cover the entire column header area
  ui_setItemAllowOverlap()

  -- determine the position of where to place the invisible button which will capture the hover for the tooltip
  local scrollX = ui_getScrollX()
  local scrollY = ui_getScrollY()
  local windowPosition = ui_windowPos()
  addTooltipOverLastItem_scrollPosition:set(scrollX, scrollY)
  addTooltipOverLastItem_invisibleButtonPosition:set(windowPosition):sub(addTooltipOverLastItem_scrollPosition):add(itemRectMin)
  ui_setCursorScreenPos(addTooltipOverLastItem_invisibleButtonPosition)

  -- draw the invisible button over the column header
  ui_invisibleButton(idPrefix..idSuffix, addTooltipOverLastItem_invisibleButtonSize)

  -- show the tooltip if hovered over the invisible button
  if ui_itemHovered() then
    ui_setTooltip(text)
  end

  -- restore previous cursor screen position before we added the invisible button
  ui_setCursorScreenPos(previousCursorScreenPosition)
end

return UIOperations