-- WRITE-OFF / lib/save.lua
-- Writing things down, which is the only thing the company reliably does.

return function(CU)

local U = CU.util
local D = CU.data
local Sv = {}

Sv.dir = "/writeoff-data"

--------------------------------------------------------------------- serialise

local function ser(v, indent)
  indent = indent or ""
  local t = type(v)
  if t == "number" then
    if v ~= v then return "0" end
    if v == math.huge or v == -math.huge then return "0" end
    return string.format("%.6g", v)
  elseif t == "string" then
    return string.format("%q", v)
  elseif t == "boolean" then
    return tostring(v)
  elseif t == "table" then
    local parts = { "{" }
    local inner = indent .. " "
    local n = 0
    for i = 1, #v do
      parts[#parts + 1] = inner .. ser(v[i], inner) .. ","
      n = i
    end
    for k, val in pairs(v) do
      local skip = (type(k) == "number" and k >= 1 and k <= n and math.floor(k) == k)
      if not skip and type(val) ~= "function" then
        local key
        if type(k) == "string" and k:match("^[%a_][%w_]*$") then key = k .. "="
        else key = "[" .. ser(k, inner) .. "]=" end
        parts[#parts + 1] = inner .. key .. ser(val, inner) .. ","
      end
    end
    parts[#parts + 1] = indent .. "}"
    return table.concat(parts, "\n")
  end
  return "nil"
end
Sv.serialise = ser

local function unser(text)
  local chunk
  if loadstring then
    chunk = loadstring("return " .. text)
    if chunk and setfenv then setfenv(chunk, {}) end
  else
    chunk = load("return " .. text, "save", "t", {})
  end
  if not chunk then return nil end
  local ok, result = pcall(chunk)
  if ok then return result end
  return nil
end

--------------------------------------------------------------------- files

local function ensure()
  if fs and not fs.exists(Sv.dir) then fs.makeDir(Sv.dir) end
end

local function writeFile(path, text)
  if fs then
    ensure()
    local f = fs.open(path, "w")
    if not f then return false end
    f.write(text)
    f.close()
    return true
  end
  local f = io.open(path, "w")
  if not f then return false end
  f:write(text)
  f:close()
  return true
end

local function readFile(path)
  if fs then
    if not fs.exists(path) then return nil end
    local f = fs.open(path, "r")
    if not f then return nil end
    local text = f.readAll()
    f.close()
    return text
  end
  local f = io.open(path, "r")
  if not f then return nil end
  local text = f:read("*a")
  f:close()
  return text
end

local function deleteFile(path)
  if fs then
    if fs.exists(path) then fs.delete(path) end
    return
  end
  os.remove(path)
end

Sv.write, Sv.read, Sv.delete = writeFile, readFile, deleteFile

--------------------------------------------------------------------- meta

local function metaPath() return Sv.dir .. "/ledger.dat" end
local function runPath() return Sv.dir .. "/run.dat" end

local DEFAULT_META = {
  attempts = 0, best = 0, deepest = 0, totalScore = 0,
  ledger = {}, seniority = 0,
  settings = { arcade = false, loot = "normal", light = "normal", kit = "full" },
}

-- What each setting actually does, so the screen and the game agree.
Sv.LOOT_LEVELS  = { sparse = 0.6, normal = 1.0, generous = 1.7 }
Sv.LIGHT_LEVELS = { dim = 0.7, normal = 1.0, bright = 1.5 }
Sv.KIT_LEVELS   = { "nothing", "basic", "full" }

-- Published to the rest of the game, which only ever reads them.
function Sv.applySettings(meta)
  local st = (meta and meta.settings) or DEFAULT_META.settings
  CU.settings = {
    arcade = st.arcade and true or false,
    loot   = Sv.LOOT_LEVELS[st.loot or "normal"] or 1,
    light  = Sv.LIGHT_LEVELS[st.light or "normal"] or 1,
    kit    = st.kit or "full",
  }
  return CU.settings
end

function Sv.loadMeta()
  local text = readFile(metaPath())
  if not text then return U.copy(DEFAULT_META) end
  local data = unser(text)
  if type(data) ~= "table" then return U.copy(DEFAULT_META) end
  for k, v in pairs(DEFAULT_META) do
    if data[k] == nil then data[k] = U.copy(v) end
  end
  for k, v in pairs(DEFAULT_META.settings) do
    if data.settings[k] == nil then data.settings[k] = v end
  end
  Sv.applySettings(data)
  return data
end

function Sv.saveMeta(meta)
  return writeFile(metaPath(), ser(meta))
end

-- Starting kit improves slowly with seniority. Nothing dramatic.
function Sv.kitFor(meta)
  local mode = (meta.settings and meta.settings.kit) or "full"
  if mode == "nothing" then return {} end
  if mode == "basic" then
    return { "rag_strip", "hand_torch", "cell" }
  end
  local kit = { "rag_strip", "rag_strip", "hand_torch", "cell", "ration_brick",
                "water_flask", "pipe" }
  local s = meta.seniority or 0
  if s >= 1 then table.insert(kit, "field_dressing") end
  if s >= 2 then table.insert(kit, "painkillers") end
  if s >= 3 then table.insert(kit, "antiseptic") end
  if s >= 4 then table.insert(kit, "tourniquet") end
  if s >= 5 then table.insert(kit, "cutter") end
  if s >= 6 then table.insert(kit, "splint") end
  if s >= 8 then table.insert(kit, "gloves") end
  if s >= 10 then table.insert(kit, "field_dressing") end
  return kit
end

function Sv.record(meta, g)
  meta.attempts = (meta.attempts or 0) + 1
  local score = g:score()
  meta.totalScore = (meta.totalScore or 0) + score
  if score > (meta.best or 0) then meta.best = score end
  if g.stats.maxDepth > (meta.deepest or 0) then meta.deepest = math.floor(g.stats.maxDepth) end
  meta.seniority = math.min(12, math.floor(meta.attempts / 2) + math.floor((meta.deepest or 0) / 600))
  table.insert(meta.ledger, 1, {
    id = g.id,
    name = g.playerName,
    depth = math.floor(g.stats.maxDepth),
    stratum = g.stratumIndex,
    cause = g.extracted and "recovered" or (g.cause or "unrecorded"),
    score = score,
    time = math.floor(g.clock),
  })
  while #meta.ledger > 40 do table.remove(meta.ledger) end
  Sv.saveMeta(meta)
  return meta
end

--------------------------------------------------------------------- run state

local function packInv(inv)
  local out = { slots = {}, flask = U.copy(inv.flask), wear = {}, weapon = nil, light = nil }
  local index = {}
  for i, e in ipairs(inv.slots) do
    index[e] = i
    out.slots[i] = U.copy(e)
  end
  for slot, e in pairs(inv.wear) do out.wear[slot] = index[e] end
  out.weapon = inv.weapon and index[inv.weapon] or nil
  out.light = inv.light and index[inv.light] or nil
  return out
end

local function unpackInv(data)
  local inv = CU.inv.new()
  inv.slots = {}
  for i, e in ipairs(data.slots or {}) do inv.slots[i] = U.copy(e) end
  inv.flask = data.flask or { amount = 0, clean = false }
  inv.wear = {}
  for slot, idx in pairs(data.wear or {}) do
    if inv.slots[idx] then inv.wear[slot] = inv.slots[idx] end
  end
  if data.weapon and inv.slots[data.weapon] then inv.weapon = inv.slots[data.weapon] end
  if data.light and inv.slots[data.light] then inv.light = inv.slots[data.light] end
  return inv
end

local function packSeen(map)
  local out = {}
  for y = 1, map.h do
    local row = map.seen[y]
    if row then
      local cells = {}
      for x = 1, map.w do cells[x] = row[x] and "1" or "0" end
      out[y] = table.concat(cells)
    else
      out[y] = ""
    end
  end
  return out
end

local function unpackSeen(map, packed)
  map.seen = {}
  for y = 1, map.h do
    local str = packed and packed[y] or ""
    if str ~= "" then
      local row = {}
      for x = 1, map.w do
        if str:sub(x, x) == "1" then row[x] = true end
      end
      map.seen[y] = row
    end
  end
end

local function packMap(map)
  return {
    index = map.index, w = map.w, h = map.h, rows = map.rows,
    props = map.props, entities = map.entities, galleries = map.galleries,
    blood = map.blood, dug = map.dug, pods = map.pods,
    spawn = map.spawn, exit = map.exit, depthTop = map.depthTop,
    seen = packSeen(map),
  }
end

local function unpackMap(data)
  local map = {
    index = data.index, w = data.w, h = data.h, rows = data.rows,
    props = data.props or {}, entities = data.entities or {},
    blood = data.blood or {}, dug = data.dug or {}, pods = data.pods or {},
    galleries = data.galleries or {}, spawn = data.spawn, exit = data.exit,
    depthTop = data.depthTop, seen = {},
  }
  map.strat = CU.data.stratum(map.index)
  unpackSeen(map, data.seen)
  return map
end

function Sv.saveRun(g)
  local data = {
    version = 2,
    seed = g.seed, rngState = g.rng.s,
    clock = g.clock, stratumIndex = g.stratumIndex,
    x = g.x, y = g.y, facing = g.facing,
    body = g.body,
    inv = packInv(g.inv),
    map = packMap(g.map),
    stats = g.stats, docsFound = g.docsFound, cargo = g.cargo,
    attempt = g.attempt, id = g.id,
    logLines = {},
  }
  local rows = g.log.lines
  for i = math.max(1, #rows - 24), #rows do
    data.logLines[#data.logLines + 1] = rows[i].text
  end
  return writeFile(runPath(), ser(data))
end

function Sv.hasRun()
  if fs then return fs.exists(runPath()) end
  local f = io.open(runPath(), "r")
  if f then f:close(); return true end
  return false
end

function Sv.loadRun()
  local text = readFile(runPath())
  if not text then return nil end
  local data = unser(text)
  if type(data) ~= "table" or not data.body or not data.map then return nil end
  local g = setmetatable({}, CU.run.Game)
  g.seed = data.seed
  g.rng = U.newRng(data.seed)
  g.rng.s = data.rngState or g.rng.s
  g.clock = data.clock or 0
  g.stratumIndex = data.stratumIndex or 1
  g.x, g.y = data.x or 1, data.y or 1
  g.facing = data.facing or 1
  g.body = data.body
  g.inv = unpackInv(data.inv or {})
  g.map = unpackMap(data.map)
  g.stats = data.stats or {}
  g.docsFound = data.docsFound or {}
  g.cargo = data.cargo or false
  g.attempt = data.attempt or 1
  g.id = data.id or "0000-0000"
  g.over = false
  g.log = CU.ui.newLog()
  for _, line in ipairs(data.logLines or {}) do g.log:add(line, CU.ui.c.dim) end
  g.log:add("Run resumed.", CU.ui.c.accent)
  CU.inv.updateGear(g.inv, g.body)
  return g
end

function Sv.clearRun()
  deleteFile(runPath())
end

CU.save = Sv
return Sv

end
