local UILateralOffsetsImageWidget = {}

-- ========== CONFIGURABLE CONSTANTS ==========
-- Layout
local PREVIEW_WIDTH              = 360
local PREVIEW_HEIGHT             = 96
local PREVIEW_MARGIN             = 12
local CARD_ROUNDING              = 6
local TRACK_ROUNDING             = 4
local TRACK_HALF_HEIGHT          = 14
local TICK_HEIGHT                = 10
local TICK_HEIGHT_CENTER         = 20

-- Marker (car) shape
local CAR_WIDTH                  = 26
local CAR_HEIGHT                 = 18
local CAR_ROUNDING               = 4
local CAR_NOSE_SIZE              = 6

-- If STACK_MARKERS = true, each marker is drawn on a separate "row" around track midline.
-- Row index is an integer offset from midline: -1 = above, 0 = center, +1 = below (you can use any integers).
local STACK_MARKERS              = true
local ROW_SPACING                = 18            -- pixels between rows
local DEFAULT_ROW_INDEX          = 0             -- e.g., 0   (center)
local YIELDING_ROW_INDEX         = 1             -- e.g., +1  (below)
local OVERTAKE_ROW_INDEX         = -1            -- e.g., -1  (above)

-- If STACK_MARKERS = false, all markers share the same baseline (track midline).
-- You can still nudge captions using CAPTION_OFFSET_Y below.
local CAPTION_OFFSET_Y           = 6             -- pixels below marker to place caption text

-- Colors
local COLOR_CARD_BG              = rgbm(0.08, 0.08, 0.08, 0.90)
local COLOR_CARD_BORDER          = rgbm(0.25, 0.25, 0.25, 1.00)
local COLOR_TRACK_FILL           = rgbm(0.14, 0.14, 0.14, 1.00)
local COLOR_TRACK_BORDER         = rgbm(0.32, 0.32, 0.32, 1.00)
local COLOR_TICK                 = rgbm(0.55, 0.55, 0.55, 1.00)
local COLOR_TEXT                 = rgbm(0.85, 0.85, 0.85, 1.00)
local COLOR_TEXT_MINOR           = rgbm(0.80, 0.80, 0.80, 1.00)
local COLOR_CAR_OUTLINE          = rgbm(0.00, 0.00, 0.00, 0.55)

-- Marker colors
local COLOR_DEFAULT_MARKER       = rgbm(0.20, 0.65, 1.00, 1.00)
local COLOR_YIELDING_MARKER      = rgbm(1.00, 0.70, 0.20, 1.00)
local COLOR_OVERTAKE_MARKER      = rgbm(0.40, 1.00, 0.40, 1.00)

-- Lines/weights
local CENTERLINE_THICKNESS       = 2
local TICK_THICKNESS             = 1
local MARKER_NOSE_THICKNESS      = 2

-- Fonts
local CAPTION_FONT_SIZE          = 11
local LABEL_FONT_SIZE            = 11

-- Labels/toggles
local SHOW_EDGE_LABELS_L0R       = true        -- draw "L", "0", "R"
local SHOW_CAPTIONS              = true        -- draw "Default", "Yielding", "Overtake" under markers
local LABEL_LEFT_TEXT            = "L"
local LABEL_CENTER_TEXT          = "0"
local LABEL_RIGHT_TEXT           = "R"
local CAPTION_DEFAULT_TEXT       = "Default"
local CAPTION_YIELDING_TEXT      = "Yielding"
local CAPTION_OVERTAKE_TEXT      = "Overtake"

local function clampNorm(x)
  if x < -1 then return -1 end
  if x >  1 then return  1 end
  return x
end

-- Map normalized lateral offset [-1..1] to an X pixel within the inner track bar.
local function mapOffsetToX(offsetNormalized, trackLeftX, trackWidth)
  local t = (clampNorm(offsetNormalized) * 0.5) + 0.5   -- -1 → 0, 0 → 0.5, +1 → 1
  return trackLeftX + t * trackWidth
end

-- Draw a simple rounded rectangle “car” with a small “nose” triangle.
local function drawCarMarker(xCenter, midY, color)
  local halfW = CAR_WIDTH * 0.5
  local halfH = CAR_HEIGHT * 0.5
  local p1 = vec2(xCenter - halfW, midY - halfH)
  local p2 = vec2(xCenter + halfW, midY + halfH)

  ui.drawRectFilled(p1, p2, color, CAR_ROUNDING)
  ui.drawRect(p1, p2, COLOR_CAR_OUTLINE, CAR_ROUNDING)

  -- nose pointing “up” to hint forward direction
  local noseY = p1.y - CAR_NOSE_SIZE
  ui.drawLine(vec2(xCenter - CAR_NOSE_SIZE, p1.y), vec2(xCenter, noseY), color, MARKER_NOSE_THICKNESS)
  ui.drawLine(vec2(xCenter + CAR_NOSE_SIZE, p1.y), vec2(xCenter, noseY), color, MARKER_NOSE_THICKNESS)
end

-- Compute baseline Y for a marker based on row index and STACK_MARKERS toggle.
local function rowY(trackMidY, rowIndex)
  if STACK_MARKERS then
    return trackMidY + (rowIndex * ROW_SPACING)
  else
    return trackMidY
  end
end

