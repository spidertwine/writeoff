-- WRITE-OFF / lib/screens.lua
-- Everything the player looks at.

return function(CU)

local U = CU.util
local D = CU.data
local B = CU.body
local Inv = CU.inv
local UI = CU.ui

local S = {}

--------------------------------------------------------------------- chrome

--[[
  The top bar had a hole in the middle of it, so the keys nobody remembers live
  there now. It picks the longest set that fits beside the depth and the clock,
  and shows none of them on a monitor, where there is no keyboard to press.
]]
local HEADER_HINTS = {
  "x mine  f use  m med  v cond  q menu",
  "x mine  f use  m med  q menu",
  "x mine  f use  q menu",
  "x mine  q menu",
}

function S.header(g, override)
  local c = UI.c
  local w = UI.w
  local strat = g.map.strat
  local left = override or (U.roman(g.stratumIndex) .. "  " ..
    (w >= 58 and strat.name or string.upper(strat.tag)))
  local depth = math.floor(CU.mapgen.depthAt(g.map, g.y)) .. " m"
  local right = U.clock(g.clock)

  UI.fill(1, 1, w, 1, c.panel)

  local rightEdge = w - #right - #depth - 4       -- where the depth starts
  local leftRoom = math.max(8, math.min(#left, rightEdge - 3))

  local hint
  -- no keyboard on a monitor, so no keyboard hints there
  if not (UI.touch or UI.usingMonitor or override) then
    for _, h in ipairs(HEADER_HINTS) do
      if leftRoom + 3 + #h < rightEdge then hint = h; break end
    end
  end

  UI.write(2, 1, U.trunc(left, leftRoom), c.title, c.panel)
  if hint then
    -- dim, not faint: faint is the same grey as the panel behind it
    UI.write(rightEdge - #hint - 1, 1, hint, c.dim, c.panel)
  end
  UI.write(rightEdge, 1, depth, c.accent, c.panel)
  UI.write(w - #right, 1, right, c.dim, c.panel)
  UI.hrule(1, 2, w, c.faint)
end

function S.limbColour(body, id)
  local l = body.limbs[id]
  local c = UI.c
  if l.amputated then return c.dead end
  local frac = B.limbCondition(body, id)
  if l.revealed and l.infection > 50 then return c.infect end
  return UI.healthColour(frac)
end

function S.limbGlyphs(body, id)
  local l = body.limbs[id]
  local c = UI.c
  local out = {}
  if l.amputated then out[#out + 1] = { "X", c.crit }; return out end
  if l.tourniquet then out[#out + 1] = { "T", c.text } end
  if l.bone == "fractured" then out[#out + 1] = { "#", c.text }
  elseif l.bone == "dislocated" then out[#out + 1] = { "!", c.text } end
  local flow = l.bleed
  if l.dressing then flow = flow * (1 - l.dressing.stop) end
  if flow > 0.02 then out[#out + 1] = { "~", c.blood } end
  if l.dressing then out[#out + 1] = { "+", c.bone } end
  if l.shrapnel > 0 then out[#out + 1] = { "*", c.warn } end
  if l.revealed then out[#out + 1] = { "o", c.infect } end
  if l.splint then out[#out + 1] = { "|", c.bone } end
  return out
end

function S.miniBody(x, y, body, highlight)
  UI.figure(x, y,
    function(id) return S.limbColour(body, id) end,
    function(id) return S.limbGlyphs(body, id) end,
    highlight)
end

function S.vitals(y, g)
  local c = UI.c
  local b = g.body
  local pain = select(1, B.effectivePain(b))
  local bleed = B.totalBleed(b)
  local parts = {}
  local function add(label, value, colour) parts[#parts + 1] = { label, value, colour } end
  add("hr", b.arrest and "--" or tostring(math.floor(b.hr)),
      (b.hr > 150 or b.hr < 48 or b.arrest) and c.crit or c.text)
  add("oxy", math.floor(b.spo2) .. "%", b.spo2 < 88 and c.crit or c.text)
  add("blood", U.fmt1(b.blood) .. "L", b.blood < 3.6 and c.crit or (b.blood < 4.4 and c.bad or c.text))
  add("pain", tostring(math.floor(pain)), pain > 60 and c.crit or (pain > 30 and c.warn or c.text))
  if bleed > 0.018 then
    add("bleeding", U.fmt2(bleed) .. "L/m", c.blood)
  else
    add("temp", U.fmt1(b.temp), (b.temp < 35 or b.temp > 38.5) and c.bad or c.text)
  end
  local x = 2
  for i = 1, #parts do
    local p = parts[i]
    if x + #p[1] + #p[2] + 3 > UI.w then break end
    UI.write(x, y, p[1], c.faint)
    x = x + #p[1] + 1
    UI.write(x, y, p[2], p[3])
    x = x + #p[2] + 2
  end
end

-- Stacked version for the side panel on wide screens.
function S.vitalsColumn(x, y, g)
  local c = UI.c
  local b = g.body
  local pain = select(1, B.effectivePain(b))
  local bleed = B.totalBleed(b)
  local function row(label, value, colour)
    UI.write(x, y, U.pad(label, 7), c.faint)
    UI.write(x + 7, y, U.trunc(value, 8), colour or c.text)
    y = y + 1
  end
  row("hr", b.arrest and "arrest" or tostring(math.floor(b.hr)),
      (b.arrest or b.hr > 150) and c.crit or c.text)
  row("oxygen", math.floor(b.spo2) .. "%", b.spo2 < 88 and c.crit or c.text)
  row("blood", U.fmt1(b.blood) .. "L", b.blood < 3.6 and c.crit or c.text)
  row("pain", tostring(math.floor(pain)), pain > 60 and c.crit or c.text)
  row("temp", U.fmt1(b.temp) .. "C", (b.temp < 35 or b.temp > 38.5) and c.bad or c.text)
  if bleed > 0.018 then row("losing", U.fmt2(bleed) .. "L/m", c.blood) end
  local light = CU.inv.lightRadius(g.inv)
  row("light", U.fmt1(light), light < 1 and c.bad or c.dim)
  row("energy", math.floor(b.energy) .. "%", b.energy < 25 and c.bad or c.dim)
  row("carry", math.floor(CU.inv.mass(g.inv)) .. "/" .. math.floor(B.carryCapacity(g.body)), c.dim)
end

-- Anything already shown as a number does not need to be shown as a word too.
local COVERED = {
  PAI = true, pai = true, BLD = true, bld = true, HYP = true, hyp = true,
  ["O2!"] = true, o2 = true, TAC = true, BRA = true,
  ["BP-"] = true, ["bp-"] = true, ["BP+"] = true,
}

function S.moodleStrip(y, g)
  local list = B.moodles(g.body)
  UI.write(1, y, string.rep(" ", UI.w), UI.c.text, UI.c.bg)
  if #list == 0 then
    UI.write(2, y, "nothing wrong with you", UI.c.faint)
    return
  end
  local x = 2
  for i = 1, #list do
    local m = list[i]
    if x + #m.label + 2 > UI.w then break end
    UI.write(x, y, m.label, m.colour)
    x = x + #m.label + 2
  end
end

--[[
  The one row under the log. It carries what you cannot afford to miss and
  nothing else.

  Left: blood and pain, always. Everything else only when it has gone wrong,
  because a heart rate of 72 is not news.

  Right: whichever of these matters most right now.
    1. a drop beside you, and what is at the bottom
    2. something under your feet worth pressing F on
    3. whatever is wrong with you that is not already a number
]]
-- Returns a list of versions of the same message, longest first, so the row can
-- take whichever one fits instead of chopping a word in half.
function S.statusTail(g)
  local c = UI.c
  local P = CU.phys
  local Mg = CU.mapgen
  local Tl = CU.tiles

  for _, dx in ipairs({ -1, 1 }) do
    local pv = P.edgePreview(g, dx)
    if pv.kind == "drop" and pv.effective >= 1 then
      local col = c.ok
      if pv.effective >= 3 then col = c.warn end
      if pv.effective >= 30 then col = c.crit end
      local arrow = dx < 0 and "<" or ">"
      local dist = g.hasGauge and math.floor(pv.metres)
                   or math.floor(pv.metres / 5 + 0.5) * 5
      local head = arrow .. " " .. dist .. "m"
      if pv.effective < 3 then
        return { head .. " onto " .. pv.surface, head .. ", safe", head }, col
      end
      local wall = (pv.slideable and pv.effective >= 12) and ", wall" or ""
      return {
        head .. " " .. pv.surface .. ", " .. pv.verdict .. wall,
        head .. ", " .. pv.verdict .. wall,
        head .. ", " .. pv.verdict,
        head,
      }, col
    end
  end

  local t = g.body.trapped
  if t then
    return { "leg trap. f to pry it open, or move to pull", "leg trap. f to pry" },
      c.crit
  end

  if g.sliding then
    return { "sliding, keep pushing into the wall", "sliding" }, c.gold
  end

  if CU.phys.waterHere(g) then
    local _, clean = CU.phys.waterHere(g)
    local what = clean and "clean water" or "water"
    if g.body.thirst < 70 then
      return { what .. ". down to kneel and drink", "down to drink" }, c.cold
    end
  end

  for _, off in ipairs({ 0, 1 }) do
    local d = Tl.get(Mg.get(g.map, g.x, g.y + off))
    if d.shaft then
      return { "the way down. press DOWN to take it", "DOWN to descend" }, c.accent
    end
    if d.hatch then
      return { "the surface lift. press DOWN to call it", "DOWN for the lift" }, c.gold
    end
    if d.prop or d.fixture then
      return { d.name .. ", f to use", d.name, "f to use" }, c.accent
    end
  end

  local words = {}
  for _, m in ipairs(B.moodles(g.body)) do
    if not COVERED[m.code] then words[#words + 1] = m.label end
  end
  if #words == 0 then return nil end
  local col = c.warn
  local variants = {}
  for n = math.min(3, #words), 1, -1 do
    variants[#variants + 1] = table.concat(words, ", ", 1, n)
  end
  return variants, col, true          -- soft: yields the row to the numbers
end

--[[
  The whole readout is one row, so it has to share. The tail is reserved first,
  because a ledge or a trader in front of you outranks a heart rate, then the
  numbers fill whatever is left in order of how much trouble they mean.
]]
function S.statusLine(y, g, numbers)
  local c = UI.c
  local b = g.body
  UI.write(1, y, string.rep(" ", UI.w), c.text, c.bg)

  local variants, tcol, soft = S.statusTail(g)
  local tail = nil

  local nums = {}
  if numbers then
    local pain = select(1, B.effectivePain(b))
    local bleed = B.totalBleed(b)
    local function add(label, value, colour)
      nums[#nums + 1] = { label = label, value = value, colour = colour }
    end
    add("blood", U.fmt1(b.blood) .. "L",
      b.blood < 3.6 and c.crit or (b.blood < 4.4 and c.bad or c.text))
    add("pain", tostring(math.floor(pain)),
      pain > 60 and c.crit or (pain > 30 and c.warn or c.text))
    -- the rest only speak up when something has gone wrong
    if bleed > 0.018 then add("losing", U.fmt2(bleed), c.blood) end
    if b.spo2 < 92 then add("oxy", math.floor(b.spo2) .. "%", c.crit) end
    if b.arrest then add("hr", "arrest", c.crit)
    elseif b.hr > 140 or b.hr < 50 then add("hr", tostring(math.floor(b.hr)), c.crit) end
    if b.temp < 35.5 or b.temp > 38.2 then add("temp", U.fmt1(b.temp), c.bad) end
    if b.consciousness < 60 then
      add("awake", math.floor(b.consciousness) .. "%", c.bad)
    end
  end

  -- work out how wide the numbers want to be, keeping the first two whatever happens
  local widths, total = {}, 0
  for i, n in ipairs(nums) do
    widths[i] = #n.label + #n.value + 3
    total = total + widths[i]
  end
  local room = UI.w - 3
  if variants then
    local want = soft and 10
      or math.max(14, math.min(#variants[1], math.floor(UI.w * 0.55)))
    local keep = 0
    for i = 1, #nums do
      if i <= 2 or keep + widths[i] <= room - want then
        keep = keep + widths[i]
      else
        for j = #nums, i, -1 do table.remove(nums, j) end
        break
      end
    end
    total = keep
    local left = room - total
    for _, v in ipairs(variants) do
      if #v <= left then tail = v; break end
    end
    if not tail and left >= 8 then tail = U.trunc(variants[#variants], left) end
  end

  local x = 2
  for _, n in ipairs(nums) do
    if x + #n.label + #n.value + 2 > UI.w then break end
    UI.write(x, y, n.label, c.faint)
    x = x + #n.label + 1
    UI.write(x, y, n.value, n.colour)
    x = x + #n.value + 2
  end
  if tail then
    UI.write(math.max(x, UI.w - #tail), y, tail, tcol or c.dim)
  end
end

--------------------------------------------------------------------- blackout

function S.blackout(g)
  UI.beginFrame()
  UI.clear()
  local msgs = {
    "Dark.", "Someone is counting.", "Cold through the back.",
    "The lamp is still on. You are not.", "Water, somewhere, still going.",
  }
  UI.write(math.floor((UI.w - 20) / 2), math.floor(UI.h / 2),
    U.center(msgs[g.rng:int(1, #msgs)], 20), UI.c.faint)
  UI.endFrame()
  if not UI.headless then os.sleep(0.6) end
  g:blackout()
end

--------------------------------------------------------------------- condition

-- One line explaining what is driving each moodle, so the player can act on it.
local MOODLE_NOTE = {
  BLD = "find the wound and dress it, nothing else",
  bld = "dress it before it is the thing that kills",
  INT = "torn inside. procoagulant, or a surgeon",
  HTX = "blood in the chest cavity. it needs draining",
  HYP = "not enough volume left to carry oxygen",
  hyp = "volume down. saturation follows",
  VOL = "too much volume. pressure has nowhere to go",
  ["O2!"] = "the brain is running on what is left",
  o2 = "saturation falling. check chest and volume",
  ARR = "no rhythm. paddles, or adrenaline, now",
  FIB = "the rhythm has gone chaotic. it will arrest",
  RSP = "not breathing. opiates, neck tourniquet, chest",
  TAC = "the heart is compensating for something",
  BRA = "cold or heavily drugged",
  ["BP-"] = "pressure too low to perfuse",
  ["bp-"] = "pressure low",
  ["BP+"] = "pressure high. thickened blood, usually",
  PAI = "hands will not do fine work at this level",
  pai = "steadiness is suffering",
  ["OD!"] = "too much opiate. naloxone reverses it",
  OPI = "heavily masked. you cannot feel new damage",
  opi = "pain masked, breathing shallower",
  WDR = "asking for more of what you gave it",
  adr = "temporary. hiding the damage, not fixing it",
  SEP = "the infection is systemic now",
  sep = "infection has left the limb",
  INF = "antiseptic on the limb, antibiotics in blood",
  COM = "not coming back without oxygen to the brain",
  NEU = "permanent unless the cause stops",
  neu = "brain tissue lost",
  cog = "reading and fine work are affected",
  FRZ = "core temperature critical",
  col = "warmth, dry clothing, shelter",
  HOT = "core too high. cold water or leave the heat",
  fev = "usually infection",
  wet = "wet halves every layer you are wearing",
  SIC = "bad food, bad water, or a bad wound",
  sic = "settle it before it costs you a meal",
  STV = "muscle is being taken to keep you upright",
  hun = "eat when the chamber is quiet",
  DEH = "the blood is thickening",
  thi = "drink",
  EXH = "everything is slower and less accurate",
  tir = "rest costs time, not resting costs accuracy",
  OUT = "the chamber continues without you",
  daz = "reactions are late",
  LOD = "carrying more than the frame will take",
  lod = "over the comfortable load",
  TQ = "on the clock. the limb under it is dying",
  EMB = "something is lodged in the lung",
  AMP = "the limb is gone. keep the stump covered",
}

function S.condition(g)
  local c = UI.c
  local b = g.body
  local scroll = 0
  while not g.over do
    local list = B.moodles(b)
    UI.beginFrame()
    S.header(g, "CONDITION")

    -- left: the moodle list
    local rows = UI.h - 6
    local listW = UI.w - 17
    for i = 1, rows do
      local m = list[i + scroll]
      if m then
        local sev = string.rep("|", math.min(4, m.sev))
        UI.write(2, 2 + i, U.pad(sev, 5), m.colour)
        UI.write(7, 2 + i, U.trunc(m.label, listW), m.colour)
      end
    end
    if #list == 0 then
      UI.write(2, 4, "Nothing on file. Enjoy it.", c.faint)
    end

    -- right: the numbers behind them
    local x = UI.w - 15
    local y = 3
    local function row(label, value, colour)
      UI.write(x, y, U.pad(label, 6), c.faint)
      UI.write(x + 6, y, U.trunc(value, 9), colour or c.text)
      y = y + 1
    end
    row("hr", b.arrest and "arrest" or math.floor(b.hr) .. "",
      (b.arrest or b.hr > 150 or b.hr < 48) and c.crit or c.text)
    row("bp", math.floor(b.bp) .. "", b.bp < 85 and c.bad or c.text)
    row("spo2", math.floor(b.spo2) .. "%", b.spo2 < 88 and c.crit or c.text)
    row("resp", math.floor(b.resp) .. "", b.resp < 8 and c.crit or c.text)
    row("blood", U.fmt1(b.blood) .. "L", b.blood < 3.6 and c.crit or c.text)
    row("visc", math.floor(b.visc) .. "", math.abs(b.visc) > 60 and c.bad or c.dim)
    row("temp", U.fmt1(b.temp), (b.temp < 35 or b.temp > 38.5) and c.bad or c.text)
    row("brain", math.floor(b.brain) .. "", b.brain < 80 and c.crit or c.text)
    row("cons", math.floor(b.consciousness) .. "", b.consciousness < 50 and c.bad or c.text)
    row("immun", math.floor(b.immunity) .. "", b.immunity < 60 and c.bad or c.dim)

    -- the three bars nobody looks at until they matter
    UI.hrule(1, UI.h - 5, UI.w, c.faint)
    UI.stat(2, UI.h - 4, "food", 6, b.hunger / 100, UI.healthColour(b.hunger / 100), nil, 12)
    UI.stat(22, UI.h - 4, "water", 6, b.thirst / 100, UI.healthColour(b.thirst / 100), nil, 12)
    UI.stat(2, UI.h - 3, "rest", 6, b.energy / 100, UI.healthColour(b.energy / 100), nil, 12)
    UI.stat(22, UI.h - 3, "mood", 6, b.mood / 100, UI.healthColour(b.mood / 100), nil, 12)

    local top = list[1 + scroll]
    if top and MOODLE_NOTE[top.code] then
      UI.write(2, UI.h - 2, U.trunc(MOODLE_NOTE[top.code], UI.w - 3), c.dim)
    end
    UI.write(2, UI.h - 1, "up/down read   m medical   q back", c.faint)
    UI.endFrame()

    local ev = UI.read()
    if ev.kind == "char" then
      if ev.char == "q" then return end
      if ev.char == "m" then S.medical(g); return end
    elseif ev.kind == "key" then
      if ev.name == "back" then return end
      if ev.name == "down" then scroll = math.min(math.max(0, #list - 1), scroll + 1) end
      if ev.name == "up" then scroll = math.max(0, scroll - 1) end
      if ev.name == "enter" then return end
    end
  end
end

--------------------------------------------------------------------- medical

local function limbLine(body, id)
  local l = body.limbs[id]
  local meta = D.LIMBS[id]
  local bits = {}
  if l.amputated then return "gone" end
  if l.bone == "fractured" then bits[#bits + 1] = "fracture" end
  if l.bone == "dislocated" then bits[#bits + 1] = "dislocated" end
  local flow = l.bleed
  if l.tourniquet then flow = 0 elseif l.dressing then flow = flow * (1 - l.dressing.stop) end
  if flow > 0.02 then bits[#bits + 1] = "bleeding" end
  if l.shrapnel > 0 then bits[#bits + 1] = l.shrapnel .. " frag" end
  if l.revealed then bits[#bits + 1] = "infected" end
  if #bits == 0 then return "" end
  return table.concat(bits, ", ")
end

local function drawMedical(g, sel)
  local c = UI.c
  local body = g.body
  UI.beginFrame()
  S.header(g, "TRIAGE")
  S.miniBody(10, 4, body, sel)

  -- triage list down the left edge
  for i, id in ipairs(D.LIMB_ORDER) do
    local meta = D.LIMBS[id]
    local row = 3 + i
    local chosen = (id == sel)
    local bg = chosen and c.select or c.bg
    UI.write(1, row, " " .. meta.key .. " " .. meta.short .. " ",
      chosen and c.text or S.limbColour(body, id), bg)
  end

  local x = 22
  local w = UI.w - x + 1
  local l = body.limbs[sel]
  local meta = D.LIMBS[sel]
  UI.write(x, 3, string.upper(meta.name), S.limbColour(body, sel))
  if l.amputated then
    UI.write(x, 5, "amputated.", c.crit)
    UI.write(x, 6, "bleeding " .. U.fmt2(l.bleed) .. " L/m", c.blood)
  else
    UI.stat(x, 5, "skin", 7, l.skin / 100, UI.healthColour(l.skin / 100), tostring(math.floor(l.skin)), 15)
    UI.stat(x, 6, "muscle", 7, l.muscle / 100, UI.healthColour(l.muscle / 100), tostring(math.floor(l.muscle)), 15)
    local boneTxt = "sound"
    local boneCol = c.dim
    if l.bone == "fractured" then boneTxt = "FRACTURED " .. math.ceil(l.boneTimer) .. "m"; boneCol = c.crit
    elseif l.bone == "dislocated" then boneTxt = "DISLOCATED " .. math.ceil(l.boneTimer) .. "m"; boneCol = c.bad end
    if l.splint then boneTxt = boneTxt .. " +splint" end
    UI.write(x, 7, U.trunc("bone   " .. boneTxt, w - 1), boneCol)

    local flow = l.bleed
    if l.tourniquet then flow = 0 elseif l.dressing then flow = flow * (1 - l.dressing.stop) end
    local bleedTxt = flow > 0.001 and (U.fmt2(flow) .. " L/m") or "none"
    UI.write(x, 8, U.trunc("bleed  " .. bleedTxt, w - 1), flow > 0.05 and c.crit or (flow > 0 and c.blood or c.dim))
    if l.dressing then
      local soak = l.dressing.absorb > 0 and math.floor(l.dressing.soak / l.dressing.absorb * 100) or 0
      UI.write(x, 9, U.trunc("dress  " .. l.dressing.name .. " " .. soak .. "% soaked", w - 1), c.bone)
    elseif l.tourniquet then
      UI.write(x, 9, U.trunc("tourniquet " .. U.dur(l.tourniquet.time), w - 1), c.warn)
    else
      UI.write(x, 9, "dress  none", c.faint)
    end
    UI.write(x, 10, U.trunc("pain   " .. math.floor(l.pain), w - 1), l.pain > 55 and c.crit or c.text)
    local infTxt = l.revealed and (math.floor(l.infection) .. "%") or (l.disinfect > 0 and "clean" or "-")
    UI.write(x, 11, U.trunc("infect " .. infTxt, w - 1), l.revealed and c.infect or c.dim)
    UI.write(x, 12, U.trunc("frags  " .. (l.shrapnel > 0 and l.shrapnel or "-"), w - 1),
      l.shrapnel > 0 and c.warn or c.dim)
    if l.burn > 1 then UI.write(x, 13, "burns  " .. math.floor(l.burn), c.hot) end
  end

  UI.hrule(1, UI.h - 4, UI.w, c.faint)
  S.vitals(UI.h - 3, g)
  S.moodleStrip(UI.h - 2, g)
  if UI.w >= 58 then
    UI.write(2, UI.h - 5, "~bleed  #broken  !out of joint", c.faint)
    UI.write(2, UI.h - 4, "+dressed  Ttourniquet  *shrapnel  oinfected", c.faint)
  end
  UI.write(2, UI.h - 1, U.trunc("1-7 limb  t treat  g drugs  e exercise  v cond  q back", UI.w - 2), c.faint)
  UI.endFrame()
end

local function treatmentMenu(g, sel)
  local body = g.body
  local l = body.limbs[sel]
  local items = {}
  local function add(label, hint, fn, colour)
    items[#items + 1] = { label = label, hint = hint, run = fn, colour = colour }
  end

  -- dressings
  for _, e in ipairs(Inv.entries(g.inv, function(_, it) return it.kind == "dressing" end)) do
    local it = D.ITEMS[e.id]
    add("apply " .. it.short, "x" .. e.n, function()
      g:advance(it.dressing.time, { exertion = 0.2 })
      local ok, msg = B.med.applyDressing(body, sel, it, g.rng)
      if ok then Inv.removeEntry(g.inv, e, 1); g.stats.treatments = g.stats.treatments + 1 end
      g:say(msg, ok and UI.c.ok or UI.c.warn)
      UI.sfx(ok and "heal" or "deny")
    end)
  end

  -- tourniquet
  if l.tourniquet then
    add("remove tourniquet", "", function()
      g:advance(10)
      local ok, msg = B.med.tourniquet(body, sel, false)
      Inv.add(g.inv, "tourniquet", 1)
      g:say(msg, UI.c.warn)
    end, UI.c.warn)
  elseif Inv.count(g.inv, "tourniquet") > 0 and D.LIMBS[sel].limb then
    add("apply tourniquet", "", function()
      g:advance(16, { exertion = 0.2 })
      local ok, msg = B.med.tourniquet(body, sel, true)
      if ok then Inv.remove(g.inv, "tourniquet", 1) end
      g:say(msg, ok and UI.c.ok or UI.c.warn)
    end)
  end

  -- splints
  if l.splint then
    add("remove splint", "", function()
      Inv.add(g.inv, l.splint.id, 1)
      B.med.splint(body, sel, nil, false)
      g:advance(10)
      g:say("Splint off.", UI.c.dim)
    end)
  else
    for _, e in ipairs(Inv.entries(g.inv, function(_, it) return it.tool and it.tool.type == "splint" end)) do
      local it = D.ITEMS[e.id]
      add("splint with " .. it.short, "", function()
        g:advance(it.tool.time, { exertion = 0.2 })
        local ok, msg = B.med.splint(body, sel, it, true)
        if ok then Inv.removeEntry(g.inv, e, 1) end
        g:say(msg, ok and UI.c.ok or UI.c.warn)
      end)
    end
  end

  -- dislocation
  if l.bone == "dislocated" then
    local wrench = Inv.count(g.inv, "joint_wrench") > 0
    local painNow = select(1, B.effectivePain(body))
    if painNow > 75 and not wrench then
      add("reduce joint", "pain too high", function() end, UI.c.faint)
      items[#items].disabled = true
    else
      add(wrench and "set joint with wrench" or "set joint by hand", "", function()
        local steady = B.steadiness(body, wrench and 0.28 or 0)
        local ok = UI.steadyCheck("SET JOINT",
          "Line the head of the bone up with the socket and commit.", steady,
          { zoneColour = UI.c.warn })
        g:advance(7, { exertion = 0.5 })
        if ok == nil then return end
        local done, msg = B.med.reduce(body, sel, g.rng, wrench and ok)
        g:say(msg, done and UI.c.ok or UI.c.warn)
        UI.sfx(done and "heal" or "crack")
      end)
    end
  end

  -- fracture
  if l.bone == "fractured" then
    local welder = U.find(Inv.entries(g.inv), function(e)
      local it = D.ITEMS[e.id]
      return it.tool and it.tool.type == "welder" and (e.charges or 0) > 0
    end)
    if welder then
      add("weld bone", (welder.charges or 0) .. " charges", function()
        g:advance(26, { exertion = 0.3 })
        welder.charges = welder.charges - 1
        local ok, msg = B.med.weld(body, sel)
        g:say(msg, UI.c.warn)
      end)
    end
  end

  -- shrapnel
  if l.shrapnel > 0 then
    local forceps = Inv.count(g.inv, "forceps") > 0
    add(forceps and "pull fragment (forceps)" or "pull fragment", l.shrapnel .. " in", function()
      local steady = B.steadiness(body, forceps and 0.34 or 0)
      local ok = UI.steadyCheck("EXTRACTION",
        "Grip it, follow the angle it went in at, and pull straight.", steady,
        { zoneColour = UI.c.accent })
      g:advance(9, { exertion = 0.15 })
      if ok == nil then return end
      local done, msg = B.med.removeShrapnel(body, sel, g.rng, ok, forceps)
      g:say(msg, done and UI.c.ok or UI.c.warn)
      UI.sfx(done and "confirm" or "hurt")
    end)
  end

  -- sutures
  local suture = U.find(Inv.entries(g.inv), function(e)
    local it = D.ITEMS[e.id]
    return it.tool and it.tool.type == "suture" and (e.charges or 0) > 0
  end)
  if suture and l.skin < 80 and not l.amputated then
    add("suture", (suture.charges or 0) .. " left", function()
      local steady = B.steadiness(body)
      local ok = UI.steadyCheck("SUTURE", "Pass the needle through both edges and draw them together.",
        steady, { zoneColour = UI.c.ok })
      g:advance(45, { exertion = 0.15 })
      if ok == nil then return end
      suture.charges = suture.charges - 1
      local done, msg = B.med.suture(body, sel, g.rng, ok)
      g:say(msg, done and UI.c.ok or UI.c.warn)
    end)
  end

  -- antiseptic
  if Inv.count(g.inv, "antiseptic") > 0 then
    add("disinfect", "", function()
      g:advance(12, { exertion = 0.1 })
      Inv.remove(g.inv, "antiseptic", 1)
      local ok, msg = B.med.disinfect(body, sel, D.ITEMS.antiseptic.drug.disinfect)
      g:say(msg, UI.c.ok)
    end)
  end

  -- ice pack
  local ice = U.find(Inv.entries(g.inv), function(e)
    local it = D.ITEMS[e.id]
    return it.tool and it.tool.type == "chill" and (e.uses or 0) > 0
  end)
  if ice then
    add("ice pack", (ice.uses or 0) .. " uses", function()
      g:advance(8)
      ice.uses = ice.uses - 1
      if ice.uses <= 0 then Inv.removeEntry(g.inv, ice, 1) end
      l.chill = 900
      body.temp = body.temp - 1
      g:say("Cold pack on. The pain drops.", UI.c.cold)
    end)
  end

  -- amputation
  if D.LIMBS[sel].limb and not l.amputated then
    local blade = U.find(Inv.entries(g.inv), function(e)
      local it = D.ITEMS[e.id]
      return it.weapon and (it.weapon.butcher or it.weapon.dig)
    end)
    if blade and (l.infection > 70 or l.muscle < 12 or l.bone == "fractured") then
      add("amputate", "no coming back", function()
        if not UI.confirm("AMPUTATE", "Take the " .. D.LIMBS[sel].name .. " off at the joint. "
          .. (l.tourniquet and "The tourniquet is on." or "There is no tourniquet on it.")) then return end
        g:advance(120, { exertion = 0.8 })
        local out = {}
        B.amputate(body, sel, out, "off")
        g:sayAll(out)
        if not l.tourniquet then
          g:say("Without a tourniquet this is a way of dying more slowly.", UI.c.crit)
        end
        body.amputations = (body.amputations or 0) + 1
      end, UI.c.crit)
    end
  end

  if #items == 0 then
    UI.message("nothing to do", "You have nothing in your pack that helps this limb.")
    return
  end
  local sel2 = UI.pick("treat " .. D.LIMBS[sel].name, items,
    { under = function() drawMedical(g, sel) end, width = 40 })
  if sel2 and sel2.run then sel2.run() end
end

local function drugMenu(g)
  local body = g.body
  local items = {}
  for _, e in ipairs(Inv.entries(g.inv, function(_, it) return it.kind == "drug" and it.drug.via ~= "topical" end)) do
    local it = D.ITEMS[e.id]
    items[#items + 1] = { label = it.name, hint = "x" .. e.n, entry = e, def = it }
  end
  -- systemic tools
  local defib = U.find(Inv.entries(g.inv), function(e)
    local it = D.ITEMS[e.id]; return it.tool and it.tool.type == "defib" and (e.charges or 0) > 0
  end)
  if defib then
    items[#items + 1] = { label = "defibrillator", hint = (defib.charges or 0) .. " chg", special = "defib", entry = defib }
  end
  local drain = U.find(Inv.entries(g.inv), function(e)
    local it = D.ITEMS[e.id]; return it.tool and it.tool.type == "drain"
  end)
  if drain then
    items[#items + 1] = { label = "chest drain", hint = "", special = "drain", entry = drain }
  end
  if #items == 0 then
    UI.message("nothing to take", "You have no drugs, no paddles and no chest drain.")
    return
  end
  local pick = UI.pick("systemic", items, { under = function() drawMedical(g, "thorax") end })
  if not pick then return end

  if pick.special == "defib" then
    g:advance(20, { exertion = 0.4 })
    pick.entry.charges = pick.entry.charges - 1
    local ok, msg = B.med.defib(body, g.rng)
    g:say(msg, ok and UI.c.ok or UI.c.crit)
    return
  end
  if pick.special == "drain" then
    g:advance(40, { exertion = 0.2 })
    local ok, msg = B.med.drain(body)
    if ok then Inv.removeEntry(g.inv, pick.entry, 1) end
    g:say(msg, ok and UI.c.ok or UI.c.warn)
    return
  end

  local it = pick.def
  local doses = 1
  if pick.entry.n > 1 and (it.drug.opioid or it.drug.via == "oral") then
    local opts = {}
    for i = 1, math.min(4, pick.entry.n) do
      opts[#opts + 1] = { label = i .. (i == 1 and " dose" or " doses"), key = tostring(i), value = i }
    end
    local d = UI.pick("how much", opts, { under = function() drawMedical(g, "thorax") end })
    if not d then return end
    doses = d.value
  end
  g:advance(it.drug.time * doses, { exertion = 0.1 })
  Inv.removeEntry(g.inv, pick.entry, doses)
  local msg = B.med.drug(body, it, g.rng, doses)
  g:say(msg, UI.c.accent)
  UI.sfx("heal")
end

function S.medical(g, under)
  local sel = "thorax"
  -- open on the worst limb
  local worst, worstScore = nil, 2
  for _, id in ipairs(D.LIMB_ORDER) do
    local sc = B.limbCondition(g.body, id)
    if g.body.limbs[id].bleed > 0.05 then sc = sc - 0.5 end
    if sc < worstScore then worstScore = sc; worst = id end
  end
  if worst then sel = worst end

  while not g.over do
    drawMedical(g, sel)
    local ev = UI.read()
    if ev.kind == "char" then
      local ch = ev.char
      if ch == "q" then return end
      if ch == "t" then treatmentMenu(g, sel) end
      if ch == "g" then drugMenu(g) end
      if ch == "v" then S.condition(g); return end
      if ch == "e" then S.exercise(g) end
      for id, meta in pairs(D.LIMBS) do
        if meta.key == ch then sel = id end
      end
    elseif ev.kind == "key" then
      if ev.name == "back" then return end
      if ev.name == "tab" then return end
      if ev.name == "enter" then treatmentMenu(g, sel) end
      local order = D.LIMB_ORDER
      local idx = 1
      for i, id in ipairs(order) do if id == sel then idx = i end end
      if ev.name == "down" then sel = order[idx % #order + 1] end
      if ev.name == "up" then sel = order[(idx - 2) % #order + 1] end
    elseif ev.kind == "click" then
      -- click on the figure
      local fx, fy = ev.x - 10 + 1, ev.y - 4 + 1
      for id, anchor in pairs(UI.limbAnchor) do
        if math.abs(fx - anchor[1]) <= 1 and math.abs(fy - anchor[2]) <= 1 then sel = id end
      end
      if ev.x <= 8 then
        local idx = ev.y - 3
        if D.LIMB_ORDER[idx] then sel = D.LIMB_ORDER[idx] end
      end
    end
    if g.body.dead then g:endRun(g.body.cause) end
  end
end

--------------------------------------------------------------------- gear

--[[
  What is on you and where. Seven worn slots, one hand, one light, and the
  numbers those add up to, because "am I wearing the boots" should not be a
  question you answer by reading your whole pack.
]]
local SLOTS = {
  { key = "head",  label = "head" },
  { key = "face",  label = "face" },
  { key = "torso", label = "torso" },
  { key = "hands", label = "hands" },
  { key = "legs",  label = "legs" },
  { key = "feet",  label = "feet" },
  { key = "back",  label = "back" },
}

local function wearSummary(it)
  local w = it.wear or {}
  local bits = {}
  if w.armour and w.armour > 0 then bits[#bits + 1] = "armour " .. w.armour end
  if w.warmth and w.warmth > 0 then bits[#bits + 1] = "warm " .. w.warmth end
  if w.carry and w.carry > 0 then bits[#bits + 1] = "carry +" .. w.carry end
  if w.fallGuard then bits[#bits + 1] = "softens falls" end
  if w.skullGuard then bits[#bits + 1] = "skull" end
  if w.cutGuard then bits[#bits + 1] = "cut" end
  if w.grip then bits[#bits + 1] = "grip" end
  if w.spore then bits[#bits + 1] = "spores" end
  if w.eyeGuard then bits[#bits + 1] = "eyes" end
  if w.lightRadius then bits[#bits + 1] = "light " .. w.lightRadius end
  if w.encumber and w.encumber > 0 then bits[#bits + 1] = "bulky" end
  return table.concat(bits, ", ")
end

local function handSummary(it)
  local w = it.weapon
  if not w then return "" end
  local bits = { (w.dmg or 0) .. " dmg" }
  if w.dig and w.dig > 0 then bits[#bits + 1] = "digs " .. w.dig end
  if w.pry then bits[#bits + 1] = "opens lockers" end
  if w.butcher then bits[#bits + 1] = "cuts" end
  if w.ranged then bits[#bits + 1] = "ranged" end
  if (w.hands or 1) > 1 then bits[#bits + 1] = "two handed" end
  return table.concat(bits, ", ")
end

local function drawGear(g, sel)
  local c = UI.c
  local body = g.body
  local gear = body.gear or {}
  UI.beginFrame()
  S.header(g, "GEAR")

  local wide = UI.w >= 58
  local nameW = wide and 18 or 15
  local y = 3
  for i, slot in ipairs(SLOTS) do
    local e = g.inv.wear[slot.key]
    local it = e and D.ITEMS[e.id]
    local chosen = (i == sel)
    local bg = chosen and c.select or c.bg
    UI.write(1, y, " " .. U.pad(slot.label, 6), chosen and c.text or c.faint, bg)
    UI.write(8, y, U.pad(it and it.name or "-", nameW),
      it and (chosen and c.text or c.dim) or c.faint, bg)
    if wide and it then
      UI.write(8 + nameW + 1, y, U.trunc(wearSummary(it), UI.w - 9 - nameW), c.faint, bg)
    end
    y = y + 1
  end

  y = y + 1
  local hand = g.inv.weapon and D.ITEMS[g.inv.weapon.id]
  local lit = g.inv.light and D.ITEMS[g.inv.light.id]
  local hs = (sel == #SLOTS + 1)
  local ls = (sel == #SLOTS + 2)
  UI.write(1, y, " " .. U.pad("hand", 6), hs and c.text or c.faint, hs and c.select or c.bg)
  UI.write(8, y, U.pad(hand and hand.name or "empty", nameW),
    hand and c.text or c.faint, hs and c.select or c.bg)
  if wide and hand then
    UI.write(8 + nameW + 1, y, U.trunc(handSummary(hand), UI.w - 9 - nameW), c.faint,
      hs and c.select or c.bg)
  end
  y = y + 1
  UI.write(1, y, " " .. U.pad("light", 6), ls and c.text or c.faint, ls and c.select or c.bg)
  local lightTxt = lit and lit.name or "none"
  if lit and g.inv.light.cell then lightTxt = lightTxt .. "  " .. math.floor(g.inv.light.cell) .. "%" end
  if lit and g.inv.light.fuel then lightTxt = lightTxt .. "  " .. U.dur(g.inv.light.fuel) end
  UI.write(8, y, U.trunc(lightTxt, UI.w - 9), lit and c.gold or c.faint,
    ls and c.select or c.bg)

  UI.hrule(1, UI.h - 4, UI.w, c.faint)
  UI.write(2, UI.h - 3, string.format("armour  head %d  torso %d  arms %d  legs %d",
    math.floor(B.armourAt(body, "head")), math.floor(B.armourAt(body, "thorax")),
    math.floor(B.armourAt(body, "larm")), math.floor(B.armourAt(body, "lleg"))), c.dim)
  UI.write(2, UI.h - 2, string.format("warmth %d   carrying %.0f of %.0f kg   light %.1f",
    gear.warmth or 0, Inv.mass(g.inv), B.carryCapacity(body),
    Inv.lightRadius(g.inv)), c.dim)
  UI.write(2, UI.h - 1, "up and down pick a slot   enter change it   q back", c.faint)
  UI.endFrame()
end

local function changeSlot(g, sel)
  local under = function() drawGear(g, sel) end
  if sel <= #SLOTS then
    local slot = SLOTS[sel].key
    local items = {}
    if g.inv.wear[slot] then
      items[#items + 1] = { label = "take it off", run = function()
        Inv.unequipWear(g.inv, slot)
        Inv.updateGear(g.inv, g.body)
        g:advance(12)
        g:say("Off.", UI.c.dim)
      end }
    end
    for _, e in ipairs(Inv.entries(g.inv, function(_, it)
      return it.wear and it.wear.slot == slot end)) do
      if not e.equipped then
        local it = D.ITEMS[e.id]
        items[#items + 1] = { label = "wear " .. it.name, hint = wearSummary(it),
          run = function()
            local ok, msg = Inv.equipWear(g.inv, e)
            Inv.updateGear(g.inv, g.body)
            g:advance(15, { exertion = 0.1 })
            g:say(msg, ok and UI.c.ok or UI.c.warn)
          end }
      end
    end
    if #items == 0 then
      UI.message("nothing for it", "You have nothing to wear on your " .. SLOTS[sel].label .. ".")
      return
    end
    local pick = UI.pick(SLOTS[sel].label, items, { under = under, width = 44 })
    if pick and pick.run then pick.run() end

  elseif sel == #SLOTS + 1 then
    local items = {}
    if g.inv.weapon then
      items[#items + 1] = { label = "empty your hands", run = function()
        g.inv.weapon = nil
        g:say("Stowed.", UI.c.dim)
      end }
    end
    for _, e in ipairs(Inv.entries(g.inv, function(_, it) return it.weapon end)) do
      if g.inv.weapon ~= e then
        local it = D.ITEMS[e.id]
        items[#items + 1] = { label = "hold the " .. it.name, hint = handSummary(it),
          run = function()
            local ok, msg = Inv.equipWeapon(g.inv, e, g.body)
            g:say(msg, ok and UI.c.ok or UI.c.warn)
          end }
      end
    end
    if #items == 0 then
      UI.message("empty handed", "You have nothing you could hold.")
      return
    end
    local pick = UI.pick("in hand", items, { under = under, width = 44 })
    if pick and pick.run then pick.run() end

  else
    local items = {}
    if g.inv.light then
      items[#items + 1] = { label = "put it out", run = function()
        g.inv.light.lit = false
        g.inv.light = nil
        g:say("Dark.", UI.c.dim)
      end }
    end
    for _, e in ipairs(Inv.entries(g.inv, function(_, it)
      return it.light or (it.wear and it.wear.lightRadius) end)) do
      if g.inv.light ~= e then
        local it = D.ITEMS[e.id]
        items[#items + 1] = { label = "light the " .. it.name, run = function()
          local ok, msg = Inv.equipLight(g.inv, e)
          g:say(msg, ok and UI.c.gold or UI.c.warn)
        end }
      end
    end
    if #items == 0 then
      UI.message("no light", "You have nothing that gives off light.")
      return
    end
    local pick = UI.pick("light", items, { under = under, width = 44 })
    if pick and pick.run then pick.run() end
  end
  Inv.updateGear(g.inv, g.body)
end

function S.gear(g)
  local sel = 1
  local total = #SLOTS + 2
  while not g.over do
    drawGear(g, sel)
    local ev = UI.read()
    if ev.kind == "char" then
      if ev.char == "q" or ev.char == "g" then return end
      if ev.char == "i" then S.inventory(g, function() drawGear(g, sel) end) end
    elseif ev.kind == "key" then
      if ev.name == "back" then return end
      if ev.name == "up" then sel = (sel - 2) % total + 1 end
      if ev.name == "down" then sel = sel % total + 1 end
      if ev.name == "enter" then changeSlot(g, sel) end
    elseif ev.kind == "click" then
      local row = ev.y - 2
      if row >= 1 and row <= #SLOTS then sel = row; changeSlot(g, sel)
      elseif row == #SLOTS + 2 then sel = #SLOTS + 1; changeSlot(g, sel)
      elseif row == #SLOTS + 3 then sel = #SLOTS + 2; changeSlot(g, sel)
      else return end
    end
  end
end

--------------------------------------------------------------------- exercise

--[[
  Work for the sake of working. It puts muscle back on, which nothing else in
  the game does quickly, and it warms you up, which matters more than it sounds
  like on the cold levels. It costs food, water and most of your energy, and a
  broken bone rules it out.
]]
function S.exercise(g)
  local body = g.body
  local broken = nil
  for _, id in ipairs(D.LIMB_ORDER) do
    if body.limbs[id].bone == "fractured" then broken = D.LIMBS[id].name end
  end
  if broken then
    UI.message("not with that", "You are not working out on a broken " .. broken .. ".")
    return
  end
  local pain = select(1, B.effectivePain(body))
  if pain > 62 then
    UI.message("too sore", "You are in too much pain to push yourself.")
    return
  end
  if body.energy < 20 then
    UI.message("nothing left", "You have no energy to spend. Rest first.")
    return
  end
  if not UI.confirm("EXERCISE", "Twenty minutes of hard work. It puts muscle back on "
    .. "and warms you through. It will cost you food, water and most of what you "
    .. "have left in the tank.") then return end

  -- the work itself is a heat source, so the cold does not just take it back
  g:advance(1200, { exertion = 1.0, heat = 5 })
  if g.over then return end

  local gained = 0
  for _, id in ipairs(D.LIMB_ORDER) do
    local l = body.limbs[id]
    local cap = (l.bone ~= "ok") and 50 or 100
    if not l.amputated and l.infection < D.TUNE.INFECT_REVEAL and l.muscle < cap then
      local add = math.min(cap - l.muscle, 7)
      l.muscle = l.muscle + add
      gained = gained + add
    end
  end
  body.temp = math.min(39.2, body.temp + 2.2)
  body.energy = math.max(0, body.energy - 26)
  body.mood = math.min(100, body.mood + 7)
  body.immunity = U.clamp(body.immunity + 3, 10, 130)
  UI.sfx("heal")
  if gained > 0 then
    g:say(string.format("Twenty minutes of work. %d points of muscle back, and you are warm.",
      math.floor(gained)), UI.c.ok)
  else
    g:say("Twenty minutes of work. Nothing left to build, but you are warm.", UI.c.ok)
  end
end

--------------------------------------------------------------------- inventory

local KINDS = { "dressing", "drug", "tool", "weapon", "wear", "light", "food", "material", "misc", "ammo", "doc", "flask" }

local function itemActions(g, e)
  local it = D.ITEMS[e.id]
  local body = g.body
  local acts = {}
  local function add(label, fn) acts[#acts + 1] = { label = label, run = fn } end

  if it.kind == "food" then
    add("eat", function()
      if body.limbs.head.bone == "dislocated" and not it.food.soft then
        g:say("Your jaw will not open far enough to eat that.", UI.c.warn)
        return
      end
      g:advance(it.food.time or 20, { exertion = 0.05 })
      body.hunger = U.clamp(body.hunger + (it.food.hunger or 0), 0, 120)
      body.thirst = U.clamp(body.thirst + (it.food.thirst or 0), 0, 120)
      if it.food.sickChance and g.rng:chance(it.food.sickChance) then
        body.sick = U.clamp(body.sick + it.food.sick, 0, 100)
        g:say("That was spoiled.", UI.c.warn)
      end
      Inv.removeEntry(g.inv, e, 1)
      g:say("Eaten.", UI.c.ok)
    end)
  end
  if it.kind == "drug" then
    add("take", function()
      g:advance(it.drug.time or 6, { exertion = 0.05 })
      Inv.removeEntry(g.inv, e, 1)
      g:say(B.med.drug(body, it, g.rng, 1), UI.c.accent)
    end)
  end
  if it.wear then
    if e.equipped then
      add("take off", function() 
        for slot, we in pairs(g.inv.wear) do
          if we == e then Inv.unequipWear(g.inv, slot) end
        end
        Inv.updateGear(g.inv, body)
        g:say("Off.", UI.c.dim)
      end)
    else
      add("wear", function()
        local ok, msg = Inv.equipWear(g.inv, e)
        Inv.updateGear(g.inv, body)
        g:advance(15, { exertion = 0.1 })
        g:say(msg, ok and UI.c.ok or UI.c.warn)
      end)
    end
  end
  if it.weapon then
    add(g.inv.weapon == e and "put away" or "take in hand", function()
      if g.inv.weapon == e then g.inv.weapon = nil; g:say("Stowed.", UI.c.dim)
      else
        local ok, msg = Inv.equipWeapon(g.inv, e, body)
        g:say(msg, ok and UI.c.ok or UI.c.warn)
      end
    end)
  end
  if it.light or (it.wear and it.wear.lightRadius) then
    add(g.inv.light == e and "put out" or "light it", function()
      if g.inv.light == e then g.inv.light = nil; e.lit = false; g:say("Dark.", UI.c.dim)
      else
        local ok, msg = Inv.equipLight(g.inv, e)
        g:say(msg, ok and UI.c.gold or UI.c.warn)
      end
    end)
    if (it.light and it.light.needsCell) or (it.wear and it.wear.needsCell) then
      add("fit a cell", function()
        local ok, msg = Inv.reload(g.inv, e)
        g:advance(12)
        g:say(msg, ok and UI.c.ok or UI.c.warn)
      end)
    end
  end
  if it.kind == "flask" then
    add("drink", function()
      g:advance(15)
      local ok, msg = Inv.drink(g.inv, body, 0.35)
      g:say(msg, ok and UI.c.ok or UI.c.warn)
    end)
  end
  if it.misc and it.misc.purify and g.inv.flask.amount > 0 and not g.inv.flask.clean then
    add("purify the flask", function()
      Inv.removeEntry(g.inv, e, 1)
      g.inv.flask.clean = true
      g:advance(60)
      g:say("Purified. The water is safe now.", UI.c.ok)
    end)
  end
  if it.doc then
    add("read", function() S.readDoc(g, e.docIndex) end)
  end
  add("drop", function()
    Inv.removeEntry(g.inv, e, e.n)
    Inv.updateGear(g.inv, body)
    g:say("Dropped.", UI.c.dim)
  end)
  return acts
end

function S.inventory(g, under)
  local filter = nil
  while not g.over do
    local list = Inv.entries(g.inv, function(_, it)
      return (not filter) or it.kind == filter
    end)
    table.sort(list, function(a, b)
      local A, Bd = D.ITEMS[a.id], D.ITEMS[b.id]
      if A.kind ~= Bd.kind then return A.kind < Bd.kind end
      return A.name < Bd.name
    end)
    local items = {}
    for _, e in ipairs(list) do
      local it = D.ITEMS[e.id]
      local tags = {}
      if e.equipped then tags[#tags + 1] = "worn" end
      if g.inv.weapon == e then tags[#tags + 1] = "hand" end
      if g.inv.light == e then tags[#tags + 1] = "lit" end
      if e.charges then tags[#tags + 1] = e.charges .. "c" end
      if e.cell then tags[#tags + 1] = math.floor(e.cell) .. "%" end
      if e.fuel then tags[#tags + 1] = U.dur(e.fuel) end
      items[#items + 1] = {
        label = (e.n > 1 and (e.n .. "x ") or "") .. it.name,
        hint = #tags > 0 and table.concat(tags, " ") or U.fmt1(it.mass * e.n) .. "kg",
        entry = e,
      }
    end
    local load = Inv.mass(g.inv)
    local cap = B.carryCapacity(g.body)
    local title = string.format("CARRIED  %.1f / %.0f kg", load, cap)
    if #items == 0 then
      items[#items + 1] = { label = "(nothing)", disabled = true }
    end
    local pick = UI.pick(title, items, {
      under = under,
      footer = "enter use   f filter   q back",
      width = 44,
    })
    if not pick then return end
    if pick.entry then
      local acts = itemActions(g, pick.entry)
      local it = D.ITEMS[pick.entry.id]
      local menu = {}
      for _, a in ipairs(acts) do menu[#menu + 1] = { label = a.label, run = a.run } end
      menu[#menu + 1] = { label = "-- " .. U.trunc(it.desc, 60), disabled = true }
      local a = UI.pick(it.name, menu, { under = under, width = 46 })
      if a and a.run then a.run() end
      Inv.updateGear(g.inv, g.body)
    end
  end
end

--------------------------------------------------------------------- overview

function S.overview(g)
  local map = g.map
  local Rr = CU.render
  local scroll = math.max(1, g.y - 6)
  while true do
    UI.beginFrame()
    S.header(g, "MAP")
    local h = UI.h - 4
    local w = UI.w
    local cx = U.clamp(g.x - math.floor(w / 2), 1, math.max(1, map.w - w + 1))
    for row = 0, h - 1 do
      local my = scroll + row
      local text, fg, bg = {}, {}, {}
      local seenRow = map.seen[my]
      local mapRow = (my >= 1 and my <= map.h) and map.rows[my] or nil
      for col = 0, w - 1 do
        local mx = cx + col
        local glyph, f, b = " ", colors.black, colors.black
        if mapRow and seenRow and seenRow[mx] then
          local ch = mapRow:sub(mx, mx)
          local l = Rr.LIT[ch] or Rr.LIT[" "]
          glyph, f, b = l[1], l[2], l[3]
        end
        if mx == g.x and my == g.y then glyph, f = "@", colors.white end
        text[#text + 1] = glyph
        fg[#fg + 1] = Rr.hex(f)
        bg[#bg + 1] = Rr.hex(b)
      end
      UI.blitLine(1, 3 + row, table.concat(text), table.concat(fg), table.concat(bg))
    end
    UI.write(2, UI.h - 1, "depth " .. math.floor(CU.mapgen.depthAt(map, scroll)) .. " m to "
      .. math.floor(CU.mapgen.depthAt(map, scroll + h)) .. " m", UI.c.dim)
    UI.write(2, UI.h, "up and down to scroll   q back", UI.c.faint)
    UI.endFrame()
    local ev = UI.read()
    if ev.kind == "key" then
      if ev.name == "up" then scroll = math.max(1, scroll - 5)
      elseif ev.name == "down" then scroll = math.min(map.h - 1, scroll + 5)
      elseif ev.name == "back" or ev.name == "enter" then return end
    elseif ev.kind == "char" then
      if ev.char == "q" or ev.char == "k" then return end
    elseif ev.kind == "click" then
      return
    end
  end
end

--------------------------------------------------------------------- interaction

local function searchProp(g, px, py, prop, thorough)
  if prop.emptied then
    g:say("Empty.", UI.c.dim)
    return
  end
  if prop.locked and not g:hasPry() then
    g:say("Locked. You need a pry bar.", UI.c.warn)
    return
  end
  local time = prop.time * (thorough and 1.5 or 0.7)
  time = time / U.clamp(B.grip(g.body) * 0.6 + 0.5, 0.35, 1.2)
  g:advance(math.floor(time), { exertion = 0.3 })
  if g.over then return end

  local rolls = prop.rolls + (thorough and 2 or 0)
  local loot = CU.mapgen.rollLoot(prop.pool, g.map.strat.lootTier, g.rng, rolls)
  prop.searched = true
  if thorough or g.rng:chance(0.5) then
    prop.emptied = true
    CU.mapgen.set(g.map, px, py, "d")
  end
  g.stats.searched = g.stats.searched + 1

  if prop.corpse and g.rng:chance(0.5) then
    Inv.add(g.inv, "company_tag", 1)
  end

  local got, capacity = {}, B.carryCapacity(g.body)
  for _, entry in ipairs(loot) do
    local it = D.ITEMS[entry.id]
    if it then
      if Inv.mass(g.inv) + it.mass * entry.n > capacity * 1.6 then
        g:say("No room for the " .. it.name .. ".", UI.c.dim)
      else
        Inv.add(g.inv, entry.id, entry.n)
        got[#got + 1] = it.short .. (entry.n > 1 and (" x" .. entry.n) or "")
      end
    end
  end
  if #got > 0 then
    g:say("Found: " .. table.concat(got, ", "), UI.c.gold)
    UI.sfx("loot")
  else
    g:say("Nothing useful in it.", UI.c.dim)
  end
  Inv.updateGear(g.inv, g.body)
end

-- Use whatever is under your feet.
function S.interact(g, under)
  local map = g.map
  local Tl = CU.tiles
  local Mg = CU.mapgen

  if g.body.trapped then
    CU.phys.pryTrap(g)
    return
  end

  local targets = {}
  for _, off in ipairs({ 0, 1 }) do
    local tx, ty = g.x, g.y + off
    local ch = Mg.get(map, tx, ty)
    local def = Tl.get(ch)
    if def.prop or def.fixture or def.shaft or def.hatch then
      targets[#targets + 1] = { x = tx, y = ty, ch = ch, def = def }
    end
  end
  local items = {}

  if CU.phys.waterHere(g) then
    local _, clean = CU.phys.waterHere(g)
    items[#items + 1] = { label = "kneel and drink", colour = UI.c.cold,
      run = function() CU.phys.drink(g) end }
    if Inv.count(g.inv, "water_flask") > 0 then
      items[#items + 1] = { label = "fill your flask", run = function()
        g:advance(40, { exertion = 0.1 })
        local ok, msg = Inv.fill(g.inv, clean)
        g:say(msg, ok and UI.c.ok or UI.c.warn)
      end }
    end
  end

  if #targets == 0 and #items == 0 then
    UI.message("nothing here", "There is nothing to use where you are standing.")
    return
  end
  for _, t in ipairs(targets) do
    local prop = Mg.prop(map, t.x, t.y)
    local id = t.def.id

    if t.def.prop and prop then
      local label = prop.name .. (prop.searched and " (already searched)" or "")
      items[#items + 1] = { label = "quick search " .. label, run = function()
        searchProp(g, t.x, t.y, prop, false) end }
      items[#items + 1] = { label = "empty it out (slower, finds more)", run = function()
        searchProp(g, t.x, t.y, prop, true) end }

    elseif id == "shaft" then
      items[#items + 1] = { label = "climb down the shaft to the next level",
        colour = UI.c.accent, run = function()
          if UI.confirm("GO DOWN", "The shaft leads to stratum "
            .. U.roman(g.stratumIndex + 1) .. ". You cannot come back up.") then
            g:descendTo(g.stratumIndex + 1, false)
          end
        end }

    elseif id == "hatch" then
      items[#items + 1] = { label = "call the surface lift", colour = UI.c.gold, run = function()
        if UI.confirm("SURFACE LIFT", g.cargo
          and "The lift checks the bond. You have the cargo."
          or "The lift checks the bond. You do not have the cargo.") then
          g:useLift()
        end
      end }

    elseif id == "cargo" then
      items[#items + 1] = { label = "take the cargo crate", colour = UI.c.gold, run = function()
        g:advance(120, { exertion = 0.6 })
        g:takeCargo()
        Mg.set(map, t.x, t.y, " ")
      end }

    elseif id == "spring" then
      items[#items + 1] = { label = "fill your flask", run = function()
        g:advance(40, { exertion = 0.1 })
        local ok, msg = Inv.fill(g.inv, true)
        g:say(msg, ok and UI.c.ok or UI.c.warn)
      end }
      items[#items + 1] = { label = "wash your wounds", run = function()
        g:advance(90, { exertion = 0.2 })
        for _, lid in ipairs(D.LIMB_ORDER) do
          local l = g.body.limbs[lid]
          if l.infection < D.TUNE.INFECT_REVEAL then
            l.infection = math.max(0, l.infection - 5)
          end
        end
        g.body.wet = 1
        g:say("You wash the wounds out. Infection risk drops a little.", UI.c.cold)
      end }

    elseif id == "bench" then
      items[#items + 1] = { label = "work at the bench", run = function() S.craft(g) end }

    elseif id == "charger" then
      items[#items + 1] = { label = "charge your cells", run = function()
        g:advance(180, { exertion = 0.05 })
        local n = 0
        for _, e in ipairs(Inv.entries(g.inv)) do
          if e.cell then e.cell = 100; n = n + 1 end
        end
        local dead = Inv.count(g.inv, "dead_cell")
        if dead > 0 then
          Inv.remove(g.inv, "dead_cell", dead)
          Inv.add(g.inv, "cell", dead)
          n = n + dead
        end
        -- and put the light back on, because that is why you came over here
        if Inv.lightRadius(g.inv) < 1 then
          for _, id in ipairs({ "hand_torch", "head_lamp", "bloom_light" }) do
            local e = U.find(Inv.entries(g.inv), function(x) return x.id == id end)
            if e then
              if e.cell then e.cell = 100 end
              local ok = Inv.equipLight(g.inv, e)
              if ok then
                g:say("Your " .. D.ITEMS[id].name .. " is lit again.", UI.c.gold)
                break
              end
            end
          end
        end
        g:say("Recharged " .. n .. " item" .. (n == 1 and "" or "s") .. ".", UI.c.gold)
      end }

    elseif id == "trader" then
      local pod = Mg.podAt(map, t.x, t.y)
      if pod and pod.trader and not pod.trader.hostile then
        items[#items + 1] = { label = "talk to " .. pod.trader.name,
          colour = UI.c.gold, run = function() S.trade(g, pod) end }
      end

    elseif id == "thermostat" then
      local pod = Mg.podAt(map, t.x, t.y)
      if pod then
        items[#items + 1] = { label = "set the pod temperature (now "
          .. pod.temp .. "C)", run = function() S.thermostat(g, pod, under) end }
      end

    elseif id == "shower" then
      local pod = Mg.podAt(map, t.x, t.y)
      if pod then
        items[#items + 1] = { label = "use the decontamination shower ("
          .. (pod.showers or 0) .. " left)", colour = UI.c.ok,
          run = function() S.shower(g, pod) end }
      end

    elseif id == "pod" then
      items[#items + 1] = { label = "sleep in the pod (one hour, safe and warm)", run = function()
        g:rest(3600, true)
      end }

    elseif id == "heater" then
      items[#items + 1] = { label = "warm up by the heater (fifteen minutes)", run = function()
        g:rest(900, true)
      end }

    elseif id == "note" then
      local pr = Mg.prop(map, t.x, t.y)
      items[#items + 1] = { label = "read the paper", colour = UI.c.gold, run = function()
        g:advance(20)
        if pr and pr.doc then
          g.docsFound[pr.doc] = true
          g.stats.docs = g.stats.docs + 1
          S.readDoc(g, pr.doc)
        end
        Mg.set(map, t.x, t.y, " ")
      end }
    end
  end

  if #items == 0 then
    UI.message("nothing here", "There is nothing to use where you are standing.")
    return
  end
  if #items == 1 then
    items[1].run()
    return
  end
  local pick = UI.pick("use", items, { under = under, width = 46 })
  if pick and pick.run then pick.run() end
end

--------------------------------------------------------------------- trading

--[[
  Traders are people living in the pods. Everything in the game has a value, and
  what you actually pay or get paid depends on how they feel about you.

  Their attitude runs 0 to 100 and moves four ways:

    hugging    cheap, warm ones like it, and being visibly wrecked helps
    haggling   a real check against how shrewd they are, and it can backfire
    threatening big swing, and a bad roll means they shoot you
    trading    small drift upward every time you deal fairly
]]

local function rates(t)
  local a = U.clamp(t.attitude, 0, 100) / 100
  return 0.32 + a * 0.36, 2.15 - a * 0.75      -- they pay, they charge
end

local function priceBuy(t, id)
  local it = D.ITEMS[id]
  if not it then return 1 end
  local _, sell = rates(t)
  return math.max(1, math.floor(it.value * sell + 0.5))
end

local function priceSell(t, id)
  local it = D.ITEMS[id]
  if not it then return 1 end
  local buy = rates(t)
  return math.max(1, math.floor(it.value * buy + 0.5))
end

local function mood(t)
  local a = t.attitude
  if t.hostile then return "hostile", UI.c.crit end
  if t.cowed then return "afraid of you", UI.c.warn end
  if a >= 80 then return "glad to see you", UI.c.ok end
  if a >= 62 then return "friendly", UI.c.ok end
  if a >= 42 then return "businesslike", UI.c.text end
  if a >= 24 then return "cold", UI.c.warn end
  return "wants you gone", UI.c.crit
end

local function drawTrader(g, pod, note)
  local t = pod.trader
  local def = D.trader(t.id)
  local c = UI.c
  UI.beginFrame()
  S.header(g, "TRADE")
  UI.write(2, 3, t.name, c.gold)
  local m, mc = mood(t)
  UI.write(2 + #t.name + 2, 3, m, mc)
  UI.bar(2, 4, math.min(30, UI.w - 20), U.clamp(t.attitude, 0, 100) / 100, mc, c.panel)
  UI.write(UI.w - 16, 3, "their scrip " .. t.scrip, c.dim)
  UI.write(UI.w - 16, 4, "yours " .. Inv.count(g.inv, "scrip"), c.gold)

  local y = 6
  for _, ln in ipairs(U.wrap(def.look, UI.w - 4)) do
    if y < UI.h - 6 then UI.write(2, y, ln, c.dim); y = y + 1 end
  end
  y = y + 1
  if note then
    for _, ln in ipairs(U.wrap(note, UI.w - 4)) do
      if y < UI.h - 4 then UI.write(2, y, ln, c.text); y = y + 1 end
    end
  end

  UI.hrule(1, UI.h - 3, UI.w, c.faint)
  S.vitals(UI.h - 2, g)
  UI.write(2, UI.h, "enter choose   q leave", c.faint)
  UI.endFrame()
end

local function tradeBuy(g, pod, under)
  local t = pod.trader
  while not g.over do
    local items = {}
    for _, e in ipairs(t.stock) do
      if e.n > 0 then
        local it = D.ITEMS[e.id]
        local p = priceBuy(t, e.id)
        items[#items + 1] = {
          label = it.name .. (e.n > 1 and ("  x" .. e.n) or ""),
          hint = p .. " scrip",
          colour = (Inv.count(g.inv, "scrip") >= p) and UI.c.text or UI.c.faint,
          entry = e, price = p, def = it,
        }
      end
    end
    if #items == 0 then
      UI.message("nothing left", t.name .. " has nothing else to sell.")
      return
    end
    local pick = UI.pick("buying", items, { under = under, width = 46,
      footer = "you have " .. Inv.count(g.inv, "scrip") .. " scrip" })
    if not pick then return end
    if Inv.count(g.inv, "scrip") < pick.price then
      g:say("You cannot afford that.", UI.c.warn)
      UI.sfx("deny")
    else
      Inv.remove(g.inv, "scrip", pick.price)
      Inv.add(g.inv, pick.entry.id, 1)
      pick.entry.n = pick.entry.n - 1
      t.scrip = t.scrip + pick.price
      t.attitude = U.clamp(t.attitude + 1, 0, 100)
      Inv.updateGear(g.inv, g.body)
      g:advance(20)
      g:say("Bought " .. pick.def.name .. " for " .. pick.price .. ".", UI.c.gold)
      UI.sfx("loot")
    end
  end
end

local function tradeSell(g, pod, under)
  local t = pod.trader
  while not g.over do
    local items = {}
    for _, e in ipairs(Inv.entries(g.inv)) do
      local it = D.ITEMS[e.id]
      local sellable = it and not (it.misc and it.misc.currency)
        and not e.equipped and g.inv.weapon ~= e and g.inv.light ~= e
      if sellable then
        local p = priceSell(t, e.id)
        items[#items + 1] = {
          label = it.name .. (e.n > 1 and ("  x" .. e.n) or ""),
          hint = p .. " each",
          colour = (t.scrip >= p) and UI.c.text or UI.c.faint,
          entry = e, price = p, def = it,
        }
      end
    end
    if #items == 0 then
      UI.message("nothing to sell", "Everything you have is either worn, in your hand, or money.")
      return
    end
    local pick = UI.pick("selling", items, { under = under, width = 46,
      footer = t.name .. " has " .. t.scrip .. " scrip" })
    if not pick then return end
    if t.scrip < pick.price then
      g:say(t.name .. " cannot cover that.", UI.c.warn)
      UI.sfx("deny")
    else
      Inv.removeEntry(g.inv, pick.entry, 1)
      Inv.add(g.inv, "scrip", pick.price)
      t.scrip = t.scrip - pick.price
      t.attitude = U.clamp(t.attitude + 1, 0, 100)
      Inv.updateGear(g.inv, g.body)
      g:advance(20)
      g:say("Sold " .. pick.def.name .. " for " .. pick.price .. ".", UI.c.gold)
      UI.sfx("loot")
    end
  end
end

local HUG_GOOD = {
  "%s holds on a second longer than you expected.",
  "%s pats your back twice and lets go.",
  "%s laughs and does not step away.",
}
local HUG_BAD = {
  "%s puts a hand on your chest and keeps you at arm's length.",
  "%s does not move. You take your arms back.",
  "%s says, plainly, no.",
}

local function doHug(g, pod)
  local t = pod.trader
  local def = D.trader(t.id)
  local body = g.body
  local bloody = B.totalBleed(body) > 0.08
  local wrecked = select(1, B.effectivePain(body)) > 45 or body.blood < 4
  local chance = def.warm * 0.62 + 0.18
  if wrecked then chance = chance + 0.18 end        -- they can see the state of you
  if bloody then chance = chance - 0.28 end         -- and you are getting it on them
  if body.limbs.head.revealed then chance = chance - 0.1 end
  chance = chance - t.hugs * 0.22
  t.hugs = t.hugs + 1
  g:advance(15)

  if g.rng:chance(U.clamp(chance, 0.02, 0.92)) then
    local gain = g.rng:int(7, 15) + (wrecked and 4 or 0)
    t.attitude = U.clamp(t.attitude + gain, 0, 100)
    UI.sfx("heal")
    body.mood = math.min(100, body.mood + 6)
    return string.format(HUG_GOOD[g.rng:int(1, #HUG_GOOD)], t.name)
      .. "  Prices improve."
  end
  t.attitude = U.clamp(t.attitude - g.rng:int(3, 8), 0, 100)
  UI.sfx("deny")
  local extra = bloody and "  You are covered in blood and it is on them now." or ""
  return string.format(HUG_BAD[g.rng:int(1, #HUG_BAD)], t.name) .. extra
end

local function doHaggle(g, pod)
  local t = pod.trader
  local def = D.trader(t.id)
  local body = g.body
  if t.cowed then return t.name .. " already gives you whatever you ask for." end
  if t.haggles >= 4 then
    return t.name .. " has stopped listening to numbers from you."
  end
  local skill = 0.24 + B.steadiness(body) * 0.24 + (body.brain / 100) * 0.3
    + body.traits.int * 0.05
  local chance = skill - def.shrewd * 0.55 - t.haggles * 0.1
  t.haggles = t.haggles + 1
  g:advance(60, { exertion = 0.1 })

  if g.rng:chance(U.clamp(chance, 0.05, 0.85)) then
    local gain = g.rng:int(6, 13)
    t.attitude = U.clamp(t.attitude + gain, 0, 100)
    UI.sfx("confirm")
    return t.name .. " concedes the point. Prices move your way."
  end
  local loss = g.rng:int(4, 10)
  t.attitude = U.clamp(t.attitude - loss, 0, 100)
  UI.sfx("deny")
  if body.brain < 80 then
    return t.name .. " watches you lose your thread and waits. Prices get worse."
  end
  return t.name .. " does not move on the price, and thinks less of you for trying."
end

local function doThreaten(g, pod)
  local t = pod.trader
  local def = D.trader(t.id)
  local body = g.body
  local weapon = g.inv.weapon
  local wdef = weapon and D.ITEMS[weapon.id]
  local armed = wdef and wdef.weapon and wdef.weapon.dmg or 0

  local menace = 0.16 + B.swingPower(body) * 0.3 + math.min(0.3, armed / 60)
  if body.blood < 3.6 then menace = menace - 0.15 end
  if B.mobility(body) < 0.4 then menace = menace - 0.15 end
  local chance = menace + 0.24 - def.nerve
  t.threats = t.threats + 1
  g:advance(20, { exertion = 0.3 })

  if g.rng:chance(U.clamp(chance, 0.04, 0.88)) then
    t.attitude = 88
    t.cowed = true
    UI.sfx("alarm")
    return t.name .. " puts both hands flat on the counter. You can have it at your price."
  end

  t.hostile = true
  UI.sfx("alarm")
  return nil        -- the caller starts the fight
end

function S.trade(g, pod)
  local t = pod.trader
  if not t then return end
  local def = D.trader(t.id)
  local under = function() drawTrader(g, pod) end
  local note = nil
  if not t.met then
    t.met = true
    note = def.greet
  end

  while not g.over and not t.hostile do
    drawTrader(g, pod, note)
    local pick = UI.pick("with " .. t.name, {
      { label = "buy", key = "b", value = "buy" },
      { label = "sell", key = "s", value = "sell" },
      { label = "haggle", key = "h", value = "haggle",
        hint = t.haggles >= 4 and "refused" or nil },
      { label = "hug", key = "u", value = "hug" },
      { label = "threaten", key = "t", value = "threaten", colour = UI.c.crit },
      { label = "leave", key = "q", value = "leave" },
    }, { under = under, width = 34 })
    if not pick or pick.value == "leave" then return end

    if pick.value == "buy" then
      tradeBuy(g, pod, under); note = nil
    elseif pick.value == "sell" then
      tradeSell(g, pod, under); note = nil
    elseif pick.value == "hug" then
      note = doHug(g, pod)
    elseif pick.value == "haggle" then
      note = doHaggle(g, pod)
    elseif pick.value == "threaten" then
      if not UI.confirm("THREATEN", t.name .. " may simply shoot you. "
        .. "If it works, you get your price.") then
        note = nil
      else
        note = doThreaten(g, pod)
        if t.hostile then
          g:say(t.name .. " reaches under the counter.", UI.c.crit)
          local ent = { id = "trader_armed", x = pod.traderX or g.x, y = g.y,
                        awake = true, cooldown = 0, fromTrader = true }
          ent.name = t.name
          g.map.entities[#g.map.entities + 1] = ent
          if pod.traderX then CU.mapgen.set(g.map, pod.traderX, pod.y2 - 1, " ") end
          CU.combat.begin(g, ent)
          return
        end
      end
    end
  end
end

--------------------------------------------------------------------- pod fixtures

local TEMPS = {
  { label = "off, let it freeze", value = 2 },
  { label = "cool", value = 12 },
  { label = "mild", value = 19 },
  { label = "warm", value = 27 },
  { label = "as hot as it goes", value = 35 },
}

function S.thermostat(g, pod, under)
  local items = {}
  for _, e in ipairs(TEMPS) do
    items[#items + 1] = {
      label = e.label, hint = e.value .. "C", value = e.value,
      colour = (pod.temp == e.value) and UI.c.gold or UI.c.text,
    }
  end
  local pick = UI.pick("pod temperature, now " .. pod.temp .. "C", items,
    { under = under, width = 38 })
  if not pick then return end
  pod.temp = pick.value
  g:advance(20)
  g:say("Pod set to " .. pod.temp .. " degrees.", UI.c.accent)
end

function S.shower(g, pod)
  if (pod.showers or 0) <= 0 then
    UI.message("dry", "The tank is empty. This shower has nothing left in it.")
    return
  end
  if not UI.confirm("SHOWER", "Four minutes under it. It cleans out every wound at once "
    .. "and leaves you soaked.") then return end
  pod.showers = pod.showers - 1
  g:advance(240, { exertion = 0.2 })
  if g.over then return end

  local body = g.body
  local cleared = 0
  for _, id in ipairs(D.LIMB_ORDER) do
    local l = body.limbs[id]
    if l.infection > 0 then
      if l.infection < D.TUNE.INFECT_REVEAL then
        l.infection = 0
      else
        l.infection = math.max(0, l.infection - 38)
        cleared = cleared + 1
      end
      if l.infection < D.TUNE.INFECT_REVEAL then l.revealed = false end
    end
    l.disinfect = math.max(l.disinfect, 2400)
  end
  body.wet = 1
  body.oil = false
  body.sick = U.clamp(body.sick - 22, 0, 100)
  body.immunity = U.clamp(body.immunity + 8, 10, 130)
  body.mood = math.min(100, body.mood + 8)
  -- and it washes the floor under you
  CU.mapgen.addBlood(g.map, g.x, g.y, -4)
  UI.sfx("heal")
  g:say("Every wound is washed out and sealed against new infection for a while.", UI.c.ok)
  if cleared > 0 then
    g:say(cleared .. " wound" .. (cleared == 1 and " was" or "s were")
      .. " already bad. The shower knocked it back but did not finish it.", UI.c.warn)
  end
  g:say("You are soaked. Turn the pod up before you go out.", UI.c.cold)
end


--------------------------------------------------------------------- hud pieces

-- What a step to either side would cost. The whole point of the game is not
-- being surprised by this, so it gets its own line.
function S.edgeLine(g, x, y, w)
  local P = CU.phys
  local c = UI.c
  local shown = false
  local cx = x
  for _, dx in ipairs({ -1, 1 }) do
    local pv = P.edgePreview(g, dx)
    if pv.kind == "drop" then
      local arrow = dx < 0 and "<" or ">"
      local col = c.ok
      if pv.effective >= 3 then col = c.warn end
      if pv.effective >= 30 then col = c.crit end
      local txt
      if g.hasGauge then
        txt = string.format("%s %dm onto %s, %s", arrow, math.floor(pv.metres),
          pv.surface, pv.verdict)
      else
        txt = string.format("%s about %dm down onto %s", arrow,
          math.floor(pv.metres / 5 + 0.5) * 5, pv.surface)
      end
      if pv.slideable and pv.effective >= 3 then txt = txt .. " (wall to grab)" end
      if cx + #txt <= x + w then
        UI.write(cx, y, txt, col)
        cx = cx + #txt + 2
        shown = true
      end
    end
  end
  return shown
end

function S.hints(g)
  if UI.touch then
    return "arrows move and steer a jump   use the buttons below"
  end
  if UI.w >= 58 then
    return "arrows move  space jump  x mine  f use  m med  v cond  i pack  ? menu"
  end
  return "arrows move  space jump  x mine  f use  m med  q menu"
end

local TOUCH_ROWS = {
  { { "USE", "use" }, { "MINE", "mine" }, { "MED", "med" }, { "PACK", "pack" },
    { "REST", "rest" }, { "MAP", "map" } },
  { { "WAIT", "wait" }, { "CRAFT", "craft" }, { "PAPER", "paper" }, { "COND", "cond" },
    { "MENU", "menu" } },
}

function S.touchBar(g, y, h)
  local c = UI.c
  -- direction pad on the left
  UI.button(2, y, 5, 2, "JUMP", "jump", c.title, c.panel)
  UI.button(8, y, 5, 2, "^", "up", c.text, c.panel)
  UI.button(2, y + 2, 5, 2, "<", "left", c.text, c.panel)
  UI.button(8, y + 2, 5, 2, "v", "down", c.text, c.panel)
  UI.button(14, y + 2, 5, 2, ">", "right", c.text, c.panel)

  local ax = 21
  local avail = UI.w - ax - 1
  local cols = 6
  local bw = math.max(6, math.floor(avail / cols))
  for r = 1, 2 do
    for i, b in ipairs(TOUCH_ROWS[r]) do
      local bx = ax + (i - 1) * bw
      if bx + bw - 1 <= UI.w then
        UI.button(bx, y + (r - 1) * 2, bw - 1, 2, b[1], b[2], c.text, c.panel)
      end
    end
  end
end

--------------------------------------------------------------------- play

local function drawPlay(g)
  local c = UI.c
  local Rr = CU.render
  local w, h = UI.w, UI.h

  g.blink = (g.blink or 0) + 1
  UI.beginFrame()
  S.header(g)

  local side = (w >= 58) and 15 or 0
  local touchH = UI.touch and 4 or 0
  local logH = (h >= 24) and 3 or 2

  -- bottom up: buttons if there are any, one status row, the log, then a rule.
  -- everything else is map.
  local statusY = h - touchH
  local logBottom = statusY - 1
  local logY = logBottom - logH + 1
  local ruleY = logY - 1
  local mapH = ruleY - 3
  local mapW = w - side
  if mapH < 6 then
    logH = 1
    logY = logBottom
    ruleY = logY - 1
    mapH = ruleY - 3
  end

  Rr.drawMap(g, 1, 3, mapW, mapH)
  local rgb, strength = UI.painOverlay(select(1, B.effectivePain(g.body)))
  if rgb then UI.vignette(1, 3, mapW, mapH, rgb, strength) end
  UI.hrule(1, ruleY, mapW, c.faint)
  g.log:render(2, logY, mapW - 3, logH)

  if side > 0 then
    local sx = w - side + 1
    UI.fill(sx - 1, 3, 1, h - 3 - touchH, c.bg)
    S.miniBody(sx + 1, 3, g.body)
    S.vitalsColumn(sx, 13, g)
    S.statusLine(statusY, g, false)
  else
    S.statusLine(statusY, g, true)
  end

  if touchH > 0 then S.touchBar(g, h - touchH + 1, touchH) end
  UI.endFrame()
end

S.frame = drawPlay

local function moreMenu(g)
  local opts = {
    { label = "craft", key = "c", value = "craft" },
    { label = "rest", key = "r", value = "rest" },
    { label = "recovered paper", key = "j", value = "paper" },
    { label = "condition", key = "v", value = "cond" },
  }
  local Tl = CU.tiles
  local onShaft = Tl.get(CU.mapgen.get(g.map, g.x, g.y + 1)).shaft
    or Tl.get(CU.mapgen.get(g.map, g.x, g.y)).shaft
  if onShaft then
    table.insert(opts, { label = "save and stop here", key = "s", value = "suspend",
      colour = UI.c.accent })
  end
  table.insert(opts, { label = "give up", key = "x", value = "quit", colour = UI.c.crit })
  local pick = UI.pick("menu", opts, { under = function() drawPlay(g) end, width = 38 })
  if not pick then return end
  if pick.value == "craft" then S.craft(g)
  elseif pick.value == "rest" then S.restMenu(g)
  elseif pick.value == "paper" then S.journal(g)
  elseif pick.value == "cond" then S.condition(g)
  elseif pick.value == "suspend" then
    if UI.confirm("SAVE AND STOP", "You can save at a shaft. The run is written to disk "
      .. "and you can pick it up later.") then
      g:suspend()
    end
  elseif pick.value == "quit" then
    if UI.confirm("GIVE UP", "The bond in your skull ends the contract for you. "
      .. "This kills the character.", "do it", "no") then
      g.body.brain = 0
      g:endRun("bond enforcement")
    end
  end
end

function S.restMenu(g)
  local pick = UI.pick("rest", {
    { label = "five minutes", value = 300 },
    { label = "twenty minutes", value = 1200 },
    { label = "one hour", value = 3600 },
    { label = "two hours", value = 7200 },
  }, { under = function() drawPlay(g) end, width = 34 })
  if pick then g:rest(pick.value) end
end

local ACTIONS = {}

function ACTIONS.left(g)  CU.phys.walk(g, -1) end
function ACTIONS.right(g) CU.phys.walk(g, 1) end
function ACTIONS.up(g)    CU.phys.climb(g, -1) end
function ACTIONS.down(g)
  local r = CU.phys.climb(g, 1)
  if r == "exit" then S.interact(g, function() drawPlay(g) end) end
end
function ACTIONS.use(g)   S.interact(g, function() drawPlay(g) end) end
function ACTIONS.med(g)   S.medical(g) end
function ACTIONS.pack(g)  S.inventory(g, function() drawPlay(g) end) end
function ACTIONS.map(g)   S.overview(g) end
function ACTIONS.rest(g)  S.restMenu(g) end
function ACTIONS.craft(g) S.craft(g) end
function ACTIONS.paper(g) S.journal(g) end
function ACTIONS.cond(g)  S.condition(g) end
function ACTIONS.wait(g)  g:advance(30, { exertion = 0.05 }) end
function ACTIONS.jump(g)  CU.phys.jump(g) end
function ACTIONS.mine(g)  CU.phys.mine(g) end
function ACTIONS.gear(g)  S.gear(g) end
function ACTIONS.menu(g)  moreMenu(g) end

function S.play(g)
  g.onFrame = function() drawPlay(g) end
  CU.phys.reveal(g)
  CU.phys.settle(g)
  while not g.over do
    if g.body.consciousness < D.TUNE.CONSCIOUS_OUT and not g.body.dead then
      S.blackout(g)
    end
    if g.over then break end

    g.hasGauge = Inv.count(g.inv, "drop_gauge") > 0
    CU.phys.reveal(g)
    UI.tickFx()
    drawPlay(g)

    -- redraw on a timer while anything is throbbing, so it actually moves
    local pain = select(1, B.effectivePain(g.body))
    local animating = UI.advanced and (UI.fxActive() or pain > 20)
    local ev = UI.read(animating and 0.13 or nil)
    if ev.kind == "timer" then ev = { kind = "none" } end
    local act = nil
    if ev.kind == "key" then
      local n = ev.name
      if n == "left" then act = "left"
      elseif n == "right" then act = "right"
      elseif n == "up" then act = "up"
      elseif n == "down" then act = "down"
      elseif n == "enter" then act = "use"
      elseif n == "tab" then act = "med"
      elseif n == "back" then act = "menu" end
    elseif ev.kind == "char" then
      local ch = ev.char
      local map = { a = "left", d = "right", w = "up", s = "down",
                    f = "use", m = "med", i = "pack", k = "map", r = "rest",
                    c = "craft", j = "paper", v = "cond", ["?"] = "menu",
                    q = "menu", z = "wait", x = "mine", g = "gear",
                    [" "] = "jump" }
      act = map[ch]
    elseif ev.kind == "click" then
      act = UI.hitButton(ev.x, ev.y)
    end

    if act and ACTIONS[act] then
      ACTIONS[act](g)
      if not g.over then
        CU.phys.stepEntities(g)
        if g.body.dead then g:endRun(g.body.cause) end
      end
    end
  end
end


--------------------------------------------------------------------- documents

function S.readDoc(g, index)
  local doc = D.DOCS[index]
  if not doc then return end
  UI.message(doc.title, doc.body, UI.c.gold)
end

function S.journal(g)
  local items = {}
  for idx in pairs(g.docsFound) do
    items[#items + 1] = { label = D.DOCS[idx].title, value = idx }
  end
  table.sort(items, function(a, b) return a.value < b.value end)
  if #items == 0 then
    UI.message("nothing on file", "You have not picked up any paper yet.")
    return
  end
  local pick = UI.pick("recovered paper", items)
  if pick then S.readDoc(g, pick.value) end
end

--------------------------------------------------------------------- crafting

function S.craft(g)
  while not g.over do
    local list = Inv.availableRecipes(g.inv, g.body)
    local items = {}
    for _, r in ipairs(list) do
      local rec = r.recipe
      local out = D.ITEMS[rec.out]
      local needBits = {}
      for id, n in pairs(rec.need) do
        needBits[#needBits + 1] = D.ITEMS[id].short .. " " .. Inv.count(g.inv, id) .. "/" .. n
      end
      items[#items + 1] = {
        label = out.name .. ((rec.n or 1) > 1 and (" x" .. rec.n) or ""),
        hint = U.dur(rec.time),
        colour = r.can and UI.c.text or UI.c.faint,
        disabled = not r.can,
        recipe = rec,
        detail = table.concat(needBits, ", "),
      }
    end
    table.sort(items, function(a, b)
      if a.disabled ~= b.disabled then return not a.disabled end
      return a.label < b.label
    end)
    local pick = UI.pick("BENCH", items, { footer = "enter make   q back", width = 46 })
    if not pick then return end
    if pick.recipe then
      g:advance(pick.recipe.time, { exertion = 0.2 })
      local ok, msg = Inv.craft(g.inv, pick.recipe, g.body)
      g:say(msg, ok and UI.c.ok or UI.c.warn)
      UI.sfx(ok and "confirm" or "deny")
    end
  end
end

--------------------------------------------------------------------- report

function S.report(g, meta)
  local c = UI.c
  local lines = {}
  local function L(t, col) lines[#lines + 1] = { t, col or c.text } end
  L("FORM 12-B  RECOVERY OF ASSET", c.accent)
  L("")
  L("asset ......... " .. g.id)
  L("class ......... 4")
  L("depth reached . " .. math.floor(g.stats.maxDepth) .. " m")
  L("stratum ....... " .. U.roman(g.stratumIndex) .. "  " .. g.map.strat.name)
  L("time under .... " .. U.clock(g.clock, true))
  L("")
  if g.extracted then
    L("disposition ... RECOVERED", c.ok)
  else
    L("disposition ... NOT RECOVERED, POSITION KNOWN", c.crit)
    L("cause ......... " .. g.cause, c.crit)
  end
  L("blood lost .... " .. U.fmt1(g.body.bloodLost or 0) .. " L")
  L("fallen ........ " .. math.floor(g.stats.fallMetres or 0) .. " m")
  L("longest fall .. " .. math.floor(g.stats.longestFall or 0) .. " m")
  L("searched ...... " .. g.stats.searched)
  L("contacts ...... " .. g.stats.encounters .. " (" .. g.stats.kills .. " ended)")
  L("paper ......... " .. g.stats.docs)
  L("salvage ....... " .. Inv.value(g.inv))
  L("")
  L("score ......... " .. g:score(), c.gold)
  if g.cargo then L("CARGO RECOVERED", c.gold) end
  L("")
  L("Booked to: Casualties: Unknown", c.faint)

  local scroll = 0
  while true do
    UI.beginFrame()
    UI.fill(1, 1, UI.w, 1, c.panel)
    UI.write(2, 1, "STATUS REPORT", c.title, c.panel)
    UI.hrule(1, 2, UI.w, c.faint)
    local h = UI.h - 4
    for i = 1, h do
      local ln = lines[i + scroll]
      if ln then UI.write(3, 2 + i, U.trunc(ln[1], UI.w - 4), ln[2]) end
    end
    UI.hrule(1, UI.h - 1, UI.w, c.faint)
    UI.write(2, UI.h, "any key to file", c.faint)
    UI.endFrame()
    local ev = UI.read()
    if ev.kind == "key" and ev.name == "down" and #lines > UI.h - 4 then
      scroll = math.min(#lines - (UI.h - 4), scroll + 1)
    elseif ev.kind == "key" and ev.name == "up" then
      scroll = math.max(0, scroll - 1)
    else
      return
    end
  end
end

CU.screens = S
return S

end
