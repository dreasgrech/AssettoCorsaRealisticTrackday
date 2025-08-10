-- PassLeft: nudge AI to the right so the player can pass on the left (Trackday / AI Flood)

-- Tunables (live-editable in UI)
local DETECT_INNER_M        = 42.0   -- start yielding if player within this radius
local DETECT_HYSTERESIS_M   = 60.0   -- stop only after distance grows past inner+this
local MIN_PLAYER_SPEED_KMH  = 70.0   -- don’t try to organize traffic at low speeds
local MIN_SPEED_DELTA_KMH   = 5.0    -- require some closing speed
local YIELD_OFFSET_M        = 2.5    -- desired rightward offset in meters (very obvious)
local RAMP_SPEED_MPS        = 4.0    -- how fast we ramp offset up/down
local CLEAR_AHEAD_M         = 6.0    -- how far ahead (in AI forward direction) until we drop yielding
local RIGHT_MARGIN_M        = 0.6    -- keep this much space from right edge when clamping

local enabled, debugDraw = true, true
local ai = {}

-- Small vec helpers
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

-- Clamp desired rightward offset by available right side width
local function clampRightOffsetMeters(aiWorldPos, desired)
  local prog = ac.worldCoordinateToTrackProgress(aiWorldPos)   -- 0..1 around the lap
  if prog < 0 then return desired end                          -- no spline? trust CSP clamping
  local sides = ac.getTrackAISplineSides(prog)                 -- vec2(left, right) in meters
  local maxRight = math.max(0, (sides.y or 0) - RIGHT_MARGIN_M)
  return math.max(0, math.min(desired, maxRight))
end

-- Decide target offset for a single AI given player state and current AI state
local function desiredOffsetFor(aiCar, playerCar, wasYielding)
  -- speed checks
  if playerCar.speedKmh < MIN_PLAYER_SPEED_KMH then return 0 end
  if (playerCar.speedKmh - aiCar.speedKmh) < MIN_SPEED_DELTA_KMH then return 0 end
  if aiCar.speedKmh < 35.0 then return 0 end  -- avoid forcing a line in very slow corners

  -- distance checks with hysteresis
  local radius = wasYielding and (DETECT_INNER_M + DETECT_HYSTERESIS_M) or DETECT_INNER_M
  local d = vlen(vsub(playerCar.position, aiCar.position))
  if d > radius then return 0 end

  if not isBehind(aiCar, playerCar) then return 0 end
  -- We want a clear and visible move to the right:
  local unclamped = YIELD_OFFSET_M
  return clampRightOffsetMeters(aiCar.position, unclamped)
end

function script.__init__()
  ac.log('PassLeft: init')
end

function script.update(dt)
  if not enabled then return end
  -- Guard for older CSP where physics helpers might be missing:
  if not physics or not physics.setAISplineAbsoluteOffset then return end  -- physics API per SDK stubs :contentReference[oaicite:5]{index=5}

  local sim = ac.getSim(); if not sim then return end
  local player = ac.getCar(0); if not player then return end

  -- Iterate AIs (player is 0)
  for i = 1, (sim.carsCount or 0) - 1 do
    local c = ac.getCar(i)
    if c and c.isAIControlled ~= false then
      ai[i] = ai[i] or { offset = 0.0, yielding = false }

      -- Compute desired state
      local desired = desiredOffsetFor(c, player, ai[i].yielding)

      -- If we were yielding and player is clearly ahead, drop target back to center
      if ai[i].yielding and playerIsClearlyAhead(c, player, CLEAR_AHEAD_M) then
        desired = 0.0
      end

      ai[i].yielding = (desired > 0.01)
      ai[i].offset = approach(ai[i].offset, desired, RAMP_SPEED_MPS * dt)

      -- Apply rightward offset along the AI spline (meters, positive = right)
      physics.setAISplineAbsoluteOffset(i, ai[i].offset, true)  -- override AI awareness for consistency :contentReference[oaicite:6]{index=6}

      if debugDraw and ai[i].offset > 0.02 then
        render.debugText(c.position + vec3(0, 2.0, 0), string.format('→ %.1f m', ai[i].offset))  -- on-track marker :contentReference[oaicite:7]{index=7}
      end
    end
  end
end

function script.windowMain(dt)
  ui.text('Pass Left — keep right, pass left')
  enabled   = ui.checkbox('Enabled', enabled)
  debugDraw = ui.checkbox('Debug markers', debugDraw)
  ui.separator()
  DETECT_INNER_M       = ui.slider('Detect radius (m)', DETECT_INNER_M, 20, 90)     -- sliders per SDK :contentReference[oaicite:8]{index=8}
  DETECT_HYSTERESIS_M  = ui.slider('Hysteresis (m)', DETECT_HYSTERESIS_M, 20, 120)
  YIELD_OFFSET_M       = ui.slider('Right offset (m)',  YIELD_OFFSET_M, 0.5, 4.0)
  RIGHT_MARGIN_M       = ui.slider('Right margin (m)',  RIGHT_MARGIN_M, 0.3, 1.2)
  MIN_PLAYER_SPEED_KMH = ui.slider('Min player speed (km/h)', MIN_PLAYER_SPEED_KMH, 40, 160)
  MIN_SPEED_DELTA_KMH  = ui.slider('Min speed delta (km/h)',  MIN_SPEED_DELTA_KMH, 0, 30)
  RAMP_SPEED_MPS       = ui.slider('Offset ramp (m/s)', RAMP_SPEED_MPS, 1.0, 10.0)
end
