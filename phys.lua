-- WRITE-OFF / lib/phys.lua
-- Walking, climbing, jumping, and the part where the floor stops being there.
-- The character is one tile wide and two tiles tall. The drawn figure is three
-- tall; the head only takes up screen space, not physical space.

return function(CU)

local U = CU.util
local D = CU.data
local Tl = CU.tiles
local M = CU.mapgen
local P = {}

local MPT = Tl.METRES_PER_TILE

P.BODY_H = 2          -- collision height in tiles, feet included

-- animation timing. these are the numbers to change if the jump feels wrong.
P.AIR_FRAME  = 0.11   -- seconds per cell of a jump arc
P.APEX_HANG  = 0.20   -- extra beat at the top of a jump
P.FALL_FRAME = 0.05   -- seconds per tile of a fall
P.SLIDE_FRAME = 0.07  -- seconds per tile while sliding a wall

--------------------------------------------------------------------- fitting

-- Is there room for the whole body with its feet at (x, y)?
function P.fits(map, x, y)
  if x < 1 or x > map.w or y < 2 or y > map.h then return false end
  for i = 0, P.BODY_H - 1 do
    if not Tl.passable(M.get(map, x, y - i)) then return false end
  end
  return true
end

function P.supported(map, x, y)
  if Tl.isClimb(M.get(map, x, y)) then return true end
  if Tl.isLiquid(M.get(map, x, y)) then return true end
  local below = M.get(map, x, y + 1)
  return Tl.isFloor(below) or Tl.isClimb(below) or Tl.isLiquid(below)
end

function P.canStand(map, x, y)
  return P.fits(map, x, y) and P.supported(map, x, y)
end

-- A wall you could get a hand on, on the given side.
function P.wallAt(map, x, y, dx)
  return Tl.isSolid(M.get(map, x + dx, y)) or Tl.isSolid(M.get(map, x + dx, y - 1))
end

--------------------------------------------------------------------- falling

-- How far a drop from (x, y) goes, and what is at the bottom.
function P.scanDrop(map, x, y)
  local tiles = 0
  local cy = y
  while cy < map.h do
    local below = M.get(map, x, cy + 1)
    local d = Tl.get(below)
    if d.shaft or d.hatch then return tiles, below, cy + 1, true end
    if Tl.isLiquid(below) then return tiles, below, cy + 1, false end
    if not Tl.passable(below) or Tl.isFloor(below) then return tiles, below, cy, false end
    if Tl.isClimb(below) then return tiles, below, cy, false end
    cy = cy + 1
    tiles = tiles + 1
  end
  return tiles, "#", map.h, false
end

local function waterDepth(map, x, y)
  local n, cy = 0, y
  while Tl.isLiquid(M.get(map, x, cy)) and n < 12 do n = n + 1; cy = cy + 1 end
  return n
end

