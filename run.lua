-- WRITE-OFF / lib/run.lua
-- The run: where you are, what time it is, and what your body is doing about it.

return function(CU)

local U = CU.util
local D = CU.data
local B = CU.body
local Inv = CU.inv
local Mg = CU.mapgen
local Tl = CU.tiles
local UI = CU.ui

local R = {}
local Game = {}
Game.__index = Game
R.Game = Game

--------------------------------------------------------------------- creation

function R.new(seed, meta)
  meta = meta or {}
  local g = setmetatable({}, Game)
  g.seed = seed or 1
  g.rng = U.newRng(g.seed)
  g.clock = 0
  g.log = UI.newLog()
  g.body = B.new({ traits = meta.traits })
  g.inv = Inv.new()
  g.stratumIndex = 1
  g.facing = 1
  g.stats = { searched = 0, kills = 0, docs = 0, maxDepth = 0,
              fallMetres = 0, longestFall = 0, encounters = 0, treatments = 0 }
  g.docsFound = {}
  g.cargo = false
  g.over = false
  g.attempt = (meta.attempts or 0) + 1
  g.id = string.format("%04d-%s", g.attempt, tostring(g.seed):sub(-4))

  local kit = meta.kit or { "rag_strip", "rag_strip", "hand_torch", "cell",
                            "ration_brick", "water_flask", "pipe" }
  for _, id in ipairs(kit) do Inv.add(g.inv, id, 1) end
  local torch = U.find(Inv.entries(g.inv), function(e) return e.id == "hand_torch" end)
  if torch then torch.cell = 100; Inv.equipLight(g.inv, torch) end
  for _, wid in ipairs({ "cutter", "pry_bar", "rock_hammer", "pipe" }) do
    local wpn = U.find(Inv.entries(g.inv), function(e) return e.id == wid end)
    if wpn then Inv.equipWeapon(g.inv, wpn, g.body); break end
  end
  Inv.updateGear(g.inv, g.body)

  g.map = Mg.generate(1, g.rng)
  g.x, g.y = g.map.spawn.x, g.map.spawn.y
  g:say("Stratum I. " .. g.map.strat.name .. ".", UI.c.accent)
  g:say(g.map.strat.blurb, UI.c.text)
  g:say("Arrows walk. Up and down climb ropes. Walk off a ledge and you fall.", UI.c.dim)
  return g
end

--------------------------------------------------------------------- logging

function Game:say(text, colour) self.log:add(text, colour or UI.c.text) end

function Game:sayAll(events)
  for i = 1, #events do
    if events[i].text and events[i].text ~= "" then
      self.log:add(events[i].text, events[i].colour)
    end
  end
end

function Game:blank() self.log:blank() end

--------------------------------------------------------------------- environment

function Game:env(overrides)
  local strat = self.map.strat
  local heat, dirty = 0, 0.2 + self.stratumIndex * 0.03

  for dx = -2, 2 do
    for _, c in ipairs({ Mg.get(self.map, self.x + dx, self.y),
                         Mg.get(self.map, self.x + dx, self.y + 1) }) do
      local id = Tl.get(c).id
      if id == "heater" then heat = heat + 7 end
      if id == "pod" then heat = heat + 3 end
      if id == "moss" then dirty = dirty + 0.08 end
    end
  end
  if Tl.isLiquid(Mg.get(self.map, self.x, self.y)) then self.body.wet = 1 end

  local pod = Mg.insidePod(self.map, self.x, self.y)
  local temp = strat.temp
  if pod then
    temp = pod.temp
    heat = heat + 2
    dirty = 0.04                      -- a sealed pod is the cleanest air down here
  end

  local env = { temp = temp, heat = heat, dirty = dirty,
                exertion = 0.15, resting = false }
  if overrides then for k, v in pairs(overrides) do env[k] = v end end
  return env
end

--------------------------------------------------------------------- time

