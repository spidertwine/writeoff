-- WRITE-OFF / lib/data.lua
-- All content and tuning. Edit numbers here rather than in the simulation.

return function(CU)

local U = CU.util
local D = {}

--------------------------------------------------------------------- tuning

D.TUNE = {
  BLOOD_FULL        = 5.00,   -- litres
  BLOOD_DEAD        = 0.85,
  BLOOD_CAP_FLOOR   = 2.78,   -- below this, oxygen ceiling drops through 30%
  CLOT_BASE         = 0.0022, -- L/min of bleed removed per second, before modifiers
  SKIN_PAIN_DIV     = 6.667,  -- skin damage per point of pain
  MUSCLE_PAIN_DIV   = 5.0,
  PAIN_DECAY        = 0.55,   -- points per minute
  BONE_HEAL_MIN     = 39,     -- minutes for an untended fracture
  DISLO_HEAL_MIN    = 14,
  SPLINT_MULT       = 2.5,
  WELDER_DIV        = 4,
  INFECT_REVEAL     = 25,
  INFECT_RATE       = 0.35,   -- points per minute at skin 0, immunity 100
  SEPSIS_AT         = 200,    -- summed infection across limbs
  BRAIN_REGEN       = 0.18,   -- percent per minute
  RESP_BASE         = 14,
  HR_BASE           = 72,
  BP_BASE           = 112,
  TEMP_BASE         = 36.8,
  HUNGER_RATE       = 0.55,   -- percent per minute
  THIRST_RATE       = 0.78,
  ENERGY_RATE       = 0.30,
  CARRY_BASE        = 22,     -- kg before encumbrance
  ARREST_GRACE      = 240,    -- seconds of cardiac arrest before death
  CONSCIOUS_OUT     = 8,      -- below this the subject cannot act
}

--------------------------------------------------------------------- limbs

D.LIMB_ORDER = { "head", "thorax", "abdomen", "larm", "rarm", "lleg", "rleg" }

D.LIMBS = {
  head    = { name = "head",      short = "HEAD", key = "1", vital = true,  bleedMult = 1.35, painWeight = 1.4, side = "c" },
  thorax  = { name = "thorax",    short = "THRX", key = "2", vital = true,  bleedMult = 1.20, painWeight = 1.2, side = "c" },
  abdomen = { name = "abdomen",   short = "ABDO", key = "3", vital = true,  bleedMult = 1.15, painWeight = 1.1, side = "c" },
  larm    = { name = "left arm",  short = "L.AR", key = "4", limb = true,   bleedMult = 0.90, painWeight = 0.9, side = "l", arm = true },
  rarm    = { name = "right arm", short = "R.AR", key = "5", limb = true,   bleedMult = 0.90, painWeight = 0.9, side = "r", arm = true },
  lleg    = { name = "left leg",  short = "L.LG", key = "6", limb = true,   bleedMult = 1.00, painWeight = 1.0, side = "l", leg = true },
  rleg    = { name = "right leg", short = "R.LG", key = "7", limb = true,   bleedMult = 1.00, painWeight = 1.0, side = "r", leg = true },
}

-- limbs a tourniquet on X also chokes off
D.TOURNIQUET_GROUP = {
  larm = { "larm" }, rarm = { "rarm" }, lleg = { "lleg" }, rleg = { "rleg" },
  head = { "head" },
}

D.WEAR_SLOTS = { "head", "face", "torso", "hands", "legs", "feet", "back" }

--------------------------------------------------------------------- items

D.ITEMS = {}

local function item(id, t)
  t.id = id
  t.stack = t.stack or 1
  t.mass = t.mass or 0.1
  t.tier = t.tier or 1
  t.value = t.value or 1
  t.short = t.short or t.name
  D.ITEMS[id] = t
  return t
end

-- ---- dressings -------------------------------------------------------
-- stop:   fraction of a limb's bleed held back while the dressing holds
-- absorb: litres it can soak before it fails
-- time:   seconds to apply

item("rag_strip", { name = "rag strip", short = "rag", kind = "dressing", mass = 0.04, stack = 8, value = 1,
  desc = "Torn cloth. Slows light bleeding. Soaks through fast and can cause infection.",
  dressing = { stop = 0.38, absorb = 0.14, skin = 2, time = 9, infect = 0.22 } })

item("field_dressing", { name = "field dressing", short = "dressing", kind = "dressing", mass = 0.07, stack = 6, value = 4,
  desc = "Sealed pad and tie. Stops most bleeding on one limb. The reliable first choice.",
  dressing = { stop = 0.70, absorb = 0.38, skin = 7, time = 12 } })

item("gauze_roll", { name = "gauze roll", short = "gauze", kind = "dressing", mass = 0.11, stack = 4, value = 7,
  desc = "Long cotton wrap. Stops heavy bleeding and holds a lot before it soaks through.",
  dressing = { stop = 0.86, absorb = 0.62, skin = 11, bone = 0.25, time = 20 } })

item("pressure_pack", { name = "pressure pack", short = "pres.pack", kind = "dressing", mass = 0.15, stack = 3, value = 11,
  desc = "Pad with a windlass strap. Stops nearly all bleeding. Hurts going on.",
  dressing = { stop = 0.95, absorb = 0.9, skin = 6, pain = 8, time = 22 } })

item("polymer_seal", { name = "polymer seal", short = "seal", kind = "dressing", mass = 0.09, stack = 4, value = 9,
  desc = "Sets rigid over the wound. Stops bleeding and holds a broken bone still.",
  dressing = { stop = 0.78, absorb = 0.5, skin = 9, bone = 0.9, time = 18 } })

item("bruise_pack", { name = "bruise pack", short = "bruise pk", kind = "dressing", mass = 0.22, stack = 3, value = 13,
  desc = "Cold compound sachet. Reduces pain in one limb.",
  dressing = { stop = 0.4, absorb = 0.24, skin = 14, muscle = 20, dislo = 0.45, time = 24 } })

item("clot_agent", { name = "clotting agent", short = "clot", kind = "dressing", mass = 0.05, stack = 4, value = 18,
  desc = "Granules that clot on contact. Stops bleeding instantly. Burns, and thickens the blood.",
  dressing = { stop = 1.0, absorb = 0, skin = -3, pain = 20, visc = 14, instant = true, time = 14 } })

item("burn_gel", { name = "burn gel", short = "burn gel", kind = "dressing", mass = 0.1, stack = 3, value = 8,
  desc = "Cooling gel and cover. Treats burns.",
  dressing = { stop = 0.3, absorb = 0.2, skin = 16, burn = true, pain = -10, time = 16 } })

-- ---- medical tools ---------------------------------------------------

item("tourniquet", { name = "tourniquet", short = "tourniq.", kind = "tool", mass = 0.09, stack = 2, value = 12, tier = 1,
  desc = "Strap and windlass. Stops all bleeding in a limb. The limb starts dying after six minutes.",
  tool = { type = "tourniquet", time = 16 } })

item("splint", { name = "splint", short = "splint", kind = "tool", mass = 0.35, stack = 2, value = 10,
  desc = "Moulded brace. Heals bone 2.5 times faster and restores some use of the limb.",
  tool = { type = "splint", time = 22, mult = D.TUNE.SPLINT_MULT } })

item("makeshift_splint", { name = "makeshift splint", short = "m.splint", kind = "tool", mass = 0.5, stack = 2, value = 3,
  desc = "Scrap and cloth. Works like a splint, not as well.",
  tool = { type = "splint", time = 30, mult = 1.7 } })

item("joint_wrench", { name = "joint wrench", short = "wrench", kind = "tool", mass = 0.65, stack = 1, value = 16, tier = 2,
  desc = "Weighted lever. Setting a dislocated joint works far more often, and hurts much less.",
  tool = { type = "wrench", steady = 0.28, painMult = 0.35 } })

item("forceps", { name = "forceps", short = "forceps", kind = "tool", mass = 0.04, stack = 1, value = 14, tier = 1,
  desc = "Sprung gripping tool. Makes pulling shrapnel out far more reliable.",
  tool = { type = "forceps", steady = 0.34 } })

item("bone_welder", { name = "bone welder", short = "welder", kind = "tool", mass = 1.15, stack = 1, value = 40, tier = 3,
  desc = "Induction coil. Cuts the remaining fracture time to a quarter. Burns the flesh around it.",
  tool = { type = "welder", charges = 6, time = 26 } })

item("chest_drain", { name = "chest drain", short = "drain", kind = "tool", mass = 0.28, stack = 2, value = 34, tier = 3,
  desc = "Catheter, valve and bag. Drains blood out of the chest cavity.",
  tool = { type = "drain", time = 40, uses = 1 } })

item("suture_kit", { name = "suture kit", short = "sutures", kind = "tool", mass = 0.13, stack = 1, value = 22, tier = 2,
  desc = "Curved needle and thread. Closes a wound properly. Needs steady hands.",
  tool = { type = "suture", charges = 5, time = 45, steady = 0.0 } })

item("auto_pump", { name = "auto-pump", short = "autopump", kind = "wear", mass = 0.95, stack = 1, value = 55, tier = 4,
  desc = "Chest harness. Keeps you breathing if you stop.",
  wear = { slot = "torso", pump = true, warmth = 1 } })

item("defibrillator", { name = "defibrillator", short = "defib", kind = "tool", mass = 2.2, stack = 1, value = 60, tier = 4,
  desc = "Paddles and capacitor. Restarts a stopped or fibrillating heart. Burns the chest.",
  tool = { type = "defib", charges = 4, time = 20 } })