--[[
  Gravity, one tile at a time, so the player can react on the way down.

  Pushing into a wall while falling catches it and turns the fall into a slide.
  Sliding wipes out the speed you had built up, which is the point: a slide is
  how you survive a shaft you should not have stepped into. It costs skin off
  your hands and arms, and it needs arms that still work.
]]
function P.settle(g, opts)
  opts = opts or {}
  local map = g.map
  local metres = 0
  local slidTiles = 0
  local guard = 0
  g.sliding = false

  while not P.supported(map, g.x, g.y) and guard < 2000 and not g.over do
    guard = guard + 1

    -- straight into the shaft below
    local under = M.get(map, g.x, g.y + 1)
    local ud = Tl.get(under)
    if ud.shaft or ud.hatch then
      g:say("You drop into the shaft.", CU.ui.c.crit)
      metres = metres + 20
      g.sliding = false
      if not g:descendTo(g.stratumIndex + 1, true) then return metres end
      map = g.map
      if P.supported(map, g.x, g.y) then
        P.resolveLanding(g, metres, M.get(map, g.x, g.y + 1))
        return metres
      end
    end

    -- which way is the player pushing, and is there a wall there
    local dir = 0
    if not (CU.ui.headless or opts.instant) then
      dir = CU.ui.pollDirection(g.sliding and P.SLIDE_FRAME or P.FALL_FRAME)
    elseif opts.slideDir then
      dir = opts.slideDir
    end

    local gripping = false
    local drift = 0
    if dir ~= 0 then
      if P.wallAt(map, g.x, g.y, dir) then
        local grip = CU.body.grip(g.body)
        if grip >= 0.25 then
          gripping = true
        elseif not g.slideFailed then
          g.slideFailed = true
          g:say("You get a hand to the wall and it does not hold.", CU.ui.c.bad)
        end
      elseif P.fits(map, g.x + dir, g.y) then
        drift = dir            -- steering in the air, the same as any platformer
      end
    end
    if drift ~= 0 then
      g.x = g.x + drift
      g.facing = drift
    end

    if gripping then
      if not g.sliding then
        g.sliding = true
        g:say("You catch the wall and start sliding.", CU.ui.c.gold)
        CU.ui.sfx("slide")
      end
      metres = 0                       -- the slide takes the speed out of it
      slidTiles = slidTiles + 1
      local glove = (g.body.gear.cutGuard or 0)
      local arm = (dir < 0) and "larm" or "rarm"
      if not g.body.limbs[arm].amputated then
        CU.body.hurt(g.body, {
          skin = 0.9 * (1 - glove * 0.7),
          pain = 1.4 * (1 - glove * 0.5),
          bleed = 0.0016 * (1 - glove * 0.8),
        }, g.rng, { limb = arm, silent = true })
      end
      g.body.energy = math.max(0, g.body.energy - 0.35)
      g:advance(1, { exertion = 0.9 })
    else
      if g.sliding then
        g.sliding = false
        g:say("The wall runs out.", CU.ui.c.warn)
      end
      metres = metres + MPT
    end

    g.y = g.y + 1
    if CU.body.totalBleed(g.body) > 0.05 then M.addBlood(map, g.x, g.y, 1) end
    local frame = opts.onFrame or g.onFrame
    if frame then frame(g) end
    if g.body.dead then g:endRun(g.body.cause); return metres end
  end

  if slidTiles > 0 then
    g:say(string.format("Slid %d m down the wall.", slidTiles * MPT), CU.ui.c.dim)
    g.stats.slidMetres = (g.stats.slidMetres or 0) + slidTiles * MPT
  end
  g.sliding = false
  g.slideFailed = false
  g.airBudget = nil

  metres = math.max(0, metres - (opts.freeMetres or 0))
  if P.trapAt(g, g.x, g.y) and metres >= 1 then
    P.springTrap(g, "fall", metres)
  end
  if metres >= 1 then
    local surfaceCh = M.get(map, g.x, g.y + 1)
    if Tl.isLiquid(M.get(map, g.x, g.y)) then
      P.resolveLanding(g, metres, M.get(map, g.x, g.y),
        waterDepth(map, g.x, g.y))
    else
      P.resolveLanding(g, metres, surfaceCh)
    end
  end
  return metres
end

function P.resolveLanding(g, metres, surfaceCh, waterTiles)
  if metres < 1 then return end
  CU.ui.sfx(metres >= 14 and "landhard" or "land")
  if waterTiles and waterTiles > 0 then g.body.wet = 1 end
  local ticks = math.max(1, math.floor(metres / 25))
  g:advance(ticks, { exertion = 0.4 })
  local before = CU.body.totalBleed(g.body)
  g:sayAll(CU.fall.land(g.body, metres, surfaceCh, g.rng))
  local added = CU.body.totalBleed(g.body) - before
  if added > 0.02 then g:splashBlood(math.min(0.35, added * 0.9)) end
  g.stats.fallMetres = (g.stats.fallMetres or 0) + metres
  if CU.body.totalBleed(g.body) > 0.05 then
    M.addBlood(g.map, g.x, g.y, 3)
  end
  if metres > (g.stats.longestFall or 0) then g.stats.longestFall = metres end
  if g.body.dead then g:endRun(g.body.cause) end
end

--------------------------------------------------------------------- the edge readout

function P.edgePreview(g, dx)
  local map = g.map
  local nx = g.x + dx
  if not P.fits(map, nx, g.y) then
    if P.fits(map, nx, g.y - 1) and P.fits(map, g.x, g.y - 1) then
      return { kind = "step" }
    end
    return { kind = "wall" }
  end
  if P.supported(map, nx, g.y) then return { kind = "walk" } end
  local tiles, surfaceCh = P.scanDrop(map, nx, g.y)
  local metres = tiles * MPT
  local surface = Tl.impact(surfaceCh)
  local verdict, eff = CU.fall.forecast(metres, surface, g.body.gear)
  local slideable = P.wallAt(map, nx, g.y, dx) or P.wallAt(map, nx, g.y, -dx)
  return { kind = "drop", metres = metres, surface = surface.name,
           verdict = verdict, effective = eff, slideable = slideable }
