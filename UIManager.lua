local UIManager = {}

local UI_ELEMENTS = {
    { kind='checkbox', k='enabled',   label='Enabled', tip='Master switch for this app.' },
    { kind='checkbox', k='debugDraw', label='Debug markers (3D)', tip='Shows floating text above AI cars currently yielding.' },
    { kind='checkbox', k='drawOnTop', label='Draw markers on top (no depth test)', tip='If markers are hidden by car bodywork, enable this so text ignores depth testing.' },
    { kind='checkbox', k='YIELD_TO_LEFT', label='Yield to LEFT (instead of RIGHT)', tip='If enabled, AI moves left to let you pass on the right. Otherwise AI moves right so you pass on the left.' },
    { kind='slider',   k='DETECT_INNER_M', label='Detect radius (m)', min=5,  max=90, tip='Start yielding if the player is within this distance AND behind the AI car.' },
    { kind='slider',   k='DETECT_HYSTERESIS_M', label='Hysteresis (m)', min=20, max=120, tip='Extra distance while yielding so AI doesn’t flicker on/off near threshold.' },
    { kind='slider',   k='YIELD_OFFSET_M', label='Side offset (m)', min=0.5, max=4.0, tip='How far to move towards the chosen side when yielding.' },
    { kind='slider',   k='RIGHT_MARGIN_M', label='Edge margin (m)', min=0.3, max=1.2, tip='Safety gap from the outer edge on the chosen side.' },
    { kind='slider',   k='MIN_PLAYER_SPEED_KMH', label='Min player speed (km/h)', min=0, max=160, tip='Ignore very low-speed approaches (pit exits, traffic jams).' },
    { kind='slider',   k='MIN_SPEED_DELTA_KMH',  label='Min speed delta (km/h)', min=0,  max=30, tip='Require some closing speed before asking AI to yield.' },
    { kind='slider',   k='RAMP_SPEED_MPS', label='Offset ramp (m/s)', min=1.0, max=10.0, tip='Ramp speed of offset change.' },
    { kind='slider',   k='RAMP_RELEASE_MPS', label='Offset release (m/s)', min=0.2, max=6.0, tip='How quickly offset returns to center once you’re past the AI.' },
    { kind='slider',   k='LIST_RADIUS_FILTER_M', label='List radius filter (m)', min=0, max=1000, tip='Only show cars within this distance in the list (0 = show all).' },
    { kind='slider',   k='MIN_AI_SPEED_KMH', label='Min AI speed (km/h)', min=0, max=120, tip='Don’t ask AI to yield if its own speed is below this (corners/traffic).' },
}

function UIManager.indicatorStatusText(st)
    local l = st.indLeft
    local r = st.indRight
    local ph = st.indPhase
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
    if st.hasTL == false then indTxt = indTxt .. '(!)' end
    if st.blocked then
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
    SettingsManager._dirty = true
    SettingsManager._autosaveTimer = 0
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
    local st = CarManager.ai[i]
    if st and (math.abs(st.offset or 0) > 0.02 or st.blocked) then
      local c = ac.getCar(i)
      if c then
        local txt = string.format(
          "#%02d d=%5.1fm  v=%3dkm/h  offset=%4.1f",
          i, st.dist, math.floor(c.speedKmh or 0), st.offset or 0
        )
        do
          local indTxt = UIManager.indicatorStatusText(st)
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