item("drop_gauge", { name = "drop gauge", short = "gauge", kind = "tool", mass = 0.3, stack = 1, value = 16,
  desc = "Laser rangefinder. Shows the exact drop and landing surface beside any ledge you stand on.",
  tool = { type = "gauge" } })

item("terrain_scanner", { name = "terrain scanner", short = "scanner", kind = "tool", mass = 0.45, stack = 1, value = 26, tier = 2,
  desc = "Handheld scanner. Reveals the map for a wide area around you.",
  tool = { type = "scanner", charges = 12, time = 8 } })

-- ---- drugs -----------------------------------------------------------

item("painkillers", { name = "painkillers", short = "painkill", kind = "drug", mass = 0.02, stack = 12, value = 5,
  desc = "Oral tablets. Reduces pain a moderate amount. Does not affect breathing.",
  drug = { via = "oral", time = 6, pain = -22, ramp = 60, sick = 2 } })

item("opiate_amp", { name = "opiate ampoule", short = "opiate", kind = "drug", mass = 0.03, stack = 8, value = 15, tier = 2,
  desc = "Injected opiate. Removes most pain. Too many doses stop you breathing.",
  drug = { via = "inject", time = 8, opioid = 26, pain = -55, ramp = 25 } })

item("fentanyl", { name = "fentanyl patch", short = "fentanyl", kind = "drug", mass = 0.01, stack = 6, value = 34, tier = 3,
  desc = "Removes all pain in about a minute. One patch is a dose. Two will stop you breathing. Keep naloxone on you.",
  drug = { via = "patch", time = 25, opioid = 74, pain = -100, ramp = 55 } })

item("naloxone", { name = "naloxone", short = "naloxone", kind = "drug", mass = 0.03, stack = 4, value = 20, tier = 3,
  desc = "Reverses an opiate overdose in under a minute. Every masked pain returns at once.",
  drug = { via = "inject", time = 8, opioidClear = true } })

item("adrenaline", { name = "adrenaline shot", short = "adren.", kind = "drug", mass = 0.04, stack = 6, value = 17, tier = 2,
  desc = "Thigh injector. Masks pain and raises heart rate for a few minutes. You crash afterwards.",
  drug = { via = "inject", time = 6, adren = 78, hr = 30 } })

item("epinephrine", { name = "epinephrine", short = "epi", kind = "drug", mass = 0.04, stack = 4, value = 30, tier = 3,
  desc = "Cardiac dose. Can restart a stopped heart.",
  drug = { via = "inject", time = 10, cardiac = true, adren = 40, hr = 45 } })

item("antibiotics", { name = "antibiotics", short = "antibio.", kind = "drug", mass = 0.03, stack = 8, value = 19, tier = 2,
  desc = "Oral course. Clears infection in every limb at once.",
  drug = { via = "oral", time = 6, infectionAll = -38, immunity = 12, sick = 6 } })

item("antiseptic", { name = "antiseptic", short = "antisept", kind = "drug", mass = 0.06, stack = 8, value = 9,
  desc = "Wound wash. Clears infection in one limb and blocks new infection for a while. Stings.",
  drug = { via = "topical", time = 12, disinfect = 900, pain = 7 } })

item("stimulant", { name = "stimulant", short = "stim", kind = "drug", mass = 0.02, stack = 8, value = 11,
  desc = "Alertness tab. Restores energy for two hours, then takes back more than it gave.",
  drug = { via = "oral", time = 5, energy = 42, hr = 14, crash = 0.6 } })

item("sedative", { name = "sedative", short = "sedative", kind = "drug", mass = 0.02, stack = 6, value = 8,
  desc = "Sleeping dose. Lets you rest through pain. Slows your breathing.",
  drug = { via = "oral", time = 5, sleep = true, resp = -3.5, energy = 12 } })

item("blood_bag", { name = "blood bag", short = "blood", kind = "drug", mass = 0.62, stack = 3, value = 34, tier = 2,
  desc = "Half a litre of donor blood. Restores volume. Sometimes carries an infection.",
  drug = { via = "inject", time = 95, blood = 0.5, infectChance = 0.12, visc = 4 } })

item("saline", { name = "saline", short = "saline", kind = "drug", mass = 0.55, stack = 3, value = 14,
  desc = "Volume without oxygen. Raises pressure but thins what is left.",
  drug = { via = "inject", time = 70, blood = 0.35, visc = -18 } })

item("ice_pack", { name = "ice pack", short = "ice pack", kind = "tool", mass = 0.3, stack = 2, value = 12,
  desc = "Snap and shake. Numbs one limb for fifteen minutes.",
  tool = { type = "chill", time = 8, uses = 3 } })

item("heat_pack", { name = "heat pack", short = "heat pk", kind = "tool", mass = 0.3, stack = 2, value = 12, tier = 5,
  desc = "Snap and shake. Warms one limb and raises core temperature.",
  tool = { type = "warm", time = 8, uses = 3 } })

-- ---- consumables -----------------------------------------------------

item("ration_brick", { name = "ration brick", short = "ration", kind = "food", mass = 0.33, stack = 6, value = 6,
  desc = "Compressed field ration. A lot of food. Needs chewing.",
  food = { hunger = 46, thirst = -6, time = 30 } })

item("protein_paste", { name = "protein paste", short = "paste", kind = "food", mass = 0.2, stack = 6, value = 4,
  desc = "Tube of paste. Moderate food. Can be eaten with a broken jaw.",
  food = { hunger = 30, thirst = 3, time = 20, soft = true } })

item("canned_meat", { name = "canned meat", short = "can", kind = "food", mass = 0.4, stack = 4, value = 5,
  desc = "Tinned meat. Good food. About one in five is spoiled.",
  food = { hunger = 42, thirst = 4, time = 40, sickChance = 0.18, sick = 26 } })

item("bittercap", { name = "bittercap", short = "bittercap", kind = "food", mass = 0.08, stack = 10, value = 2,
  desc = "Cave fungus. A little food. Often makes you sick.",
  food = { hunger = 13, thirst = 6, time = 14, sickChance = 0.1, sick = 12 } })

item("sap_fruit", { name = "sap fruit", short = "sapfruit", kind = "food", mass = 0.15, stack = 8, value = 3, tier = 5,
  desc = "Wall fruit. A little food and a lot of water.",
  food = { hunger = 18, thirst = 22, time = 16 } })

item("water_flask", { name = "water flask", short = "flask", kind = "flask", mass = 0.25, stack = 1, value = 8,
  desc = "Holds three quarters of a litre. Fill it at a spring or a pool.",
  flask = { capacity = 0.75 } })

item("purifier_tab", { name = "purifier tab", short = "purifier", kind = "misc", mass = 0.01, stack = 12, value = 4,
  desc = "One tab makes a flask of dirty water safe. Takes twenty minutes.",
  misc = { purify = true, time = 20 } })

-- ---- light -----------------------------------------------------------

item("hand_torch", { name = "hand torch", short = "torch", kind = "light", mass = 0.4, stack = 1, value = 14,
  desc = "Battery torch. Wide light. Takes one cell and drains it steadily.",
  light = { radius = 3, needsCell = true, drain = 1.0, hands = 1 } })

item("head_lamp", { name = "head lamp", short = "headlamp", kind = "wear", mass = 0.3, stack = 1, value = 20, tier = 2,
  desc = "Headband lamp. Weaker light, but both hands stay free.",
  wear = { slot = "head", lightRadius = 2, needsCell = true, drain = 0.7 } })

item("glow_stick", { name = "glow stick", short = "glowstk", kind = "light", mass = 0.05, stack = 10, value = 3,
  desc = "Snap and shake. Twenty minutes of light. Can be thrown.",
  light = { radius = 2, fuel = 1200, throwable = true } })

item("flare", { name = "flare", short = "flare", kind = "light", mass = 0.12, stack = 6, value = 9,
  desc = "Four minutes of bright light and smoke. Most creatures back away from it.",
  light = { radius = 4, fuel = 240, throwable = true, repel = 0.7, heat = 1.4 } })

item("bloom_light", { name = "bloom light", short = "bloom", kind = "light", mass = 0.35, stack = 2, value = 26, tier = 3,
  desc = "Cultured filament. Weak light. Infection shows up as a green stain under it.",
  light = { radius = 4, fuel = 5400, reveal = true } })

item("cell", { name = "power cell", short = "cell", kind = "misc", mass = 0.12, stack = 8, value = 6,
  desc = "Power cell. Recharges a torch, a headlamp or a shock prod.",
  misc = { cell = 100 } })

-- ---- weapons ---------------------------------------------------------

item("pry_bar", { name = "pry bar", short = "pry bar", kind = "weapon", mass = 1.5, stack = 1, value = 15,
  desc = "Steel bar. Opens locked containers and works as a heavy weapon.",
  weapon = { dmg = 15, muscle = 12, bleed = 0.06, hands = 1, speed = 1.0, noise = 0.5,
             fracture = 0.10, pry = true, dig = 26 } })

item("pipe", { name = "steel pipe", short = "pipe", kind = "weapon", mass = 1.2, stack = 1, value = 8,
  desc = "Length of pipe. Basic weapon. Loud.",
  weapon = { dmg = 12, muscle = 14, bleed = 0.02, hands = 1, speed = 1.05, noise = 0.6, fracture = 0.12, dig = 14 } })