end

--------------------------------------------------------------------- walking

function P.walk(g, dx)
  local map = g.map
  local nx = g.x + dx
  g.facing = dx
  if g.body.trapped then return P.struggle(g) end
  if nx < 1 or nx > map.w then return false end

  if not P.fits(map, nx, g.y) then
    -- step up one tile if there is room above
    if P.fits(map, nx, g.y - 1) then
      local mob = CU.body.mobility(g.body)
      if mob < 0.25 then
        g:say("Your legs cannot lift you up that step.", CU.ui.c.warn)
        return false
      end
      g.x, g.y = nx, g.y - 1
      g:advance(4, { exertion = 0.6 })
      P.settle(g)
      return true
    end
    return false
  end

  local mob = CU.body.mobility(g.body)
  local cost = 2 / U.clamp(mob, 0.12, 1.3)
  if Tl.isLiquid(M.get(map, nx, g.y)) then cost = cost * 2.2 end

  -- a single-tile hole gets strided over. anything wider is a ledge, and
  -- walking off it is a decision.
  if not P.supported(map, nx, g.y) then
    local beyond = nx + dx
    if P.canStand(map, beyond, g.y) and mob > 0.35 then
      g.x = beyond
      g:advance(math.floor(cost * 1.6), { exertion = 0.6 })
      return true
    end
  end

  if mob < 0.2 then
    cost = cost * 2.2
    if not g.crawlWarned then
      g.crawlWarned = true
      g:say("Your legs will not hold you. You are crawling, and it is slow.", CU.ui.c.crit)
    end
  end

  g.x = nx
  g:advance(math.floor(cost), { exertion = 0.45 })
  if g.over then return true end
  P.settle(g)
  if not g.over then P.springTrap(g, "step") end
  return true
end

--------------------------------------------------------------------- jumping

--[[
  A jump is an arc, drawn one cell at a time so you can see it happen: you rise,
  you travel, and then gravity takes over and P.settle brings you down. Landing
  back at the height you left from costs nothing, because the rise is subtracted
  from the fall. Landing lower than you left from costs the difference.

  Push the other way in mid air and you cut the jump short. Push into a wall on
  the way down and you grab it, the same as any other fall.
]]

local function airFrame(g, hang)
  local frame = g.onFrame
  if frame then frame(g) end
  return CU.ui.pollDirection(hang or P.AIR_FRAME)
end

function P.jump(g)
  local map = g.map
  local body = g.body

  if body.trapped then return P.struggle(g) end
  if not P.supported(map, g.x, g.y) then
    g:say("You cannot jump in mid air.", CU.ui.c.dim)
    return false
  end
  local mob = CU.body.mobility(body)
  if mob < 0.45 then
    g:say("Your legs will not take a jump.", CU.ui.c.warn)
    return false
  end
  if body.energy < 6 then
    g:say("You have nothing left for a jump.", CU.ui.c.warn)
    return false
  end

  local rise = (mob >= 0.70 and 2) or 1
  local maxDrift = (mob >= 0.85 and 3) or (mob >= 0.62 and 2) or 1

  body.energy = math.max(0, body.energy - 5)
  g:advance(2, { exertion = 1.0 })
  if g.over then return true end
  CU.ui.sfx("jump")

  local startY = g.y
  local drifted = 0

  local function tryDrift(d)
    if d == 0 or drifted >= maxDrift then return false end
    if not P.fits(map, g.x + d, g.y) then return false end
    g.x = g.x + d
    g.facing = d
    drifted = drifted + 1
    return true
  end

  -- going up. whichever way you are pushing is the way you travel.
  for _ = 1, rise do
    if not P.fits(map, g.x, g.y - 1) then break end
    g.y = g.y - 1
    local d = airFrame(g)
    if tryDrift(d) then airFrame(g) end
  end

  -- a beat at the top, still steerable
  local hang = true
  while drifted < maxDrift do
    local d = airFrame(g, hang and P.APEX_HANG or nil)
    hang = false
    if not tryDrift(d) then break end
  end
  if drifted == 0 then airFrame(g, P.APEX_HANG) end

  local risen = math.max(0, startY - g.y)
  P.settle(g, { freeMetres = risen * MPT })
  if not g.over and P.trapAt(g, g.x, g.y) then P.springTrap(g, "jump") end
  return true
