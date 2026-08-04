-- WRITE-OFF / lib/inv.lua
-- Carrying, wearing, wielding, burning fuel, and making things out of scrap.

return function(CU)

local U = CU.util
local D = CU.data
local Inv = {}

function Inv.new()
  return {
    slots = {},
    wear = {},          -- slot -> entry
    weapon = nil,       -- entry
    light = nil,        -- entry
    flask = { amount = 0, clean = false },
  }
end

local function def(entry) return D.ITEMS[entry.id] end
Inv.def = def

--------------------------------------------------------------------- stacks

function Inv.add(inv, id, n, meta)
  local it = D.ITEMS[id]
  if not it then return 0 end
  n = n or 1
  local added = 0
  if it.stack > 1 and not meta then
    for i = 1, #inv.slots do
      local e = inv.slots[i]
      if e.id == id and not e.equipped and e.n < it.stack then
        local room = it.stack - e.n
        local take = math.min(room, n - added)
        e.n = e.n + take
        added = added + take
        if added >= n then return added end
      end
    end
  end
  while added < n do
    local take = math.min(it.stack, n - added)
    local e = { id = id, n = take }
    if it.tool and it.tool.charges then e.charges = it.tool.charges end
    if it.tool and it.tool.uses then e.uses = it.tool.uses end
    if it.light and it.light.fuel then e.fuel = it.light.fuel end
    if it.misc and it.misc.cell then e.cell = it.misc.cell end
    if meta then for k, v in pairs(meta) do e[k] = v end end
    inv.slots[#inv.slots + 1] = e
    added = added + take
  end
  return added
end

function Inv.count(inv, id)
  local n = 0
  for i = 1, #inv.slots do
    if inv.slots[i].id == id then n = n + inv.slots[i].n end
  end
  return n
end

function Inv.remove(inv, id, n)
  n = n or 1
  local removed = 0
  for i = #inv.slots, 1, -1 do
    local e = inv.slots[i]
    if e.id == id and not e.equipped then
      local take = math.min(e.n, n - removed)
      e.n = e.n - take
      removed = removed + take
      if e.n <= 0 then
        if inv.weapon == e then inv.weapon = nil end
        if inv.light == e then inv.light = nil end
        table.remove(inv.slots, i)
      end
      if removed >= n then return removed end
    end
  end
  return removed
end

function Inv.removeEntry(inv, entry, n)
  n = n or 1
  entry.n = entry.n - n
  if entry.n <= 0 then
    for i = #inv.slots, 1, -1 do
      if inv.slots[i] == entry then table.remove(inv.slots, i) end
    end
    if inv.weapon == entry then inv.weapon = nil end
    if inv.light == entry then inv.light = nil end
    for slot, e in pairs(inv.wear) do
      if e == entry then inv.wear[slot] = nil end
    end
  end
end

function Inv.entries(inv, filter)
  local out = {}
  for i = 1, #inv.slots do
    local e = inv.slots[i]
    local it = def(e)
    if it and (not filter or filter(e, it)) then out[#out + 1] = e end
  end
  return out
end

function Inv.mass(inv)
  local m = 0
  for i = 1, #inv.slots do
    local it = def(inv.slots[i])
    if it then m = m + it.mass * inv.slots[i].n end
  end
  m = m + (inv.flask.amount or 0)
  return m
end

function Inv.value(inv)
  local v = 0
  for i = 1, #inv.slots do
    local it = def(inv.slots[i])
    if it then v = v + it.value * inv.slots[i].n end
  end
  return v
end

--------------------------------------------------------------------- wearing

function Inv.wearableSlot(it)
  return it.wear and it.wear.slot or nil
end

function Inv.equipWear(inv, entry)
  local it = def(entry)
  local slot = Inv.wearableSlot(it)
  if not slot then return false, "Not something you wear." end
  if inv.wear[slot] then
    inv.wear[slot].equipped = nil
  end
  entry.equipped = true
  inv.wear[slot] = entry
  return true, it.name .. " on."
end

function Inv.unequipWear(inv, slot)
  local e = inv.wear[slot]
  if not e then return false end
  e.equipped = nil
  inv.wear[slot] = nil
  return true
end

function Inv.equipWeapon(inv, entry, body)
  local it = def(entry)
  if not it.weapon then return false, "That is not a weapon." end
  local hands = CU.body.handsFree(body)
  if (it.weapon.hands or 1) > hands then
    return false, "You need more working hands for that."
  end
  inv.weapon = entry
  return true, it.name .. " in hand."
end

function Inv.equipLight(inv, entry)
  local it = def(entry)
  if not it.light and not (it.wear and it.wear.lightRadius) then
    return false, "That does not give off light."
  end
  inv.light = entry
  entry.lit = true
  return true, it.name .. " lit."
end

--------------------------------------------------------------------- gear

function Inv.updateGear(inv, body)
  local g = {
    head = 0, face = 0, torso = 0, hands = 0, legs = 0, feet = 0,
    warmth = 0, carry = 0, rad = 0, spore = 0, grip = 0,
    fallGuard = 0, footGuard = 0, skullGuard = 0, cutGuard = 0, eyeGuard = 0,
    mood = 0, encumber = 0, pump = false, lightRadius = 0,
  }
  for slot, e in pairs(inv.wear) do
    local it = def(e)
    if it and it.wear then
      local w = it.wear
      g[slot] = (g[slot] or 0) + (w.armour or 0)
      g.warmth = g.warmth + (w.warmth or 0)
      g.carry = g.carry + (w.carry or 0)
      g.rad = math.min(0.92, g.rad + (w.rad or 0))
      g.spore = math.min(0.95, g.spore + (w.spore or 0))
      g.grip = g.grip + (w.grip or 0)
      g.fallGuard = math.min(0.8, g.fallGuard + (w.fallGuard or 0))
      g.footGuard = math.min(0.95, g.footGuard + (w.footGuard or 0))
      g.skullGuard = math.min(0.8, g.skullGuard + (w.skullGuard or 0))
      g.cutGuard = math.min(0.85, g.cutGuard + (w.cutGuard or 0))
      g.eyeGuard = math.min(0.9, g.eyeGuard + (w.eyeGuard or 0))
      g.mood = g.mood + (w.mood or 0)
      g.encumber = g.encumber + (w.encumber or 0)
      if w.pump then g.pump = true end
    end
  end
  body.gear = g
  body.load = Inv.mass(inv) + g.encumber * 2
  return g
end

--------------------------------------------------------------------- light

function Inv.lightRadius(inv)
  local r = 0.35   -- what the eyes manage unaided down here
  local e = inv.light
  if e and e.lit then
    local it = def(e)
    local spec = it.light or (it.wear and it.wear)
    if spec then
      local ok = true
      if spec.needsCell and (e.cell or 0) <= 0 then ok = false end
      if spec.fuel and (e.fuel or 0) <= 0 then ok = false end
      if ok then r = math.max(r, spec.radius or spec.lightRadius or 0) end
    end
  end
  for _, we in pairs(inv.wear) do
    local it = def(we)
    if it and it.wear and it.wear.lightRadius and (we.cell or 0) > 0 then
      r = math.max(r, it.wear.lightRadius)
    end
  end
  return r
end

function Inv.revealsInfection(inv)
  local e = inv.light
  if e and e.lit then
    local it = def(e)
    if it.light and it.light.reveal then return true end
  end
  return false
end

function Inv.tickLights(inv, dt)
  local msgs = {}
  local function drainEntry(e, spec)
    if not e or not spec then return end
    if spec.fuel and e.fuel then
      e.fuel = e.fuel - dt
      if e.fuel <= 0 then
        e.fuel = 0
        e.lit = false
        msgs[#msgs + 1] = def(e).name .. " has burnt out."
        if inv.light == e then
          inv.light = nil
          Inv.removeEntry(inv, e, e.n)
        end
      end
    elseif spec.needsCell and e.cell then
      e.cell = e.cell - (spec.drain or 1) * dt / 60
      if e.cell <= 0 then
        e.cell = 0
        msgs[#msgs + 1] = def(e).name .. " is out of charge. It needs a cell."
      end
    end
  end
  local e = inv.light
  if e and e.lit then
    local it = def(e)
    drainEntry(e, it.light)
  end
  for _, we in pairs(inv.wear) do
    local it = def(we)
    if it and it.wear and it.wear.lightRadius then drainEntry(we, it.wear) end
  end
  return msgs
end

function Inv.reload(inv, entry)
  local it = def(entry)
  local spec = it.light or (it.wear and it.wear)
  if not spec or not spec.needsCell then return false, "That does not take a cell." end
  if Inv.count(inv, "cell") <= 0 then return false, "No cells." end
  Inv.remove(inv, "cell", 1)
  entry.cell = 100
  return true, "New cell fitted."
end

--------------------------------------------------------------------- crafting

function Inv.canCraft(inv, recipe)
  for id, n in pairs(recipe.need) do
    if Inv.count(inv, id) < n then return false end
  end
  return true
end

function Inv.craft(inv, recipe, body)
  if not Inv.canCraft(inv, recipe) then return false, "You do not have the parts." end
  if recipe.int and body and body.traits.int < recipe.int then
    return false, "You cannot work out how it goes together."
  end
  for id, n in pairs(recipe.need) do Inv.remove(inv, id, n) end
  Inv.add(inv, recipe.out, recipe.n or 1)
  return true, "Made: " .. D.ITEMS[recipe.out].name ..
    ((recipe.n or 1) > 1 and (" x" .. recipe.n) or "")
end

function Inv.availableRecipes(inv, body)
  local out = {}
  for i = 1, #D.RECIPES do
    local r = D.RECIPES[i]
    local can = Inv.canCraft(inv, r)
    local smart = (not r.int) or (body and body.traits.int >= r.int)
    out[#out + 1] = { recipe = r, can = can and smart, missing = not can, dumb = not smart }
  end
  return out
end

--------------------------------------------------------------------- water

function Inv.drink(inv, body, amount)
  amount = amount or 0.25
  if inv.flask.amount <= 0 then return false, "The flask is empty." end
  local take = math.min(amount, inv.flask.amount)
  inv.flask.amount = inv.flask.amount - take
  body.thirst = U.clamp(body.thirst + take * 100, 0, 120)
  if not inv.flask.clean then
    body.sick = U.clamp(body.sick + take * 40, 0, 100)
    return true, "Dirty water. That may make you sick."
  end
  return true, "Clean water."
end

function Inv.fill(inv, clean)
  if Inv.count(inv, "water_flask") <= 0 then return false, "You need a flask." end
  inv.flask.amount = 0.75
  inv.flask.clean = clean and true or false
  return true, clean and "Flask filled with clean water." or "Flask filled. The water is not clean."
end

CU.inv = Inv
return Inv

end