item("rock_hammer", { name = "rock hammer", short = "hammer", kind = "weapon", mass = 2.5, stack = 1, value = 18, tier = 2,
  desc = "Mining hammer. Slow and heavy. Good at breaking things open.",
  weapon = { dmg = 21, muscle = 22, bleed = 0.04, hands = 2, speed = 0.72, noise = 0.8, fracture = 0.3, dig = 46 } })

item("cutter", { name = "cutter", short = "cutter", kind = "weapon", mass = 0.3, stack = 1, value = 12,
  desc = "Short blade. Fast, cuts deep, causes bleeding. Can amputate a limb.",
  weapon = { dmg = 9, muscle = 6, bleed = 0.22, hands = 1, speed = 1.4, noise = 0.15, butcher = true, dig = 8 } })

item("bolt_gun", { name = "bolt gun", short = "bolt gun", kind = "weapon", mass = 2.8, stack = 1, value = 34, tier = 3,
  desc = "Fastener tool used as a weapon. Fires bolts at range.",
  weapon = { dmg = 24, muscle = 10, bleed = 0.16, hands = 2, speed = 0.8, noise = 0.7,
             ranged = true, ammo = "bolts", shrapnel = 0.4 } })

item("scatter_pistol", { name = "scatter pistol", short = "scatter", kind = "weapon", mass = 1.9, stack = 1, value = 48, tier = 4,
  desc = "Two barrels, break action. Heavy damage close up. Fires shells.",
  weapon = { dmg = 38, muscle = 26, bleed = 0.3, hands = 1, speed = 0.6, noise = 1.6,
             ranged = true, ammo = "shells", shrapnel = 0.5 } })

item("shock_prod", { name = "shock prod", short = "prod", kind = "weapon", mass = 1.1, stack = 1, value = 26, tier = 3,
  desc = "Livestock prod. Low damage, but reliably stuns. Runs off a cell.",
  weapon = { dmg = 7, muscle = 4, bleed = 0, hands = 1, speed = 1.0, noise = 0.3,
             stun = 0.65, needsCell = true, drain = 8 } })

item("bolts", { name = "bolts", short = "bolts", kind = "ammo", mass = 0.03, stack = 40, value = 1, tier = 3,
  desc = "Ammunition for the bolt gun.", ammo = true })

item("shells", { name = "shells", short = "shells", kind = "ammo", mass = 0.05, stack = 24, value = 2, tier = 4,
  desc = "Ammunition for the scatter pistol. About a third are damp.", ammo = true })

-- ---- wearables -------------------------------------------------------

item("hard_hat", { name = "hard hat", short = "hard hat", kind = "wear", mass = 0.55, stack = 1, value = 12,
  desc = "Cracked shell, working straps. Protects the head, including in a fall.",
  wear = { slot = "head", armour = 4, skullGuard = 0.45 } })

item("respirator", { name = "respirator", short = "resp.", kind = "wear", mass = 0.4, stack = 1, value = 22, tier = 3,
  desc = "Half mask with cartridges. Filters spores out of the air.",
  wear = { slot = "face", spore = 0.8, rad = 0.25, speech = true } })

item("goggles", { name = "goggles", short = "goggles", kind = "wear", mass = 0.15, stack = 1, value = 9,
  desc = "Scratched lenses. Keeps grit out of your eyes.",
  wear = { slot = "face", eyeGuard = 0.7 } })

item("work_jacket", { name = "work jacket", short = "jacket", kind = "wear", mass = 1.3, stack = 1, value = 10,
  desc = "Canvas jacket. Light protection for the torso and a little warmth.",
  wear = { slot = "torso", armour = 3, warmth = 3, carry = 2 } })

item("thermal_liner", { name = "thermal liner", short = "thermal", kind = "wear", mass = 0.9, stack = 1, value = 18, tier = 5,
  desc = "Quilted liner. Keeps you warm in the cold strata.",
  wear = { slot = "torso", warmth = 7, armour = 1 } })

item("lead_wrap", { name = "lead wrap", short = "lead wrp", kind = "wear", mass = 4.5, stack = 1, value = 24, tier = 4,
  desc = "Lead-lined apron. Heavy protection for the torso. Slows you down.",
  wear = { slot = "torso", armour = 5, encumber = 1.4 } })

item("gloves", { name = "gloves", short = "gloves", kind = "wear", mass = 0.18, stack = 1, value = 7,
  desc = "Work gloves. Better grip for climbing and for fine medical work.",
  wear = { slot = "hands", armour = 1, grip = 0.12, cutGuard = 0.6 } })

item("knee_pads", { name = "knee pads", short = "kneepads", kind = "wear", mass = 0.4, stack = 1, value = 9,
  desc = "Shell over foam. Takes about a third out of every fall.",
  wear = { slot = "legs", armour = 2, fallGuard = 0.35 } })

item("steel_boots", { name = "steel-toe boots", short = "boots", kind = "wear", mass = 1.6, stack = 1, value = 13,
  desc = "Heavy soles. Protects the feet and softens landings.",
  wear = { slot = "feet", armour = 3, footGuard = 0.85, fallGuard = 0.2 } })

item("pack_small", { name = "satchel", short = "satchel", kind = "wear", mass = 0.6, stack = 1, value = 10,
  desc = "Small pack. Carry a little more.",
  wear = { slot = "back", carry = 6 } })

item("pack_large", { name = "frame pack", short = "pack", kind = "wear", mass = 1.7, stack = 1, value = 24, tier = 2,
  desc = "Frame pack. Carry a lot more. Sits badly on an injured back.",
  wear = { slot = "back", carry = 14 } })

item("med_tin", { name = "med tin", short = "med tin", kind = "wear", mass = 0.35, stack = 1, value = 15, tier = 2,
  desc = "Sealed medical tin. Holds nothing but medicine.",
  wear = { slot = "back", carry = 5, only = { dressing = true, drug = true, tool = true } } })

-- ---- materials -------------------------------------------------------

local function mat(id, name, mass, value, desc)
  item(id, { name = name, short = name, kind = "material", mass = mass, stack = 20,
             value = value, desc = desc, material = true })
end

mat("scrap_metal", "scrap metal", 0.3, 2, "Torn plate and bar stock.")
mat("plastic_chunk", "plastic chunk", 0.12, 2, "Snapped off something moulded.")
mat("cloth_strip", "cloth strip", 0.05, 1, "Cut from whatever was to hand.")
mat("wire", "wire", 0.08, 2, "Copper under cracked insulation.")
mat("resin", "resin", 0.1, 3, "Sets hard. Used in crafting.")
mat("chitin", "chitin plate", 0.2, 4, "Peeled off something that stopped moving.")
mat("bone_shard", "bone shard", 0.06, 2, "Splintered bone. Sharp enough to hold an edge.")
mat("chem_vial", "chem vial", 0.09, 4, "Unlabelled chemical. Used in crafting.")
mat("fibre", "plant fibre", 0.03, 1, "Stringy, damp, plentiful where anything grows.")
mat("glass_shard", "glass shard", 0.04, 1, "Broken glass. Sharp on every edge.")
mat("alloy_plate", "alloy plate", 0.7, 8, "Stamped with a part number and nothing else.")
mat("dead_cell", "spent cell", 0.12, 1, "Flat. Can be recharged at a charge post.")
item("scrip", { name = "company scrip", short = "scrip", kind = "misc", mass = 0.004,
  stack = 999, value = 1, tier = 1,
  desc = "Stamped credit chits. Traders take them. Nothing else down here does.",
  misc = { currency = true } })

mat("stone_chunk", "stone chunk", 0.4, 1, "Broken out of the wall. Ballast, or something to throw.")

-- ---- oddities and documents -----------------------------------------

item("company_tag", { name = "identity tag", short = "tag", kind = "misc", mass = 0.01, stack = 20, value = 3,
  desc = "Stamped alloy tag. Worth money on the surface.",
  misc = { tag = true } })

item("red_scarf", { name = "red scarf", short = "scarf", kind = "wear", mass = 0.15, stack = 1, value = 12,
  desc = "Wool scarf. A little warmth.",
  wear = { slot = "face", warmth = 2, mood = 6 } })

item("sleeping_roll", { name = "sleeping roll", short = "roll", kind = "tool", mass = 1.9, stack = 1, value = 16, tier = 2,
  desc = "Insulated roll. Makes resting warmer and more effective.",
  tool = { type = "bedroll", warmth = 5 } })

item("grapple", { name = "grapple line", short = "grapple", kind = "tool", mass = 1.4, stack = 1, value = 20, tier = 2,
  desc = "Forty metres of line and a hook. Lets you climb down a drop instead of falling it.",
  tool = { type = "grapple", uses = 20 } })

item("document", { name = "document", short = "document", kind = "doc", mass = 0.01, stack = 20, value = 5,
  desc = "Paper recovered from the mine.", doc = true })

--------------------------------------------------------------------- crafting