end

--------------------------------------------------------------------- traps

--[[
  Three of them, all sitting at standing height so you walk into them.

  Impaler   a spike. It only gives itself away with a light, two tiles out,
            and the light blinks. Walking onto it is a cut. Landing on it from
            a height is a puncture, and can take an eye or a jaw.
  Launch    a plate that throws you up and sideways, never straight up. The
            ceiling is a risk. The landing is the real one.
  Leg trap  closes on a leg and does not let go. Waiting it out bleeds you
            steadily. Struggling is faster and worse. Prying it open with your
            hands is best, if your hands still work.
]]

function P.trapAt(g, x, y)
  local ch = M.get(g.map, x, y)
  if Tl.isTrap(ch) then return ch end
  return nil
end

local function impale(g, mode, metres)
  local body = g.body
  local rng = g.rng
  local leg = rng:pick({ "lleg", "rleg" })
  local hit
  if mode == "fall" then
    local m = metres or 10
    hit = { skin = 18 + m * 0.35, muscle = 10 + m * 0.2,
            bleed = 0.10 + m * 0.006, pain = 30 + m * 0.5, shrap = 1 }
  elseif mode == "jump" then
    hit = { skin = 24, muscle = 12, bleed = 0.13, pain = 30 }
  else
    hit = { skin = 12, muscle = 5, bleed = 0.055, pain = 16 }
  end
  g:say("A spike goes through your " .. D.LIMBS[leg].name .. ".", CU.ui.c.crit)
  CU.ui.sfx("bitten")
  g:sayAll(CU.body.hurt(body, hit, rng, { limb = leg, silent = true }))
  M.addBlood(g.map, g.x, g.y, 3)

  -- coming down on one face first is a different injury altogether
  if mode == "fall" then
    local m = metres or 10
    if rng:chance(U.clamp((m - 8) / 60, 0, 0.5)) then
      CU.body.hurt(body, { skin = 30, muscle = 14, bleed = 0.16, pain = 60 },
        rng, { limb = "head", silent = true })
      if rng:chance(0.5) and not body.eyeLost then
        body.eyeLost = true
        g:say("It takes an eye. You will not see as well down here again.", CU.ui.c.crit)
      else
        body.limbs.head.bone = "dislocated"
        body.limbs.head.boneTimer = D.TUNE.DISLO_HEAL_MIN
        g:say("Your jaw comes away from the joint. Nothing solid is going in it.",
          CU.ui.c.crit)
      end
      CU.ui.sfx("crack")
    end
  end
end

local function launch(g)
  local map = g.map
  local body = g.body
  local rng = g.rng
  g:say("The plate throws you.", CU.ui.c.warn)
  CU.ui.sfx("jump")

  local dx = rng:chance(0.5) and 1 or -1
  if not P.fits(map, g.x + dx, g.y) then dx = -dx end
  local rise = rng:int(3, 5)
  local across = rng:int(2, 4)
  g.facing = dx

  local risen = 0
  for i = 1, rise do
    if not P.fits(map, g.x, g.y - 1) then
      -- the ceiling stops you before the arc does
      CU.body.hurt(body, { skin = 7, muscle = 6, pain = 22 }, rng,
        { limb = "head", silent = true })
      if rng:chance(0.3) then
        body.brain = U.clamp(body.brain - rng:range(1, 4), 0, 100)
      end
      g:say("You hit the ceiling.", CU.ui.c.crit)
      CU.ui.sfx("crack")
      break
    end
    g.y = g.y - 1
    risen = risen + 1
    if i <= across and P.fits(map, g.x + dx, g.y) then g.x = g.x + dx end
    local frame = g.onFrame
    if frame then frame(g) end
    if not CU.ui.headless then CU.ui.pollDirection(P.AIR_FRAME) end
  end
  P.settle(g, { freeMetres = risen * MPT })
end

