-- WRITE-OFF / lib/body.lua
-- The simulation. Seven limbs, one cardiovascular system, one clock.

return function(CU)

local U = CU.util
local D = CU.data
local T = D.TUNE

local B = {}

--------------------------------------------------------------------- construction

local function newLimb()
  return {
    skin = 100, muscle = 100,
    bone = "ok",            -- ok | dislocated | fractured
    boneTimer = 0,          -- minutes remaining
    bleed = 0,              -- L/min, external
    pain = 0,
    infection = 0, revealed = false,
    shrapnel = 0, burn = 0,
    dressing = nil,         -- { id, stop, absorb, soak }
    tourniquet = nil,       -- { time }
    splint = nil,           -- { mult }
    disinfect = 0,          -- seconds remaining
    chill = 0, warm = 0,
    amputated = false,
  }
end

function B.new(opts)
  opts = opts or {}
  local b = {
    limbs = {},
    blood = T.BLOOD_FULL, visc = 0,
    spo2 = 98, maxO2 = 100, hr = T.HR_BASE, bp = T.BP_BASE, resp = T.RESP_BASE,
    consciousness = 100, brain = 100,
    adren = 0, opioid = 0, tolerance = 0, withdrawal = 0,
    internal = 0, hemothorax = 0, embolism = false,
    fib = 0, arrest = false, arrestTime = 0, respArrest = false,
    temp = T.TEMP_BASE, wet = 0, oil = false,
    hunger = 100, thirst = 100, energy = 100, mood = 62, sick = 0, immunity = 100,
    sepsis = 0, weight = 62,
    traits = { str = 0, int = 0, res = 0 },
    gear = {},
    dead = false, cause = nil,
    seen = {}, painPeak = 0, held = nil,
  }
  for _, id in ipairs(D.LIMB_ORDER) do b.limbs[id] = newLimb() end
  if opts.traits then
    for k, v in pairs(opts.traits) do b.traits[k] = v end
  end
  return b
end

function B.limb(b, id) return b.limbs[id] end

--------------------------------------------------------------------- geometry

local ARM_LIMBS = { "larm", "rarm" }
local LEG_LIMBS = { "lleg", "rleg" }
local CORE_LIMBS = { "head", "thorax", "abdomen" }