D.RECIPES = {
  { out = "cloth_strip", n = 2, need = { fibre = 3 }, time = 40, int = 0 },
  { out = "rag_strip", n = 2, need = { cloth_strip = 1 }, time = 25, int = 0 },
  { out = "field_dressing", n = 1, need = { rag_strip = 2, resin = 1 }, time = 60, int = 1 },
  { out = "gauze_roll", n = 1, need = { cloth_strip = 3, chem_vial = 1 }, time = 90, int = 2 },
  { out = "polymer_seal", n = 1, need = { plastic_chunk = 2, resin = 1 }, time = 70, int = 2 },
  { out = "makeshift_splint", n = 1, need = { scrap_metal = 2, cloth_strip = 2 }, time = 80, int = 1 },
  { out = "tourniquet", n = 1, need = { cloth_strip = 2, wire = 1 }, time = 60, int = 1 },
  { out = "forceps", n = 1, need = { wire = 2, scrap_metal = 1 }, time = 90, int = 2 },
  { out = "antiseptic", n = 2, need = { chem_vial = 1, fibre = 2 }, time = 100, int = 2 },
  { out = "painkillers", n = 3, need = { chem_vial = 2 }, time = 110, int = 3 },
  { out = "clot_agent", n = 1, need = { chem_vial = 2, bone_shard = 2 }, time = 140, int = 4 },
  { out = "suture_kit", n = 1, need = { wire = 1, fibre = 3, bone_shard = 1 }, time = 150, int = 3 },
  { out = "glow_stick", n = 2, need = { chem_vial = 1, plastic_chunk = 1 }, time = 50, int = 1 },
  { out = "flare", n = 1, need = { chem_vial = 1, scrap_metal = 1, cloth_strip = 1 }, time = 70, int = 2 },
  { out = "cell", n = 1, need = { dead_cell = 1, chem_vial = 1 }, time = 80, int = 2 },
  { out = "pipe", n = 1, need = { scrap_metal = 3 }, time = 90, int = 1 },
  { out = "cutter", n = 1, need = { glass_shard = 1, wire = 1, cloth_strip = 1 }, time = 70, int = 1 },
  { out = "rock_hammer", n = 1, need = { scrap_metal = 4, alloy_plate = 1 }, time = 160, int = 3 },
  { out = "pack_small", n = 1, need = { cloth_strip = 4, wire = 2 }, time = 140, int = 2 },
  { out = "knee_pads", n = 1, need = { chitin = 2, cloth_strip = 2 }, time = 110, int = 2 },
  { out = "hard_hat", n = 1, need = { chitin = 3, resin = 1 }, time = 130, int = 3 },
  { out = "water_flask", n = 1, need = { plastic_chunk = 2, resin = 1 }, time = 90, int = 1 },
  { out = "purifier_tab", n = 3, need = { chem_vial = 1 }, time = 60, int = 2 },
  { out = "ice_pack", n = 1, need = { chem_vial = 1, plastic_chunk = 1, fibre = 1 }, time = 100, int = 3 },
  { out = "bolts", n = 8, need = { scrap_metal = 1, wire = 1 }, time = 90, int = 3 },
  { out = "sleeping_roll", n = 1, need = { cloth_strip = 6, fibre = 4 }, time = 220, int = 2 },
}

--------------------------------------------------------------------- strata

-- Each stratum is a 300 m section of the mine.
D.STRATA = {
  {
    id = 1, name = "Spoil Banks", tag = "SPOIL",
    blurb = "Loose gravel and standing water. Shalecrawlers live in the scree. Cold, but nothing here is trying very hard to kill you.",
    temp = 11, dark = 0.35, lootTier = 1,
    creatures = { { id = "shalecrawler", w = 6 } },
    hazards = { "spike_bed", "loose_rock", "drop", "sump" },
    features = { "water", "scaffold", "moss" },
    floorBias = { ["%"] = 2.0, ["o"] = 1.6 },
    palette = "stone",
    lines = {
      "Water comes off the roof in a thin steady line and has been doing it long enough to cut a channel in the spoil.",
      "Scaffold poles stand at angles that suggest the floor moved after they were put in.",
      "The gravel here is graded. Someone sorted it, and then stopped.",
      "Boot prints in the silt, filled in and gone soft at the edges.",
    },
  },
  {
    id = 2, name = "The Underspoil", tag = "USPOIL",
    blurb = "Sealed workings. Concrete beams, barbed line at shin height, grit ticks in the corners.",
    temp = 9, dark = 0.7, lootTier = 2,
    creatures = { { id = "shalecrawler", w = 5 }, { id = "grit_tick", w = 4 } },
    hazards = { "spike_bed", "loose_rock", "drop", "sump", "barbed_line", "snap_trap" },
    features = { "water", "scaffold", "moss", "cache" },
    floorBias = { ["#"] = 1.4, ["o"] = 1.3 },
    palette = "stone",
    lines = {
      "Concrete beams every nine metres, cast in place, numbered in paint that has outlasted the crew.",
      "Barbed line strung at shin height between two anchors. Nothing on the far side worth defending.",
      "The lumalgae on the wet stone gives off enough light to see that there is nothing to see.",
      "Someone chalked a tally on a beam. Forty-one strokes, then a gap, then two more.",
    },
  },
  {
    id = 3, name = "Saltglass Flats", tag = "SALT",
    blurb = "Dry and warm. The salt crust breaks under weight. Wallgnaws sit in the rock face with only the mouth showing.",
    temp = 24, dark = 0.55, lootTier = 3,
    creatures = { { id = "shalecrawler", w = 3 }, { id = "wallgnaw", w = 5 }, { id = "grit_tick", w = 3 } },
    hazards = { "shock_mine", "sentry", "arc_coil", "long_drop", "stalactite", "glass_field", "oil_pool" },
    features = { "water", "cache", "workbench", "recharge" },
    floorBias = { ["#"] = 1.6, ["^"] = 1.3 },
    palette = "salt",
    lines = {
      "Salt crust over a void. It holds until it does not, and it gives no warning either way.",
      "A sentry post sits on a cut ledge with its optic still turning, ten degrees, back, ten degrees.",
      "Sand has drifted against the pipe run and buried it to the collar.",
      "The crust is scorched in a circle four metres across, and nothing has grown back over it.",
    },
  },
  {
    id = 4, name = "The Slagfield", tag = "SLAG",
    blurb = "Hot slag and sharp waste. The worst ground in the mine to land on. No wildlife, but the automated sentries still run.",
    temp = 28, dark = 0.6, lootTier = 4,
    creatures = {},
    hazards = { "shock_mine", "sentry", "resonator", "slagrock", "spent_rod", "long_drop", "oil_pool" },
    features = { "cache", "workbench", "recharge", "pod" },
    floorBias = { ["^"] = 2.4, ["o"] = 1.5 },
    palette = "waste",
    lines = {
      "Racks of spent rods stand in a shed with three walls. The fourth was never built or was taken away.",
      "The dust here is finer than sand and gets into the seals of everything.",
      "A resonator cycles somewhere out of sight, and the teeth register it before the ears do.",
      "Brick, laid in courses, holding up nothing. Somebody built a wall down here on purpose.",
    },
  },
  {
    id = 5, name = "Greenrot", tag = "GREEN",
    blurb = "Wet, warm and overgrown. Plenty to forage and thick moss to land on. Barrowbacks come through here.",
    temp = 31, dark = 0.45, lootTier = 4,
    creatures = { { id = "grit_tick", w = 4 }, { id = "bloat_tick", w = 3 }, { id = "wallgnaw", w = 3 },
                  { id = "barrowback", w = 4 }, { id = "elder_barrowback", w = 1 } },
    hazards = { "gullet_vine", "drop_press", "long_drop", "sump", "stalactite" },
    features = { "water", "growth", "pod", "workbench", "cache" },
    floorBias = { ["\""] = 3.0, ["~"] = 1.8 },
    palette = "green",
    lines = {
      "Vines with a wrist's thickness run up the chamber wall and into a crack that they widened themselves.",
      "Sap fruit hangs low enough to reach without a jump, which should be more comforting than it is.",
      "Something has cropped the growth flat in a band a metre off the floor, all the way along.",
      "The air is warm and full and moving, and the moving is not from a draught.",
    },
  },
  {
    id = 6, name = "The Rime", tag = "RIME",
    blurb = "Well below freezing. You will lose core temperature fast without a thermal liner. Rimestriders hunt on the ice.",
    temp = -14, dark = 0.5, lootTier = 5,
    creatures = { { id = "rimestrider", w = 5 }, { id = "shalecrawler", w = 2 } },
    hazards = { "long_drop", "ice_shelf", "shock_mine", "stalactite" },
    features = { "heater", "pod", "cache", "workbench" },
    floorBias = { ["#"] = 1.8 },
    palette = "ice",
    lines = {
      "Frost has grown out of the rock in feathers the length of a forearm.",
      "An ion heater runs in the corner of the chamber on a circuit nobody has switched off in years.",
      "The ice holds a light for a long way and gives back nothing useful.",
      "Meltwater at the base of the wall, refrozen, holding a boot with the laces still tied.",
    },
  },
  {
    id = 7, name = "Sporeworks", tag = "SPORE",
    blurb = "Fungal growth everywhere. The air carries spores that infect open wounds. A respirator helps.",
    temp = 17, dark = 0.75, lootTier = 5,
    creatures = { { id = "palefly", w = 5 }, { id = "bloat_tick", w = 4 }, { id = "wallgnaw", w = 3 } },
    hazards = { "sawblade", "gullet_vine", "sump", "spore_burst", "drop_press" },
    features = { "water", "growth", "pod", "workbench" },
    floorBias = { ["\""] = 2.2, ["o"] = 1.4 },
    palette = "fungal",
    lines = {
      "Water falls from the roof in a fine constant rain and the floor has given up draining it.",
      "Caps the size of a table, undersides packed with gills, and the gills are moving.",
      "A sawblade rig turns over on a bearing that has not been greased since it was installed.",
      "Every surface wears a film. The film is alive and does not much care what it is on.",
    },
  },
  {
    id = 8, name = "Facet Hollow", tag = "FACET",
    blurb = "Crystal growth. Everything you land on here punctures rather than crushes. Facets split in two when you break them.",
    temp = 20, dark = 0.3, lootTier = 6,
    creatures = { { id = "facet", w = 5 }, { id = "rimestrider", w = 2 } },
    hazards = { "crystal_burst", "arc_coil", "long_drop", "shock_mine" },
    features = { "recharge", "cache", "workbench", "pod" },
    floorBias = { ["^"] = 3.0 },
    palette = "crystal",
    lines = {
      "A seam of yellow crystal runs the height of the chamber and hums at the edge of hearing.",
      "Something has been growing here on a schedule, and the schedule is geological.",
      "The floor is fragile crystal over a drop. It reads as solid right up to the step that matters.",
      "Light entering the hollow comes out somewhere else, changed, and nobody has mapped where.",
    },
  },
  {
    id = 9, name = "The Boiling Floor", tag = "BOIL",
    blurb = "Very hot. Steam vents, burns, and no drinkable water.",
    temp = 44, dark = 0.4, lootTier = 6,
    creatures = { { id = "cinderling", w = 5 }, { id = "facet", w = 2 } },
    hazards = { "vent_burst", "long_drop", "stalactite", "resonator" },
    features = { "water", "cache", "workbench" },
    floorBias = { ["#"] = 1.5, ["^"] = 1.4 },
    palette = "heat",
    lines = {
      "A vent goes off four metres away and the steam reaches the roof before it spreads.",
      "The stone is warm through the boot sole and stays warm through the night.",
      "Mineral crusts around each vent mouth, layered, each layer a year or a decade.",
      "Air shimmers over the floor and makes the far wall look further away than it is.",
    },
  },
  {
    id = 10, name = "Manifest Depth", tag = "MNFST",
    blurb = "The consignment is on this level, sitting on the floor of a gallery. Elder barrowbacks are down here with it.",
    temp = 22, dark = 0.85, lootTier = 7,
    creatures = { { id = "meter_reader", w = 4 }, { id = "elder_barrowback", w = 3 }, { id = "facet", w = 2 } },
    hazards = { "sentry", "shock_mine", "resonator", "long_drop", "drop_press" },
    features = { "cache", "pod", "workbench", "cargo" },
    floorBias = { ["#"] = 1.4 },
    palette = "deep",
    lines = {
      "Racking, floor to roof, most of it empty, all of it labelled.",
      "The chamber was cut square. Not worn square, cut, with a machine, by someone with a plan.",
      "A shipping crate on its side with the seals intact and the manifest still in the sleeve.",
      "Every identity tag in this chamber has been collected into one pile and counted.",
    },
  },
  {
    id = 11, name = "The Lift Head", tag = "CLIMB",
    blurb = "The bottom of the workings. The surface lift is down here. It reads the bond before it opens, so arrive with the cargo.",
    temp = 18, dark = 0.6, lootTier = 6,
    creatures = { { id = "barrowback", w = 3 }, { id = "wallgnaw", w = 3 }, { id = "meter_reader", w = 2 } },
    hazards = { "long_drop", "loose_rock", "stalactite", "shock_mine" },
    features = { "cache", "pod", "water" },
    floorBias = { ["#"] = 1.6 },
    palette = "stone",
    lines = {
      "The rope you fixed on the way down is still where you left it, which proves nothing about the anchor.",
      "Going up costs about three times what coming down did, in every currency.",
      "Chalk marks in your own hand, made hours ago, meaning something you can no longer reconstruct.",
    },
  },
}