local function snap(g)
  local body = g.body
  local rng = g.rng
  local leg = rng:pick({ "lleg", "rleg" })
  if body.limbs[leg].amputated then leg = (leg == "lleg") and "rleg" or "lleg" end
  body.trapped = { limb = leg, timer = P.TRAP_SECONDS, struggles = 0 }
  g:say("A leg trap closes on your " .. D.LIMBS[leg].name .. ".", CU.ui.c.crit)
  CU.ui.sfx("crack")
  g:sayAll(CU.body.hurt(body, {
    skin = 20, muscle = 13, bleed = 0.10, pain = 44, frac = 0.12,
  }, rng, { limb = leg, silent = true }))
  M.addBlood(g.map, g.x, g.y, 2)
end

P.TRAP_SECONDS = 8

-- mode is "step", "jump" or "fall"
function P.springTrap(g, mode, metres)
  local ch = P.trapAt(g, g.x, g.y)
  if not ch then return false end
  local d = Tl.get(ch)
  if d.id == "impaler" then
    impale(g, mode, metres)
    return true
  elseif d.id == "jumppad" then
    if mode ~= "launch" then launch(g) end
    return true
  elseif d.id == "beartrap" then
    M.set(g.map, g.x, g.y, " ")        -- it only closes once
    snap(g)
    return true
  end
  return false
end

-- Fighting the trap. Faster than waiting, and it costs you.
function P.struggle(g)
  local body = g.body
  local t = body.trapped
  if not t then return false end
  t.struggles = t.struggles + 1
  local leg = t.limb
  g:sayAll(CU.body.hurt(body, {
    skin = 6, muscle = 4, bleed = 0.06, pain = 14,
  }, g.rng, { limb = leg, silent = true }))
  M.addBlood(g.map, g.x, g.y, 1)
  t.timer = t.timer - 3
  g:advance(3, { exertion = 1.0 })
  CU.ui.sfx("hurt")
  if t.timer <= 0 then
    body.trapped = nil
    g:say("The jaws come apart and you drag the leg out.", CU.ui.c.ok)
  else
    g:say("It does not let go. " .. math.ceil(t.timer) .. " seconds of it left.",
      CU.ui.c.warn)
  end
  return true
end

-- Working it open with your hands. Slower, but it does not tear the leg up.
function P.pryTrap(g)
  local body = g.body
  local t = body.trapped
  if not t then return false end
  local grip = CU.body.grip(body)
  if grip < 0.25 then
    g:say("Your hands cannot open it. You will have to pull.", CU.ui.c.warn)
    return false
  end
  g:advance(6, { exertion = 0.9 })
  if g.rng:chance(U.clamp(0.3 + grip * 0.6, 0.2, 0.92)) then
    body.trapped = nil
    g:say("You get both hands into the jaws and force them apart.", CU.ui.c.ok)
    CU.ui.sfx("confirm")
  else
    t.timer = math.max(0, t.timer - 2)
    g:say("It slips. Try again.", CU.ui.c.warn)
  end
  return true
end

--------------------------------------------------------------------- water

function P.waterHere(g)
  local map = g.map
  -- a spring beats a pool, so standing in dirty water beside one still gets you
  -- the clean drink
  for dx = -2, 2 do
    for dy = 0, 1 do
      if Tl.get(M.get(map, g.x + dx, g.y + dy)).id == "spring" then
        return true, true
      end
    end
  end
  if Tl.isLiquid(M.get(map, g.x, g.y)) then return true, false end
  if Tl.isLiquid(M.get(map, g.x, g.y + 1)) then return true, false end
  return false, false
end

-- Kneel and drink straight from it. No flask needed.
function P.drink(g)
  local ok, clean = P.waterHere(g)
  if not ok then return false end
  local body = g.body
  if body.thirst >= 118 then
    g:say("You have had enough.", CU.ui.c.dim)
    return true
  end
  g:advance(18, { exertion = 0.05 })
  if g.over then return true end
  body.thirst = U.clamp(body.thirst + 34, 0, 120)
  if clean then
    g:say("You kneel and drink. Clean.", CU.ui.c.ok)
  else
    body.sick = U.clamp(body.sick + 11, 0, 100)
    g:say("You kneel and drink. It tastes of the rock, and it may cost you later.",
      CU.ui.c.warn)
  end
  CU.ui.sfx("heal")
  return true
end

--------------------------------------------------------------------- mining

