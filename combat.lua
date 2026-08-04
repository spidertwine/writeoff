-- WRITE-OFF / lib/combat.lua
-- Encounters. Short, expensive, and rarely worth starting.

return function(CU)

local U = CU.util
local D = CU.data
local B = CU.body
local Inv = CU.inv
local UI = CU.ui

local C = {}

local function newFoe(id, rng, scale)
  local def = D.CREATURES[id]
  if not def then return nil end
  scale = scale or 1
  return {
    id = id, def = def,
    name = def.name,
    hp = math.floor(def.hp * scale * rng:range(0.85, 1.15)),
    maxhp = math.floor(def.hp * scale),
    armour = def.armour * scale,
    stun = 0, rage = 0, scale = scale,
    fled = false,
  }
end

--------------------------------------------------------------------- screen

local function draw(g, foes, hint)
  local body = g.body
  UI.beginFrame()
  local w = UI.w
  CU.screens.header(g, "CONTACT")

  local y = 3
  for i = 1, #foes do
    local f = foes[i]
    if not f.dead then
      local frac = f.hp / math.max(1, f.maxhp)
      UI.write(2, y, U.trunc(string.upper(f.name), 20), UI.c.crit)
      UI.bar(24, y, w - 30, frac, frac > 0.5 and UI.c.bad or UI.c.crit, UI.c.panel)
      if f.stun > 0 then UI.write(w - 4, y, "STN", UI.c.warn) end
      y = y + 1
    end
  end
  y = y + 1

  local logH = UI.h - y - 4
  g.log:render(2, y, w - 15, logH)

  -- compact body readout down the right edge
  CU.screens.miniBody(w - 12, y, body)

  CU.screens.vitals(UI.h - 3, g)
  if UI.touch then
    local bw = math.max(7, math.floor((UI.w - 2) / 5))
    local labels = { { "ATTACK", "attack" }, { "BACK OFF", "flee" }, { "LIGHT", "light" },
                     { "MED", "med" }, { "PACK", "pack" } }
    for i, b in ipairs(labels) do
      UI.button(2 + (i - 1) * bw, UI.h - 1, bw - 1, 2, b[1], b[2])
    end
  else
    UI.write(2, UI.h - 1, U.trunc(hint or
      "a attack   f back off   l throw light   i pack   m medical", w - 2), UI.c.faint)
  end
  UI.endFrame()
end

--------------------------------------------------------------------- resolution