--------------------------------------------------------------------- creatures

-- attacks: { name=, skin=, muscle=, bleed=, pain=, frac=, dislo=, shrap=, infect=,
--            target="any"|"low"|"high"|"limb", weight= }
D.CREATURES = {
  shalecrawler = {
    name = "shalecrawler", tier = 1, hp = 38, armour = 1, speed = 1.0, senses = 0.45,
    light = -0.6,           -- dislikes light; negative means light reduces aggression
    flee = 0.55, noiseDraw = 0.8,
    desc = "Flat and blind, the width of a door. Slow. Knocks you down and works on your legs.",
    drops = { { id = "chitin", n = 2, w = 5 }, { id = "bone_shard", n = 1, w = 3 } },
    attacks = {
      { name = "raked you across the shin", skin = 16, muscle = 6, bleed = 0.09, pain = 12, target = "low", w = 5 },
      { name = "dragged you down onto the gravel", skin = 9, muscle = 14, bleed = 0.03, pain = 16, dislo = 0.12, target = "any", w = 3 },
    },
  },
  grit_tick = {
    name = "grit tick swarm", tier = 2, hp = 22, armour = 0, speed = 1.5, senses = 0.7,
    flee = 0.3, noiseDraw = 0.4, swarm = true,
    desc = "Thumbnail sized, and never alone. They swarm and go for exposed skin. Light drives them off.",
    drops = { { id = "chitin", n = 1, w = 4 } },
    attacks = {
      { name = "got under your cuff", skin = 7, muscle = 1, bleed = 0.05, pain = 6, infect = 0.5, target = "low", w = 6 },
      { name = "found the gap at your collar", skin = 6, muscle = 1, bleed = 0.04, pain = 7, infect = 0.55, target = "high", w = 3 },
    },
  },
  bloat_tick = {
    name = "bloat tick", tier = 5, hp = 46, armour = 2, speed = 0.9, senses = 0.6,
    flee = 0.35, noiseDraw = 0.5,
    desc = "A tick that kept feeding. Slow and fragile, but it bursts and the wound goes bad fast.",
    drops = { { id = "chitin", n = 3, w = 5 }, { id = "chem_vial", n = 1, w = 2 } },
    attacks = {
      { name = "buried its mouthparts in you", skin = 14, muscle = 4, bleed = 0.28, pain = 20, infect = 0.7, target = "any", w = 6 },
      { name = "burst against you", skin = 5, muscle = 2, bleed = 0.02, pain = 9, infect = 0.9, target = "high", w = 2 },
    },
  },
  wallgnaw = {
    name = "wallgnaw", tier = 3, hp = 60, armour = 4, speed = 0.5, senses = 0.25,
    flee = 0.8, noiseDraw = 1.3, ambush = true,
    desc = "Lives in the rock face with only the mouth exposed. It cannot follow you. It can take an arm.",
    drops = { { id = "chitin", n = 2, w = 4 }, { id = "alloy_plate", n = 1, w = 2 }, { id = "bone_shard", n = 2, w = 3 } },
    attacks = {
      { name = "closed on your forearm", skin = 22, muscle = 26, bleed = 0.18, pain = 34, frac = 0.28, target = "arm", w = 6 },
      { name = "took hold and would not let go", skin = 12, muscle = 30, bleed = 0.1, pain = 40, dislo = 0.4, target = "arm", w = 3 },
    },
  },
  barrowback = {
    name = "barrowback", tier = 5, hp = 130, armour = 7, speed = 1.1, senses = 0.8,
    flee = 0.15, noiseDraw = 1.6,
    desc = "Plated, taller at the shoulder than you are, and fast. It charges. Do not fight it in the open.",
    drops = { { id = "chitin", n = 4, w = 6 }, { id = "alloy_plate", n = 1, w = 2 }, { id = "bone_shard", n = 3, w = 4 } },
    attacks = {
      { name = "put its shoulder through you", skin = 18, muscle = 34, bleed = 0.12, pain = 46, frac = 0.42, target = "any", w = 5 },
      { name = "caught you and threw you", skin = 24, muscle = 20, bleed = 0.2, pain = 38, frac = 0.25, dislo = 0.3, target = "any", w = 3 },
      { name = "went for the head", skin = 30, muscle = 24, bleed = 0.3, pain = 55, frac = 0.35, target = "head", w = 1 },
    },
  },
  elder_barrowback = {
    name = "elder barrowback", tier = 7, hp = 260, armour = 11, speed = 1.0, senses = 0.9,
    flee = 0.05, noiseDraw = 2.0, boss = true,
    desc = "Fully fused plating. Heavy armour, and it takes limbs off deliberately. Almost nothing hurts it.",
    drops = { { id = "chitin", n = 8, w = 6 }, { id = "alloy_plate", n = 3, w = 4 } },
    attacks = {
      { name = "took your arm in its jaw and set its feet", skin = 40, muscle = 50, bleed = 0.6, pain = 80, frac = 0.7, sever = 0.3, target = "arm", w = 4 },
      { name = "drove you into the floor", skin = 26, muscle = 44, bleed = 0.2, pain = 62, frac = 0.6, target = "any", w = 4 },
      { name = "closed on your leg", skin = 36, muscle = 46, bleed = 0.5, pain = 74, frac = 0.6, sever = 0.22, target = "leg", w = 3 },
    },
  },
  rimestrider = {
    name = "rimestrider", tier = 6, hp = 74, armour = 3, speed = 1.4, senses = 0.75,
    flee = 0.45, noiseDraw = 0.9, cold = 1.6,
    desc = "Long limbed and pale. Fast on ice. Its hits drop your core temperature as well as your blood.",
    drops = { { id = "chitin", n = 3, w = 5 }, { id = "chem_vial", n = 1, w = 3 } },
    attacks = {
      { name = "struck downward with a foreleg", skin = 26, muscle = 16, bleed = 0.22, pain = 30, target = "high", w = 5 },
      { name = "pinned you against the ice", skin = 10, muscle = 12, bleed = 0.05, pain = 22, cold = 6, target = "any", w = 3 },
    },
  },
  palefly = {
    name = "palefly cloud", tier = 7, hp = 34, armour = 0, speed = 1.7, senses = 0.85,
    flee = 0.25, noiseDraw = 0.3, swarm = true, spore = true,
    desc = "Drawn to light. Weak on its own, but it lands on open wounds and lays in them.",
    drops = { { id = "fibre", n = 2, w = 4 } },
    attacks = {
      { name = "got into your mouth and nose", skin = 4, muscle = 1, bleed = 0.01, pain = 8, infect = 1.1, spore = true, target = "head", w = 6 },
      { name = "settled on every exposed patch of you", skin = 9, muscle = 1, bleed = 0.03, pain = 7, infect = 0.8, target = "any", w = 3 },
    },
  },
  facet = {
    name = "facet", tier = 8, hp = 58, armour = 6, speed = 1.2, senses = 0.6,
    flee = 0.4, noiseDraw = 0.7, splits = true,
    desc = "Crystal. Breaking it splits it in two and both halves keep coming. Cuts deep and bleeds you out.",
    drops = { { id = "glass_shard", n = 3, w = 5 }, { id = "chem_vial", n = 1, w = 3 } },
    attacks = {
      { name = "drove a point through your guard", skin = 20, muscle = 10, bleed = 0.16, pain = 26, shrap = 2, target = "any", w = 5 },
      { name = "shattered against you", skin = 14, muscle = 4, bleed = 0.12, pain = 20, shrap = 4, target = "high", w = 2 },
    },
  },
  cinderling = {
    name = "cinderling", tier = 9, hp = 66, armour = 4, speed = 1.3, senses = 0.7,
    flee = 0.35, noiseDraw = 0.8, heat = 2.2,
    desc = "Runs hot. Burns on contact and sets fire to anything flammable you are carrying.",
    drops = { { id = "resin", n = 2, w = 4 }, { id = "chem_vial", n = 2, w = 3 } },
    attacks = {
      { name = "closed the distance and held on", skin = 24, muscle = 12, bleed = 0.1, pain = 34, burn = 18, heat = 5, target = "any", w = 5 },
      { name = "opened along its back and vented", skin = 18, muscle = 6, bleed = 0.04, pain = 28, burn = 26, heat = 8, target = "high", w = 2 },
    },
  },
  trader_armed = {
    name = "the trader", humanoid = true, hue = "red", tier = 4, hp = 70, armour = 3, speed = 1.1, senses = 0.9,
    flee = 0.2, noiseDraw = 1.0,
    desc = "A person with a weapon, no reason left to be careful, and your description.",
    drops = { { id = "scrip", n = 12, w = 8 }, { id = "shells", n = 2, w = 3 },
              { id = "field_dressing", n = 1, w = 3 } },
    attacks = {
      { name = "fires from the hip", skin = 26, muscle = 20, bleed = 0.22, pain = 30,
        shrap = 1, target = "core", w = 4 },
      { name = "puts a round through your leg", skin = 22, muscle = 26, bleed = 0.26,
        pain = 34, frac = 0.25, target = "leg", w = 3 },
      { name = "clubs you with the stock", skin = 8, muscle = 14, pain = 22,
        target = "high", w = 3 },
    },
  },

  meter_reader = {
    name = "meter reader", humanoid = true, hue = "yellow", tier = 10, hp = 150, armour = 8, speed = 1.0, senses = 1.0,
    flee = 0.1, noiseDraw = 1.0, talks = true,
    desc = "Company survey machine, still running its route. Armoured, armed, and it does not negotiate.",
    drops = { { id = "company_tag", n = 5, w = 6 }, { id = "alloy_plate", n = 2, w = 3 } },
    attacks = {
      { name = "took a reading", skin = 22, muscle = 28, bleed = 0.24, pain = 44, frac = 0.3, target = "any", w = 5 },
      { name = "logged a discrepancy", skin = 34, muscle = 18, bleed = 0.4, pain = 50, shrap = 3, target = "high", w = 3 },
    },
    voice = {
      "Asset four, class four. Condition on arrival: ambulatory.",
      "Noted. Amend the line.",
      "You are not on the manifest for this depth.",
      "Recovery is billable. Hold still.",
    },
  },
}

