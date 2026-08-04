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

  say(string.format("You fall %d m and land on %s.", math.floor(metres), surface.name),
      eff > 30 and c.crit or c.warn)
  CU.ui.sfx(eff > 30 and "crack" or "hurt")

  -- which legs take it
  local legs = {}
  for _, id in ipairs({ "lleg", "rleg" }) do
    if not body.limbs[id].amputated then legs[#legs + 1] = id end
  end
  if #legs == 0 then legs = { "abdomen" } end

  -- the first leg down takes more than the second
  local share = { 1.0, 0.78 }
  for i, id in ipairs(legs) do
    local s = share[i] or 0.6
    local hit = {
      muscle = eff * 0.85 * s * (1 - sharp * 0.45),
      skin   = eff * 0.50 * s * (0.30 + sharp),
      bleed  = eff * 0.0055 * s * sharp * 2.2,
      pain   = eff * 1.30 * s,
    }
    B.hurt(body, hit, rng, { limb = id, silent = true })

    local l = body.limbs[id]
    local fracP = ((eff * s) - 18) / 90 * (1 - sharp * 0.4)
    local disloP = ((eff * s) - 7) / 45
    if chance(rng, fracP) then
      B.breakBone(body, id, rng, out)
    elseif chance(rng, disloP) then
      B.dislocate(body, id, rng, out)
    end
    if sharp > 0.5 and chance(rng, (eff * s - 10) / 140) then
      l.shrapnel = l.shrapnel + rng:int(1, 2)
      say("Rock fragments are lodged in your " .. D.LIMBS[id].name .. ".", c.warn)
    end
  end

  -- you put your hands out
  if chance(rng, (eff - 32) / 190) then
    local arm = rng:pick({ "larm", "rarm" })
    if not body.limbs[arm].amputated then
      B.hurt(body, {
        muscle = eff * 0.35, skin = eff * 0.28 * (0.3 + sharp),
        bleed = eff * 0.002 * sharp, pain = eff * 0.7,
      }, rng, { limb = arm, silent = true })
      if chance(rng, (eff - 45) / 150) then
        B.breakBone(body, arm, rng, out)
      elseif chance(rng, (eff - 25) / 90) then
        B.dislocate(body, arm, rng, out)
      end
    end
  end

  -- the trunk folds
  if eff > 25 then
    B.hurt(body, { muscle = eff * 0.22, pain = eff * 0.4 }, rng,
      { limb = "abdomen", silent = true })
  end
  local internalP = (eff - 45) / 300
  if chance(rng, internalP) then
    body.internal = body.internal + eff * 0.00035
    say("Something has torn inside you.", c.crit)
  end

  -- the head, last, and only from a real height
  local headP = (eff - 60) / 280 * (1 - (gear.skullGuard or 0))
  if chance(rng, headP) then
    B.hurt(body, {
      muscle = eff * 0.18, skin = eff * 0.2 * (0.3 + sharp), pain = eff * 0.5,
    }, rng, { limb = "head", silent = true })
    body.brain = U.clamp(body.brain - eff * 0.06, 0, 100)
    say("Your head hit the ground.", c.crit)
  end

  body.adren = math.min(100, body.adren + math.min(70, eff * 0.9))
  return out
end

CU.fall = F
return F

end
