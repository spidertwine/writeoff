-- WRITE-OFF / lib/tiles.lua
-- The world is made of these. Every tile that can be landed on says how it hurts.

return function(CU)

local T = {}

-- solid    : blocks movement
-- platform : stand on the top, pass through from underneath, drop through with DOWN
-- climb    : up and down move one tile with no fall
-- liquid   : slows you, breaks falls by depth
-- hard     : blunt force multiplier on landing. 1.0 is bare stone.
-- sharp    : how much of the impact arrives as a puncture instead of a crush
-- cushion  : fraction of the fall absorbed before it reaches you
-- name     : what the player is told they landed on

local function tile(t) return t end

T.DEFS = {
  [" "] = tile{ id = "air", name = "open air", colour = "bg" },

  ["#"] = tile{ id = "stone", name = "bare stone", solid = true, colour = "stone",
                hard = 1.00, sharp = 0.05, cushion = 0.00,
                dig = 100, drop = "stone_chunk" },

  ["%"] = tile{ id = "packed", name = "packed gravel", solid = true, colour = "gravel",
                hard = 0.80, sharp = 0.10, cushion = 0.12,
                dig = 62, drop = "stone_chunk" },

  ["o"] = tile{ id = "rubble", name = "loose rubble", solid = true, colour = "gravel",
                hard = 0.72, sharp = 0.38, cushion = 0.16,
                dig = 38, drop = "stone_chunk" },

  ["^"] = tile{ id = "spikes", name = "broken rock", solid = true, colour = "spike",
                hard = 0.85, sharp = 0.90, cushion = 0.00,
                dig = 78, drop = "glass_shard" },

  ['"'] = tile{ id = "moss", name = "a moss bed", solid = true, colour = "moss",
                hard = 0.42, sharp = 0.00, cushion = 0.46,
                dig = 24, drop = "fibre" },

  ["~"] = tile{ id = "water", name = "water", liquid = true, colour = "water",
                hard = 0.55, sharp = 0.00, cushion = 0.35 },

  ["="] = tile{ id = "plank", name = "a plank deck", platform = true, colour = "wood",
                hard = 0.78, sharp = 0.14, cushion = 0.10,
                dig = 30, drop = "plastic_chunk" },

  ["|"] = tile{ id = "rope", name = "rope", climb = true, colour = "wood" },
  ["H"] = tile{ id = "ladder", name = "a ladder", climb = true, colour = "metal" },
  ["+"] = tile{ id = "scaffold", name = "scaffold", climb = true, platform = true,
                colour = "metal", hard = 0.80, sharp = 0.30, cushion = 0.08 },

  ["V"] = tile{ id = "shaft", name = "the shaft down", shaft = true, colour = "shaft" },
  ["A"] = tile{ id = "hatch", name = "the surface hatch", hatch = true, colour = "gold" },

  -- things you interact with. they sit on the floor and you stand on their tile.
  ["c"] = tile{ id = "crate", name = "a crate", prop = true, colour = "wood" },
  ["m"] = tile{ id = "medbox", name = "a med box", prop = true, colour = "medbox" },
  ["b"] = tile{ id = "body", name = "a body", prop = true, colour = "corpse" },
  ["t"] = tile{ id = "toolchest", name = "a tool chest", prop = true, colour = "metal" },
  ["d"] = tile{ id = "debris", name = "debris", prop = true, colour = "gravel" },
  ["g"] = tile{ id = "growth", name = "growth", prop = true, colour = "moss" },
  ["l"] = tile{ id = "locker", name = "a locker", prop = true, colour = "metal" },
  ["h"] = tile{ id = "cache", name = "a sealed cache", prop = true, colour = "gold" },

  -- traps. all of them sit at standing height, so you walk into them.
  ["I"] = tile{ id = "impaler", name = "a spike", trap = true, colour = "spike" },
  ["J"] = tile{ id = "jumppad", name = "a launch plate", trap = true, colour = "metal" },
  ["K"] = tile{ id = "beartrap", name = "a leg trap", trap = true, colour = "metal" },

  -- pods: a hull you cannot break, doors you walk through, and what is inside
  ["B"] = tile{ id = "hull", name = "pod hull", solid = true, colour = "metal",
                hard = 0.80, sharp = 0.20, cushion = 0.10 },
  ["D"] = tile{ id = "door", name = "the pod door", colour = "metal" },
  ["T"] = tile{ id = "trader", name = "a trader", fixture = true, colour = "gold" },
  ["Z"] = tile{ id = "thermostat", name = "the thermostat", fixture = true, colour = "metal" },
  ["Y"] = tile{ id = "shower", name = "the decontamination shower", fixture = true,
                colour = "water" },

  -- fixtures
  ["W"] = tile{ id = "bench", name = "a workbench", fixture = true, colour = "wood" },
  ["C"] = tile{ id = "charger", name = "a charge post", fixture = true, colour = "metal" },
  ["P"] = tile{ id = "pod", name = "a life pod", fixture = true, colour = "medbox" },
  ["S"] = tile{ id = "spring", name = "a spring", fixture = true, colour = "water" },
  ["F"] = tile{ id = "heater", name = "an ion heater", fixture = true, colour = "spike" },
  ["X"] = tile{ id = "cargo", name = "the cargo crate", fixture = true, colour = "gold" },
  ["n"] = tile{ id = "note", name = "paper", fixture = true, colour = "gold" },
}

function T.get(ch) return T.DEFS[ch] or T.DEFS[" "] end

function T.isSolid(ch)
  local d = T.DEFS[ch]
  return d and d.solid or false
end

-- Something you can stand on the top of.
function T.isFloor(ch)
  local d = T.DEFS[ch]
  if not d then return false end
  return d.solid or d.platform or d.prop or d.fixture or false
end

function T.isClimb(ch)
  local d = T.DEFS[ch]
  return d and d.climb or false
end

function T.isLiquid(ch)
  local d = T.DEFS[ch]
  return d and d.liquid or false
end

-- Can the player's body occupy this tile?
function T.passable(ch)
  local d = T.DEFS[ch]
  if not d then return true end
  if d.solid then return false end
  return true
end

-- Landing surface properties, with sane defaults for anything unusual.
-- Work needed to break through, or nil if it cannot be mined.
function T.isTrap(ch)
  local d = T.DEFS[ch]
  return d and d.trap or false
end

function T.digCost(ch)
  local d = T.DEFS[ch]
  if not d then return nil end
  return d.dig
end

function T.digDrop(ch)
  local d = T.DEFS[ch]
  return d and d.drop or nil
end

function T.impact(ch)
  local d = T.DEFS[ch] or {}
  return {
    name = d.name or "the floor",
    hard = d.hard or 0.9,
    sharp = d.sharp or 0.1,
    cushion = d.cushion or 0.0,
  }
end

T.METRES_PER_TILE = 2

CU.tiles = T
return T

end