--------------------------------------------------------------------- hazards

-- avoid: which check gives you the chance to dodge
--   "notice" = perception, "agile" = mobility, "none" = unavoidable
D.HAZARDS = {
  spike_bed = { name = "spike bed", p = 0.16, avoid = "notice", noise = 0.2,
    text = "Rebar driven upward through a plank, and the plank under a finger of silt.",
    hit = { skin = 26, muscle = 8, bleed = 0.16, pain = 26, target = "leg", shrap = 1, infect = 0.4 } },
  loose_rock = { name = "loose rock", p = 0.14, avoid = "agile", noise = 0.5,
    text = "The ledge takes your weight for a step and a half.",
    hit = { skin = 12, muscle = 18, bleed = 0.05, pain = 24, target = "any", frac = 0.16, fall = 2 } },
  drop = { name = "drop", p = 0.13, avoid = "agile", noise = 0.4,
    text = "The floor stops. You find this out with a foot already out over it.",
    hit = { fall = 4, target = "leg" } },
  long_drop = { name = "long drop", p = 0.12, avoid = "agile", noise = 0.4,
    text = "A long way down onto rock that has not been graded by anything.",
    hit = { fall = 9, target = "leg" } },
  sump = { name = "flooded sump", p = 0.12, avoid = "notice", noise = 0.3,
    text = "Standing water, deeper than it reads, and cold enough to take the breath.",
    hit = { wet = true, cold = 9, pain = 6, drown = 0.25 } },
  barbed_line = { name = "barbed line", p = 0.15, avoid = "notice", noise = 0.1,
    text = "Wire strung shin-high between two anchors, rusted to the colour of the rock.",
    hit = { skin = 20, bleed = 0.12, pain = 16, target = "leg", infect = 0.6 } },
  snap_trap = { name = "snap trap", p = 0.13, avoid = "notice", noise = 0.7,
    text = "Sprung steel under leaf litter that has no business being this deep.",
    hit = { skin = 24, muscle = 22, bleed = 0.2, pain = 44, frac = 0.45, target = "leg", infect = 0.5 } },
  shock_mine = { name = "shock mine", p = 0.13, avoid = "notice", noise = 1.5,
    text = "A disc set flush with the floor, painted the colour of the floor.",
    hit = { skin = 30, muscle = 26, bleed = 0.3, pain = 60, frac = 0.4, shrap = 4, sever = 0.12,
            target = "leg", fall = 3 } },
  sentry = { name = "sentry post", p = 0.14, avoid = "notice", noise = 1.2,
    text = "The optic finds you before you find it, and the barrel is already turning.",
    hit = { skin = 26, muscle = 20, bleed = 0.26, pain = 40, shrap = 2, target = "any" } },
  arc_coil = { name = "arc coil", p = 0.12, avoid = "notice", noise = 0.9,
    text = "Two terminals and a gap that stops being a gap when you cross it.",
    hit = { skin = 14, muscle = 10, burn = 24, pain = 44, fib = 0.3, target = "any" } },
  stalactite = { name = "falling stone", p = 0.11, avoid = "notice", noise = 0.6,
    text = "Something lets go of the roof.",
    hit = { skin = 18, muscle = 24, bleed = 0.08, pain = 38, frac = 0.4, target = "high" } },
  glass_field = { name = "glass field", p = 0.16, avoid = "notice", noise = 0.2,
    text = "A pane came down here once and has been walked through several times since.",
    hit = { skin = 14, bleed = 0.1, pain = 18, shrap = 3, target = "leg", foot = true, infect = 0.5 } },
  oil_pool = { name = "oil pool", p = 0.12, avoid = "notice", noise = 0.2,
    text = "Black to the ankle, and heavier than water in every way that matters.",
    hit = { wet = true, oil = true, pain = 4, drown = 0.4 } },
  resonator = { name = "resonator", p = 0.13, avoid = "notice", noise = 0.4,
    text = "A tone below hearing that arrives through the sternum.",
    hit = { pain = 30, brain = 1.2, fib = 0.2, target = "head", muscle = 6 } },
  slagrock = { name = "slagrock", p = 0.15, avoid = "notice", noise = 0.1,
    text = "Rock that reads warm on the back of a hand held near it.",
    hit = { pain = 6 } },
  spent_rod = { name = "spent rod", p = 0.10, avoid = "notice", noise = 0.1,
    text = "A rack of rods, one of them out of its sleeve and lying on the floor.",
    hit = { pain = 10, sick = 14 } },
  gullet_vine = { name = "gullet vine", p = 0.14, avoid = "agile", noise = 0.5,
    text = "The growth closes on an ankle with more speed than a plant should have.",
    hit = { skin = 16, muscle = 20, bleed = 0.08, pain = 34, dislo = 0.4, target = "leg", hold = true } },
  drop_press = { name = "drop press", p = 0.10, avoid = "agile", noise = 1.0,
    text = "A slab on a counterweight, tripped by the floor plate you are standing on.",
    hit = { skin = 22, muscle = 40, bleed = 0.14, pain = 68, frac = 0.65, target = "high" } },
  sawblade = { name = "sawblade rig", p = 0.13, avoid = "agile", noise = 0.8,
    text = "A disc on a shaft, still turning, still driven by something.",
    hit = { skin = 34, muscle = 30, bleed = 0.4, pain = 56, sever = 0.15, target = "any" } },
  spore_burst = { name = "spore burst", p = 0.16, avoid = "notice", noise = 0.2,
    text = "The cap splits and empties itself into the air at chest height.",
    hit = { infect = 1.2, sick = 12, pain = 6, spore = true, target = "head" } },
  ice_shelf = { name = "ice shelf", p = 0.14, avoid = "agile", noise = 0.5,
    text = "Clear ice over a void, thick enough to argue about.",
    hit = { fall = 6, cold = 14, wet = true, target = "leg" } },
  crystal_burst = { name = "crystal burst", p = 0.13, avoid = "notice", noise = 0.7,
    text = "The seam lets go along its length.",
    hit = { skin = 20, bleed = 0.14, pain = 30, shrap = 5, target = "any" } },
  vent_burst = { name = "vent burst", p = 0.15, avoid = "agile", noise = 0.6,
    text = "The vent cycles early.",
    hit = { burn = 34, pain = 46, heat = 9, skin = 16, target = "any" } },
}

