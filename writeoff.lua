-- WRITE-OFF
-- A side-on descent game for CC:Tweaked.
-- Runs on an advanced computer, and better on an advanced monitor.

local ARGS = { ... }

local ROOT
if shell and shell.getRunningProgram then
  ROOT = fs.getDir(shell.getRunningProgram())
elseif WRITEOFF_ROOT then
  ROOT = WRITEOFF_ROOT
else
  ROOT = "."
end
if ROOT == "" then ROOT = "/" end

local CU = { root = ROOT }

--------------------------------------------------------------------- loader

local function slurp(path)
  if fs and fs.exists then
    if not fs.exists(path) then return nil end
    local f = fs.open(path, "r")
    if not f then return nil end
    local src = f.readAll()
    f.close()
    return src
  end
  local f = io.open(path, "r")
  if not f then return nil end
  local src = f:read("*a")
  f:close()
  return src
end

--[[
  A cheap fingerprint of what is actually loaded, so "did the update take" has an
  answer you can see rather than guess at. Per file, summed, so the order the
  modules load in does not matter. The installer computes the same number over
  what it downloaded; if the two agree you are running what you installed.
]]
local function stampOf(src)
  local h = #src % 4294967296
  for i = 1, #src, 97 do
    h = (h * 131 + src:byte(i)) % 4294967296
  end
  return h
end

CU.build = 0

local function loadModule(name)
  local path = ROOT .. "/lib/" .. name .. ".lua"
  local src = slurp(path)
  if not src then error("missing module: " .. path, 0) end
  local compile = loadstring or load
  local chunk, err = compile(src, "@" .. name .. ".lua")
  if not chunk then error("syntax error in " .. name .. ": " .. tostring(err), 0) end
  CU.build = (CU.build + stampOf(src)) % 4294967296
  local factory = chunk()
  if type(factory) ~= "function" then
    error("module " .. name .. " did not return a factory", 0)
  end
  return factory(CU)
end

do
  local self = slurp(ROOT .. "/writeoff.lua")
  if self then CU.build = (CU.build + stampOf(self)) % 4294967296 end
end

for _, name in ipairs({ "util", "ui", "data", "tiles", "body", "fall", "inv",
                        "mapgen", "phys", "render", "combat", "run",
                        "screens", "save" }) do
  loadModule(name)
end

CU.buildTag = string.format("%04x", CU.build % 65536)

local U, UI, D, S, R, Sv = CU.util, CU.ui, CU.data, CU.screens, CU.run, CU.save

--------------------------------------------------------------------- screen choice

-- Sets the largest text size on a monitor that still leaves room for the layout.
-- Returns nil if the monitor cannot fit the game at any scale.
local function fitMonitor(mon)
  if not mon or not mon.setTextScale then return nil end
  local scales = { 5, 4, 3, 2, 1.5, 1, 0.5 }
  for _, sc in ipairs(scales) do
    pcall(mon.setTextScale, sc)
    local w, h = mon.getSize()
    if w >= 68 and h >= 24 then return sc end
  end
  for _, sc in ipairs(scales) do
    pcall(mon.setTextScale, sc)
    local w, h = mon.getSize()
    if w >= UI.MINW and h >= UI.MINH then return sc end
  end
  return nil
end

local function findMonitor()
  if not (peripheral and peripheral.find) then return nil end
  local ok, mon = pcall(peripheral.find, "monitor")
  if not ok then return nil end
  return mon
end

-- Asks once, on the terminal, so the terminal never goes dark without being told to.
local function askScreen(mon)
  local w, h = term.getSize()
  term.setBackgroundColour(colours.black)
  term.setTextColour(colours.white)
  term.clear()
  term.setCursorPos(2, 2)
  term.write("WRITE-OFF")
  term.setCursorPos(2, 4)
  term.write("A monitor is attached. Where do you want")
  term.setCursorPos(2, 5)
  term.write("to play?")
  term.setCursorPos(2, 7)
  term.setTextColour(colours.yellow)
  term.write("[1]")
  term.setTextColour(colours.white)
  term.write(" this terminal, keyboard")
  term.setCursorPos(2, 8)
  term.setTextColour(colours.yellow)
  term.write("[2]")
  term.setTextColour(colours.white)
  term.write(" the monitor, touch buttons")
  term.setCursorPos(2, 10)
  term.setTextColour(colours.lightGrey)
  term.write("run `writeoff term` or `writeoff monitor`")
  term.setCursorPos(2, 11)
  term.write("to skip this next time")
  term.setTextColour(colours.white)
  while true do
    local ev, a = os.pullEvent()
    if ev == "char" then
      if a == "1" or a == "t" then return false end
      if a == "2" or a == "m" then return true end
    elseif ev == "key" then
      if a == keys.one then return false end
      if a == keys.two then return true end
    end
  end