function B.livingLimbs(b, filter)
  local out = {}
  for _, id in ipairs(D.LIMB_ORDER) do
    local l = b.limbs[id]
    if not l.amputated then
      if not filter or filter(id, l) then out[#out + 1] = id end
    end
  end
  return out
end

-- resolves a hazard/attack target descriptor into a limb id
function B.pickTarget(b, target, rng)
  local pool
  if target == "arm" then pool = { "larm", "rarm" }
  elseif target == "leg" then pool = { "lleg", "rleg" }
  elseif target == "head" then pool = { "head" }
  elseif target == "low" then pool = { "lleg", "rleg", "lleg", "rleg", "abdomen" }
  elseif target == "high" then pool = { "head", "thorax", "thorax", "larm", "rarm" }
  elseif target == "core" then pool = { "thorax", "abdomen" }
  else pool = { "head", "thorax", "thorax", "abdomen", "abdomen", "larm", "rarm", "lleg", "rleg", "lleg", "rleg" }
  end
  local live = {}
  for i = 1, #pool do
    if not b.limbs[pool[i]].amputated then live[#live + 1] = pool[i] end
  end
  if #live == 0 then return "thorax" end
  return live[rng:int(1, #live)]
end

--------------------------------------------------------------------- gear

-- Aggregated protection is written here by the inventory module.
function B.armourAt(b, id)
  local g = b.gear or {}
  local a = 0
  if id == "head" then a = (g.head or 0) + (g.face or 0) * 0.5
  elseif id == "thorax" or id == "abdomen" then a = (g.torso or 0)
  elseif id == "larm" or id == "rarm" then a = (g.hands or 0) * 0.6 + (g.torso or 0) * 0.3
  else a = (g.legs or 0) * 0.7 + (g.feet or 0) * 0.4 end
  return a
end

--------------------------------------------------------------------- damage

local function addPain(l, n)
  l.pain = U.clamp(l.pain + n, 0, 100)
end

-- spec fields are documented in data.lua HAZARDS
-- returns a list of { text, colour } style event descriptions
function B.hurt(b, spec, rng, opts)
  opts = opts or {}
  local out = {}
  local id = opts.limb or B.pickTarget(b, spec.target or "any", rng)
  local l = b.limbs[id]
  local meta = D.LIMBS[id]
  local g = b.gear or {}

  local function say(text, colour) out[#out + 1] = { text = text, colour = colour } end

  if spec.fall then
    local h = spec.fall
    local guard = (g.fallGuard or 0)
    local force = math.max(0, h - 1.5) * (1 - guard * 0.5)
    local legTargets = {}
    for _, lid in ipairs(LEG_LIMBS) do
      if not b.limbs[lid].amputated then legTargets[#legTargets + 1] = lid end
    end
    if #legTargets == 0 then legTargets = { "abdomen" } end
    for _, lid in ipairs(legTargets) do
      local ll = b.limbs[lid]
      local skin = force * 2.6 * (1 - B.armourAt(b, lid) / 24)
      local muscle = force * 3.4
      ll.skin = U.clamp(ll.skin - skin, 0, 100)
      ll.muscle = U.clamp(ll.muscle - muscle, 0, 100)
      addPain(ll, force * 4)
      if rng:chance(U.clamp(force * 0.07, 0, 0.85)) then
        B.breakBone(b, lid, rng, out)
      elseif rng:chance(U.clamp(force * 0.06, 0, 0.6)) then
        B.dislocate(b, lid, rng, out)
      end
    end
    if force > 5 and rng:chance(0.4) then
      local core = rng:pick({ "abdomen", "thorax" })
      b.limbs[core].muscle = U.clamp(b.limbs[core].muscle - force * 2, 0, 100)
      addPain(b.limbs[core], force * 2.5)
      b.internal = b.internal + force * 0.012
    end
    if force > 7 and rng:chance(0.3) then
      b.brain = U.clamp(b.brain - force * 0.35, 0, 100)
      say("The landing rings through the skull.", CU.ui.c.bad)
    end
    say(string.format("You come down hard. %.1f metres.", h), CU.ui.c.bad)
    CU.ui.sfx("hurt")
    return out
  end

  local armour = B.armourAt(b, id)
  local mitigate = 1 - U.clamp(armour / 26, 0, 0.62)

  if spec.skin and spec.skin > 0 then
    local amount = spec.skin * mitigate
    if spec.foot and (g.footGuard or 0) > 0 then amount = amount * (1 - g.footGuard) end
    if (g.cutGuard or 0) > 0 and (id == "larm" or id == "rarm") then amount = amount * (1 - g.cutGuard * 0.6) end
    l.skin = U.clamp(l.skin - amount, 0, 100)
  end
  if spec.muscle and spec.muscle > 0 then
    l.muscle = U.clamp(l.muscle - spec.muscle * mitigate, 0, 100)
  end
  if spec.bleed and spec.bleed > 0 then
    l.bleed = l.bleed + spec.bleed * meta.bleedMult * (0.7 + 0.6 * (1 - l.skin / 100))
  end
  if spec.pain and spec.pain > 0 then
    addPain(l, spec.pain * (1 - U.clamp(armour / 40, 0, 0.35)))
  end
  if spec.burn and spec.burn > 0 then
    l.burn = U.clamp(l.burn + spec.burn * mitigate, 0, 100)
    l.skin = U.clamp(l.skin - spec.burn * 0.4, 0, 100)
    addPain(l, spec.burn * 0.8)
  end
  if spec.shrap and spec.shrap > 0 then
    local n = math.floor(spec.shrap * (0.5 + rng:float()) + 0.5)
    if n > 0 then
      l.shrapnel = l.shrapnel + n
      addPain(l, n * 5)
      l.bleed = l.bleed + n * 0.012
      say(n .. " fragment" .. (n == 1 and "" or "s") .. " in the " .. meta.name .. ".", CU.ui.c.warn)
    end
  end
  if spec.infect and spec.infect > 0 then
    local chance = spec.infect * (1.2 - b.immunity / 130)
    if l.disinfect > 0 then chance = chance * 0.15 end
    if rng:chance(U.clamp(chance, 0, 0.95)) then
      l.infection = l.infection + 6 + rng:float() * 10
    end
  end
  if spec.sever and rng:chance(spec.sever) and meta.limb then
    B.amputate(b, id, out, "torn away")
    return out
  end
  if spec.frac and rng:chance(spec.frac) then
    B.breakBone(b, id, rng, out)
  elseif spec.dislo and rng:chance(spec.dislo) then
    B.dislocate(b, id, rng, out)
  end

  -- body-wide riders
  if spec.sick then b.sick = U.clamp(b.sick + spec.sick, 0, 100) end
  if spec.brain then b.brain = U.clamp(b.brain - spec.brain, 0, 100) end
  if spec.cold then b.temp = b.temp - spec.cold * 0.06 end
  if spec.heat then b.temp = b.temp + spec.heat * 0.06 end
  if spec.wet then b.wet = 1 end
  if spec.oil then b.oil = true; b.wet = 1 end
  if spec.fib and rng:chance(spec.fib) then
    b.fib = math.max(b.fib, 40)
    say("Your heart has gone into fibrillation.", CU.ui.c.crit)
  end
  if spec.spore then
    local prot = (b.gear.spore or 0)
    if rng:chance(1 - prot) then
      b.sick = U.clamp(b.sick + 8, 0, 100)
      b.limbs.head.infection = b.limbs.head.infection + 5
    end
  end
  if spec.hold then b.held = 3 end

  if opts.silent ~= true then
    local sev = (spec.pain or 0) + (spec.muscle or 0)
    CU.ui.sfx(sev > 30 and "crack" or "hurt")
  end
  return out, id
end

function B.breakBone(b, id, rng, out)
  local l = b.limbs[id]
  if l.amputated then return end
  local was = l.bone
  l.bone = "fractured"
  l.boneTimer = T.BONE_HEAL_MIN
  l.skin = U.clamp(l.skin - 33, 0, 100)
  l.bleed = l.bleed + rng:range(0, 0.2)
  addPain(l, 100)
  b.adren = math.min(100, b.adren + 80)
  if id == "head" then
    if rng:chance(0.8) then
      b.neck = true
    elseif rng:chance(0.5) then
      b.disfigured = true
    end
  end
  if out then
    out[#out + 1] = { text = "Your " .. D.LIMBS[id].name .. " is broken.",
                      colour = CU.ui.c.crit }
  end
  CU.ui.sfx("crack")
  return was ~= "fractured"
end

function B.dislocate(b, id, rng, out)
  local l = b.limbs[id]
  if l.amputated or l.bone == "fractured" then return end
  l.bone = "dislocated"
  l.boneTimer = T.DISLO_HEAL_MIN
  l.skin = U.clamp(l.skin - 8, 0, 100)
  addPain(l, 48)
  b.adren = math.min(100, b.adren + 40)
  if out then
    out[#out + 1] = { text = "Your " .. D.LIMBS[id].name .. " is out of its joint.",
                      colour = CU.ui.c.bad }
  end
  CU.ui.sfx("crack")
end

function B.amputate(b, id, out, how)
  local l = b.limbs[id]
  if not D.LIMBS[id].limb then return false end
  l.amputated = true
  l.bleed = 1.4
  l.pain = 100
  l.dressing = nil
  l.splint = nil
  b.adren = 100
  if out then
    out[#out + 1] = { text = "Your " .. D.LIMBS[id].name .. " is " .. (how or "gone") .. ".",
                      colour = CU.ui.c.crit }
  end
  CU.ui.sfx("death")
  return true
end

--------------------------------------------------------------------- derived

local function limbFn(b, id)
  local l = b.limbs[id]
  if l.amputated then return 0 end
  local f = l.muscle / 100
  if l.bone == "fractured" then f = f * 0.15 end
  if l.bone == "dislocated" then f = f * 0.5 end
  if l.splint and l.bone ~= "ok" then f = f * 1.5 end
  if l.tourniquet then f = f * 0.55 end
  f = f * (1 - U.clamp(l.pain / 260, 0, 0.5))
  return U.clamp(f, 0, 1)
end
B.limbFunction = limbFn

function B.effectivePain(b)
  local peak, total = 0, 0
  for _, id in ipairs(D.LIMB_ORDER) do
    local l = b.limbs[id]
    local p = l.pain * D.LIMBS[id].painWeight
    if p > peak then peak = p end
    total = total + l.pain
  end
  local raw = U.clamp(peak * 0.62 + total * 0.085, 0, 100)
  local relief = U.clamp(b.opioid / 105, 0, 0.88) + U.clamp(b.adren / 190, 0, 0.5)
  return U.clamp(raw * (1 - U.clamp(relief, 0, 0.93)), 0, 100), raw
end

function B.mobility(b)
  local l = (limbFn(b, "lleg") + limbFn(b, "rleg")) / 2
  local core = limbFn(b, "abdomen") * 0.5 + 0.5
  local m = l * core
  if b.limbs.thorax.bone == "dislocated" then m = m * 0.7 end
  if b.limbs.abdomen.bone == "fractured" then m = m * 0.6 end
  m = m * U.clamp(b.consciousness / 70, 0.15, 1)
  m = m * (1 - U.clamp((B.encumbrance(b) - 1) * 0.5, 0, 0.6))
  if b.temp < 34 then m = m * 0.85 end
  return U.clamp(m, 0.05, 1.15)
end

function B.grip(b, which)
  if which then return limbFn(b, which) end
  return math.max(limbFn(b, "larm"), limbFn(b, "rarm"))
end

function B.handsFree(b)
  local n = 0
  for _, id in ipairs(ARM_LIMBS) do
    local l = b.limbs[id]
    if not l.amputated and l.bone ~= "fractured" and l.muscle >= 20 then n = n + 1 end
  end
  return n
end

function B.steadiness(b, bonus)
  local s = 1.0
  local pain = select(1, B.effectivePain(b))
  s = s - pain / 145
  s = s - (100 - b.consciousness) / 210
  s = s - U.clamp(b.opioid, 0, 100) / 260
  s = s - (100 - b.brain) / 190
  s = s + (b.gear.grip or 0)
  local arms = (limbFn(b, "larm") + limbFn(b, "rarm")) / 2
  s = s - (1 - arms) * 0.35
  if b.temp < 35.2 then s = s - (35.2 - b.temp) * 0.09 end
  if b.sick > 50 then s = s - 0.12 end
  s = s + (bonus or 0)
  s = s + b.traits.int * 0.02
  return U.clamp(s, 0.03, 1)
end

function B.perception(b, lightRadius)
  local p = 0.5 + (lightRadius or 0) * 0.11
  p = p * U.clamp(b.consciousness / 100, 0.2, 1)
  p = p * U.clamp(b.brain / 100, 0.3, 1)
  if b.limbs.head.muscle < 40 then p = p * 0.8 end
  if b.eyeLost then p = p * 0.6 end
  if b.gear.eyeGuard then p = p + 0.05 end
  p = p + b.traits.int * 0.03
  return U.clamp(p, 0.05, 1.1)
end

function B.swingPower(b)
  local best = math.max(limbFn(b, "larm"), limbFn(b, "rarm"))
  local core = 0.5 + limbFn(b, "thorax") * 0.5
  local p = best * core
  if b.neck then p = p * 0.6 end
  if b.limbs.thorax.bone ~= "ok" then p = p * 0.6 end
  p = p * U.clamp(0.55 + b.energy / 180, 0.4, 1.1)
  p = p * (1 + b.traits.str * 0.05)
  p = p * (1 + U.clamp(b.adren, 0, 100) / 320)
  return U.clamp(p, 0.05, 1.6)
end

function B.carryCapacity(b)
  local base = T.CARRY_BASE + (b.gear.carry or 0)
  base = base * (1 + b.traits.str * 0.06)
  local arms = (limbFn(b, "larm") + limbFn(b, "rarm")) / 2
  base = base * (0.55 + 0.45 * arms)
  return base
end

function B.encumbrance(b)
  local cap = B.carryCapacity(b)
  if cap <= 0 then return 3 end
  return (b.load or 0) / cap
end

function B.totalBleed(b)
  local n = b.internal or 0
  for _, id in ipairs(D.LIMB_ORDER) do
    local l = b.limbs[id]
    if l.bleed > 0 then
      local flow = l.bleed
      if l.tourniquet then flow = 0
      elseif l.dressing then flow = flow * (1 - l.dressing.stop) end
      n = n + flow
    end
  end
  return n
end

function B.limbCondition(b, id)
  local l = b.limbs[id]
  if l.amputated then return 0 end
  local f = (l.skin * 0.4 + l.muscle * 0.6) / 100
  if l.bone == "fractured" then f = f * 0.5 end
  if l.bone == "dislocated" then f = f * 0.75 end
  return U.clamp(f, 0, 1)
end

--------------------------------------------------------------------- treatments

local Med = {}
B.med = Med

function Med.applyDressing(b, id, item, rng)
  local l = b.limbs[id]
  local d = item.dressing
  if l.amputated and not d.instant then return false, "There is nothing left to wrap." end
  if d.instant then
    l.bleed = 0
    l.skin = U.clamp(l.skin + (d.skin or 0), 0, 100)
    addPain(l, d.pain or 0)
    b.visc = U.clamp(b.visc + (d.visc or 0), -100, 100)
    return true, "The granules clot the wound. Bleeding stopped."
  end
  l.dressing = { id = item.id, stop = d.stop, absorb = d.absorb, soak = 0, name = item.short }
  l.skin = U.clamp(l.skin + (d.skin or 0), 0, 100)
  l.muscle = U.clamp(l.muscle + (d.muscle or 0), 0, 100)
  addPain(l, d.pain or 0)
  if d.burn then l.burn = U.clamp(l.burn - 40, 0, 100) end
  if d.bone and l.bone ~= "ok" then
    l.boneTimer = math.max(0, l.boneTimer - d.bone * 6)
  end
  if d.dislo and l.bone == "dislocated" then
    l.boneTimer = l.boneTimer * (1 - d.dislo)
    if l.boneTimer <= 0.5 then
      l.bone = "ok"; l.boneTimer = 0
      b.mood = b.mood + 5
      return true, "The joint went back in under the pressure."
    end
  end
  if d.infect and rng:chance(d.infect) then
    l.infection = l.infection + 5
  end
  return true, "Dressing on the " .. D.LIMBS[id].name .. "."
end

function Med.tourniquet(b, id, on)
  local l = b.limbs[id]
  if on then
    if id == "thorax" or id == "abdomen" then
      return false, "There is nothing to tie it around."
    end
    l.tourniquet = { time = 0 }
    if id == "head" then
      b.respArrest = true
      return true, "That is around your neck. You have stopped breathing."
    end
    return true, "Tourniquet on. Bleeding stopped, and the limb is now on a clock."
  else
    l.tourniquet = nil
    if id == "head" then b.respArrest = false end
    return true, "Tourniquet off. The bleeding starts again."
  end
end

function Med.splint(b, id, item, on)
  local l = b.limbs[id]
  if on then
    if l.bone == "ok" then return false, "Nothing in there is broken." end
    l.splint = { mult = item.tool.mult, id = item.id }
    return true, "Splinted."
  else
    l.splint = nil
    return true, "Splint off."
  end
end

-- Manual reduction of a dislocation. Returns success, message, fractured
function Med.reduce(b, id, rng, withWrench)
  local l = b.limbs[id]
  if l.bone ~= "dislocated" then return false, "That joint is not dislocated." end
  local painAdd = withWrench and rng:range(5, 10) or rng:range(15, 24)
  addPain(l, painAdd)
  if rng:chance(withWrench and 0.01 or 0.05) then
    B.breakBone(b, id, rng, nil)
    return false, "You forced it and broke the bone.", true
  end
  local progress = withWrench and rng:range(0.4, 0.7) or rng:range(0.2, 0.45)
  l.boneTimer = l.boneTimer * (1 - progress)
  if l.boneTimer <= 1.5 then
    l.bone = "ok"; l.boneTimer = 0
    b.mood = b.mood + 5
    return true, "The joint is back in place."
  end
  return false, "Closer, but not in yet. Try again."
end

function Med.removeShrapnel(b, id, rng, success, withForceps)
  local l = b.limbs[id]
  if l.shrapnel <= 0 then return false, "No shrapnel left in it." end
  if success then
    l.shrapnel = l.shrapnel - 1
    l.bleed = l.bleed + 0.008
    addPain(l, rng:range(2, 5))
    return true, "Out. " .. (l.shrapnel > 0 and (l.shrapnel .. " to go.") or "That was the last one.")
  else
    addPain(l, rng:range(9, 16))
    l.skin = U.clamp(l.skin - 5, 0, 100)
    l.bleed = l.bleed + 0.02
    if id == "head" and rng:chance(0.8) then
      b.brain = U.clamp(b.brain - rng:range(0, 1), 0, 100)
    end
    return false, "It slips and goes in deeper."
  end
end

function Med.suture(b, id, rng, success)
  local l = b.limbs[id]
  if success then
    l.skin = U.clamp(l.skin + 26, 0, 100)
    l.bleed = l.bleed * 0.25
    addPain(l, 12)
    return true, "The wound is closed."
  end
  addPain(l, 20)
  l.skin = U.clamp(l.skin - 4, 0, 100)
  return false, "The needle tore through. Start again."
end

function Med.weld(b, id)
  local l = b.limbs[id]
  if l.bone == "ok" then return false, "Nothing in there is broken." end
  l.boneTimer = l.boneTimer * (1 - 1 / T.WELDER_DIV)
  l.skin = U.clamp(l.skin - 25, 0, 100)
  l.muscle = U.clamp(l.muscle - 26, 0, 100)
  l.bleed = l.bleed + 0.07
  b.visc = U.clamp(b.visc + 2, -100, 100)
  addPain(l, 30)
  if l.boneTimer <= 1 then
    l.bone = "ok"; l.boneTimer = 0
    b.mood = b.mood + 5
    return true, "The bone is welded. The flesh around it is burnt."
  end
  return true, "Partly welded. It needs another pass."
end

function Med.drug(b, item, rng, doses)
  doses = doses or 1
  local d = item.drug
  local msg = {}
  if d.opioidClear then
    b.opioid = 0
    b.withdrawal = math.min(100, b.withdrawal + 25)
    msg[#msg + 1] = "The opiates are gone. All the pain comes back."
  end
  if d.opioid then
    b.opioid = U.clamp(b.opioid + d.opioid * doses * (1 - b.tolerance / 260), 0, 220)
    b.tolerance = math.min(100, b.tolerance + 3 * doses)
    if b.opioid > 110 then
      b.respArrest = true
      msg[#msg + 1] = "Too much opiate. You have stopped breathing."
      CU.ui.sfx("overdose")
    end
  end
  if d.pain then
    -- distributed as a temporary relief pool rather than deleting pain
    b.painRelief = (b.painRelief or 0) + math.abs(d.pain) * doses
    b.painReliefRamp = d.ramp or 40
  end
  if d.adren then b.adren = U.clamp(b.adren + d.adren * doses, 0, 100) end
  if d.hr then b.hrKick = (b.hrKick or 0) + d.hr * doses end
  if d.blood then
    b.blood = U.clamp(b.blood + d.blood * doses, 0, 7.2)
    if b.blood > 6.1 then msg[#msg + 1] = "Too much volume. Blood pressure is dangerously high." end
  end
  if d.visc then b.visc = U.clamp(b.visc + d.visc * doses, -100, 100) end
  if d.infectionAll then
    for _, id in ipairs(D.LIMB_ORDER) do
      local l = b.limbs[id]
      l.infection = U.clamp(l.infection + d.infectionAll * doses, 0, 100)
    end
    msg[#msg + 1] = "The antibiotics take hold. Infection is falling."
  end
  if d.immunity then b.immunity = U.clamp(b.immunity + d.immunity, 0, 130) end
  if d.sick then b.sick = U.clamp(b.sick + d.sick * doses, 0, 100) end
  if d.energy then b.energy = U.clamp(b.energy + d.energy * doses, 0, 100) end
  if d.resp then b.respMod = (b.respMod or 0) + d.resp * doses end
  if d.crash then b.crash = (b.crash or 0) + d.crash end
  if d.cardiac then
    if b.arrest or b.fib > 0 then
      if rng:chance(0.45) then
        b.arrest = false; b.arrestTime = 0; b.fib = 0
        msg[#msg + 1] = "The heart restarts."
      else
        msg[#msg + 1] = "No effect. Try again, or use the paddles."
      end
    end
  end
  if d.infectChance and rng:chance(d.infectChance) then
    local id = rng:pick(D.LIMB_ORDER)
    b.limbs[id].infection = b.limbs[id].infection + 14
    msg[#msg + 1] = "That blood was carrying an infection."
  end
  if d.sleep then b.sleepy = 600 end
  -- overdose bookkeeping
  if d.via == "oral" and doses >= 3 then
    b.sick = U.clamp(b.sick + 20, 0, 100)
    msg[#msg + 1] = "That was more than one dose should be."
  end
  if #msg == 0 then msg[1] = "Taken." end
  return table.concat(msg, " ")
end

function Med.disinfect(b, id, seconds)
  local l = b.limbs[id]
  l.disinfect = math.max(l.disinfect, seconds)
  l.infection = U.clamp(l.infection - 12, 0, 100)
  addPain(l, 7)
  return true, "Disinfected. That wound will not go bad for a while."
end

function Med.defib(b, rng)
  if not (b.arrest or b.fib > 0) then
    b.fib = math.max(b.fib, 25)
    return false, "There was a rhythm. Now there is not."
  end
  if rng:chance(0.6) then
    b.arrest = false; b.arrestTime = 0; b.fib = 0
    b.limbs.thorax.burn = U.clamp(b.limbs.thorax.burn + 8, 0, 100)
    return true, "The heart restarts."
  end
  b.limbs.thorax.burn = U.clamp(b.limbs.thorax.burn + 10, 0, 100)
  return false, "No response. The capacitor is refilling."
end

function Med.drain(b)
  if b.hemothorax <= 1 then return false, "There is no blood in the chest cavity." end
  local drained = b.hemothorax
  b.hemothorax = 0
  b.limbs.thorax.skin = U.clamp(b.limbs.thorax.skin - 6, 0, 100)
  addPain(b.limbs.thorax, 22)
  return true, string.format("Chest drained. Breathing improves. (%.0f cleared)", drained)
end

--------------------------------------------------------------------- moodles

local function push(list, code, label, colour, sev)
  list[#list + 1] = { code = code, label = label, colour = colour, sev = sev or 1 }
end

function B.moodles(b)
  local c = CU.ui.c
  local out = {}
  local bleed = B.totalBleed(b)
  if bleed > 0.35 then push(out, "BLD", "catastrophic bleeding", c.crit, 3)
  elseif bleed > 0.12 then push(out, "bld", "heavy bleeding", c.blood, 2)
  elseif bleed > 0.018 then push(out, "bld", "bleeding", c.blood, 1) end
  if b.internal > 0.04 then push(out, "INT", "internal bleeding", c.crit, 3) end
  if b.hemothorax > 4 then push(out, "HTX", "hemothorax", c.crit, 3) end
  if b.blood < 3.4 then push(out, "HYP", "hypovolemic", c.crit, 3)
  elseif b.blood < 4.3 then push(out, "hyp", "blood loss", c.bad, 2) end
  if b.blood > 6.0 then push(out, "VOL", "hypervolemic", c.bad, 2) end
  if b.spo2 < 70 then push(out, "O2!", "critical hypoxemia", c.crit, 3)
  elseif b.spo2 < 88 then push(out, "o2", "hypoxemia", c.bad, 2) end
  if b.arrest then push(out, "ARR", "cardiac arrest", c.crit, 4) end
  if b.fib > 0 then push(out, "FIB", "fibrillation", c.crit, 3) end
  if b.respArrest then push(out, "RSP", "respiratory arrest", c.crit, 3) end
  if b.hr > 155 then push(out, "TAC", "tachycardia", c.bad, 2)
  elseif b.hr < 45 and not b.arrest then push(out, "BRA", "bradycardia", c.bad, 2) end
  if b.bp < 72 then push(out, "BP-", "severe hypotension", c.crit, 3)
  elseif b.bp < 88 then push(out, "bp-", "hypotension", c.bad, 2)
  elseif b.bp > 165 then push(out, "BP+", "hypertension", c.bad, 2) end
  local pain = select(1, B.effectivePain(b))
  if pain > 78 then push(out, "PAI", "agony", c.crit, 3)
  elseif pain > 52 then push(out, "pai", "severe pain", c.bad, 2)
  elseif pain > 26 then push(out, "pai", "in pain", c.warn, 1) end
  if b.opioid > 110 then push(out, "OD!", "opioid overdose", c.crit, 4)
  elseif b.opioid > 55 then push(out, "OPI", "heavily drugged", c.drug, 2)
  elseif b.opioid > 12 then push(out, "opi", "opiated", c.drug, 1) end
  if b.withdrawal > 45 then push(out, "WDR", "withdrawal", c.drug, 2) end
  if b.adren > 40 then push(out, "adr", "adrenaline", c.gold, 1) end
  if b.sepsis > 50 then push(out, "SEP", "septic shock", c.crit, 4)
  elseif b.sepsis > 12 then push(out, "sep", "sepsis", c.infect, 3) end
  local inf = 0
  for _, id in ipairs(D.LIMB_ORDER) do
    if b.limbs[id].revealed then inf = inf + 1 end
  end
  if inf > 0 then push(out, "INF", inf .. " infected", c.infect, 2) end
  if b.brain < 30 then push(out, "COM", "comatose", c.crit, 4)
  elseif b.brain < 60 then push(out, "NEU", "neurological damage", c.crit, 3)
  elseif b.brain < 80 then push(out, "neu", "neurological damage", c.bad, 2)
  elseif b.brain < 95 then push(out, "cog", "cognitive impairment", c.warn, 1) end
  if b.temp < 32 then push(out, "FRZ", "freezing to death", c.crit, 4)
  elseif b.temp < 35 then push(out, "col", "hypothermia", c.cold, 2)
  elseif b.temp > 40.5 then push(out, "HOT", "heatstroke", c.crit, 3)
  elseif b.temp > 38.4 then push(out, "fev", "fever", c.hot, 2) end
  if b.wet > 0.4 then push(out, "wet", "soaked", c.cold, 1) end
  if b.sick > 55 then push(out, "SIC", "sick", c.infect, 2)
  elseif b.sick > 22 then push(out, "sic", "queasy", c.warn, 1) end
  if b.hunger < 12 then push(out, "STV", "starving", c.crit, 3)
  elseif b.hunger < 34 then push(out, "hun", "hungry", c.warn, 1) end
  if b.thirst < 12 then push(out, "DEH", "dehydrated", c.crit, 3)
  elseif b.thirst < 34 then push(out, "thi", "thirsty", c.warn, 1) end
  if b.energy < 18 then push(out, "EXH", "exhausted", c.bad, 2)
  elseif b.energy < 40 then push(out, "tir", "tired", c.warn, 1) end
  if b.consciousness < T.CONSCIOUS_OUT then push(out, "OUT", "unconscious", c.crit, 4)
  elseif b.consciousness < 45 then push(out, "daz", "dazed", c.bad, 2) end
  local enc = B.encumbrance(b)
  if enc > 1.25 then push(out, "LOD", "overloaded", c.bad, 2)
  elseif enc > 1 then push(out, "lod", "heavy", c.warn, 1) end
  for _, id in ipairs(D.LIMB_ORDER) do
    if b.limbs[id].tourniquet then push(out, "TQ", "tourniquet", c.warn, 2); break end
  end
  if b.embolism then push(out, "EMB", "pulmonary embolism", c.crit, 4) end
  if b.trapped then push(out, "TRP", "leg trap", c.crit, 4) end
  if b.eyeLost then push(out, "EYE", "one eye", c.bad, 2) end
  if b.limbs.head.bone == "dislocated" then push(out, "JAW", "jaw out", c.bad, 2) end
  if b.amputations and b.amputations > 0 then push(out, "AMP", "amputated", c.crit, 3) end
  table.sort(out, function(x, y) return x.sev > y.sev end)
  return out
end

--------------------------------------------------------------------- the tick

local function stepOnce(b, dt, env, rng, events)
  local m = dt / 60   -- minutes
  local c = CU.ui.c

  ------------------------------------------------ bleeding and clotting
  local bleed = B.totalBleed(b)
  if bleed > 0 then
    b.blood = math.max(0, b.blood - bleed * m)
    b.bloodLost = (b.bloodLost or 0) + bleed * m
  end

  local clotBase = T.CLOT_BASE * (1 + b.visc / 100) * (1 + b.traits.res * 0.08)
  if b.blood < 3.5 then clotBase = clotBase * 0.75 end
  for _, id in ipairs(D.LIMB_ORDER) do
    local l = b.limbs[id]
    if l.bleed > 0 then
      local rate = clotBase
      if l.shrapnel > 0 then rate = rate * 0.15 end
      if l.dressing then rate = rate * (1 + l.dressing.stop * 2.2) end
      if l.tourniquet then rate = rate * 1.6 end
      if l.amputated and not l.tourniquet then rate = rate * 0.25 end
      l.bleed = math.max(0, l.bleed - rate * dt)
    end
    -- dressings soak and fail
    if l.dressing then
      local through = l.bleed * (1 - l.dressing.stop) + l.bleed * l.dressing.stop
      l.dressing.soak = l.dressing.soak + through * m
      if l.dressing.absorb > 0 and l.dressing.soak >= l.dressing.absorb then
        events[#events + 1] = { text = "The dressing on your " .. D.LIMBS[id].name ..
          " has soaked through.", colour = c.bad }
        l.dressing = nil
      end
    end
    -- tourniquet damage
    if l.tourniquet then
      l.tourniquet.time = l.tourniquet.time + dt
      addPain(l, 8 * m)
      if l.tourniquet.time > 360 then
        l.muscle = U.clamp(l.muscle - 0.9 * m, 0, 100)
        if not l.tqWarn and l.tourniquet.time > 400 then
          l.tqWarn = true
          events[#events + 1] = { text = "The limb under the tourniquet is dying. Take it off or lose it.",
            colour = c.crit }
        end
      end
    end
  end

  ------------------------------------------------ internal bleeding / hemothorax
  if b.limbs.abdomen.muscle < 22 or b.limbs.thorax.muscle < 22 then
    b.internal = b.internal + 0.0016 * m
  end
  if b.internal > 0 then
    b.internal = math.max(0, b.internal - 0.0006 * (1 + b.visc / 100) * m)
    if b.internal >= 0.0427 then
      b.hemothorax = b.hemothorax + (b.internal / 0.0427) * 2.64 * m
      addPain(b.limbs.thorax, b.internal * 0.25 * m * 60)
    end
  end
  if b.hemothorax > 0 then
    b.hemothorax = math.max(0, b.hemothorax - 0.1 * m)
  end

  ------------------------------------------------ bones
  for _, id in ipairs(D.LIMB_ORDER) do
    local l = b.limbs[id]
    if l.bone ~= "ok" and l.boneTimer > 0 then
      local rate = m
      if l.splint then rate = rate * l.splint.mult end
      if b.hunger < 20 then rate = rate * 0.5 end
      l.boneTimer = l.boneTimer - rate
      if l.boneTimer <= 0 then
        local was = l.bone
        l.bone = "ok"; l.boneTimer = 0
        b.mood = math.min(100, b.mood + 5)
        events[#events + 1] = { text = "Your " .. D.LIMBS[id].name .. " has healed.", colour = c.ok }
      end
    end
    -- bone injury caps muscle
    if l.bone ~= "ok" and l.muscle > 50 then l.muscle = 50 end
  end

  ------------------------------------------------ infection
  local totalInf = 0
  local feverSources = 0
  for _, id in ipairs(D.LIMB_ORDER) do
    local l = b.limbs[id]
    if l.disinfect > 0 then l.disinfect = l.disinfect - dt end
    if not l.amputated then
      local wound = (100 - l.skin) / 100
      if l.shrapnel > 0 then wound = wound + 0.15 * l.shrapnel end
      local immFactor = U.clamp((160 - b.immunity) / 60, 0.35, 2.5)
      if l.disinfect > 0 then
        -- antiseptic holds it and pushes it back
        l.infection = math.max(0, l.infection - 0.4 * m)
      elseif wound > 0.08 then
        local rate = T.INFECT_RATE * wound * immFactor * (1 + (env.dirty or 0))
        l.infection = U.clamp(l.infection + rate * m, 0, 100)
      elseif l.infection < T.INFECT_REVEAL then
        -- a closed wound sheds a small contamination on its own
        l.infection = math.max(0, l.infection - 0.3 * m)
      end
      if l.infection >= T.INFECT_REVEAL and not l.revealed then
        l.revealed = true
        events[#events + 1] = { text = "The wound on your " .. D.LIMBS[id].name ..
          " is infected.", colour = c.infect }
      end
      if l.infection >= 75 then
        l.skin = math.max(0, l.skin - 0.9 * m)
      end
      if l.revealed then feverSources = feverSources + 1 end
      totalInf = totalInf + l.infection
    end
  end
  if totalInf > T.SEPSIS_AT then
    b.sepsis = U.clamp(b.sepsis + (totalInf - T.SEPSIS_AT) * 0.02 * m, 0, 100)
  else
    b.sepsis = math.max(0, b.sepsis - 0.6 * m)
  end
  b.immunity = U.clamp(b.immunity + 0.25 * m
    - (b.sepsis > 0 and 0.5 * m or 0), 10, 130)

  ------------------------------------------------ pain
  local relief = 0
  if b.painRelief and b.painRelief > 0 then
    local shed = math.min(b.painRelief, (b.painReliefRamp or 40) * m)
    relief = shed
    b.painRelief = b.painRelief - shed * 0.35
  end
  for _, id in ipairs(D.LIMB_ORDER) do
    local l = b.limbs[id]
    local floor = 0
    if not l.amputated then
      floor = (100 - l.skin) / T.SKIN_PAIN_DIV
        + (100 - l.muscle) / T.MUSCLE_PAIN_DIV
        + (l.bone == "fractured" and 34 or l.bone == "dislocated" and 20 or 0)
        + l.shrapnel * 4.5 + l.burn * 0.45 + l.infection * 0.22
      if l.splint and l.bone ~= "ok" then floor = floor - 8 end
      if l.tourniquet then floor = floor + 18 end
    else
      floor = 30
    end
    floor = U.clamp(floor, 0, 100)
    local decay = T.PAIN_DECAY * (1 + (l.chill > 0 and 1.5 or 0)) * m
      + relief * 0.12 * D.LIMBS[id].painWeight
    if l.pain > floor then
      l.pain = math.max(floor, l.pain - decay)
    else
      l.pain = math.min(floor, l.pain + T.PAIN_DECAY * 1.4 * m)
    end
    if l.chill > 0 then l.chill = l.chill - dt end
    if l.warm > 0 then l.warm = l.warm - dt end
    if l.burn > 0 then l.burn = math.max(0, l.burn - 0.5 * m) end
  end

  ------------------------------------------------ drugs
  b.opioid = math.max(0, b.opioid - 0.55 * m * (1 + b.traits.res * 0.05))
  b.adren = math.max(0, b.adren - 4.5 * m)
  b.tolerance = math.max(0, b.tolerance - 0.05 * m)
  if b.tolerance > 25 and b.opioid < 4 then
    b.withdrawal = U.clamp(b.withdrawal + 0.5 * m, 0, 100)
  else
    b.withdrawal = math.max(0, b.withdrawal - 1.2 * m)
  end
  if b.withdrawal > 40 then
    b.mood = math.max(0, b.mood - 0.8 * m)
    b.sick = U.clamp(b.sick + 0.5 * m, 0, 100)
  end
  if b.held and b.held > 0 then b.held = math.max(0, b.held - m) end
  if b.trapped then
    b.trapped.timer = b.trapped.timer - dt
    local l = b.limbs[b.trapped.limb]
    if l then
      l.bleed = math.max(l.bleed, 0.09)
      addPain(l, 3 * m)
    end
    if b.trapped.timer <= 0 then b.trapped = nil end
  end
  if b.hrKick then b.hrKick = b.hrKick * (1 - 0.35 * m) end
  if b.respMod then b.respMod = b.respMod * (1 - 0.25 * m) end
  if b.crash and b.crash > 0 then
    b.crash = math.max(0, b.crash - 0.02 * m)
    b.energy = math.max(0, b.energy - b.crash * 2 * m)
  end
  if b.opioid > 110 then
    b.respArrest = true
    b.brain = math.max(0, b.brain - 0.6 * m)
    b.temp = b.temp - 0.02 * m
  elseif b.opioid < 90 and b.respArrest and not b.arrest then
    local stillArrested = false
    for _, id in ipairs(D.LIMB_ORDER) do
      if b.limbs[id].tourniquet and id == "head" then stillArrested = true end
    end
    if not stillArrested then b.respArrest = false end
  end

  ------------------------------------------------ oxygen and circulation
  -- Saturation holds up until volume gets genuinely low, then falls off a cliff.
  local maxO2 = 100
  if b.blood < 4.5 then
    if b.blood >= T.BLOOD_CAP_FLOOR then
      maxO2 = U.remap(b.blood, T.BLOOD_CAP_FLOOR, 4.5, 30, 100)
    else
      maxO2 = U.remap(b.blood, 1.0, T.BLOOD_CAP_FLOOR, 0, 30)
    end
  end
  maxO2 = maxO2 - b.hemothorax * 0.3 - b.sepsis * 0.22
  if math.abs(b.visc) > 40 then maxO2 = maxO2 - (math.abs(b.visc) - 40) * 0.4 end
  if b.limbs.thorax.muscle < 30 then maxO2 = maxO2 - (30 - b.limbs.thorax.muscle) * 0.9 end
  maxO2 = U.clamp(maxO2, 0, 100)
  b.maxO2 = maxO2

  local resp = T.RESP_BASE + (env.exertion or 0) * 8 - b.opioid * 0.16
    - b.hemothorax * 0.125 + (b.respMod or 0)
  if b.limbs.thorax.muscle <= 0 then resp = 0 end
  if b.respArrest or b.arrest then resp = 0 end
  b.resp = U.clamp(resp, 0, 44)

  if b.resp > 12.5 and not b.arrest then
    b.spo2 = U.approach(b.spo2, maxO2, 26 * m)
  else
    b.spo2 = math.max(0, b.spo2 - 36 * m)
  end
  if b.spo2 > maxO2 then b.spo2 = U.approach(b.spo2, maxO2, 40 * m) end

  local fever = math.max(0, b.temp - 37.2)
  local hr = T.HR_BASE + b.adren * 0.55 + select(1, B.effectivePain(b)) * 0.28
    + (T.BLOOD_FULL - b.blood) * 16 + (env.exertion or 0) * 26
    - b.opioid * 0.3 + fever * 6 + (b.hrKick or 0) + b.sepsis * 0.3
  if b.temp < 34 then hr = hr - (34 - b.temp) * 6 end
  b.hr = U.clamp(hr, 0, 235)
  if b.arrest then b.hr = 0 end

  b.bp = U.clamp(T.BP_BASE + b.adren * 0.25 - (T.BLOOD_FULL - b.blood) * 13
    - b.sepsis * 0.5 - b.opioid * 0.22 + (b.visc > 60 and (b.visc - 60) * 0.4 or 0), 0, 210)

  -- fibrillation and arrest
  if b.hr > 195 and not b.arrest then b.fib = math.min(100, b.fib + 6 * m) end
  if math.abs(b.visc) > 88 then
    if rng:chance(0.02 * m * 60) then
      b.embolism = true
      events[#events + 1] = { text = "A clot has reached your lung.", colour = c.crit }
    end
  elseif math.abs(b.visc) < 50 then
    b.embolism = false
  end
  if b.embolism then
    b.limbs.thorax.muscle = math.max(0, b.limbs.thorax.muscle - 36 * m)
  end
  if b.fib > 0 then
    b.fib = b.fib + 3 * m
    b.spo2 = math.max(0, b.spo2 - 14 * m)
    if b.fib > 100 and not b.arrest then
      b.arrest = true
      events[#events + 1] = { text = "The heart stops.", colour = c.crit }
      CU.ui.sfx("alarm")
    end
  end
  if b.blood < 1.6 and not b.arrest and rng:chance(0.03 * m * 60) then
    b.arrest = true
    events[#events + 1] = { text = "You have lost too much blood. Your heart has stopped.", colour = c.crit }
  end
  if b.arrest then
    b.arrestTime = b.arrestTime + dt
    b.brain = math.max(0, b.brain - 1.6 * m)
  end
  b.visc = U.approach(b.visc, 0, 3 * m)

  ------------------------------------------------ brain and consciousness
  if b.spo2 < 55 then
    b.brain = math.max(0, b.brain - (55 - b.spo2) * 0.06 * m)
  elseif not b.arrest then
    b.brain = math.min(100, b.brain + T.BRAIN_REGEN * m * (b.energy > 25 and 1 or 0.4))
  end
  if b.temp > 40.5 then b.brain = math.max(0, b.brain - (b.temp - 40.5) * 1.4 * m) end


  local o2cap
  if b.spo2 >= 90 then o2cap = 100
  elseif b.spo2 >= 50 then o2cap = U.remap(b.spo2, 50, 90, 22, 100)
  else o2cap = U.remap(b.spo2, 0, 50, 0, 22) end
  local painCap = 100 - math.max(0, select(1, B.effectivePain(b)) - 68) * 2.4
  local opioidCap = 100 - math.max(0, b.opioid - 60) * 1.4
  local energyCap = b.energy < 12 and (40 + b.energy * 4) or 100
  local cap = math.min(b.brain, o2cap, painCap, opioidCap, energyCap, 100)
  if b.sleepy and b.sleepy > 0 then
    b.sleepy = b.sleepy - dt
    cap = math.min(cap, 30)
  end
  if cap < b.consciousness then
    b.consciousness = math.max(cap, b.consciousness - 70 * m)
  else
    b.consciousness = math.min(cap, b.consciousness + 34 * m)
  end

  ------------------------------------------------ temperature
  local ambient = (env.temp or 20)
  local warmth = (b.gear.warmth or 0) + (env.heat or 0)
  local effective = ambient + warmth * 1.6 + (env.exertion or 0) * 6
  if b.wet > 0.2 then effective = effective - 9 * b.wet end
  if b.oil then effective = effective - 3 end
  local target = U.clamp(28 + (effective - 4) * 0.28, 20, 45)
  local drift = (target - b.temp) * 0.012 * m
  b.temp = b.temp + drift
  if feverSources > 0 and b.temp < 40.5 then
    b.temp = math.min(40.5, b.temp + 0.08 * feverSources * m)
  end
  if b.sepsis > 20 then b.temp = math.min(41.5, b.temp + 0.02 * m) end
  b.wet = math.max(0, b.wet - 0.02 * m * (b.temp > 20 and 1.4 or 0.7))
  if b.wet <= 0 then b.oil = false end
  if b.temp < 35 then
    b.energy = math.max(0, b.energy - (35 - b.temp) * 0.4 * m)
  end
  if b.temp < 28 then
    b.consciousness = math.max(0, b.consciousness - 8 * m)
    b.hr = math.max(0, b.hr - 20)
  end
  if b.temp > 41.5 then b.sick = U.clamp(b.sick + 3 * m, 0, 100) end

  ------------------------------------------------ needs
  local burn = 1 + (env.exertion or 0) * 1.4
  b.hunger = U.clamp(b.hunger - T.HUNGER_RATE * burn * m, 0, 120)
  b.thirst = U.clamp(b.thirst - T.THIRST_RATE * burn * (b.temp > 38 and 1.5 or 1) * m, 0, 120)
  if env.resting then
    b.energy = U.clamp(b.energy + 3.2 * m, 0, 100)
  else
    b.energy = U.clamp(b.energy - T.ENERGY_RATE * burn * m, 0, 100)
  end
  if b.hunger <= 0 then
    for _, id in ipairs(D.LIMB_ORDER) do
      b.limbs[id].muscle = math.max(0, b.limbs[id].muscle - 0.5 * m)
    end
  end
  if b.thirst <= 0 then b.visc = U.clamp(b.visc + 1.6 * m, -100, 100) end
  if b.sick > 0 then b.sick = math.max(0, b.sick - 0.5 * m) end
  if b.sick > 70 and rng:chance(0.02 * m * 60) then
    b.hunger = math.max(0, b.hunger - 18)
    b.consciousness = math.max(0, b.consciousness - 10)
    events[#events + 1] = { text = "You throw up.", colour = c.warn }
  end

  ------------------------------------------------ natural repair
  if b.hunger > 15 and b.blood > 3 then
    for _, id in ipairs(D.LIMB_ORDER) do
      local l = b.limbs[id]
      if not l.amputated and l.infection < T.INFECT_REVEAL and l.shrapnel == 0 then
        local rate = (env.resting and 2.2 or 0.55) * m * (1 + b.traits.res * 0.1)
        if l.skin < 100 then l.skin = math.min(100, l.skin + rate * 0.7) end
        local cap = (l.bone ~= "ok") and 50 or 100
        if l.muscle < cap then l.muscle = math.min(cap, l.muscle + rate * 0.35) end
      end
    end
  end

  ------------------------------------------------ mood
  local moodTarget = 62 - select(1, B.effectivePain(b)) * 0.3 - (100 - b.hunger) * 0.08
    - (100 - b.thirst) * 0.06 - b.sick * 0.15 - (100 - b.brain) * 0.2
    + (b.gear.mood or 0)
  b.mood = U.approach(b.mood, U.clamp(moodTarget, 0, 100), 3 * m)

  ------------------------------------------------ death
  if not b.dead then
    if b.blood <= T.BLOOD_DEAD then
      b.dead = true; b.cause = "exsanguination"
    elseif b.brain <= 0 then
      b.dead = true; b.cause = "loss of brain function"
    elseif b.arrest and b.arrestTime > T.ARREST_GRACE then
      b.dead = true; b.cause = "cardiac arrest"
    elseif b.temp < 24 then
      b.dead = true; b.cause = "hypothermia"
    elseif b.temp > 43 then
      b.dead = true; b.cause = "hyperthermia"
    end
    if b.dead then
      events[#events + 1] = { text = "", colour = c.crit }
      CU.ui.sfx("death")
    end
  end
end

-- Public tick. dt in seconds, sliced internally.
function B.tick(b, dt, env, rng)
  env = env or {}
  local events = {}
  if b.dead then return events end
  local remaining = dt
  local slice = (dt > 120) and 10 or 2
  local guard = 0
  while remaining > 0 and not b.dead and guard < 4000 do
    local step = math.min(slice, remaining)
    stepOnce(b, step, env, rng, events)
    remaining = remaining - step
    guard = guard + 1
  end
  -- collapse duplicate messages
  local seen, out = {}, {}
  for i = 1, #events do
    local key = events[i].text
    if key ~= "" and not seen[key] then
      seen[key] = true
      out[#out + 1] = events[i]
    end
  end
  return out
end

function B.status(b)
  if b.dead then return "deceased" end
  if b.consciousness < T.CONSCIOUS_OUT then return "unconscious" end
  return "ambulatory"
end

CU.body = B
return B

end
