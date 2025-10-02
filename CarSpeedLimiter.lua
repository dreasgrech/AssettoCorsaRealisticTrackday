--[========[
local CarSpeedLimiter = {}

--[===[
Andreas: Here I tried to create a speed limiter that works by modulating throttle and brake pedals directly.
         My motivation was because physics.setAITopSpeed() currently does not seem to work on AI cars when on Trackday with AI Flood enabled.

         But I encountered a major issue with this speed limiter approach because of the way the API offers the pedal modulation functionality.
         When setting a pedal input value, the api chooses the final value to be either your value or the original maximum the AI thinks it should be.
         So because of this, I am unable to reliably limit the speed of AI cars because if the AI thinks it should be at full throttle, it will ignore my throttle reduction.
         I don't understand why the API is designed this way instead of allowing me to set absolute pedal values.
         So because of this limitation, I am not able to use this speed limiter approach.
--]===]

-- Policy:
--   • If speed is ~at the cap → do nothing (deadband).
--   • If slightly above the cap → still do nothing (coast margin / hysteresis) and let drag/engine braking work.
--   • If well above the cap → brake ramps up linearly with overspeed.
--   • If below the cap → throttle ramps up linearly with how far below the cap we are.
--   • Throttle/Brake changes are rate-limited per second and scaled by dt for smoothness.

local _stateByCar = {}  -- remembers per-car pedal outputs between frames: {throttle=0, brake=0}

-- Tunables (km/h bands; pedals in 0..1; slew in units/second)
local Tune = {
  deadband_kmh          = 0.8,    -- ± window around cap where we do nothing (prevents twitch). Deadband reduces chatter. 
  coast_margin_kmh      = 2.0,    -- small overspeed allowed with no braking (hysteresis gap). 
  throttle_ramp_kmh     = 15.0,   -- how far BELOW cap maps throttle from 0 → 1 (linear P mapping).
  brake_ramp_kmh        = 10.0,   -- how far ABOVE cap (beyond coast) maps brake 0 → 1 (linear P mapping).

  throttle_rise_per_s   = 2.0,    -- max throttle increase per second (rate limiting)
  throttle_fall_per_s   = 3.5,    -- max throttle decrease per second
  brake_rise_per_s      = 3.0,    -- max brake increase per second
  brake_fall_per_s      = 5.0,    -- max brake decrease per second
  -- Slew limiting (rate-of-change limiting) is a standard filter to cap how fast a command can change.
}

local function clamp01(x) return (x < 0 and 0) or (x > 1 and 1) or x end

-- Rate-limit "current" toward "target" using asymmetric rise/fall limits scaled by dt.
local function slew_to(current, target, rise_per_s, fall_per_s, dt)
  local max_rise = rise_per_s * dt
  local max_fall = fall_per_s * dt
  local delta = target - current
  if delta > 0 then
    if delta > max_rise then delta = max_rise end
  else
    if -delta > max_fall then delta = -max_fall end
  end
  return current + delta
end

local resetTopSpeedLimiter = function(carIndex)
  _stateByCar[carIndex] = nil
  CarOperations.resetPedalPosition(carIndex, CarOperations.CarPedals.Gas)
  CarOperations.resetPedalPosition(carIndex, CarOperations.CarPedals.Brake)
end

--- Limit top speed by modulating throttle and brake (dt-aware).
--- @param carIndex integer
--- @param maxSpeedKmh number
--- @param dt number   -- seconds since previous call; REQUIRED for correct slew behavior
function CarSpeedLimiter.limitTopSpeed(carIndex, maxSpeedKmh, dt)
  local car = ac.getCar(carIndex)
  if not car or not dt or dt <= 0 then return end

  if maxSpeedKmh == math.huge then
    resetTopSpeedLimiter(carIndex)
    return
  end

  -- Per-car memory (for smooth interpolation)
  local mem = _stateByCar[carIndex]
  if not mem then
    mem = { throttle = 0.0, brake = 0.0 }
    _stateByCar[carIndex] = mem
  end

  local speed_kmh = car.speedKmh or 0.0
  local error_kmh = maxSpeedKmh - speed_kmh  -- +ve: below cap; -ve: above cap

  -- Desired (unsmoothed) pedal commands before rate limiting
  local wanted_throttle, wanted_brake = 0.0, 0.0

  -- Zone 1: near setpoint → do nothing (deadband)
  if math.abs(error_kmh) <= Tune.deadband_kmh then
    wanted_throttle, wanted_brake = 0.0, 0.0

  -- Zone 2: slightly above cap → coast (hysteresis gap)
  elseif error_kmh < 0 and (-error_kmh) <= Tune.coast_margin_kmh then
    wanted_throttle, wanted_brake = 0.0, 0.0

  -- Zone 3: well above cap → ramp brake with overspeed beyond coast margin
  elseif error_kmh < 0 then
    local overspeed = (-error_kmh) - Tune.coast_margin_kmh
    wanted_brake = clamp01(overspeed / Tune.brake_ramp_kmh)
    wanted_throttle = 0.0

  -- Zone 4: below cap → ramp throttle with margin below deadband
  else
    local below = error_kmh - Tune.deadband_kmh
    wanted_throttle = clamp01(below / Tune.throttle_ramp_kmh)
    wanted_brake = 0.0
  end

  -- Rate-limit (slew) for smoothness; scale by dt
  mem.throttle = slew_to(mem.throttle, wanted_throttle, Tune.throttle_rise_per_s, Tune.throttle_fall_per_s, dt)
  mem.brake    = slew_to(mem.brake,    wanted_brake,    Tune.brake_rise_per_s,    Tune.brake_fall_per_s,    dt)

  -- Apply to the sim
  CarOperations.setPedalPosition(carIndex, CarOperations.CarPedals.Gas,   mem.throttle)
  CarOperations.setPedalPosition(carIndex, CarOperations.CarPedals.Brake, mem.brake)
end


return CarSpeedLimiter
--]========]