end

-- Returns the terminal to draw on, and the monitor if one is being used.
local function pickScreen()
  local mode = tostring(ARGS[1] or ""):lower()
  local mon = findMonitor()

  if mode == "term" or mode == "terminal" or mode == "computer" then
    return term.current(), nil
  end

  if not mon then return term.current(), nil end

  local scale = fitMonitor(mon)
  if not scale then
    -- monitor is too small to be useful, so stay on the terminal
    return term.current(), nil
  end

  local useMonitor
  if mode == "monitor" or mode == "mon" then
    useMonitor = true
  else
    local tw, th = term.getSize()
    if tw < UI.MINW or th < UI.MINH then
      useMonitor = true          -- the terminal cannot show it anyway
    else
      useMonitor = askScreen(mon)
    end
  end

  if useMonitor then
    pcall(mon.setTextScale, scale)
    return mon, mon
  end
  return term.current(), nil
end

--------------------------------------------------------------------- title art

local FONT = {
  W = { "#...#", "#...#", "#.#.#", "##.##", "#...#" },
  R = { "####.", "#...#", "####.", "#..#.", "#...#" },
  I = { "#####", "..#..", "..#..", "..#..", "#####" },
  T = { "#####", "..#..", "..#..", "..#..", "..#.." },
  E = { "#####", "#....", "####.", "#....", "#####" },
  O = { ".###.", "#...#", "#...#", "#...#", ".###." },
  F = { "#####", "#....", "####.", "#....", "#...." },
  ["-"] = { ".....", ".....", "###..", ".....", "....." },
}

local function drawWord(word, x, y, colour)
  for i = 1, #word do
    local glyph = FONT[word:sub(i, i)]
    if glyph then
      for row = 1, 5 do
        for col = 1, 5 do
          if glyph[row]:sub(col, col) == "#" then
            UI.write(x + (i - 1) * 6 + col - 1, y + row - 1, " ", colour, colour)
          end
        end
      end
    end
  end
end

local function titleArt(y)
  local c = UI.c
  if UI.w >= 40 then
    drawWord("WRITE", math.floor((UI.w - 29) / 2) + 1, y, c.text)
    drawWord("-OFF", math.floor((UI.w - 23) / 2) + 1, y + 6, c.crit)
    return y + 11
  end
  UI.write(2, y, "WRITE-OFF", c.text)
  return y + 2
end

--------------------------------------------------------------------- briefing

local BRIEFING = {
  {
    "THE JOB",
    "A consignment was foolishly lost, three thousand metres deep in the spoiled earth's core. You are being paid, in safety promised to your family, to bring it back.",
    "Eleven levels with three hundred metres each. The whole floor of the bottom gallery is the way on: stand on the arrows and press DOWN. The cargo is on layer 10, and the lift back up is layer 11. It will not let you on without it.",
  },
  {
    "MOVING",
    "Use the arrow keys, or A and D, to move your unit. Spacebar to jump, and whichever way you are holding steers it.",
    "W and S, or UP and DOWN, climb ropes, which you will find as | around the world. Ropes are far safer than jumping. But sometimes jumping may lead somewhere more useful.",
  },
  {
    "FALLING",
    "Falling off a ledge will always be a risk. But if you press against a wall, you will begin to slide, and that can greatly reduce your fall damage. Moss beds and water help as well.",
    "The line under the map tells you how far the drop is and what is at the bottom.",
  },
  {
    "YOUR BODY",
    "Seven limbs and parts, all tracked separately, each with skin, muscle and bone.",
    "Skin damage will eventually bleed, and may become infected. Muscle damage starts weakening that limb's function, and in the thorax it can cause asphyxiation.",
    "Really pay attention to your status. Press V for the list.",
  },
  {
    "TRIAGE",
    "Press M for the medical page. 1 to 7 picks a body part, and you can tap the part directly instead. T brings up a list of treatments.",
    "Pain will make your hands shake, causing more failures in setting joints and pulling shrapnel. Good old opiates fix that.",
  },
  {
    "TRAPS AND WATER",
    "Somebody wanted these levels to themselves. Spikes show only a blinking red light, within two tiles. Landing on one from height can take an eye or a jaw.",
    "Launch plates throw you up and sideways, never straight up. Leg traps hold you eight seconds and bleed you. Press F to pry one open, or move to pull free and pay for it.",
    "Press DOWN in water to kneel and drink. No flask needed. Springs are clean, pools are not.",
  },
  {
    "PODS AND TRADERS",
    "About one level in three has a pod: a sealed shell with doors. Some hold containers, good loot that was lost and is now yours. Some hold people willing to show you their wares. Treat them kindly.",
    "Every pod is lit throughout and has a charge post for your lights, a thermostat in Celsius, sorry you filthy americans, and a decontamination shower. A cleanse kills weak and medium infection in every limb and seals them for a while.",
  },
  {
    "KEYS",
    "arrows or WASD move and climb.  SPACE jumps, and whichever way you hold steers it.  F or ENTER uses what you are standing on.",
    "X mines.  M medical.  V condition.  I pack.  K map.  R rest.  C craft.  J paper.  Z wait.  Q menu.",
    "On a monitor, use the buttons along the bottom instead.",
  },
  {
    "REMEMBER",
    "You are expendable.",
    centre = true,
  },
}

