-- AC_AICarsOvertake.lua
-- Nudge AI to the RIGHT so the player can pass on the LEFT (Trackday / AI Flood).
-- Requires CSP Lua apps enabled. Uses standard CSP Lua API (ac.*, ui.*, render.*, physics.*).

----------------------------------------------------------------------
-- Tunables (live-editable in UI)
----------------------------------------------------------------------
local DETECT_INNER_M        = 42.0   -- start yielding if player within this radius
local DETECT_HYSTERESIS_M   = 60.0   -- keep yielding until distance grows past inner+this
local MIN_PLAYER_SPEED_KMH  = 70.0   -- ignore very low speeds / pit exits
local MIN_SPEED_DELTA_KMH   = 5.0    -- require some closing speed
local YIELD_OFFSET_M        = 2.5    -- desired rightward offset (meters) — very visible
local RAMP_SPEED_MPS        = 4.0    -- how fast offset ramps (m/s)
local CLEAR_AHEAD_M         = 6.0    -- drop yielding once player is this far ahead (longitudinal)
local RIGHT_MARGIN_M        = 0.6    -- keep this much space from right edge when clamping

----------------------------------------------------------------------
-- State
----------------------------------------------------------------------
local enabled, debugDraw, drawOnTop = true, true, true
local ai = {}  -- per-AI memory: [index] = { offset=0.0, yielding=false, dist=0, desired=0, maxRight=0 }

-- Persist UI toggles across unloads (LAZY = FULL)
local S = ac.storage and ac.storage('AC_AICarsOvertake') or nil
if S then
  enabled    = S.enabled    ~= nil and S.enabled    or enabled
  debugDraw  = S.debugDraw  ~= nil and S.debugDraw  or debugDraw
  drawOnTop  = S.drawOnTop  ~= nil and S.drawOnTop  or drawOnTop
end

----------------------------------------------------------------------
-- Small vec helpers
----------------------------------------------------------------------
local function vsub(a,b) return vec3(a.x-b.x, a.y-b.y, a.z-b.z) end
local function vlen(v) return math.sqrt(v.x*v.x + v.y*v.y + v.z*v.z) end
local function dot(a,b) return a.x*b.x + a.y*b.y + a.z*b.z end
local function approach(curr, target, step)
  if math.abs(target - curr) <= step then return target end
  return curr + (target > curr and step or -step)
end

local function isBehind(aiCar, playerCar)
  local fwd = aiCar.look or aiCar.forward or vec3(0,0,1)
  local rel = vsub(playerCar.position, aiCar.position)
  return dot(fwd, rel) < 0
end

local function playerIsClearlyAhead(aiCar, playerCar, meters)
  local fwd = aiCar.look or aiCar.forward or vec3(0,0,1)
  local rel = vsub(playerCar.position, aiCar.position)
  return dot(fwd, rel) > meters
end

----------------------------------------------------------------------
-- Clamp desired rightward offset by available right side width
----------------------------------------------------------------------
local function clampRightOffsetMeters(aiWorldPos, desired)
  if not ac.worldCoordinateToTrackProgress or not ac.getTrackAISplineSides then
    -- Older CSP: trust internal clamping
    return desired
  end
  local prog = ac.worldCoordinateToTrackProgress(aiWorldPos)   -- 0..1 around the lap
  if prog < 0 then return desired end                          -- no spline? trust CSP clamping
  local sides = ac.getTrackAISplineSides(prog)                 -- vec2(left, right) in meters
  local maxRight = math.max(0, (sides.y or 0) - RIGHT_MARGIN_M)
  return math.max(0, math.min(desired, maxRight)), prog, (sides.y or 0)
end

----------------------------------------------------------------------
-- Decide target offset for a single AI
----------------------------------------------------------------------
local function desiredOffsetFor(aiCar, playerCar, wasYielding)
  -- speed sanity
  if playerCar.speedKmh < MIN_PLAYER_SPEED_KMH then return 0 end
  if (playerCar.speedKmh - aiCar.speedKmh) < MIN_SPEED_DELTA_KMH then return 0 end
  if aiCar.speedKmh < 35.0 then return 0 end  -- avoid forcing a line in very slow corners

  -- distance with hysteresis
  local radius = wasYielding and (DETECT_INNER_M + DETECT_HYSTERESIS_M) or DETECT_INNER_M
  local d = vlen(vsub(playerCar.position, aiCar.position))
  if d > radius then return 0, d end

  if not isBehind(aiCar, playerCar) then return 0, d end
  local clamped, prog, rightSide = clampRightOffsetMeters(aiCar.position, YIELD_OFFSET_M)
  -- Return desired and also the distance/progress/side for debugging
  return clamped, d, prog, rightSide
end

----------------------------------------------------------------------
-- CSP entry points
----------------------------------------------------------------------
function script.__init__()
  ac.log('AC_AICarsOvertake: init')
  if S then
    enabled    = S.enabled    ~= nil and S.enabled    or enabled
    debugDraw  = S.debugDraw  ~= nil and S.debugDraw  or debugDraw
    drawOnTop  = S.drawOnTop  ~= nil and S.drawOnTop  or drawOnTop
  end
