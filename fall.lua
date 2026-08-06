-- WRITE-OFF / lib/fall.lua
-- Falling is the main way this game hurts you. It only counts if you descended.

return function(CU)

local U = CU.util
local D = CU.data
local F = {}

-- How far you can drop onto bare stone before anything happens at all.
F.FREE_DROP = 3

--[[
  Distance and surface decide everything.

    effective = metres * (1 - cushion) * hardness, minus what your boots absorb

  A moss bed takes about three quarters of the impact out of a fall. Broken rock
  takes none of it and turns most of what is left into punctures rather than
  crush injuries. Bare stone is the baseline.

  Rough shape of the curve, landing on bare stone with no gear:

     under 3 m   nothing
       3 - 12 m  bruising, a little pain
      12 - 30 m  torn muscle, a joint may come out
      30 - 60 m  a joint almost certainly, a fracture becomes likely
     60 - 150 m  legs break, arms often follow
    150 - 400 m  multiple fractures, internal bleeding, head injury
        400 m +  usually fatal, not always
]]

function F.effective(metres, surface, gear)
  local eff = metres * (1 - (surface.cushion or 0)) * (surface.hard or 0.9)
  local boots = (gear and gear.fallGuard or 0)
  eff = eff * (1 - U.clamp(boots, 0, 0.55))
  return math.max(0, eff)
end

-- Predict what a drop from here would cost, for the ledge-peek readout.
function F.forecast(metres, surface, gear)
  local eff = F.effective(metres, surface, gear)
  if eff < F.FREE_DROP then return "safe", eff end
  if eff < 12 then return "bruising", eff end
  if eff < 30 then return "torn muscle", eff end
  if eff < 60 then return "joints and bones", eff end
  if eff < 150 then return "broken legs", eff end
  if eff < 400 then return "severe, multiple", eff end
  return "probably fatal", eff
end

local function chance(rng, p) return rng:chance(U.clamp(p, 0, 0.97)) end

-- Resolve a landing. Returns a list of { text, colour } lines in plain language.
--[[
  How you land matters as much as how far you fell. Slow drops you take on your
  feet, which is what legs are for. Past that you tip, and once you are tipping
  the ground meets your hands, your ribs and eventually your head instead.

  So the same fifty metres is a pair of broken legs or a broken arm and a torn
  chest, depending on whether you kept your feet under you.
]]
local SHARE = {
  feet = { legs = 1.00, arms = 0.42, trunk = 0.30, head = 0.18, how = "feet first" },
  side = { legs = 0.58, arms = 0.95, trunk = 0.75, head = 0.48, how = "on your side" },
  flat = { legs = 0.30, arms = 0.85, trunk = 1.00, head = 0.90, how = "flat, back first" },
}