local function briefing()
  local page = 1
  while true do
    local pg = BRIEFING[page]
    UI.beginFrame()
    UI.fill(1, 1, UI.w, 1, UI.c.panel)
    UI.write(2, 1, "BRIEFING  " .. page .. "/" .. #BRIEFING, UI.c.title, UI.c.panel)

    local bottom = UI.touch and (UI.h - 3) or (UI.h - 1)

    if pg.centre then
      local mid = math.floor(UI.h / 2)
      UI.write(math.floor((UI.w - #pg[1]) / 2) + 1, mid - 1, pg[1], UI.c.crit)
      for i = 2, #pg do
        UI.write(math.floor((UI.w - #pg[i]) / 2) + 1, mid + i - 1, pg[i], UI.c.text)
      end
    else
      UI.write(3, 3, pg[1], UI.c.accent)
      local y = 5
      for i = 2, #pg do
        for _, ln in ipairs(U.wrap(pg[i], UI.w - 6)) do
          if y < bottom then UI.write(3, y, ln, UI.c.text); y = y + 1 end
        end
        y = y + 1
      end
    end

    if UI.touch then
      UI.button(2, UI.h - 2, 10, 2, "BACK", "prev")
      UI.button(14, UI.h - 2, 10, 2, "NEXT", "next")
      UI.button(26, UI.h - 2, 10, 2, "CLOSE", "close")
    else
      UI.write(2, UI.h, "left and right change page.  q to go back", UI.c.faint)
    end
    UI.endFrame()
    local ev = UI.read()
    if ev.kind == "key" then
      if ev.name == "right" or ev.name == "down" or ev.name == "enter" then
        page = page % #BRIEFING + 1
      elseif ev.name == "left" or ev.name == "up" then
        page = (page - 2) % #BRIEFING + 1
      elseif ev.name == "back" then return end
    elseif ev.kind == "char" and ev.char == "q" then
      return
    elseif ev.kind == "click" then
      local hit = UI.hitButton(ev.x, ev.y)
      if hit == "next" then page = page % #BRIEFING + 1
      elseif hit == "prev" then page = (page - 2) % #BRIEFING + 1
      elseif hit == "close" then return end
    end
  end
end

--------------------------------------------------------------------- ledger

local function ledgerScreen(meta)
  local scroll = 0
  while true do
    UI.beginFrame()
    UI.fill(1, 1, UI.w, 1, UI.c.panel)
    UI.write(2, 1, "PAST RUNS", UI.c.title, UI.c.panel)
    UI.hrule(1, 2, UI.w, UI.c.faint)
    UI.write(2, 3, U.pad("run", 11) .. U.pad("depth", 8) .. U.pad("what happened", 22)
      .. "score", UI.c.faint)
    local rows = UI.h - 6
    for i = 1, rows do
      local e = meta.ledger[i + scroll]
      if e then
        local col = e.cause == "recovered" and UI.c.ok or UI.c.dim
        UI.write(2, 3 + i, U.pad(e.id, 11) .. U.pad(e.depth .. "m", 8)
          .. U.pad(U.trunc(e.cause, 21), 22) .. tostring(e.score), col)
      end
    end
    UI.hrule(1, UI.h - 2, UI.w, UI.c.faint)
    UI.write(2, UI.h - 1, "runs " .. (meta.attempts or 0) .. "   best score "
      .. (meta.best or 0) .. "   deepest " .. (meta.deepest or 0) .. " m", UI.c.dim)
    if UI.touch then
      UI.button(2, UI.h - 1, 10, 1, "CLOSE", "close")
    else
      UI.write(2, UI.h, "q to go back", UI.c.faint)
    end
    UI.endFrame()
    local ev = UI.read()
    if ev.kind == "key" then
      if ev.name == "down" then scroll = math.min(math.max(0, #meta.ledger - rows), scroll + 1)
      elseif ev.name == "up" then scroll = math.max(0, scroll - 1)
      elseif ev.name == "back" or ev.name == "enter" then return end
    elseif ev.kind == "char" and ev.char == "q" then return
    elseif ev.kind == "click" then return end
  end
end

--------------------------------------------------------------------- run

local function playRun(g, meta)
  S.play(g)
  if g.suspended then
    Sv.saveRun(g)
    UI.message("SAVED", "Run saved at stratum " .. U.roman(g.stratumIndex)
      .. ". Pick it up from the menu.", UI.c.accent)
    return
  end
  Sv.clearRun()
  S.report(g, meta)
  Sv.record(meta, g)
end

--------------------------------------------------------------------- menu

local function mainMenu()
  local meta = Sv.loadMeta()
  local sel = 1
  while true do
    local items = {}
    items[#items + 1] = { label = "new run", key = "n", value = "new" }
    if Sv.hasRun() then
      table.insert(items, 1, { label = "continue", key = "c", value = "resume",
                               colour = UI.c.gold })
    end
    items[#items + 1] = { label = "how to play", key = "h", value = "help" }
    items[#items + 1] = { label = "past runs", key = "p", value = "ledger" }
    items[#items + 1] = { label = "quit", key = "q", value = "quit" }

    UI.beginFrame()
    local y = titleArt(2)
    local sub = "a casualties: uknown rip-off. (haha, get it?)"
    if UI.w < #sub + 2 then sub = "a casualties: uknown rip-off." end
    UI.write(math.floor((UI.w - #sub) / 2) + 1, y, sub, UI.c.faint)
    local menuY = math.min(UI.h - #items - 1, y + 2)
    if sel > #items then sel = #items end
    UI.drawMenu(math.floor(UI.w / 2) - 9, menuY, 20, #items, items, sel, 0)
    UI.write(2, UI.h, U.trunc("runs " .. (meta.attempts or 0)
      .. "   deepest " .. (meta.deepest or 0) .. " m", UI.w - 14), UI.c.faint)
    local tag = "build " .. CU.buildTag
    UI.write(UI.w - #tag, UI.h, tag, UI.c.faint)
    UI.endFrame()

    local ev = UI.read()
    local chosen = nil
    if ev.kind == "key" then
      if ev.name == "up" then sel = sel > 1 and sel - 1 or #items
      elseif ev.name == "down" then sel = sel < #items and sel + 1 or 1
      elseif ev.name == "enter" then chosen = items[sel].value end
    elseif ev.kind == "char" then
      for _, it in ipairs(items) do
        if it.key == ev.char then chosen = it.value end
      end
    elseif ev.kind == "click" then
      local idx = ev.y - menuY + 1
      if items[idx] then chosen = items[idx].value end
    end

    if chosen == "quit" then return
    elseif chosen == "help" then briefing()
    elseif chosen == "ledger" then ledgerScreen(meta)
    elseif chosen == "resume" then
      local g = Sv.loadRun()
      if g then
        playRun(g, meta)
        meta = Sv.loadMeta()
      else
        UI.message("no save", "The save file could not be read. It has been removed.",
          UI.c.crit)
        Sv.clearRun()
      end
    elseif chosen == "new" then
      local go = true
      if Sv.hasRun() then
        go = UI.confirm("OVERWRITE", "There is a saved run. Starting a new one deletes it.")
        if go then Sv.clearRun() end
      end
      if go then
        local seed = math.floor((os.epoch and os.epoch("utc") or os.time() * 1000)) % 2147483
        local g = R.new(seed, { kit = Sv.kitFor(meta), attempts = meta.attempts })
        playRun(g, meta)
        meta = Sv.loadMeta()
      end
    end
  end
end

--------------------------------------------------------------------- boot

local function main()
  local screen, monitor = pickScreen()
  local restore = nil
  if monitor and term.redirect then restore = term.redirect(monitor) end

  local fits = UI.init(monitor or term.current(), monitor ~= nil)
  if not fits then
    UI.shutdown()
    if restore then term.redirect(restore) end
    print("WRITE-OFF needs a screen of at least " .. UI.MINW .. "x" .. UI.MINH .. ".")
    print("This one is " .. UI.w .. "x" .. UI.h .. ".")
    print("Use an advanced computer, or attach an advanced monitor.")
    print("`writeoff monitor` forces the monitor, `writeoff term` forces this screen.")
    return
  end
  mainMenu()
  UI.shutdown()
  if restore then term.redirect(restore) end
  print("Booked to Casualties: Unknown.")
  if monitor then
    print("Run `writeoff term` to play on this screen instead.")
  end
end

CU.main = main
if not WRITEOFF_NO_AUTORUN then
  local ok, err = pcall(main)
  if not ok then
    pcall(UI.shutdown)
    print("WRITE-OFF crashed:")
    print(tostring(err))
  end
end

return CU
