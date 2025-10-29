local UILateralOffsetsImageWidget = {}

local PREVIEW_WIDTH   = 360
local PREVIEW_HEIGHT  = 90
local PREVIEW_MARGIN  = 12
local TICK_H          = 10
local CAR_W           = 26
local CAR_H           = 18
local CAR_ROUNDING    = 4

-- Map normalized lateral offset [-1..1] to an X pixel within the inner track bar
local function __mapOffsetToX(offsetNormalized, trackLeftX, trackWidth)
  if offsetNormalized < -1 then offsetNormalized = -1 end
  if offsetNormalized >  1 then offsetNormalized =  1 end
  -- -1 => left edge, 0 => center, +1 => right edge
  local t = (offsetNormalized * 0.5) + 0.5
  return trackLeftX + t * trackWidth
end

-- Draw a simple rounded rectangle “car” with a small “nose” triangle
local function __drawCarMarker(xCenter, midY, color)
  local p1 = vec2(xCenter - CAR_W * 0.5, midY - CAR_H * 0.5)
  local p2 = vec2(xCenter + CAR_W * 0.5, midY + CAR_H * 0.5)

  ui.drawRectFilled(p1, p2, color, CAR_ROUNDING)          -- rounded body  
  ui.drawRect(p1, p2, rgbm(0, 0, 0, 0.55), CAR_ROUNDING)  -- outline       

  -- simple “nose” pointing upwards so user reads it as car facing forward
  local noseY  = p1.y - 6
  ui.drawLine(vec2(xCenter - 6, p1.y), vec2(xCenter, noseY), color, 2)
  ui.drawLine(vec2(xCenter + 6, p1.y), vec2(xCenter, noseY), color, 2)
end

-- Main preview: track bar with ticks + three car markers
---@param storage StorageTable
function UILateralOffsetsImageWidget.draw(storage)
  -- Reserve block area from current cursor
  local cursor = ui.getCursor()                     -- last-item/cursor helpers  
  local tl = vec2(cursor.x, cursor.y)
  local br = vec2(cursor.x + PREVIEW_WIDTH, cursor.y + PREVIEW_HEIGHT)

  -- Card background
  ui.drawRectFilled(tl, br, rgbm(0.08, 0.08, 0.08, 0.90), 6)
  ui.drawRect(tl, br, rgbm(0.25, 0.25, 0.25, 1.0), 6)

  -- Inner “track” bar
  local trackTL   = vec2(tl.x + PREVIEW_MARGIN, tl.y + PREVIEW_MARGIN)
  local trackBR   = vec2(br.x - PREVIEW_MARGIN, br.y - PREVIEW_MARGIN)
  local trackMidY = (trackTL.y + trackBR.y) * 0.5
  local trackW    = trackBR.x - trackTL.x

  -- Track fill and edges
  ui.drawRectFilled(vec2(trackTL.x, trackMidY - 14), vec2(trackBR.x, trackMidY + 14), rgbm(0.14, 0.14, 0.14, 1), 4)
  ui.drawRect(vec2(trackTL.x, trackMidY - 14), vec2(trackBR.x, trackMidY + 14), rgbm(0.32, 0.32, 0.32, 1), 4)

  -- Centerline & tick marks at -1, -0.5, 0, 0.5, 1
  local ticks = { -1.0, -0.5, 0.0, 0.5, 1.0 }
  for i = 1, #ticks do
    local x = __mapOffsetToX(ticks[i], trackTL.x, trackW)
    local h = (math.abs(ticks[i]) < 1e-4) and (TICK_H * 2) or TICK_H
    ui.drawLine(vec2(x, trackMidY - h), vec2(x, trackMidY + h), rgbm(0.55, 0.55, 0.55, 1), (i == 3) and 2 or 1)
  end

  -- Labels "L | 0 | R" using positioned text calls that actually exist
  ui.drawTextClipped("L", vec2(trackTL.x - 10, trackMidY - 8), vec2(trackTL.x -  2, trackMidY + 8), rgbm(0.8, 0.8, 0.8, 1), nil, false)
  ui.drawTextClipped("0", vec2(__mapOffsetToX(0, trackTL.x, trackW) - 5, trackMidY - 8),
                         vec2(__mapOffsetToX(0, trackTL.x, trackW) + 5, trackMidY + 8), rgbm(0.8, 0.8, 0.8, 1), nil, false)
  ui.drawTextClipped("R", vec2(trackBR.x +  2, trackMidY - 8), vec2(trackBR.x + 12, trackMidY + 8), rgbm(0.8, 0.8, 0.8, 1), nil, false)

  -- Pull offsets from storage (rename these fields if yours differ)
  local offDefault   = storage.defaultLateralOffset   or 0.0
  local offYielding  = storage.yieldingLateralOffset     or -0.5
  local offOvertake  = storage.overtakingLateralOffset  or 0.5

  -- Place markers
  local xDefault  = __mapOffsetToX(offDefault,  trackTL.x, trackW)
  local xYielding = __mapOffsetToX(offYielding, trackTL.x, trackW)
  local xOvertake = __mapOffsetToX(offOvertake, trackTL.x, trackW)

  __drawCarMarker(xDefault,  trackMidY, rgbm(0.20, 0.65, 1.00, 1.0))
  __drawCarMarker(xYielding, trackMidY, rgbm(1.00, 0.70, 0.20, 1.0))
  __drawCarMarker(xOvertake, trackMidY, rgbm(0.40, 1.00, 0.40, 1.0))

  -- Marker captions using positioned DWrite text that exists
  ui.dwriteDrawText("Default",   11, vec2(xDefault  - 20, trackMidY + CAR_H * 0.5 + 6), rgbm(0.85, 0.85, 0.85, 1))
  ui.dwriteDrawText("Yielding",  11, vec2(xYielding - 20, trackMidY + CAR_H * 0.5 + 6), rgbm(0.85, 0.85, 0.85, 1))
  ui.dwriteDrawText("Overtake",  11, vec2(xOvertake - 20, trackMidY + CAR_H * 0.5 + 6), rgbm(0.85, 0.85, 0.85, 1))

  -- Advance layout cursor by reserving the widget area
  ui.invisibleButton("##lateralPreviewReserve", vec2(PREVIEW_WIDTH, PREVIEW_HEIGHT))  -- keeps layout consistent
end

return UILateralOffsetsImageWidget