function F.land(body, metres, surfaceChar, rng)
  local B = CU.body
  local Tl = CU.tiles
  local c = CU.ui.c
  local out = {}
  local function say(t, col) out[#out + 1] = { text = t, colour = col or c.text } end

  local surface = Tl.impact(surfaceChar)
  local gear = body.gear or {}
  local eff = F.effective(metres, surface, gear)
  local sharp = surface.sharp or 0.1

  body.lastFall = { metres = metres, surface = surface.name, effective = eff }

  if metres < 1 then return out end

  if eff < F.FREE_DROP then
    if metres >= 4 then
      say(string.format("You drop %d m onto %s. No damage.", math.floor(metres), surface.name), c.dim)
    end
    return out
  end

  -- keeping your feet gets harder the faster you arrive
  local composure = U.clamp(1 - (eff - 8) / 82, 0.10, 0.95)
  composure = composure * U.clamp(0.55 + B.mobility(body) * 0.5, 0.35, 1.1)
  local roll = rng:float()
  local landing
  if roll < composure then landing = "feet"
  elseif roll < composure + (1 - composure) * 0.58 then landing = "side"
  else landing = "flat" end
  local sh = SHARE[landing]
  body.lastFall.landing = landing

  say(string.format("You fall %d m and land %s on %s.",
      math.floor(metres), sh.how, surface.name),
      eff > 30 and c.crit or c.warn)
  CU.ui.sfx(eff > 30 and "crack" or "hurt")
  CU.ui.flash({ 1, 0.05, 0.05 }, U.clamp(0.35 + eff / 90, 0.35, 1))

  ------------------------------------------------------------------ legs
  local legs = {}
  for _, id in ipairs({ "lleg", "rleg" }) do
    if not body.limbs[id].amputated then legs[#legs + 1] = id end
  end
  if #legs == 0 then legs = { "abdomen" } end
  local legShare = { 1.0, 0.78 }
  for i, id in ipairs(legs) do
    local s = (legShare[i] or 0.6) * sh.legs
    B.hurt(body, {
      muscle = eff * 0.85 * s * (1 - sharp * 0.45),
      skin   = eff * 0.50 * s * (0.30 + sharp),
      bleed  = eff * 0.0055 * s * sharp * 2.2,
      pain   = eff * 1.30 * s,
    }, rng, { limb = id, silent = true })

    local load = eff * s
    if chance(rng, (load - 18) / 90 * (1 - sharp * 0.4)) then
      B.breakBone(body, id, rng, out)
    elseif chance(rng, (load - 7) / 45) then
      B.dislocate(body, id, rng, out)
    end
    if sharp > 0.5 and chance(rng, (load - 10) / 140) then
      body.limbs[id].shrapnel = body.limbs[id].shrapnel + rng:int(1, 2)
      say("Rock fragments are lodged in your " .. D.LIMBS[id].name .. ".", c.warn)
    end
  end

  ------------------------------------------------------------------ arms
  -- both of them, independently, because you do not fall on one hand
  for _, arm in ipairs({ "larm", "rarm" }) do
    if not body.limbs[arm].amputated then
      local load = eff * sh.arms * (rng:chance(0.5) and 1.0 or 0.7)
      if load > 7 then
        B.hurt(body, {
          muscle = load * 0.45,
          skin   = load * 0.34 * (0.3 + sharp),
          bleed  = load * 0.0022 * sharp,
          pain   = load * 0.75,
        }, rng, { limb = arm, silent = true })
        if chance(rng, (load - 24) / 105) then
          B.breakBone(body, arm, rng, out)
        elseif chance(rng, (load - 11) / 58) then
          B.dislocate(body, arm, rng, out)
        end
      end
    end
  end

  ------------------------------------------------------------------ trunk
  local trunk = eff * sh.trunk
  if trunk > 12 then
    B.hurt(body, { muscle = trunk * 0.32, pain = trunk * 0.55 }, rng,
      { limb = "abdomen", silent = true })
    if landing ~= "feet" then
      B.hurt(body, { muscle = trunk * 0.26, skin = trunk * 0.2 * (0.3 + sharp),
                     pain = trunk * 0.45 }, rng, { limb = "thorax", silent = true })
    end
  end
  if chance(rng, (trunk - 34) / 250) then
    body.internal = body.internal + eff * 0.00035
    say("Something has torn inside you.", c.crit)
  end

  ------------------------------------------------------------------ head
  local headLoad = eff * sh.head
  if chance(rng, (headLoad - 26) / 195 * (1 - (gear.skullGuard or 0))) then
    B.hurt(body, {
      muscle = headLoad * 0.2, skin = headLoad * 0.22 * (0.3 + sharp),
      pain = headLoad * 0.55,
    }, rng, { limb = "head", silent = true })
    body.brain = U.clamp(body.brain - headLoad * 0.07, 0, 100)
    say("Your head hit the ground.", c.crit)
  end

  body.adren = math.min(100, body.adren + math.min(70, eff * 0.9))
  return out
end

CU.fall = F
return F

end