--------------------------------------------------------------------- containers

D.CONTAINERS = {
  { id = "locker",    name = "steel locker",     time = 55, rolls = 2, noise = 0.5, tier = 0,
    text = "A locker on its side with the door sprung." },
  { id = "crate",     name = "supply crate",     time = 70, rolls = 3, noise = 0.6, tier = 1,
    text = "Banded crate, one band cut, the rest holding." },
  { id = "medbox",    name = "med box",          time = 45, rolls = 2, noise = 0.3, tier = 1, medical = true,
    text = "White box on a wall bracket. Green cross, catches sealed." },
  { id = "corpse",    name = "body",             time = 60, rolls = 2, noise = 0.2, tier = 0, corpse = true,
    text = "Somebody who got this far." },
  { id = "toolchest", name = "tool chest",       time = 65, rolls = 2, noise = 0.7, tier = 1, tools = true,
    text = "Drawers, most of them out, one of them jammed." },
  { id = "cache",     name = "sealed cache",     time = 95, rolls = 4, noise = 0.8, tier = 2, locked = true,
    text = "Company cache, welded shut and stencilled with a depth it was meant for." },
  { id = "debris",    name = "debris pile",      time = 40, rolls = 2, noise = 0.4, tier = 0, junk = true,
    text = "Collapse spoil. Things fell into it and stayed." },
  { id = "growth",    name = "growth",           time = 35, rolls = 2, noise = 0.2, tier = 0, forage = true,
    text = "Fruiting bodies and fibre worth stripping." },
  { id = "vending",   name = "dispenser",        time = 50, rolls = 2, noise = 0.9, tier = 1,
    text = "A dispenser, still lit, still refusing the credit it is offered." },
}

-- loot pools by category. tier gates by stratum lootTier.
D.LOOT = {
  general = {
    { id = "scrip", n = { 2, 9 }, w = 5, tier = 1 },
    { id = "cloth_strip", n = { 1, 3 }, w = 10, tier = 1 },
    { id = "scrap_metal", n = { 1, 2 }, w = 9, tier = 1 },
    { id = "plastic_chunk", n = { 1, 3 }, w = 8, tier = 1 },
    { id = "wire", n = { 1, 2 }, w = 7, tier = 1 },
    { id = "glass_shard", n = { 1, 2 }, w = 5, tier = 1 },
    { id = "dead_cell", n = { 1, 2 }, w = 5, tier = 1 },
    { id = "resin", n = { 1, 2 }, w = 5, tier = 2 },
    { id = "chem_vial", n = { 1, 1 }, w = 5, tier = 2 },
    { id = "alloy_plate", n = { 1, 1 }, w = 3, tier = 3 },
    { id = "rag_strip", n = { 1, 2 }, w = 6, tier = 1 },
    { id = "ration_brick", n = { 1, 1 }, w = 5, tier = 1 },
    { id = "protein_paste", n = { 1, 2 }, w = 5, tier = 1 },
    { id = "canned_meat", n = { 1, 1 }, w = 4, tier = 1 },
    { id = "cell", n = { 1, 1 }, w = 5, tier = 1 },
    { id = "glow_stick", n = { 1, 2 }, w = 5, tier = 1 },
    { id = "flare", n = { 1, 1 }, w = 3, tier = 2 },
    { id = "company_tag", n = { 1, 1 }, w = 3, tier = 1 },
    { id = "hand_torch", n = { 1, 1 }, w = 2, tier = 1 },
    { id = "water_flask", n = { 1, 1 }, w = 3, tier = 1 },
    { id = "purifier_tab", n = { 1, 2 }, w = 4, tier = 1 },
    { id = "pipe", n = { 1, 1 }, w = 3, tier = 1 },
    { id = "pry_bar", n = { 1, 1 }, w = 2, tier = 1 },
    { id = "cutter", n = { 1, 1 }, w = 3, tier = 1 },
    { id = "gloves", n = { 1, 1 }, w = 3, tier = 1 },
    { id = "hard_hat", n = { 1, 1 }, w = 2, tier = 1 },
    { id = "work_jacket", n = { 1, 1 }, w = 2, tier = 1 },
    { id = "steel_boots", n = { 1, 1 }, w = 2, tier = 1 },
    { id = "knee_pads", n = { 1, 1 }, w = 2, tier = 1 },
    { id = "pack_small", n = { 1, 1 }, w = 2, tier = 1 },
    { id = "pack_large", n = { 1, 1 }, w = 1, tier = 2 },
    { id = "goggles", n = { 1, 1 }, w = 2, tier = 1 },
    { id = "rock_hammer", n = { 1, 1 }, w = 2, tier = 2 },
    { id = "sleeping_roll", n = { 1, 1 }, w = 2, tier = 2 },
    { id = "grapple", n = { 1, 1 }, w = 2, tier = 2 },
    { id = "terrain_scanner", n = { 1, 1 }, w = 2, tier = 2 },
    { id = "drop_gauge", n = { 1, 1 }, w = 2, tier = 2 },
    { id = "respirator", n = { 1, 1 }, w = 2, tier = 3 },
    { id = "bloom_light", n = { 1, 1 }, w = 2, tier = 3 },
    { id = "shock_prod", n = { 1, 1 }, w = 2, tier = 3 },
    { id = "bolt_gun", n = { 1, 1 }, w = 1, tier = 3 },
    { id = "bolts", n = { 4, 10 }, w = 3, tier = 3 },
    { id = "lead_wrap", n = { 1, 1 }, w = 1, tier = 4 },
    { id = "scatter_pistol", n = { 1, 1 }, w = 1, tier = 4 },
    { id = "shells", n = { 2, 5 }, w = 2, tier = 4 },
    { id = "thermal_liner", n = { 1, 1 }, w = 2, tier = 5 },
    { id = "heat_pack", n = { 1, 1 }, w = 2, tier = 5 },
    { id = "red_scarf", n = { 1, 1 }, w = 1, tier = 3 },
  },
  medical = {
    { id = "rag_strip", n = { 1, 3 }, w = 7, tier = 1 },
    { id = "field_dressing", n = { 1, 2 }, w = 9, tier = 1 },
    { id = "gauze_roll", n = { 1, 1 }, w = 6, tier = 1 },
    { id = "polymer_seal", n = { 1, 1 }, w = 5, tier = 2 },
    { id = "pressure_pack", n = { 1, 1 }, w = 4, tier = 2 },
    { id = "bruise_pack", n = { 1, 1 }, w = 5, tier = 2 },
    { id = "clot_agent", n = { 1, 1 }, w = 3, tier = 3 },
    { id = "burn_gel", n = { 1, 1 }, w = 3, tier = 2 },
    { id = "antiseptic", n = { 1, 2 }, w = 8, tier = 1 },
    { id = "painkillers", n = { 1, 3 }, w = 8, tier = 1 },
    { id = "antibiotics", n = { 1, 2 }, w = 5, tier = 2 },
    { id = "opiate_amp", n = { 1, 2 }, w = 5, tier = 2 },
    { id = "adrenaline", n = { 1, 1 }, w = 4, tier = 2 },
    { id = "stimulant", n = { 1, 2 }, w = 4, tier = 1 },
    { id = "sedative", n = { 1, 2 }, w = 3, tier = 1 },
    { id = "tourniquet", n = { 1, 1 }, w = 5, tier = 1 },
    { id = "splint", n = { 1, 1 }, w = 5, tier = 1 },
    { id = "suture_kit", n = { 1, 1 }, w = 4, tier = 2 },
    { id = "forceps", n = { 1, 1 }, w = 4, tier = 1 },
    { id = "joint_wrench", n = { 1, 1 }, w = 3, tier = 2 },
    { id = "ice_pack", n = { 1, 1 }, w = 3, tier = 1 },
    { id = "blood_bag", n = { 1, 1 }, w = 3, tier = 2 },
    { id = "saline", n = { 1, 1 }, w = 3, tier = 1 },
    { id = "fentanyl", n = { 1, 2 }, w = 3, tier = 3 },
    { id = "naloxone", n = { 1, 1 }, w = 4, tier = 3 },
    { id = "epinephrine", n = { 1, 1 }, w = 2, tier = 3 },
    { id = "bone_welder", n = { 1, 1 }, w = 2, tier = 3 },
    { id = "chest_drain", n = { 1, 1 }, w = 2, tier = 3 },
    { id = "defibrillator", n = { 1, 1 }, w = 1, tier = 4 },
    { id = "auto_pump", n = { 1, 1 }, w = 1, tier = 4 },
    { id = "med_tin", n = { 1, 1 }, w = 2, tier = 2 },
  },
  tools = {
    { id = "scrap_metal", n = { 2, 4 }, w = 9, tier = 1 },
    { id = "wire", n = { 1, 3 }, w = 8, tier = 1 },
    { id = "pry_bar", n = { 1, 1 }, w = 5, tier = 1 },
    { id = "pipe", n = { 1, 1 }, w = 5, tier = 1 },
    { id = "rock_hammer", n = { 1, 1 }, w = 4, tier = 2 },
    { id = "joint_wrench", n = { 1, 1 }, w = 4, tier = 2 },
    { id = "forceps", n = { 1, 1 }, w = 3, tier = 1 },
    { id = "cell", n = { 1, 2 }, w = 6, tier = 1 },
    { id = "dead_cell", n = { 1, 3 }, w = 6, tier = 1 },
    { id = "alloy_plate", n = { 1, 2 }, w = 4, tier = 2 },
    { id = "terrain_scanner", n = { 1, 1 }, w = 3, tier = 2 },
    { id = "bone_welder", n = { 1, 1 }, w = 2, tier = 3 },
    { id = "grapple", n = { 1, 1 }, w = 3, tier = 2 },
  },
  forage = {
    { id = "fibre", n = { 2, 5 }, w = 10, tier = 1 },
    { id = "bittercap", n = { 1, 3 }, w = 8, tier = 1 },
    { id = "sap_fruit", n = { 1, 3 }, w = 6, tier = 4 },
    { id = "resin", n = { 1, 2 }, w = 5, tier = 2 },
    { id = "chem_vial", n = { 1, 1 }, w = 3, tier = 2 },
  },
  junk = {
    { id = "scrip", n = { 3, 14 }, w = 6, tier = 1 },
    { id = "scrap_metal", n = { 1, 2 }, w = 10, tier = 1 },
    { id = "glass_shard", n = { 1, 3 }, w = 9, tier = 1 },
    { id = "plastic_chunk", n = { 1, 2 }, w = 8, tier = 1 },
    { id = "cloth_strip", n = { 1, 2 }, w = 8, tier = 1 },
    { id = "bone_shard", n = { 1, 2 }, w = 6, tier = 1 },
    { id = "dead_cell", n = { 1, 1 }, w = 5, tier = 1 },
    { id = "company_tag", n = { 1, 1 }, w = 4, tier = 1 },
  },
}