---@param storage StorageTable
function UILateralOffsetsImageWidget.draw(storage)
  -- Reserve block area from current cursor
  local cursor = ui.getCursor()
  local tl = vec2(cursor.x, cursor.y)
  local br = vec2(cursor.x + PREVIEW_WIDTH, cursor.y + PREVIEW_HEIGHT)

  -- Card
  ui.drawRectFilled(tl, br, COLOR_CARD_BG, CARD_ROUNDING)
  ui.drawRect(tl, br, COLOR_CARD_BORDER, CARD_ROUNDING)

  -- Inner “track” rect
  local trackTL   = vec2(tl.x + PREVIEW_MARGIN, tl.y + PREVIEW_MARGIN)
  local trackBR   = vec2(br.x - PREVIEW_MARGIN, br.y - PREVIEW_MARGIN)
  local trackMidY = (trackTL.y + trackBR.y) * 0.5
  local trackW    = trackBR.x - trackTL.x

  -- Track fill and edges
  ui.drawRectFilled(vec2(trackTL.x, trackMidY - TRACK_HALF_HEIGHT),
                    vec2(trackBR.x, trackMidY + TRACK_HALF_HEIGHT),
                    COLOR_TRACK_FILL, TRACK_ROUNDING)
  ui.drawRect(vec2(trackTL.x, trackMidY - TRACK_HALF_HEIGHT),
              vec2(trackBR.x, trackMidY + TRACK_HALF_HEIGHT),
              COLOR_TRACK_BORDER, TRACK_ROUNDING)

  -- Ticks at -1, -0.5, 0, 0.5, 1
  local ticks = { -1.0, -0.5, 0.0, 0.5, 1.0 }
  for i = 1, #ticks do
    local x = mapOffsetToX(ticks[i], trackTL.x, trackW)
    local h = (math.abs(ticks[i]) < 1e-4) and TICK_HEIGHT_CENTER or TICK_HEIGHT
    local thick = (math.abs(ticks[i]) < 1e-4) and CENTERLINE_THICKNESS or TICK_THICKNESS
    ui.drawLine(vec2(x, trackMidY - h), vec2(x, trackMidY + h), COLOR_TICK, thick)
  end

  -- Edge labels "L | 0 | R"
  if SHOW_EDGE_LABELS_L0R then
    ui.drawTextClipped(LABEL_LEFT_TEXT,
      vec2(trackTL.x - 10, trackMidY - 8), vec2(trackTL.x -  2, trackMidY + 8), COLOR_TEXT_MINOR, nil, false)

    local cx = mapOffsetToX(0, trackTL.x, trackW)
    ui.drawTextClipped(LABEL_CENTER_TEXT,
      vec2(cx - 5, trackMidY - 8), vec2(cx + 5, trackMidY + 8), COLOR_TEXT_MINOR, nil, false)

    ui.drawTextClipped(LABEL_RIGHT_TEXT,
      vec2(trackBR.x +  2, trackMidY - 8), vec2(trackBR.x + 12, trackMidY + 8), COLOR_TEXT_MINOR, nil, false)
  end

  -- Read offsets from storage
  local offDefault   = storage.defaultLateralOffset
  local offYielding  = storage.yieldingLateralOffset
  local offOvertake  = storage.overtakingLateralOffset

  -- Marker positions (X)
  local xDefault  = mapOffsetToX(offDefault,  trackTL.x, trackW)
  local xYielding = mapOffsetToX(offYielding, trackTL.x, trackW)
  local xOvertake = mapOffsetToX(offOvertake, trackTL.x, trackW)

  -- Marker positions (Y) — controlled by the new row index constants
  local yDefault  = rowY(trackMidY, DEFAULT_ROW_INDEX)
  local yYielding = rowY(trackMidY, YIELDING_ROW_INDEX)
  local yOvertake = rowY(trackMidY, OVERTAKE_ROW_INDEX)

  -- Draw markers
  drawCarMarker(xDefault,  yDefault,  COLOR_DEFAULT_MARKER)
  drawCarMarker(xYielding, yYielding, COLOR_YIELDING_MARKER)
  drawCarMarker(xOvertake, yOvertake, COLOR_OVERTAKE_MARKER)

  -- Captions under each marker
  if SHOW_CAPTIONS then
    ui.dwriteDrawText(CAPTION_DEFAULT_TEXT,  CAPTION_FONT_SIZE, vec2(xDefault  - 20, yDefault  + (CAR_HEIGHT * 0.5) + CAPTION_OFFSET_Y), COLOR_TEXT)

    ui.dwriteDrawText(CAPTION_YIELDING_TEXT, CAPTION_FONT_SIZE, vec2(xYielding - 20, yYielding + (CAR_HEIGHT * 0.5) + CAPTION_OFFSET_Y), COLOR_TEXT)

    ui.dwriteDrawText(CAPTION_OVERTAKE_TEXT, CAPTION_FONT_SIZE, vec2(xOvertake - 20, yOvertake + (CAR_HEIGHT * 0.5) + CAPTION_OFFSET_Y), COLOR_TEXT)
  end

  -- Reserve layout space so following UI doesn’t overlap the drawing
  ui.invisibleButton("##lateralPreviewReserve", vec2(PREVIEW_WIDTH, PREVIEW_HEIGHT))
end

return UILateralOffsetsImageWidget