end

function script.update(dt)
  if not enabled then return end
  -- Guard for older CSP builds where physics helpers might be missing:
  if not physics or not physics.setAISplineAbsoluteOffset then return end  -- meters, + = right; override flag available

  local sim = ac.getSim(); if not sim then return end
  local player = ac.getCar(0); if not player then return end

  -- Iterate AI cars (player is 0)
  for i = 1, (sim.carsCount or 0) - 1 do
    local c = ac.getCar(i)
    if c and c.isAIControlled ~= false then
      ai[i] = ai[i] or { offset = 0.0, yielding = false, dist = 0, desired = 0, maxRight = 0, prog = -1 }

      -- Compute desired state (+ debug metrics)
      local desired, dist, prog, rightSide = desiredOffsetFor(c, player, ai[i].yielding)
      ai[i].dist    = dist or 0
      ai[i].desired = desired or 0
      ai[i].prog    = prog or -1
      ai[i].maxRight= rightSide or 0

      -- If we were yielding and player is clearly ahead, recenter
      if ai[i].yielding and playerIsClearlyAhead(c, player, CLEAR_AHEAD_M) then
        desired = 0.0
      end

      ai[i].yielding = (desired or 0) > 0.01
      ai[i].offset   = approach(ai[i].offset, desired or 0, RAMP_SPEED_MPS * dt)

      -- Apply rightward offset along the AI spline (absolute meters). Third arg overrides AI awareness.
      physics.setAISplineAbsoluteOffset(i, ai[i].offset, true)
    end
  end
end

-- Draw 3D debug markers after main geometry; this is where CSP expects debug shapes.
-- If drawOnTop=true, disable depth test so labels aren’t hidden by cars/bodywork.
function script.draw3D()
  if not debugDraw then return end
  local sim = ac.getSim(); if not sim then return end

  if drawOnTop then
    render.setDepthMode(false, true)   -- no depth test, still write depth
  else
    render.setDepthMode(true, true)    -- default: depth test on
  end

  for i = 1, (sim.carsCount or 0) - 1 do
    local st = ai[i]
    if st and st.offset and st.offset > 0.02 then
      local c = ac.getCar(i)
      if c then
        local txt = string.format("-> %.1fm  (des=%.1f, maxR=%.1f, d=%.1fm)",
          st.offset, st.desired or 0, st.maxRight or 0, st.dist or 0)
        render.debugText(c.position + vec3(0, 2.0, 0), txt)
      end
    end
  end
end

function script.windowMain(dt)
  ui.text('AI Cars Overtake — keep right, pass left')

  -- Immediate-mode checkboxes: toggle only when clicked
  if ui.checkbox('Enabled', enabled) then
    enabled = not enabled
    if S then S.enabled = enabled end
  end
  if ui.checkbox('Debug markers (3D)', debugDraw) then
    debugDraw = not debugDraw
    if S then S.debugDraw = debugDraw end
  end
  if ui.checkbox('Draw markers on top (no depth test)', drawOnTop) then
    drawOnTop = not drawOnTop
    if S then S.drawOnTop = drawOnTop end
  end

  ui.separator()
  -- Sliders return the current numeric value each frame (safe to assign)
  DETECT_INNER_M       = ui.slider('Detect radius (m)', DETECT_INNER_M, 20, 90)
  DETECT_HYSTERESIS_M  = ui.slider('Hysteresis (m)', DETECT_HYSTERESIS_M, 20, 120)
  YIELD_OFFSET_M       = ui.slider('Right offset (m)',  YIELD_OFFSET_M, 0.5, 4.0)
  RIGHT_MARGIN_M       = ui.slider('Right margin (m)',  RIGHT_MARGIN_M, 0.3, 1.2)
  MIN_PLAYER_SPEED_KMH = ui.slider('Min player speed (km/h)', MIN_PLAYER_SPEED_KMH, 40, 160)
  MIN_SPEED_DELTA_KMH  = ui.slider('Min speed delta (km/h)',  MIN_SPEED_DELTA_KMH, 0, 30)
  RAMP_SPEED_MPS       = ui.slider('Offset ramp (m/s)', RAMP_SPEED_MPS, 1.0, 10.0)

  ui.separator()
  ui.text('Cars (Y = yielding):')
  local sim = ac.getSim()
  local player = ac.getCar(0)
  if sim and player then
    for i = 1, (sim.carsCount or 0) - 1 do
      local c = ac.getCar(i)
      local st = ai[i]
      if c and st then
        local flag = st.yielding and "[Y]" or "[ ]"
        local line = string.format(
          "%s #%02d  v=%3dkm/h  d=%5.1fm  off=%4.1f  des=%4.1f  maxR=%4.1f  prog=%.3f",
          flag, i, math.floor(c.speedKmh or 0), st.dist or 0, st.offset or 0, st.desired or 0, st.maxRight or 0, st.prog or -1
        )
        ui.text(line)
      end
    end
  end
end
