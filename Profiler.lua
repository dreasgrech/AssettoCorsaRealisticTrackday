-- Profiler.lua  — hierarchical instrumentation + optional sampling
-- Minimal allocations; safe to leave enabled with few regions.

local Profiler = {
  enabled = true,
  frameIndex = 0,
  root = { name = "[frame]", children = {}, parent = nil, total = 0.0, self = 0.0, calls = 0 },
  stack = {},
  nodes = {},         -- key -> node (for totals)
  showInLuaDebug = true,
  perfKeys = {},      -- name -> small int key for ac.perfFrameBegin/End
  nextPerfKey = 0,

  -- sampling
  sampling = { on = false, hits = {}, totalHits = 0, hookCount = 10000 } -- ~every N VM instructions
}

-- ===== timing helpers =====
local clock = os.preciseClock  -- high precision seconds
-- AC perf graphing helpers
local perfBegin, perfEnd         = ac.perfBegin, ac.perfEnd
local perfFrameBegin, perfFrameEnd = ac.perfFrameBegin, ac.perfFrameEnd
local acdebug = ac.debug

-- Acquire (or create) a node for a path element
local function getChild(parent, name)
  local c = parent.children[name]
  if not c then
    c = { name = name, children = {}, parent = parent, total = 0.0, self = 0.0, calls = 0 }
    parent.children[name] = c
  end
  return c
end

-- ===== public API: instrumentation =====
function Profiler.begin(name)
  if not Profiler.enabled then return end
  local now = clock()
  local parent = Profiler.stack[#Profiler.stack] or Profiler.root
  local node = getChild(parent, name)
  node._t0 = now
  node.calls = node.calls + 1
  -- attribute time spent so far to parent's self (it pauses here)
  parent._last = parent._last or now
  parent.self = parent.self + (now - parent._last)
  Profiler.stack[#Profiler.stack + 1] = node

  -- lightweight aggregated per-frame totals in CSP perf widget
  if Profiler.showInLuaDebug then
    local k = Profiler.perfKeys[name]
    if not k then
      Profiler.nextPerfKey = Profiler.nextPerfKey + 1
      k = Profiler.nextPerfKey
      Profiler.perfKeys[name] = k
    end
    perfFrameBegin(k)  -- accumulate this region’s cost across frame
  end
end

function Profiler.end_(name)
  if not Profiler.enabled then return end
  local now = clock()
  local node = Profiler.stack[#Profiler.stack]
  if not node then return end  -- mismatched; avoid crash in release
  Profiler.stack[#Profiler.stack] = nil

  -- complete node time
  local dt = now - (node._t0 or now)
  node.total = node.total + dt
  -- resume parent "self" timing from now
  local parent = node.parent or Profiler.root
  parent._last = now

  if Profiler.showInLuaDebug then
    local k = Profiler.perfKeys[node.name]
    if k then perfFrameEnd(k) end
  end
end

-- sugar so you can call Profiler["end"](name)
Profiler["end"] = Profiler.end_

function Profiler.beginFrame()
  Profiler.frameIndex = Profiler.frameIndex + 1
  Profiler.root._t0 = clock()
  Profiler.root._last = Profiler.root._t0
  -- clear stack safeguards
  Profiler.stack[1] = nil
end

function Profiler.endFrame()
  local now = clock()
  local root = Profiler.root
  root.self = root.self + (now - (root._last or now))
  root.total = root.total + (now - (root._t0 or now))

  -- optional: emit moving averages to Lua Debug app
  if Profiler.showInLuaDebug then
    -- show overall frame cost
    acdebug("Frame(ms)", (now - root._t0) * 1000.0, 0, 20)
  end

  -- reset transient markers for next frame traversal
  local function clearMarks(n)
    n._t0, n._last = nil, nil
    for _,child in pairs(n.children) do clearMarks(child) end
  end
  clearMarks(root)
end

-- ===== public API: reporting/UI =====
local function flatten(node, out, depth)
  depth = depth or 0
  out[#out+1] = { name = node.name, depth = depth, calls = node.calls, total = node.total, self = node.self }
  for name,child in pairs(node.children) do
    flatten(child, out, depth + 1)
  end
end

function Profiler.getHierarchy()
  local list = {}
  flatten(Profiler.root, list, 0)
  table.sort(list, function(a,b) return a.self > b.self end)
  return list
end

-- Minimal table like Unity’s “Hierarchy” (self ms, total ms, calls)
function Profiler.drawUI()
  local rows = Profiler.getHierarchy()
  ui.childWindow("Profiler", vec2(-1, 200), true, function()
    ui.columns(4, true)

    -- Headers row
    ui.header("Function");   ui.nextColumn()
    ui.header("Self ms");    ui.nextColumn()
    ui.header("Total ms");   ui.nextColumn()
    ui.header("Calls");      ui.nextColumn()   -- advance to first data row

    -- Data rows
    for _, r in ipairs(rows) do
      -- Column 1: function name (indented by depth)
      ui.indent(r.depth * 10)
      ui.text(r.name ~= "" and r.name or "—")
      ui.unindent(r.depth * 10)
      ui.nextColumn()

      -- Column 2: self time (ms)
      ui.text(string.format("%10.3f", r.self * 1000.0))
      ui.nextColumn()

      -- Column 3: total time (ms)
      ui.text(string.format("%10.3f", r.total * 1000.0))
      ui.nextColumn()

      -- Column 4: call count
      ui.text(string.format("%10d", r.calls or 0))
      ui.nextColumn()  -- move to next row
    end

    ui.columns(1, false)
  end)
end


-- ===== sampling (optional, low overhead hotspot finder) =====
local function stackKey()
  local key = {}
  local lvl = 2
  while true do
    local info = debug.getinfo(lvl, "nS")
    if not info then break end
    local name = info.name or "<anon>"
    key[#key+1] = (info.short_src or "?") .. ":" .. (info.linedefined or 0) .. "@" .. name
    lvl = lvl + 1
  end
  return table.concat(key, ";")
end

local function hook()
  local k = stackKey()
  local s = Profiler.sampling
  s.hits[k] = (s.hits[k] or 0) + 1
  s.totalHits = s.totalHits + 1
end

function Profiler.startSampling(instrCount)
  if Profiler.sampling.on then return end
  Profiler.sampling.on = true
  if instrCount then Profiler.sampling.hookCount = instrCount end
  debug.sethook(hook, "", Profiler.sampling.hookCount) -- count hook
end

function Profiler.stopSampling()
  if not Profiler.sampling.on then return end
  debug.sethook()
  Profiler.sampling.on = false
end

function Profiler.getSamplingReport(topN)
  local s = Profiler.sampling
  local arr = {}
  for k, v in pairs(s.hits) do arr[#arr+1] = { k = k, v = v } end
  table.sort(arr, function(a,b) return a.v > b.v end)
  local n = math.min(topN or 20, #arr)
  local out = {}
  for i=1,n do
    local pct = (arr[i].v / (s.totalHits > 0 and s.totalHits or 1)) * 100.0
    out[#out+1] = string.format("%5.1f%%  %s", pct, arr[i].k)
  end
  return out
end

return Profiler
