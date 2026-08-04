-- WRITE-OFF / lib/mapgen.lua
-- Builds one stratum as a 2D side-on map. Ropes are slow and safe. Drops are not.

return function(CU)

local U = CU.util
local D = CU.data
local Tl = CU.tiles
local M = {}

M.W = 80        -- tiles across  (160 m)
M.H = 150       -- tiles down    (300 m)

--------------------------------------------------------------------- loot

function M.rollLoot(pool, tier, rng, count)
  local candidates = {}
  local list = D.LOOT[pool] or D.LOOT.general
  for i = 1, #list do
    local e = list[i]
    if (e.tier or 1) <= tier then
      local w = e.w * (1 + math.max(0, tier - (e.tier or 1)) * -0.06)
      if w > 0.4 then candidates[#candidates + 1] = { w = w, e = e } end
    end
  end
  local out = {}
  for _ = 1, count do
    local sel = rng:weighted(candidates)
    if sel then
      local e = sel.e
      out[#out + 1] = { id = e.id, n = e.n and rng:int(e.n[1], e.n[2]) or 1 }
    end
  end
  return out
end

--------------------------------------------------------------------- access

function M.get(map, x, y)
  if x < 1 or x > map.w or y < 1 or y > map.h then return "#" end
  return map.rows[y]:sub(x, x)
end

function M.set(map, x, y, ch)
  if x < 1 or x > map.w or y < 1 or y > map.h then return end
  local r = map.rows[y]
  map.rows[y] = r:sub(1, x - 1) .. ch .. r:sub(x + 1)
end

function M.key(x, y) return x .. "," .. y end

function M.prop(map, x, y) return map.props[M.key(x, y)] end

--------------------------------------------------------------------- blood

-- Blood pools on the floor under you. It stays where it fell, so a trail of it
-- is both a warning and a record of where you have already been.
M.BLOOD_CAP = 600

function M.addBlood(map, x, y, amount)
  if amount <= 0 then return end
  map.blood = map.blood or {}
  -- prefer the floor under the feet, so it reads as a pool on the ground
  local ty = y
  if Tl.isFloor(M.get(map, x, y + 1)) then ty = y + 1 end
  local k = M.key(x, ty)
  map.blood[k] = math.min(0.5, (map.blood[k] or 0) + amount)
  map.bloodCount = (map.bloodCount or 0) + ((map.blood[k] == amount) and 1 or 0)

  -- keep the table from growing without limit on a very long run
  if (map.bloodCount or 0) > M.BLOOD_CAP then
    local worstKey, worstVal = nil, 1e9
    for kk, vv in pairs(map.blood) do
      if vv < worstVal then worstKey, worstVal = kk, vv end
    end
    if worstKey then map.blood[worstKey] = nil; map.bloodCount = map.bloodCount - 1 end
  end
end

-- A splash, for landings and fights. Spreads over a couple of tiles.
function M.splashBlood(map, x, y, amount, rng)
  M.addBlood(map, x, y, amount)
  for _ = 1, 2 do
    local dx = rng and rng:int(-1, 1) or 0
    if Tl.passable(M.get(map, x + dx, y)) then
      M.addBlood(map, x + dx, y, amount * 0.5)
    end
  end
end

function M.bloodAt(map, x, y)
  return map.blood and map.blood[M.key(x, y)] or nil
end

function M.seen(map, x, y)
  local row = map.seen[y]
  return row and row[x] or false
end

-- Blood you have left on the floor. It stays, so it doubles as a trail back.
function M.addBlood(map, x, y, amount)
  if x < 1 or x > map.w or y < 1 or y > map.h then return end
  map.blood = map.blood or {}
  local k = M.key(x, y)
  local v = (map.blood[k] or 0) + amount
  if v <= 0 then map.blood[k] = nil else map.blood[k] = math.min(4, v) end
end

function M.bloodAt(map, x, y)
  if not map.blood then return 0 end
  return map.blood[M.key(x, y)] or 0
end

-- Progress into a tile you are mining. Cleared when the tile breaks.
function M.digAt(map, x, y)
  if not map.dug then return 0 end
  return map.dug[M.key(x, y)] or 0
end

function M.setDig(map, x, y, n)
  map.dug = map.dug or {}
  map.dug[M.key(x, y)] = n
end

function M.clearDig(map, x, y)
  if map.dug then map.dug[M.key(x, y)] = nil end
end

function M.markSeen(map, x, y)
  map.seen[y] = map.seen[y] or {}
  map.seen[y][x] = true
end

--------------------------------------------------------------------- pods

--[[
  A pod is a sealed shell bolted onto a gallery floor. Doors both sides at body
  height, so it never blocks the way through. Two kinds:

    supply : lockers and boxes nobody has been back for
    trade  : somebody is still living in it, and they will deal

  Both have a thermostat and a decontamination shower, which is the only way to
  clear infection out of every limb at once without spending antibiotics.
]]

function M.podAt(map, x, y)
  for _, p in ipairs(map.pods or {}) do
    if x >= p.x1 and x <= p.x2 and y >= p.y1 and y <= p.y2 then return p end
  end
  return nil
end

function M.insidePod(map, x, y)
  local p = M.podAt(map, x, y)
  if p and x > p.x1 and x < p.x2 and y > p.y1 and y < p.y2 then return p end
  return nil
end

local function spanClear(map, gy, x1, x2)
  for x = x1, x2 do
    for y = gy - 4, gy do
      local ch = M.get(map, x, y)
      local d = Tl.get(ch)
      if d.climb or d.shaft or d.hatch or d.prop or d.fixture then return false end
    end
    -- there has to be a floor under the whole length
    if not Tl.isFloor(M.get(map, x, gy)) then return false end
    -- and headroom for the shell
    for y = gy - 4, gy - 1 do
      if not Tl.passable(M.get(map, x, y)) then return false end
    end
  end
  return true
end

local function makeTrader(map, rng)
  local def = D.TRADERS[rng:int(1, #D.TRADERS)]
  local tier = map.strat.lootTier
  local stock = {}
  local seen = {}
  for _, id in ipairs(def.stock) do
    if D.ITEMS[id] and not seen[id] then
      seen[id] = true
      stock[#stock + 1] = { id = id, n = rng:int(1, 3) }
    end
  end
  for _ = 1, rng:int(3, 5) do
    local roll = M.rollLoot(rng:chance(0.5) and "medical" or "general", tier, rng, 1)[1]
    if roll and not seen[roll.id] then
      seen[roll.id] = true
      stock[#stock + 1] = { id = roll.id, n = roll.n }
    end
  end
  return {
    id = def.id, name = def.name,
    attitude = 46 + rng:int(0, 12),
    scrip = 140 + tier * 70 + rng:int(0, 120),
    stock = stock,
    hostile = false, hugs = 0, haggles = 0, threats = 0, met = false,
  }
end

function M.buildPod(map, rng, gallery, kind)
  local width = rng:int(9, 13)
  local gy = gallery.y
  local tries = 0
  local x1
  while tries < 30 do
    tries = tries + 1
    local candidate = rng:int(gallery.x1 + 1, math.max(gallery.x1 + 1, gallery.x2 - width))
    if candidate + width <= gallery.x2 - 1 and spanClear(map, gy, candidate, candidate + width) then
      x1 = candidate
      break
    end
  end
  if not x1 then return nil end
  local x2 = x1 + width

  -- shell. three tiles of headroom inside, so a person fits standing up.
  for x = x1, x2 do
    M.set(map, x, gy - 4, "B")
    M.set(map, x, gy, "B")
  end
  M.set(map, x1, gy - 3, "B")
  M.set(map, x2, gy - 3, "B")
  for x = x1 + 1, x2 - 1 do M.set(map, x, gy - 3, " ") end
  for y = gy - 2, gy - 1 do
    M.set(map, x1, y, "D")
    M.set(map, x2, y, "D")
    for x = x1 + 1, x2 - 1 do M.set(map, x, y, " ") end
  end

  local pod = { x1 = x1, y1 = gy - 4, x2 = x2, y2 = gy,
                kind = kind, temp = 18, showers = 2 }

  -- what is inside, laid out along the standing row
  local slots = {}
  for x = x1 + 2, x2 - 2 do slots[#slots + 1] = x end
  rng:shuffle(slots)
  local function place(ch)
    local x = table.remove(slots)
    if not x then return nil end
    M.set(map, x, gy - 1, ch)
    return x
  end

  place("Z")            -- thermostat
  place("Y")            -- shower
  place("P")            -- bunk
  place("C")            -- charge post for your lights

  if kind == "trade" then
    pod.trader = makeTrader(map, rng)
    pod.traderX = place("T")
    local c = place("l")
    if c then
      map.props[M.key(c, gy - 1)] = {
        type = "locker", name = "the trader's locker", time = 40, rolls = 2,
        searched = false, emptied = false, pool = "general", locked = true,
      }
    end
  else
    local kinds = { { "m", "medbox", "medical" }, { "l", "locker", "general" },
                    { "t", "toolchest", "tools" }, { "h", "cache", "general" },
                    { "c", "crate", "general" } }
    rng:shuffle(kinds)
    for i = 1, rng:int(3, 4) do
      local k = kinds[i]
      if k then
        local x = place(k[1])
        if x then
          map.props[M.key(x, gy - 1)] = {
            type = k[2], name = "a " .. k[2], time = 45, rolls = 3,
            searched = false, emptied = false, pool = k[3],
          }
        end
      end
    end
  end

  map.pods[#map.pods + 1] = pod
  return pod
end

local function placePods(map, rng)
  map.pods = map.pods or {}
  local chance = 0.34 + map.index * 0.012
  if map.index == 1 then chance = 0.7 end       -- so the first run meets one
  if not rng:chance(chance) then return end
  local order = {}
  for i = 2, #map.galleries - 1 do order[#order + 1] = i end
  rng:shuffle(order)
  local kind = rng:chance(0.55) and "trade" or "supply"
  for _, gi in ipairs(order) do
    if M.buildPod(map, rng, map.galleries[gi], kind) then return end
  end
end

--------------------------------------------------------------------- generation

local FLOOR_MIX = {
  { w = 58, ch = "#" },
  { w = 14, ch = "%" },
  { w = 10, ch = "o" },
  { w = 8,  ch = '"' },
  { w = 6,  ch = "^" },
}

local function pickFloor(rng, strat)
  local pool = {}
  for _, e in ipairs(FLOOR_MIX) do
    local w = e.w
    if strat.floorBias and strat.floorBias[e.ch] then w = w * strat.floorBias[e.ch] end
    pool[#pool + 1] = { w = w, ch = e.ch }
  end
  return rng:weighted(pool).ch
end

function M.generate(index, rng)
  local strat = D.stratum(index)
  local w, h = M.W, M.H
  local grid = {}
  for y = 1, h do
    local row = {}
    for x = 1, w do row[x] = "#" end
    grid[y] = row
  end

  local function put(x, y, ch)
    if x >= 1 and x <= w and y >= 1 and y <= h then grid[y][x] = ch end
  end
  local function at(x, y)
    if x < 1 or x > w or y < 1 or y > h then return "#" end
    return grid[y][x]
  end

  -- 1. stack of galleries down the map
  local galleries = {}
  local y = 7
  local lastX1, lastX2 = 6, w - 5
  while y < h - 8 do
    local span = rng:int(30, 58)
    local x1 = U.clamp(lastX1 + rng:int(-16, 16), 3, w - span - 3)
    local x2 = math.min(w - 3, x1 + span)
    -- keep an overlap with the gallery above so a connector can always be placed
    if x2 < lastX1 + 8 then x1 = lastX1; x2 = math.min(w - 3, x1 + span) end
    if x1 > lastX2 - 8 then x2 = lastX2; x1 = math.max(3, x2 - span) end

    local headroom = rng:int(4, 6)
    for x = x1, x2 do
      for hy = y - headroom, y - 1 do put(x, hy, " ") end
    end
    -- floor material in runs, so surfaces are readable rather than noise
    local x = x1
    while x <= x2 do
      local run = rng:int(3, 11)
      local ch = pickFloor(rng, strat)
      for i = 0, run - 1 do
        if x + i <= x2 then put(x + i, y, ch) end
      end
      x = x + run
    end
    -- water sits in a carved basin so it has depth
    if rng:chance(0.35) then
      local px = rng:int(x1 + 2, math.max(x1 + 2, x2 - 8))
      local pw = rng:int(4, 9)
      local pd = rng:int(1, 2)
      for i = 0, pw - 1 do
        for dy = 0, pd - 1 do put(px + i, y - dy, "~") end
        put(px + i, y + 1, "#")
      end
    end

    galleries[#galleries + 1] = { y = y, x1 = x1, x2 = x2, head = headroom }
    lastX1, lastX2 = x1, x2
    y = y + rng:int(9, 15)
  end

  local spawnXGuess = math.floor((galleries[1].x1 + galleries[1].x2) / 2)

  -- 2. connectors. every gallery keeps a clean walking corridor from the point
  --    you arrive at to the rope you leave by, so there is always a safe route
  --    down. open drops are cut outside that corridor, where taking one is a
  --    choice rather than the only option.
  local corridor = {}
  local arriveX = spawnXGuess
  for i = 1, #galleries - 1 do
    local a, b = galleries[i], galleries[i + 1]
    local lo = math.max(a.x1 + 1, b.x1 + 1)
    local hi = math.min(a.x2 - 1, b.x2 - 1)
    if lo > hi then
      lo = math.max(a.x1 + 1, b.x1 + 1)
      hi = math.max(lo, math.min(a.x2 - 1, b.x2 - 1))
    end
    local ropeX = rng:int(lo, math.max(lo, hi))
    for cy = a.y, b.y - 1 do put(ropeX, cy, "|") end

    local c1 = math.min(arriveX, ropeX) - 1
    local c2 = math.max(arriveX, ropeX) + 1
    corridor[i] = { x1 = c1, x2 = c2 }
    a.corridor = corridor[i]
    a.ropeX = ropeX

    -- open drops, only outside the corridor
    -- wide holes now, so the whole span has to clear the corridor, not just
    -- its left edge. otherwise a five tile drop eats the safe route.
    local drops = rng:int(0, 2)
    for _ = 1, drops do
      local wide = rng:int(3, 5)
      local slots = {}
      for x = a.x1 + 1, a.x2 - wide do
        if (x + wide - 1) < c1 - 1 or x > c2 + 1 then slots[#slots + 1] = x end
      end
      if #slots == 0 then break end
      local dx = slots[rng:int(1, #slots)]
      for k = 0, wide - 1 do
        for cy = a.y, b.y - 1 do put(dx + k, cy, " ") end
      end
    end

    arriveX = ropeX
  end
  galleries[#galleries].corridor = { x1 = arriveX - 1, x2 = arriveX + 1 }

  -- 3. one long shaft, sometimes. this is where a real fall comes from.
  --    it is never cut through a gallery's safe corridor.
  if #galleries > 5 and rng:chance(0.7) then
    local start = rng:int(1, math.max(1, #galleries - 4))
    local depth = rng:int(3, math.min(7, #galleries - start))
    local top, bot = galleries[start], galleries[start + depth]
    local lo = math.max(top.x1 + 2, bot.x1 + 2)
    local hi = math.min(top.x2 - 3, bot.x2 - 3)
    local choices = {}
    for x = lo, hi do
      local clear = true
      for gi = start, start + depth do
        local co = galleries[gi].corridor
        if co and x >= co.x1 - 1 and x <= co.x2 + 2 then clear = false end
      end
      if clear then choices[#choices + 1] = x end
    end
    if #choices > 0 then
      local sx = choices[rng:int(1, #choices)]
      for cy = top.y, bot.y - 1 do
        put(sx, cy, " ")
        put(sx + 1, cy, " ")
      end
      local floorCh = rng:weighted({
        { w = 4, ch = "#" }, { w = 3, ch = "^" }, { w = 2, ch = "o" },
        { w = 3, ch = '"' }, { w = 2, ch = "~" },
      }).ch
      put(sx, bot.y, floorCh)
      put(sx + 1, bot.y, floorCh)
      if floorCh == "~" then
        put(sx, bot.y - 1, "~"); put(sx + 1, bot.y - 1, "~")
        put(sx, bot.y + 1, "#"); put(sx + 1, bot.y + 1, "#")
      end
    end
  end

  -- 4. the way out, at the bottom
  local last = galleries[#galleries]
  local co = last.corridor or { x1 = last.x1 + 2, x2 = last.x2 - 2 }
  local exitX = U.clamp(co.x1 + rng:int(0, math.max(0, co.x2 - co.x1)),
                        last.x1 + 1, last.x2 - 1)
  put(exitX, last.y, index >= 11 and "A" or "V")

  -- 5. spawn, at the top
  local first = galleries[1]
  local spawnX = spawnXGuess
  for x = spawnX - 1, spawnX + 1 do
    if at(x, first.y) == "^" or at(x, first.y) == "~" then put(x, first.y, "#") end
    for hy = first.y - 3, first.y - 1 do put(x, hy, " ") end
  end

  -- freeze rows to strings
  local rows = {}
  for gy = 1, h do rows[gy] = table.concat(grid[gy]) end

  local map = {
    index = index, strat = strat, w = w, h = h, rows = rows,
    props = {}, seen = {}, entities = {}, blood = {}, dug = {}, pods = {}, blood = {}, bloodCount = 0,
    galleries = galleries,
    spawn = { x = spawnX, y = first.y - 1 },
    exit = { x = exitX, y = last.y },
    depthTop = (index - 1) * (M.H * Tl.METRES_PER_TILE),
  }

  map.pods = {}
  placePods(map, rng)
  M.populate(map, rng)
  return map
end

--------------------------------------------------------------------- contents

local PROP_CHARS = {
  { w = 22, ch = "d", kind = "debris" },
  { w = 16, ch = "c", kind = "crate" },
  { w = 12, ch = "b", kind = "corpse" },
  { w = 12, ch = "l", kind = "locker" },
  { w = 10, ch = "t", kind = "toolchest" },
  { w = 10, ch = "m", kind = "medbox" },
  { w = 8,  ch = "g", kind = "growth" },
  { w = 4,  ch = "h", kind = "cache" },
}

local CONTAINER_BY_KIND = {}

function M.populate(map, rng)
  local strat = map.strat
  for kind, _ in pairs({}) do end
  if not CONTAINER_BY_KIND.debris then
    for _, c in ipairs(D.CONTAINERS) do CONTAINER_BY_KIND[c.id] = c end
  end

  local function standable(x, y)
    -- room for a two tile body, with a floor under it
    return Tl.passable(M.get(map, x, y)) and Tl.passable(M.get(map, x, y - 1))
      and Tl.isFloor(M.get(map, x, y + 1))
      and not Tl.isClimb(M.get(map, x, y))
      and M.get(map, x, y) ~= "V" and M.get(map, x, y) ~= "A"
      and not M.podAt(map, x, y)
  end

  local spots = {}
  for _, g in ipairs(map.galleries) do
    for x = g.x1 + 1, g.x2 - 1 do
      if standable(x, g.y - 1) then spots[#spots + 1] = { x = x, y = g.y - 1, g = g } end
    end
  end
  rng:shuffle(spots)

  local n = math.min(#spots, 14 + rng:int(0, 8) + math.floor(map.index / 2))
  local placed = 0
  local medPlaced = false
  local i = 1
  while placed < n and i <= #spots do
    local s = spots[i]; i = i + 1
    if M.get(map, s.x, s.y) == " " then
      local sel = rng:weighted(PROP_CHARS)
      local def = CONTAINER_BY_KIND[sel.kind]
      if def then
        M.set(map, s.x, s.y, sel.ch)
        map.props[M.key(s.x, s.y)] = {
          type = def.id, name = def.name, time = def.time, rolls = def.rolls,
          locked = def.locked or false, searched = false, emptied = false,
          corpse = def.corpse or false,
          pool = def.medical and "medical" or def.tools and "tools"
                 or def.forage and "forage" or def.junk and "junk" or "general",
        }
        if def.medical then medPlaced = true end
        placed = placed + 1
      end
    end
  end
  if not medPlaced and i <= #spots then
    local s = spots[i]
    local def = CONTAINER_BY_KIND.medbox
    M.set(map, s.x, s.y, "m")
    map.props[M.key(s.x, s.y)] = {
      type = "medbox", name = def.name, time = def.time, rolls = def.rolls,
      searched = false, emptied = false, pool = "medical",
    }
  end

  -- fixtures
  local FIXTURES = { { w = 5, ch = "S" }, { w = 4, ch = "W" }, { w = 3, ch = "C" },
                     { w = 3, ch = "P" }, { w = 3, ch = "F" }, { w = 4, ch = "n" } }
  local fixtures = 2 + rng:int(0, 3)
  for _ = 1, fixtures do
    if i > #spots then break end
    local s = spots[i]; i = i + 1
    if M.get(map, s.x, s.y) == " " then
      local ch = rng:weighted(FIXTURES).ch
      M.set(map, s.x, s.y, ch)
      if ch == "n" then
        map.props[M.key(s.x, s.y)] = { type = "note", doc = rng:int(1, #D.DOCS) }
      end
    end
  end

  -- the cargo sits on the floor of stratum ten
  if map.index == 10 and i <= #spots then
    local s = spots[i]; i = i + 1
    M.set(map, s.x, s.y, "X")
  end

  -- traps. left behind by people who wanted this level to themselves.
  local trapPool = { { w = 5, ch = "I" }, { w = 3, ch = "K" }, { w = 3, ch = "J" } }
  local traps = 1 + rng:int(0, 2) + math.floor(map.index / 3)
  for _ = 1, traps do
    if i > #spots then break end
    local s2 = spots[i]; i = i + 1
    if M.get(map, s2.x, s2.y) == " " and not M.podAt(map, s2.x, s2.y) then
      M.set(map, s2.x, s2.y, rng:weighted(trapPool).ch)
    end
  end

  -- creatures
  if #strat.creatures > 0 then
    local count = 3 + rng:int(0, 3) + math.floor(map.index / 3)
    for _ = 1, count do
      if i > #spots then break end
      local s = spots[i]; i = i + 1
      if M.get(map, s.x, s.y) == " " then
        local pick = rng:weighted(strat.creatures)
        if pick then
          map.entities[#map.entities + 1] = {
            id = pick.id, x = s.x, y = s.y, hp = nil, awake = false, cooldown = 0,
          }
        end
      end
    end
  end
end

--------------------------------------------------------------------- queries

-- Depth in metres of a row.
function M.depthAt(map, y)
  return map.depthTop + (y - 1) * Tl.METRES_PER_TILE
end

function M.entityAt(map, x, y)
  for _, e in ipairs(map.entities) do
    if e.x == x and e.y == y and not e.dead then return e end
  end
  return nil
end

CU.mapgen = M
return M

end
