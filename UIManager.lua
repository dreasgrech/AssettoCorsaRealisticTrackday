local UIManager = {}

local UI_ELEMENTS = {
    { kind='checkbox', k='enabled',   label='Enabled', tip='Master switch for this app.' },
    { kind='checkbox', k='debugDraw', label='Debug markers (3D)', tip='Shows floating text above AI cars currently yielding.' },
    { kind='checkbox', k='drawOnTop', label='Draw markers on top (no depth test)', tip='If markers are hidden by car bodywork, enable this so text ignores depth testing.' },
    { kind='checkbox', k='yieldToLeft', label='Yield to LEFT (instead of RIGHT)', tip='If enabled, AI moves left to let you pass on the right. Otherwise AI moves right so you pass on the left.' },
    { kind='slider',   k='detectInner_meters', label='Detect radius (m)', min=5,  max=90, tip='Start yielding if the player is within this distance AND behind the AI car.' },
    { kind='slider',   k='detectHysteresis_meters', label='Hysteresis (m)', min=20, max=120, tip='Extra distance while yielding so AI doesn’t flicker on/off near threshold.' },
    { kind='slider',   k='yieldOffset_meters', label='Side offset (m)', min=0.5, max=4.0, tip='How far to move towards the chosen side when yielding.' },
    { kind='slider',   k='rightMargin_meters', label='Edge margin (m)', min=0.3, max=1.2, tip='Safety gap from the outer edge on the chosen side.' },
    { kind='slider',   k='minPlayerSpeed_kmh', label='Min player speed (km/h)', min=0, max=160, tip='Ignore very low-speed approaches (pit exits, traffic jams).' },
    { kind='slider',   k='minSpeedDelta_kmh',  label='Min speed delta (km/h)', min=0,  max=30, tip='Require some closing speed before asking AI to yield.' },
    { kind='slider',   k='rampSpeed_mps', label='Offset ramp (m/s)', min=1.0, max=10.0, tip='Ramp speed of offset change.' },
    { kind='slider',   k='rampRelease_mps', label='Offset release (m/s)', min=0.2, max=6.0, tip='How quickly offset returns to center once you’re past the AI.' },
    { kind='slider',   k='listRadiusFilter_meters', label='List radius filter (m)', min=0, max=1000, tip='Only show cars within this distance in the list (0 = show all).' },
    { kind='slider',   k='minAISpeed_kmh', label='Min AI speed (km/h)', min=0, max=120, tip='Don’t ask AI to yield if its own speed is below this (corners/traffic).' },
}

function UIManager.indicatorStatusText(i)
    local l = CarManager.cars_indLeft[i]
    local r = CarManager.cars_indRight[i]
    local ph = CarManager.cars_indPhase[i]
    local indTxt = '-'
    if l or r then
        if l and r then
            indTxt = ph and 'H*' or 'H'
        elseif l then
            indTxt = ph and 'L*' or 'L'
        else
            indTxt = ph and 'R*' or 'R'
        end
    end
    if CarManager.cars_hasTL[i] == false then indTxt = indTxt .. '(!)' end
    if CarManager.cars_blocked[i] then
        -- explicitly show that we’re not able to move over yet and are slowing to create space
        indTxt = (indTxt ~= '-' and (indTxt .. ' ') or '') .. '(slowing due to yield lane blocked)'
    end
    return indTxt
end

-- Tooltip helper that works across CSP builds
local function tip(text)
    local hovered=false;
    if ui and ui.itemHovered then
        local ok, res=pcall(ui.itemHovered); hovered=ok and res or false
    end

    if not hovered then
        return
    end

    local fn = ui and (ui.setTooltip or ui.tooltip or ui.toolTip)
    if fn then pcall(fn, text); return end
    local b = ui and (ui.beginTooltip or ui.beginItemTooltip)
    local e = ui and (ui.endTooltip or ui.endItemTooltip)
    if b and e and pcall(b) then if ui.textWrapped then ui.textWrapped(text) else ui.text(text) end pcall(e) end
end

-- DEBOUNCED PERSIST: mark dirty and coalesce writes in update()
local function _persist(k, v)
    if SettingsManager.P then SettingsManager.P[k] = v end
    SettingsManager.SETTINGS[k] = v
    SettingsManager.settingsCurrentlyDirty = true
    SettingsManager.autosaveTimer = 0
end

function UIManager.draw3DOverheadText()
  if not SettingsManager.debugDraw then return end
  local sim = ac.getSim(); if not sim then return end
  if SettingsManager.drawOnTop then
    -- draw over everything (no depth testing)
    render.setDepthMode(render.DepthMode.Off)
  else
    -- respect existing depth, don’t write to depth (debug text won’t “punch holes”)
    render.setDepthMode(render.DepthMode.ReadOnlyLessEqual)
  end

  for i = 1, (sim.carsCount or 0) - 1 do
    CarManager.ensureDefaults(i) -- Ensure defaults are set if this car hasn't been initialized yet
    if CarManager.cars_initialized[i] and (math.abs(CarManager.cars_offset[i] or 0) > 0.02 or CarManager.cars_blocked[i]) then
      local c = ac.getCar(i)
      if c then
        local txt = string.format(
          "#%02d d=%5.1fm  v=%3dkm/h  offset=%4.1f",
          i, CarManager.cars_dist[i], math.floor(c.speedKmh or 0), CarManager.cars_offset[i] or 0
        )
        do
          local indTxt = UIManager.indicatorStatusText(i)
          txt = txt .. string.format("  ind=%s", indTxt)
        end
        render.debugText(c.position + vec3(0, 2.0, 0), txt)
      end
    end
  end
end

function UIManager.drawControls()
    for _, e in ipairs(UI_ELEMENTS) do
        local spec = SettingsManager.SETTINGS_SPEC_BY_KEY[e.k]
        if spec then
            if e.kind == 'checkbox' then
                local cur = spec.get()
                if ui.checkbox(e.label, cur) then
                    local new = not cur
                    spec.set(new)
                    _persist(e.k, new)
                end
                tip(e.tip)
            elseif e.kind == 'slider' then
                local cur = spec.get()
                local new = ui.slider(e.label, cur, e.min, e.max)
                if new ~= cur then
                    spec.set(new)
                    _persist(e.k, new)
                end
                tip(e.tip)
            end
        end
    end
end

return UIManager