--------------------------------------------------------------------- documents

-- Found on bodies and in caches. Dry on purpose.
D.DOCS = {
  { title = "form 12-B, partial",
    body = "RECOVERY OF ASSET. Tick one. (a) recovered intact (b) recovered, salvage value only (c) not recovered, position known (d) not recovered, position unknown. Where (d) is selected the loss is booked to Casualties: Unknown and no further action is required of the recovering party." },
  { title = "handwritten, on the back of a manifest",
    body = "Third time down. The trick with the salt crust is you send the light out ahead along the floor and you watch the shadow. If the shadow stops before the light does, the floor stops there too." },
  { title = "notice, laminated",
    body = "ALL PERSONNEL. The implant is not a punishment. It is a bond. The company has insured your descent against non-completion and the instrument of that insurance is fitted at the base of your skull. Completion voids it. Nothing else does." },
  { title = "memo, internal",
    body = "Re: attrition at stratum four. The figure is not a problem in itself. The problem is the figure is stable, which means we are not learning anything, which means we are paying for the same lesson repeatedly." },
  { title = "letter, unsent",
    body = "They told us the descent was eleven layers and I have been counting and it is eleven layers. I want that on the record. They were honest about the number." },
  { title = "pocket card, standard issue",
    body = "IN ORDER: stop the bleeding. Then the airway. Then the bone. Then the infection. A subject who reverses this order dies in a different sequence but at the same depth." },
  { title = "requisition, denied",
    body = "Requested: four units whole blood, cold stored, stratum five cache. Denied. Blood is issued against recoverable assets. Class four is not a recoverable asset." },
  { title = "scratched into a beam",
    body = "the counting one is not company. it wears the jacket. it is not company." },
  { title = "log fragment",
    body = "0412 set the tourniquet. 0419 pain manageable. 0446 pain not manageable. 0451 removed the tourniquet. 0451 this was a mistake." },
  { title = "form 40, blank",
    body = "STATEMENT OF CONDITION ON RETURN. To be completed by the returning asset. If the returning asset is unable to complete this form the form is completed on their behalf and countersigned. Countersignature is sufficient." },
  { title = "torn page",
    body = "the vents down here run about ninety seconds and you can set your rest by them. what you cannot do is set your rest by the one that runs at eighty." },
  { title = "note, folded four times",
    body = "If you find this I got to six. Six is further than the ones who wrote the training got. The training is written by people who got to three." },
  { title = "printed slip",
    body = "YOUR DEPTH BONUS ACCRUES PER STRATUM COMPLETED AND IS PAYABLE ON RETURN TO SURFACE. Partial strata do not accrue. Bodies do not accrue." },
  { title = "chalk, on the wall of a pod",
    body = "slept here four hours. woke with the heater off and the door open. did not open the door." },
}

-- Ambient one-liners, drawn between actions.
D.AMBIENCE = {
  "Water finds a way down through the rock and takes its time about it.",
  "Somewhere behind you a stone settles into a space another stone left.",
  "The lamp draws a circle and the circle is the whole world for as long as the cell holds.",
  "Air moves across the chamber from a direction that does not have an opening in it.",
  "The Line reads two points higher than it did at the last chamber.",
  "A drip lands on the back of the neck, and then does not land again.",
  "Rock dust hangs in the beam and settles at the speed of an hour hand.",
  "Something has been through here and did not take the obvious things.",
}

D.NODE_NAMES = {
  "chamber", "gallery", "crosscut", "sump", "drift", "stope", "adit", "run",
  "hollow", "bench", "shelf", "workings", "raise", "winze",
}

--------------------------------------------------------------------- helpers

function D.item(id) return D.ITEMS[id] end

-- ---- traders ---------------------------------------------------------
--
-- warm   : how well a hug lands.        higher is friendlier.
-- shrewd : resistance to haggling.      higher is harder to talk down.
-- nerve  : resistance to being leaned on. higher means they call the bluff.

D.TRADERS = {
  {
    id = "quillon", hue = "lightBlue", name = "Quillon",
    look = "Sat behind a counter made of a crate lid. Missing two fingers on the left hand.",
    warm = 0.55, shrewd = 0.5, nerve = 0.45,
    greet = "Quillon looks up. \"You are walking. That already puts you ahead.\"",
    stock = { "field_dressing", "gauze_roll", "antiseptic", "painkillers", "cell",
              "ration_brick", "splint" },
  },
  {
    id = "marn", hue = "green", name = "Marn",
    look = "Very tall, stooped under the pod ceiling. Speaks slowly and looks at your hands.",
    warm = 0.75, shrewd = 0.3, nerve = 0.25,
    greet = "Marn straightens up. \"Come in. You are letting the heat out.\"",
    stock = { "gauze_roll", "blood_bag", "antibiotics", "thermal_liner", "heat_pack",
              "ration_brick", "sleeping_roll" },
  },
  {
    id = "vasco", hue = "red", name = "Vasco",
    look = "Sits with a scatter pistol across his knees and does not put it down.",
    warm = 0.2, shrewd = 0.75, nerve = 0.85,
    greet = "Vasco does not stand up. \"Trade or leave. Do not do both slowly.\"",
    stock = { "cutter", "pry_bar", "shells", "bolts", "flare", "steel_boots", "hard_hat" },
  },
  {
    id = "iselle", hue = "white", name = "Iselle",
    look = "Company coat with the badge cut off. Everything on her counter is laid out in rows.",
    warm = 0.45, shrewd = 0.65, nerve = 0.55,
    greet = "Iselle finishes writing a line before she looks up. \"Name your business.\"",
    stock = { "suture_kit", "forceps", "opiate_amp", "naloxone", "fentanyl",
              "bone_welder", "drop_gauge" },
  },
  {
    id = "hob", hue = "yellow", name = "Hob",
    look = "Small, filthy, cheerful. Sells whatever fell off the last cart through here.",
    warm = 0.85, shrewd = 0.25, nerve = 0.2,
    greet = "Hob waves both hands. \"Friend! Look at the state of you. Come here.\"",
    stock = { "rag_strip", "bittercap", "glow_stick", "scrap_metal", "wire",
              "purifier_tab", "makeshift_splint" },
  },
  {
    id = "kestrel", hue = "purple", name = "Kestrel",
    look = "Rebreather on, hood up. You never see the face. The voice is patient.",
    warm = 0.3, shrewd = 0.8, nerve = 0.7,
    greet = "Kestrel taps the counter twice. \"Quickly, please.\"",
    stock = { "respirator", "antibiotics", "antiseptic", "clot_agent", "pressure_pack",
              "chest_drain", "defibrillator" },
  },
}

function D.trader(id)
  for _, t in ipairs(D.TRADERS) do
    if t.id == id then return t end
  end
  return D.TRADERS[1]
end

function D.stratum(n)
  local s = D.STRATA[n]
  if s then return s end
  -- past the written strata, loop the middle band with escalating pressure
  local base = D.STRATA[2 + ((n - 2) % 9)]
  local copy = U.copy(base)
  copy.id = n
  copy.lootTier = math.min(7, copy.lootTier + math.floor((n - 11) / 3))
  return copy
end

CU.data = D
return D

end