local function playerAttack(g, foes, rng)
  local body = g.body
  local weapon = g.inv.weapon
  local wdef = weapon and D.ITEMS[weapon.id]
  local spec = wdef and wdef.weapon or { dmg = 5, muscle = 3, bleed = 0, speed = 1.1, noise = 0.2, hands = 1 }

  -- pick a target
  local live = {}
  for _, f in ipairs(foes) do if not f.dead then live[#live + 1] = f end end
  if #live == 0 then return 0 end
  local target = live[1]
  if #live > 1 and not UI.headless then
    local items = {}
    for i, f in ipairs(live) do
      items[#items + 1] = { label = f.name .. "  " .. math.floor(f.hp / math.max(1, f.maxhp) * 100) .. "%",
                            key = tostring(i), value = f }
    end
    local pickres = UI.pick("target", items, { under = function() draw(g, foes) end })
    if not pickres then return 0 end
    target = pickres.value
  end

  if spec.ranged then
    if Inv.count(g.inv, spec.ammo) <= 0 then
      g:say("Empty.", UI.c.warn)
      return 2
    end
    Inv.remove(g.inv, spec.ammo, 1)
  end
  if spec.needsCell then
    if (weapon.cell or 0) <= 0 then
      g:say("The prod has no charge.", UI.c.warn)
      return 2
    end
    weapon.cell = weapon.cell - (spec.drain or 5)
  end

  local power = B.swingPower(body)
  local hitChance = U.clamp(0.55 + power * 0.35 + B.steadiness(body) * 0.2
    - (target.def.speed - 1) * 0.2, 0.12, 0.95)
  local time = math.floor(4 / U.clamp(spec.speed or 1, 0.4, 2))

  if not rng:chance(hitChance) then
    g:say("You miss.", UI.c.dim)
    UI.sfx("miss")
    return time
  end

  local dmg = spec.dmg * power * rng:range(0.8, 1.25)
  dmg = math.max(1, dmg - target.armour * rng:range(0.6, 1.2))
  target.hp = target.hp - dmg
  target.rage = target.rage + 1
  if spec.stun and rng:chance(spec.stun * U.clamp(power, 0.2, 1.2)) then
    target.stun = target.stun + 1
    g:say("It is stunned.", UI.c.gold)
  end
  g:say(string.format("You hit it for %d.", math.floor(dmg)), UI.c.text)
  UI.sfx("swing")

  if target.hp <= 0 then
    target.dead = true
    g.stats.kills = g.stats.kills + 1
    g:say("It is dead.", UI.c.ok)
    UI.sfx("kill")
    CU.mapgen.addBlood(g.map, g.x, g.y, 3)
    -- splitting creatures
    if target.def.splits and target.scale > 0.45 then
      for _ = 1, 2 do
        local child = newFoe(target.id, rng, target.scale * 0.55)
        child.name = "lesser " .. target.def.name
        foes[#foes + 1] = child
      end
      g:say("It splits in two and both halves keep coming.", UI.c.crit)
    end
    -- drops
    if target.def.drops then
      local drop = rng:weighted(target.def.drops)
      if drop then
        Inv.add(g.inv, drop.id, drop.n or 1)
        g:say("Salvaged: " .. D.ITEMS[drop.id].name, UI.c.gold)
      end
    end
  end
  return time
end

local function foeAttack(g, f, rng)
  local body = g.body
  if f.stun > 0 then
    f.stun = f.stun - 1
    g:say(f.name .. " is still recovering.", UI.c.dim)
    return
  end
  local atk = rng:weighted(f.def.attacks)
  if not atk then return end
  local dodge = U.clamp(B.mobility(body) * 0.3 - (f.def.speed - 1) * 0.2, 0, 0.45)
  if rng:chance(dodge) then
    g:say("You dodge it.", UI.c.dim)
    UI.sfx("miss")
    return
  end
  g:say(f.name .. " " .. atk.name .. ".", UI.c.warn)
  UI.sfx((atk.bleed or 0) > 0.1 and "bitten" or "clawed")
  local scaled = U.copy(atk)
  for _, k in ipairs({ "skin", "muscle", "bleed", "pain", "burn" }) do
    if scaled[k] then scaled[k] = scaled[k] * f.scale end
  end
  local events = B.hurt(body, scaled, rng)
  g:sayAll(events)
  if B.totalBleed(body) > 0.05 then CU.mapgen.addBlood(g.map, g.x, g.y, 2) end
  if f.def.talks and f.def.voice and rng:chance(0.4) then
    g:say('"' .. f.def.voice[rng:int(1, #f.def.voice)] .. '"', UI.c.infect)
  end
end

local function tryFlee(g, foes, rng)
  local body = g.body
  local fastest = 1
  for _, f in ipairs(foes) do
    if not f.dead then fastest = math.max(fastest, f.def.speed) end
  end
  local chance = U.clamp(B.mobility(body) * 0.8 / fastest, 0.05, 0.9)
  if body.held then chance = chance * 0.3 end
  if rng:chance(chance) then
    g:say("You get clear.", UI.c.ok)
    return true
  end
  g:say("Not fast enough. It gets a hit in.", UI.c.warn)
  for _, f in ipairs(foes) do
    if not f.dead then foeAttack(g, f, rng); break end
  end
  return false
end

local function throwLight(g, foes, rng)
  local candidates = Inv.entries(g.inv, function(e, it)
    return it.light and it.light.throwable
  end)
  if #candidates == 0 then
    g:say("You have nothing burning to throw.", UI.c.warn)
    return false
  end
  local items = {}
  for _, e in ipairs(candidates) do
    items[#items + 1] = { label = D.ITEMS[e.id].name .. " x" .. e.n, value = e }
  end
  local sel = UI.pick("throw", items, { under = function() draw(g, foes) end })
  if not sel then return false end
  local e = sel.value
  local it = D.ITEMS[e.id]
  Inv.removeEntry(g.inv, e, 1)
  local repel = it.light.repel or 0.2
  g:say("You throw it. The light floods the gallery.", UI.c.gold)
  local scared = 0
  for _, f in ipairs(foes) do
    if not f.dead then
      local resist = f.def.boss and 0.7 or 0
      local lightFear = (f.def.light and f.def.light < 0) and 0.3 or 0
      if rng:chance(U.clamp(repel + lightFear - resist, 0, 0.95)) then
        f.dead = true; f.fled = true
        scared = scared + 1
      else
        f.stun = f.stun + 1
      end
    end
  end
  if scared > 0 then
    g:say(scared .. " of them back off into the dark.", UI.c.ok)
  else
    g:say("It flinches and keeps coming.", UI.c.warn)
  end
  return true
end

--------------------------------------------------------------------- entry

function C.begin(g, ent, opts)
  opts = opts or {}
  local rng = g.rng
  local def = D.CREATURES[ent.id]
  if not def or ent.dead then return end

  local foes = {}
  local main = newFoe(ent.id, rng, 1)
  if ent.name then main.name = ent.name end
  if ent.hp then main.hp = ent.hp end
  ent.hp = main.hp
  main.ent = ent
  foes[1] = main
  if def.swarm then
    for _ = 2, rng:int(2, 3) do foes[#foes + 1] = newFoe(ent.id, rng, 0.7) end
  end

  g:blank()
  g:say((ent.name or def.name) .. ".", UI.c.crit)
  g:say(def.desc, UI.c.dim)
  UI.sfx("alarm")
  if opts.ambush then
    for _, f in ipairs(foes) do foeAttack(g, f, rng) end
  elseif opts.playerFirst then
    for _, f in ipairs(foes) do f.stun = f.stun + 1 end
  end

  local running, rounds = true, 0
  while running and not g.over do
    rounds = rounds + 1
    if rounds > 600 then break end
    local anyAlive = false
    for _, f in ipairs(foes) do if not f.dead then anyAlive = true end end
    if not anyAlive then break end

    if g.body.consciousness < D.TUNE.CONSCIOUS_OUT then
      g:say("You are unconscious and it is still here.", UI.c.crit)
      for _, f in ipairs(foes) do if not f.dead then foeAttack(g, f, rng) end end
      g:advance(20, { exertion = 0 })
      if g.body.dead then break end
      if rng:chance(0.4) then
        g:say("It loses interest in something that has stopped moving.", UI.c.dim)
        break
      end
    else
      draw(g, foes)
      local ev = UI.read()
      local acted, cost = false, 0
      if ev.kind == "char" then
        if ev.char == "a" then cost = playerAttack(g, foes, rng); acted = cost > 0
        elseif ev.char == "f" then
          if tryFlee(g, foes, rng) then
            ent.cooldown = 6
            local away = (g.x > ent.x) and -2 or 2
            ent.x = ent.x + away
            g:advance(12, { exertion = 0.9 })
            running = false
            break
          end
          acted = true; cost = 5
        elseif ev.char == "l" then acted = throwLight(g, foes, rng); cost = 4
        elseif ev.char == "i" then
          CU.screens.inventory(g, function() draw(g, foes) end); acted = true; cost = 6
        elseif ev.char == "m" then
          CU.screens.medical(g, function() draw(g, foes) end); acted = true; cost = 0
        end
      elseif ev.kind == "key" and ev.name == "enter" then
        cost = playerAttack(g, foes, rng); acted = cost > 0
      elseif ev.kind == "click" then
        local hit = UI.hitButton(ev.x, ev.y)
        if hit == "attack" then cost = playerAttack(g, foes, rng); acted = cost > 0
        elseif hit == "flee" then
          if tryFlee(g, foes, rng) then ent.cooldown = 6; running = false; break end
          acted = true; cost = 5
        elseif hit == "light" then acted = throwLight(g, foes, rng); cost = 4
        elseif hit == "med" then CU.screens.medical(g, function() draw(g, foes) end); acted = true
        elseif hit == "pack" then
          CU.screens.inventory(g, function() draw(g, foes) end); acted = true; cost = 6
        end
      end
      if acted then
        if cost > 0 then g:advance(cost, { exertion = 0.9 }) end
        if g.over then break end
        for _, f in ipairs(foes) do if not f.dead then foeAttack(g, f, rng) end end
        if g.body.dead then g:endRun(g.body.cause) end
      end
    end
    if main.ent then main.ent.hp = main.hp end
  end

  if main.dead then ent.dead = true end
  ent.hp = main.hp
end

C.newFoe = newFoe
CU.combat = C
return C

end