--[[
  Breaking through rock by hand, one tile at a time.

  Each swing puts work into the tile in front of you. Stone takes about a hundred
  points; a rock hammer does forty six a swing, a pry bar twenty six, bare hands
  six. Every swing costs energy, and energy only comes back by resting, so a long
  tunnel means stopping halfway. Swinging with nothing in your hands tears them up.

  Target order: the tile ahead at foot level, then the tile ahead at chest level,
  then the ceiling, then the floor. Break the two ahead of you and you can walk
  through. Break the ceiling and you can jump up out of a hole.
]]

P.MINE_ENERGY_TOOL = 3.2
P.MINE_ENERGY_BARE = 4.5
P.MINE_BARE_POWER  = 9
P.MINE_MIN_ENERGY  = 4

function P.mineTarget(g, hint)
  local map = g.map
  local dx = g.facing or 1
  local order
  if hint == "up" then
    order = { { g.x, g.y - 2, "above" } }
  elseif hint == "down" then
    order = { { g.x, g.y + 1, "below" } }
  else
    order = {
      { g.x + dx, g.y,     "ahead" },
      { g.x + dx, g.y - 1, "ahead" },
      { g.x,      g.y - 2, "above" },
      { g.x,      g.y + 1, "below" },
    }
  end
  for _, t in ipairs(order) do
    local ch = M.get(map, t[1], t[2])
    if Tl.digCost(ch) and not Tl.passable(ch) then
      return t[1], t[2], ch, t[3]
    end
  end
  if hint then return nil end
  -- a plank deck underfoot can be broken out too
  local ch = M.get(map, g.x, g.y + 1)
  if Tl.digCost(ch) then return g.x, g.y + 1, ch, "below" end
  return nil
end

function P.mine(g, hint)
  local map = g.map
  local body = g.body
  local x, y, ch, where = P.mineTarget(g, hint)
  if not x then
    g:say(hint and ("Nothing to break " .. hint .. " there.")
      or "There is nothing here you can break through.", CU.ui.c.dim)
    return false
  end

  if body.energy < P.MINE_MIN_ENERGY then
    g:say("You are too tired to swing again. Rest first.", CU.ui.c.warn)
    return false
  end
  if CU.body.grip(body) < 0.2 then
    g:say("You cannot grip hard enough to swing.", CU.ui.c.warn)
    return false
  end

  local weapon = g.inv.weapon
  local wdef = weapon and D.ITEMS[weapon.id]
  local digPower = wdef and wdef.weapon and wdef.weapon.dig or 0
  local bare = digPower <= 0
  local power = (bare and P.MINE_BARE_POWER or digPower)
    * U.clamp(CU.body.swingPower(body), 0.15, 1.6)
  if body.energy < 25 then power = power * 0.6 end

  local cost = bare and P.MINE_ENERGY_BARE or P.MINE_ENERGY_TOOL
  body.energy = math.max(0, body.energy - cost)

  local swingTime = math.floor(16 / U.clamp(CU.body.swingPower(body), 0.2, 1.6))
  g:advance(swingTime, { exertion = 0.95 })
  if g.over then return true end
  CU.ui.sfx("mine")

  if bare then
    local arm = (g.rng:chance(0.5)) and "larm" or "rarm"
    CU.body.hurt(body, { skin = 1.6, pain = 2.4 }, g.rng, { limb = arm, silent = true })
  end

  -- the noise carries
  for _, e in ipairs(map.entities) do
    if not e.dead and not e.awake then
      if math.abs(e.x - g.x) + math.abs(e.y - g.y) * 2 < 16 then e.awake = true end
    end
  end

  local total = Tl.digCost(ch)
  local done = M.digAt(map, x, y) + power
  if done < total then
    M.setDig(map, x, y, done)
    g:say(string.format("You work at the rock %s. %d%%.", where,
      math.floor(done / total * 100)), CU.ui.c.dim)
    return true
  end

  M.clearDig(map, x, y)
  M.set(map, x, y, " ")
  g.stats.mined = (g.stats.mined or 0) + 1
  CU.ui.sfx("breakout")
  g:say("The rock " .. where .. " breaks through.", CU.ui.c.ok)

  local drop = Tl.digDrop(ch)
  if drop and D.ITEMS[drop] and g.rng:chance(0.6) then
    CU.inv.add(g.inv, drop, 1)
    CU.inv.updateGear(g.inv, body)
  end
  if where == "below" then P.settle(g) end
  return true
end

--------------------------------------------------------------------- climbing