function Game:advance(seconds, envOverrides)
  if self.over then return {} end
  seconds = math.max(1, math.floor(seconds))
  local env = self:env(envOverrides)
  local events = B.tick(self.body, seconds, env, self.rng)
  self.clock = self.clock + seconds
  local lightMsgs = Inv.tickLights(self.inv, seconds)
  for i = 1, #lightMsgs do
    events[#events + 1] = { text = lightMsgs[i], colour = UI.c.warn }
  end
  Inv.updateGear(self.inv, self.body)

  -- you leave it where you stand
  local flow = B.totalBleed(self.body)
  if flow > 0.005 then
    Mg.addBlood(self.map, self.x, self.y, flow * (seconds / 60) * 0.85)
  end

  self.stats.maxDepth = math.max(self.stats.maxDepth, Mg.depthAt(self.map, self.y))
  self:sayAll(events)
  if self.body.dead then self:endRun(self.body.cause) end
  return events
end

--------------------------------------------------------------------- strata

function Game:descendTo(index, falling)
  if index > 11 then index = 11 end
  if not falling then
    self:advance(70, { exertion = 0.6 })
    if self.over then return false end
  end
  self.stratumIndex = index
  self.map = Mg.generate(index, self.rng)
  self.x, self.y = self.map.spawn.x, self.map.spawn.y
  self.crawlWarned = false
  self:blank()
  self:say("Stratum " .. U.roman(index) .. ". " .. self.map.strat.name .. ".", UI.c.accent)
  self:say(self.map.strat.blurb, UI.c.text)
  UI.sfx("descend")
  self.stats.maxDepth = math.max(self.stats.maxDepth, Mg.depthAt(self.map, self.y))
  if index == 10 then
    self:say("The cargo crate is on this level. Look for a yellow X.", UI.c.gold)
  elseif index == 11 then
    self:say("The surface lift is at the bottom of this level, marked A.", UI.c.gold)
  end
  if CU.save then pcall(CU.save.saveRun, self) end
  return true
end

function Game:takeCargo()
  if self.cargo then return end
  self.cargo = true
  self.body.load = (self.body.load or 0) + 12
  self:say("You have the cargo. It weighs 12 kg and you cannot put it down.", UI.c.gold)
  UI.sfx("loot")
end

function Game:useLift()
  self:advance(120, { exertion = 0.4 })
  if self.over then return end
  if self.cargo then
    self:extract("recovered")
  else
    self:say("The lift will not open without the cargo. The bond ends the contract instead.",
      UI.c.crit)
    self.body.brain = 0
    self:endRun("bond enforcement at the lift")
  end
end

--------------------------------------------------------------------- actions

function Game:hasPry()
  for _, e in ipairs(Inv.entries(self.inv)) do
    local it = D.ITEMS[e.id]
    if it.weapon and it.weapon.pry then return true end
  end
  return false
end

function Game:rest(seconds, safe)
  local bedroll = Inv.count(self.inv, "sleeping_roll") > 0
  local elapsed = 0
  while elapsed < seconds and not self.over do
    self:advance(60, { exertion = 0, resting = true,
      heat = (safe and 5 or 0) + (bedroll and 4 or 0) })
    elapsed = elapsed + 60
    if self.body.dead then break end
    if not safe and self.rng:chance(0.03) then
      CU.phys.stepEntities(self)
      if self.rng:chance(0.5) then
        self:say("Something moved nearby. You stop resting.", UI.c.warn)
        break
      end
    end
  end
  if not self.over then
    self:say("Rested for " .. U.dur(elapsed) .. ".", UI.c.dim)
  end
end

function Game:splashBlood(amount)
  Mg.splashBlood(self.map, self.x, self.y, amount, self.rng)
end

function Game:blackout()
  local ticks = 0
  while not self.over and self.body.consciousness < D.TUNE.CONSCIOUS_OUT and ticks < 120 do
    self:advance(20, { exertion = 0, resting = true })
    ticks = ticks + 1
  end
  if not self.over and ticks > 0 then
    self:say("You come round where you fell.", UI.c.bad)
  end
  return ticks
end

--------------------------------------------------------------------- ending

function Game:endRun(cause)
  if self.over then return end
  self.over = true
  self.cause = cause or "unrecorded"
  self.body.dead = true
  self:blank()
  self:say("DEAD. CAUSE: " .. string.upper(self.cause), UI.c.crit)
end

function Game:extract(reason)
  if self.over then return end
  self.over = true
  self.extracted = true
  self.cause = reason or "recovered"
  self:blank()
  self:say("The lift takes you up. You are out.", UI.c.gold)
end

function Game:suspend()
  self.suspended = true
  self.over = true
end

function Game:score()
  local s = math.floor(self.stats.maxDepth / 10)
  s = s + Inv.value(self.inv)
  s = s + self.stats.kills * 12
  s = s + self.stats.docs * 8
  if self.cargo then s = s + 500 end
  if self.extracted then s = math.floor(s * 1.6) end
  return s
end

CU.run = R
return R

end