function P.climb(g, dy)
  local map = g.map
  local here = M.get(map, g.x, g.y)
  local target = M.get(map, g.x, g.y + dy)
  local td = Tl.get(target)

  if dy > 0 and (td.shaft or td.hatch) then return "exit" end

  local onClimb = Tl.isClimb(here)
  local intoClimb = Tl.isClimb(target)

  if g.body.trapped then return P.struggle(g) end

  if dy < 0 then
    if not (onClimb or intoClimb) then
      -- nothing to climb, so up means dig up. that is how you get out of a hole.
      if P.mineTarget(g, "up") then return P.mine(g, "up") end
      g:say("There is nothing here to climb or break through.", CU.ui.c.dim)
      return false
    end
    if not P.fits(map, g.x, g.y - 1) then return false end
    if CU.body.grip(g.body) < 0.25 then
      g:say("Your arms cannot grip well enough to climb.", CU.ui.c.warn)
      return false
    end
    g.y = g.y - 1
    g:advance(4, { exertion = 0.8 })
    return true
  end

  if onClimb or intoClimb then
    if not Tl.passable(target) then
      g:say("That is the bottom of the climb.", CU.ui.c.dim)
      return false
    end
    g.y = g.y + 1
    g:advance(3, { exertion = 0.5 })
    if g.over then return true end
    P.settle(g)
    return true
  end

  if P.waterHere(g) then return P.drink(g) end

  local below = M.get(map, g.x, g.y + 1)
  local bd = Tl.get(below)
  if bd.platform and not bd.solid then
    g.y = g.y + 1
    P.settle(g)
    return true
  end

  if P.mineTarget(g, "down") then return P.mine(g, "down") end
  g:say("Nothing to climb here. Walk off a ledge, jump, or find a rope.", CU.ui.c.dim)
  return false
end

--------------------------------------------------------------------- creatures

function P.stepEntities(g)
  local map = g.map
  for _, e in ipairs(map.entities) do
    if not e.dead then
      local def = D.CREATURES[e.id]
      if def then
        local dx = g.x - e.x
        local dy = g.y - e.y
        local dist = math.abs(dx) + math.abs(dy) * 2
        local range = 5 + def.senses * 7 + CU.inv.lightRadius(g.inv)

        if dist <= 1 and math.abs(dy) <= 1 then
          if (e.cooldown or 0) <= 0 then
            g.stats.encounters = g.stats.encounters + 1
            CU.combat.begin(g, e)
            e.cooldown = 4
            e.patience = 0
          end
        elseif dist < range and math.abs(dy) <= 3 then
          if not e.seenBy then
            e.seenBy = true
            g:say(def.name .. " has noticed you.", CU.ui.c.warn)
          end
          e.awake = true
          e.patience = (e.patience or 0) + 1
        elseif e.awake then
          e.patience = (e.patience or 0) + 1
          if e.patience > 30 then
            e.awake = false; e.patience = 0; e.seenBy = false
          end
        end

        if e.awake and dist > 1 then
          e.step = (e.step or 0) + (def.speed or 1) * 0.6
          while e.step >= 1 do
            e.step = e.step - 1
            local sx = dx > 0 and 1 or (dx < 0 and -1 or 0)
            local nx = e.x + sx
            -- they will not follow you off a ledge or down a rope
            if sx ~= 0 and Tl.passable(M.get(map, nx, e.y)) and P.supported(map, nx, e.y) then
              e.x = nx
            elseif sx ~= 0 and Tl.passable(M.get(map, nx, e.y - 1))
                   and Tl.passable(M.get(map, e.x, e.y - 1))
                   and P.supported(map, nx, e.y - 1) then
              e.x, e.y = nx, e.y - 1
            end
          end
        end
        if (e.cooldown or 0) > 0 then e.cooldown = e.cooldown - 1 end
      end
    end
  end
end

--------------------------------------------------------------------- vision

function P.reveal(g)
  local map = g.map
  local r = math.max(3, math.floor(CU.inv.lightRadius(g.inv) * 2.6))
  local rv = math.max(3, math.floor(r * 0.72))
  for dy = -rv, rv do
    for dx = -r, r do
      if dx * dx + (dy * 2.1) * (dy * 2.1) <= r * r then
        M.markSeen(map, g.x + dx, g.y + dy - 1)
      end
    end
  end
  g.lightR = r
  g.lightRv = rv
end

CU.phys = P
return P

end
