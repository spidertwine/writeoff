-- WRITE-OFF / lib/ui.lua
-- Terminal drawing, input handling, menus, body diagram, sound.

return function(CU)

local U = CU.util
local UI = {}

UI.MINW, UI.MINH = 51, 19
UI.headless = false

--------------------------------------------------------------------- colours

-- semantic name -> colours constant. Falls back to white/black on basic terms.
local C = {}
UI.c = C

local function setupColours(advanced)
  local k = colors or colours
  if advanced then
    C.bg        = k.black
    C.panel     = k.gray
    C.text      = k.white
    C.dim       = k.lightGray
    C.faint     = k.gray
    C.good      = k.lime
    C.ok        = k.green
    C.warn      = k.yellow
    C.bad       = k.orange
    C.crit      = k.red
    C.dead      = k.gray
    C.blood     = k.red
    C.bone      = k.white
    C.infect    = k.purple
    C.cold      = k.lightBlue
    C.hot       = k.orange
    C.drug      = k.magenta
    C.accent    = k.cyan
    C.gold      = k.yellow
    C.rad       = k.lime
    C.select    = k.blue
    C.title     = k.white
  else
    for _, n in ipairs({ "bg","panel","text","dim","faint","good","ok","warn","bad",
      "crit","dead","blood","bone","infect","cold","hot","drug","accent","gold",
      "rad","select","title" }) do
      C[n] = k.white
    end
    C.bg = k.black
    C.panel = k.black
    C.dim = k.white
    C.faint = k.white
    C.select = k.white
  end
end

-- a grimmer palette on advanced terminals; restored on exit
local PALETTE = {
  { "red",        0x8f1d1d },
  { "orange",     0xc06a22 },
  { "yellow",     0xd6b13c },
  { "lime",       0x74a33a },
  { "green",      0x3f6b32 },
  { "lightBlue",  0x6fa8c4 },
  { "cyan",       0x3d7f86 },
  { "purple",     0x6b4a7a },
  { "magenta",    0xa9538f },
  { "gray",       0x35383c },
  { "lightGray",  0x8b8f94 },
  { "white",      0xd8d5cd },
  { "black",      0x0a0b0c },
  { "brown",      0x5b422c },
  { "blue",       0x2b3f6b },
  { "pink",       0xc98b8b },
}
local savedPalette = nil

function UI.applyPalette()
  if not UI.advanced or not UI.t.setPaletteColour then return end
  local k = colors or colours
  savedPalette = {}
  for _, p in ipairs(PALETTE) do
    local col = k[p[1]]
    if col then
      local ok, r, g, b = pcall(UI.t.getPaletteColour, col)
      if ok then savedPalette[col] = { r, g, b } end
      pcall(UI.t.setPaletteColour, col, p[2])
    end
  end
end

function UI.restorePalette()
  if not savedPalette or not UI.t.setPaletteColour then return end
  for col, rgb in pairs(savedPalette) do
    pcall(UI.t.setPaletteColour, col, rgb[1], rgb[2], rgb[3])
  end
  savedPalette = nil
end

--------------------------------------------------------------------- setup

function UI.init(target, isMonitor)
  UI.root = target or term.current()
  UI.usingMonitor = isMonitor and true or false
  UI.advanced = false
  if UI.root.isColour then
    local ok, v = pcall(UI.root.isColour)
    UI.advanced = ok and v
  end
  setupColours(UI.advanced)

  local w, h = UI.root.getSize()
  UI.w, UI.h = w, h
  UI.mode = (w >= 68 and h >= 24) and "big" or ((w >= 58) and "wide" or "compact")
  -- touch controls only exist where there is no keyboard, and only where the
  -- button bar actually fits. the terminal always keeps the keyboard layout.
  UI.touch = UI.usingMonitor and w >= 60 and h >= 22

  -- draw into an off-screen window so full redraws do not flicker
  if window and window.create then
    UI.buf = window.create(UI.root, 1, 1, w, h, true)
    UI.t = UI.buf
  else
    UI.buf = nil
    UI.t = UI.root
  end

  UI.applyPalette()
  pcall(UI.t.setCursorBlink, false)

  UI.speaker = nil
  if peripheral and peripheral.find then
    local ok, sp = pcall(peripheral.find, "speaker")
    if ok then UI.speaker = sp end
  end
  return UI.w >= UI.MINW and UI.h >= UI.MINH
end

function UI.shutdown()
  UI.restorePalette()
  if UI.buf then UI.buf.setVisible(true) end
  pcall(UI.root.setBackgroundColour, (colors or colours).black)
  pcall(UI.root.setTextColour, (colors or colours).white)
  pcall(UI.root.clear)
  pcall(UI.root.setCursorPos, 1, 1)
  pcall(UI.root.setCursorBlink, true)
end

function UI.beginFrame()
  if UI.buf then UI.buf.setVisible(false) end
  UI.clearButtons()
  UI.clear()
end

function UI.endFrame()
  if UI.buf then
    UI.buf.setVisible(true)
    UI.buf.redraw()
  end
end

--------------------------------------------------------------------- drawing

function UI.clear(bg)
  UI.t.setBackgroundColour(bg or C.bg)
  UI.t.setTextColour(C.text)
  UI.t.clear()
end

function UI.write(x, y, text, fg, bg)
  if y < 1 or y > UI.h then return end
  text = tostring(text)
  if x < 1 then
    text = string.sub(text, 2 - x)
    x = 1
  end
  if x > UI.w then return end
  if x + #text - 1 > UI.w then text = string.sub(text, 1, UI.w - x + 1) end
  if #text == 0 then return end
  UI.t.setBackgroundColour(bg or C.bg)
  UI.t.setTextColour(fg or C.text)
  UI.t.setCursorPos(x, y)
  UI.t.write(text)
end

-- Fast path for the map: one blit per row.
function UI.blitLine(x, y, text, fg, bg)
  if y < 1 or y > UI.h then return end
  if x < 1 then
    local cut = 2 - x
    text, fg, bg = text:sub(cut), fg:sub(cut), bg:sub(cut)
    x = 1
  end
  if x > UI.w then return end
  local room = UI.w - x + 1
  if #text > room then
    text, fg, bg = text:sub(1, room), fg:sub(1, room), bg:sub(1, room)
  end
  if #text == 0 then return end
  UI.t.setCursorPos(x, y)
  if UI.t.blit then
    UI.t.blit(text, fg, bg)
  else
    UI.t.write(text)
  end
end

--------------------------------------------------------------------- touch buttons

UI.buttons = {}

function UI.clearButtons() UI.buttons = {} end

-- Draws a button and registers its area for touch and mouse.
function UI.button(x, y, w, h, label, action, fg, bg, active)
  bg = bg or C.panel
  fg = fg or C.text
  if active then bg, fg = C.select, C.title end
  UI.fill(x, y, w, h, bg)
  local ly = y + math.floor((h - 1) / 2)
  local lx = x + math.max(0, math.floor((w - #label) / 2))
  UI.write(lx, ly, string.sub(label, 1, w), fg, bg)
  UI.buttons[#UI.buttons + 1] = { x = x, y = y, w = w, h = h, action = action }
end

function UI.hitButton(mx, my)
  for i = #UI.buttons, 1, -1 do
    local b = UI.buttons[i]
    if mx >= b.x and mx < b.x + b.w and my >= b.y and my < b.y + b.h then
      return b.action
    end
  end
  return nil
end

function UI.fill(x, y, w, h, bg, ch, fg)
  local row = string.rep(ch or " ", w)
  for i = 0, h - 1 do
    UI.write(x, y + i, row, fg or C.text, bg)
  end
end

-- ASCII frame. CC's font has no reliable box-drawing glyphs, so this uses + - |
function UI.frame(x, y, w, h, title, fg, bg)
  fg = fg or C.faint
  bg = bg or C.bg
  UI.write(x, y, "+" .. string.rep("-", w - 2) .. "+", fg, bg)
  UI.write(x, y + h - 1, "+" .. string.rep("-", w - 2) .. "+", fg, bg)
  for i = 1, h - 2 do
    UI.write(x, y + i, "|", fg, bg)
    UI.write(x + w - 1, y + i, "|", fg, bg)
  end
  if title then
    UI.write(x + 2, y, " " .. U.trunc(title, w - 6) .. " ", C.title, bg)
  end
end

function UI.hrule(x, y, w, fg, ch)
  UI.write(x, y, string.rep(ch or "-", w), fg or C.faint, C.bg)
end

-- horizontal gauge. On colour terms it is a run of coloured cells.
function UI.bar(x, y, w, frac, fg, bg)
  frac = U.clamp(frac or 0, 0, 1)
  local filled = math.floor(frac * w + 0.5)
  if frac > 0 and filled == 0 then filled = 1 end
  if UI.advanced then
    if filled > 0 then UI.fill(x, y, filled, 1, fg) end
    if w - filled > 0 then UI.fill(x + filled, y, w - filled, 1, bg or C.panel) end
  else
    UI.write(x, y, string.rep("#", filled) .. string.rep(".", w - filled), C.text, C.bg)
  end
end

-- label + gauge + value, all on one row
function UI.stat(x, y, label, labelw, frac, fg, valueText, barw)
  UI.write(x, y, U.pad(label, labelw), C.dim)
  UI.bar(x + labelw, y, barw, frac, fg, C.panel)
  if valueText then
    UI.write(x + labelw + barw + 1, y, valueText, fg)
  end
end

-- colour ramp for a 0..1 health value
function UI.healthColour(frac)
  if frac >= 0.85 then return C.good end
  if frac >= 0.6  then return C.ok end
  if frac >= 0.35 then return C.warn end
  if frac >= 0.15 then return C.bad end
  return C.crit
end

--------------------------------------------------------------------- log

local Log = {}
Log.__index = Log

function UI.newLog(limit)
  return setmetatable({ lines = {}, limit = limit or 240, dirty = true }, Log)
end

function Log:add(text, colour)
  if text == nil then return end
  self.lines[#self.lines + 1] = { text = tostring(text), colour = colour or C.text }
  while #self.lines > self.limit do table.remove(self.lines, 1) end
  self.dirty = true
end

function Log:blank()
  if #self.lines > 0 and self.lines[#self.lines].text ~= "" then
    self:add("")
  end
end

function Log:clear() self.lines = {} end

-- Returns wrapped display rows, newest last.
function Log:rows(width)
  local out = {}
  for i = 1, #self.lines do
    local entry = self.lines[i]
    local wrapped = U.wrap(entry.text, width)
    for j = 1, #wrapped do
      out[#out + 1] = { text = wrapped[j], colour = entry.colour }
    end
  end
  return out
end

function Log:render(x, y, w, h, scroll)
  local rows = self:rows(w)
  local total = #rows
  local offset = total - h - (scroll or 0)
  if offset < 0 then offset = 0 end
  for i = 1, h do
    local r = rows[offset + i]
    UI.write(x, y + i - 1, U.pad(r and r.text or "", w), r and r.colour or C.text, C.bg)
  end
  return total
end

--------------------------------------------------------------------- input

local KEYMAP
local function keyname(code)
  if not KEYMAP then
    KEYMAP = {}
    if keys then
      KEYMAP[keys.up] = "up"
      KEYMAP[keys.down] = "down"
      KEYMAP[keys.left] = "left"
      KEYMAP[keys.right] = "right"
      KEYMAP[keys.enter] = "enter"
      if keys.numPadEnter then KEYMAP[keys.numPadEnter] = "enter" end
      KEYMAP[keys.space] = "space"
      KEYMAP[keys.backspace] = "back"
      KEYMAP[keys.tab] = "tab"
      KEYMAP[keys.pageUp] = "pageup"
      KEYMAP[keys.pageDown] = "pagedown"
      if keys.leftShift then KEYMAP[keys.leftShift] = "shift" end
      if keys.rightShift then KEYMAP[keys.rightShift] = "shift" end
    end
  end
  return KEYMAP[code]
end

-- Normalised blocking read. Returns one of:
--   { kind="key",   name="up"|"down"|"enter"|... }
--   { kind="char",  char="a" }
--   { kind="click", x=n, y=n }
--   { kind="timer", id=n }
-- Drains whatever input is waiting, without blocking longer than `seconds`.
-- Used during falls so the player can grab a wall on the way down.
-- Which movement keys are currently held down. Used so that holding a direction
-- and pressing jump throws you that way.
UI.heldKeys = {}

local function noteKey(code, down)
  if code == keys.left or code == keys.a then UI.heldKeys.left = down
  elseif code == keys.right or code == keys.d then UI.heldKeys.right = down end
end

function UI.heldDirection()
  if UI.heldKeys.left and not UI.heldKeys.right then return -1 end
  if UI.heldKeys.right and not UI.heldKeys.left then return 1 end
  return 0
end

function UI.drain(seconds)
  if UI.headless then
    if UI.headlessDrain then return UI.headlessDrain() end
    return {}
  end
  local out = {}
  local timer = os.startTimer(seconds or 0)
  local guard = 0
  while guard < 200 do
    guard = guard + 1
    local ev = { os.pullEvent() }
    if ev[1] == "timer" and ev[2] == timer then break end
    if ev[1] == "key" then noteKey(ev[2], true)
    elseif ev[1] == "key_up" then noteKey(ev[2], nil) end
    out[#out + 1] = ev
  end
  return out
end

-- -1, 0 or 1: which way the player is pushing right now.
function UI.pollDirection(seconds)
  if UI.headless then return UI.headlessDir or 0 end
  local dir = 0
  for _, ev in ipairs(UI.drain(seconds)) do
    local name = ev[1]
    if name == "key" then
      local k = ev[2]
      if k == keys.left or k == keys.a then dir = -1
      elseif k == keys.right or k == keys.d then dir = 1 end
    elseif name == "key_up" then
      if dir == -1 and (ev[2] == keys.left or ev[2] == keys.a) then dir = 0 end
      if dir == 1 and (ev[2] == keys.right or ev[2] == keys.d) then dir = 0 end
    elseif name == "char" then
      if ev[2] == "a" then dir = -1 elseif ev[2] == "d" then dir = 1 end
    elseif name == "monitor_touch" or name == "mouse_click" then
      local mx, my = ev[3], ev[4]
      local hit = UI.hitButton(mx, my)
      if hit == "left" then dir = -1 elseif hit == "right" then dir = 1 end
    end
  end
  if dir == 0 then dir = UI.heldDirection() end
  return dir
end

function UI.read(timeout)
  if UI.headless then
    UI.headlessReads = (UI.headlessReads or 0) + 1
    return UI.headlessRead and UI.headlessRead() or { kind = "key", name = "back" }
  end
  local timerId
  if timeout then timerId = os.startTimer(timeout) end
  while true do
    local ev = { os.pullEvent() }
    local name = ev[1]
    if name == "key_up" then
      noteKey(ev[2], nil)
    elseif name == "key" then
      noteKey(ev[2], true)
      local n = keyname(ev[2])
      if n and n ~= "shift" then
        if timerId then os.cancelTimer(timerId) end
        return { kind = "key", name = n }
      end
    elseif name == "char" then
      if timerId then os.cancelTimer(timerId) end
      return { kind = "char", char = string.lower(ev[2]) }
    elseif name == "mouse_click" or name == "monitor_touch" then
      if timerId then os.cancelTimer(timerId) end
      local mx, my = ev[3], ev[4]
      if name == "monitor_touch" then mx, my = ev[3], ev[4] end
      return { kind = "click", x = mx, y = my, button = ev[2] }
    elseif name == "mouse_scroll" then
      if timerId then os.cancelTimer(timerId) end
      return { kind = "key", name = ev[2] > 0 and "down" or "up" }
    elseif name == "timer" and timerId and ev[2] == timerId then
      return { kind = "timer", id = ev[2] }
    elseif name == "term_resize" then
      local w, h = UI.root.getSize()
      if w ~= UI.w or h ~= UI.h then
        UI.w, UI.h = w, h
        if UI.buf then UI.buf.reposition(1, 1, w, h) end
        if timerId then os.cancelTimer(timerId) end
        return { kind = "resize" }
      end
    end
  end
end

--------------------------------------------------------------------- menus

-- items: { {label=, key=, hint=, colour=, disabled=, value=}, ... }
-- Renders in place; caller owns the frame. Returns the number of visible rows.
function UI.drawMenu(x, y, w, h, items, sel, scroll)
  scroll = scroll or 0
  for i = 1, h do
    local idx = i + scroll
    local it = items[idx]
    if it then
      local chosen = (idx == sel)
      local bg = chosen and C.select or C.bg
      local fg = it.colour or C.text
      if it.disabled then fg = C.faint end
      if chosen and not UI.advanced then fg = C.text end
      local key = it.key and ("[" .. it.key .. "] ") or "    "
      local label = key .. it.label
      local hintRoom = (#items > h) and 1 or 0
      UI.write(x, y + i - 1, U.pad(U.trunc(label, w), w), fg, bg)
      if it.hint then
        local hs = U.trunc(it.hint, 14)
        UI.write(x + w - #hs - hintRoom, y + i - 1, hs, chosen and C.text or C.dim, bg)
      end
    else
      UI.write(x, y + i - 1, string.rep(" ", w), C.text, C.bg)
    end
  end
  if #items > h then
    local frac = (sel - 1) / math.max(1, #items - 1)
    local ty = y + math.floor(frac * (h - 1) + 0.5)
    for i = 0, h - 1 do
      UI.write(x + w, y + i, (y + i == ty) and "|" or ":", C.faint, C.bg)
    end
  end
  return h
end

function UI.menuScroll(sel, h, count, scroll)
  scroll = scroll or 0
  if sel - scroll > h then scroll = sel - h end
  if sel - scroll < 1 then scroll = sel - 1 end
  if scroll > count - h then scroll = count - h end
  if scroll < 0 then scroll = 0 end
  return scroll
end

-- Modal list picker. Returns item, index or nil if cancelled.
function UI.pick(title, items, opts)
  opts = opts or {}
  if #items == 0 then return nil end
  local sel, scroll = opts.sel or 1, 0
  local w = math.min(UI.w - 4, opts.width or 44)
  local listh = math.min(#items, UI.h - 8)
  local h = listh + 4
  local x = math.floor((UI.w - w) / 2) + 1
  local y = math.floor((UI.h - h) / 2) + 1
  local spins = 0
  while true do
    spins = spins + 1
    if spins > 4000 then return nil end
    scroll = UI.menuScroll(sel, listh, #items, scroll)
    UI.beginFrame()
    if opts.under then opts.under() end
    UI.fill(x, y, w, h, C.bg)
    UI.frame(x, y, w, h, title, C.accent)
    UI.drawMenu(x + 2, y + 1, w - 5, listh, items, sel, scroll)
    UI.write(x + 2, y + h - 2, U.trunc(opts.footer or "enter select   q back", w - 4), C.faint)
    UI.endFrame()
    local ev = UI.read()
    if ev.kind == "key" then
      if ev.name == "up" then sel = sel > 1 and sel - 1 or #items
      elseif ev.name == "down" then sel = sel < #items and sel + 1 or 1
      elseif ev.name == "pageup" then sel = math.max(1, sel - listh)
      elseif ev.name == "pagedown" then sel = math.min(#items, sel + listh)
      elseif ev.name == "enter" or ev.name == "space" then
        if not items[sel].disabled then return items[sel], sel end
      elseif ev.name == "back" then return nil end
    elseif ev.kind == "char" then
      if ev.char == "q" then return nil end
      for i = 1, #items do
        if items[i].key and string.lower(items[i].key) == ev.char and not items[i].disabled then
          return items[i], i
        end
      end
    elseif ev.kind == "click" then
      local idx = ev.y - y + scroll
      if idx >= 1 and idx <= #items and ev.x > x and ev.x < x + w then
        if not items[idx].disabled then return items[idx], idx end
      end
    end
  end
end

function UI.message(title, text, colour)
  local w = math.min(UI.w - 4, 44)
  local lines = U.wrap(text, w - 4)
  local h = math.min(UI.h - 2, #lines + 4)
  local x = math.floor((UI.w - w) / 2) + 1
  local y = math.floor((UI.h - h) / 2) + 1
  UI.beginFrame()
  UI.fill(x, y, w, h, C.bg)
  UI.frame(x, y, w, h, title, colour or C.accent)
  for i = 1, math.min(#lines, h - 3) do
    UI.write(x + 2, y + i, lines[i], C.text)
  end
  UI.write(x + 2, y + h - 2, "press any key", C.faint)
  UI.endFrame()
  UI.read()
end

function UI.confirm(title, text, yesLabel, noLabel)
  local items = {
    { label = yesLabel or "yes", key = "y", value = true },
    { label = noLabel or "no", key = "n", value = false },
  }
  local w = math.min(UI.w - 4, 42)
  local lines = U.wrap(text, w - 4)
  local sel = 2
  local h = #lines + 6
  local x = math.floor((UI.w - w) / 2) + 1
  local y = math.floor((UI.h - h) / 2) + 1
  local spins = 0
  while true do
    spins = spins + 1
    if spins > 4000 then return false end
    UI.beginFrame()
    UI.fill(x, y, w, h, C.bg)
    UI.frame(x, y, w, h, title, C.warn)
    for i = 1, #lines do UI.write(x + 2, y + i, lines[i], C.text) end
    UI.drawMenu(x + 2, y + #lines + 2, w - 5, 2, items, sel, 0)
    UI.endFrame()
    local ev = UI.read()
    if ev.kind == "key" then
      if ev.name == "up" or ev.name == "down" then sel = 3 - sel
      elseif ev.name == "enter" then return items[sel].value
      elseif ev.name == "back" then return false end
    elseif ev.kind == "char" then
      if ev.char == "y" then return true end
      if ev.char == "n" or ev.char == "q" then return false end
    elseif ev.kind == "click" then
      local idx = ev.y - (y + #lines + 1)
      if idx == 1 or idx == 2 then return items[idx].value end
    end
  end
end

--------------------------------------------------------------------- body art

-- limb code -> figure cells. l/r are arms, L/R legs.
local FIGURE = {
  "    hhh    ",
  "    hhh    ",
  " ll ttt rr ",
  " ll ttt rr ",
  " ll ttt rr ",
  "    aaa    ",
  "   LL RR   ",
  "   LL RR   ",
  "   LL RR   ",
}
UI.FIGW, UI.FIGH = 11, 9

local CODE2LIMB = {
  h = "head", t = "thorax", a = "abdomen",
  l = "larm", r = "rarm", L = "lleg", R = "rleg",
}

-- anchor cell for status glyphs, in figure-local coordinates
local ANCHOR = {
  head    = { 6, 1 }, thorax  = { 6, 3 }, abdomen = { 6, 6 },
  larm    = { 2, 3 }, rarm    = { 10, 3 },
  lleg    = { 4, 7 }, rleg    = { 7, 7 },
}
UI.limbAnchor = ANCHOR

-- Draws the figure. colourFn(limbId) -> bgColour. glyphFn(limbId) -> {char, fg} list
function UI.figure(x, y, colourFn, glyphFn, highlight)
  for row = 1, UI.FIGH do
    local line = FIGURE[row]
    for col = 1, UI.FIGW do
      local ch = string.sub(line, col, col)
      local limb = CODE2LIMB[ch]
      if limb then
        local bg = colourFn(limb) or C.panel
        local fg = C.bg
        local body = " "
        if highlight == limb then
          fg = C.text
          body = ":"
        end
        UI.write(x + col - 1, y + row - 1, body, fg, bg)
      end
    end
  end
  if glyphFn then
    for limb, pos in pairs(ANCHOR) do
      local marks = glyphFn(limb)
      if marks and #marks > 0 then
        local bg = colourFn(limb) or C.panel
        for i = 1, math.min(#marks, 3) do
          local gx = x + pos[1] - 1 + (i - 2)
          if limb == "larm" then gx = x + pos[1] - 1 + (i - 1) end
          if limb == "rarm" then gx = x + pos[1] - 1 - (i - 1) end
          UI.write(gx, y + pos[2] - 1 + math.floor((i - 1) / 3), marks[i][1], marks[i][2], bg)
        end
      end
    end
  end
end

--------------------------------------------------------------------- skill check

-- A moving marker crosses a track; the player locks it with space.
-- steadiness 0..1 sets the target width. Returns true on success, plus
-- how far off the marker landed (0 = perfect).
function UI.steadyCheck(title, prompt, steadiness, opts)
  opts = opts or {}
  steadiness = U.clamp(steadiness, 0.03, 1)
  if UI.headless then
    local ok = math.random() < (0.25 + 0.7 * steadiness)
    return ok, ok and 0 or 1
  end
  local w = math.min(UI.w - 6, 40)
  local track = w - 4
  local zone = math.max(1, math.floor(track * (0.06 + 0.42 * steadiness)))
  local zoneStart = math.random(1, math.max(1, track - zone + 1))
  local speed = U.lerp(0.10, 0.035, steadiness)   -- seconds per step
  local pos, dir = 1, 1
  local h = 9
  local x = math.floor((UI.w - w) / 2) + 1
  local y = math.floor((UI.h - h) / 2) + 1
  local lines = U.wrap(prompt, w - 4)
  local timer = os.startTimer(speed)
  while true do
    UI.beginFrame()
    UI.fill(x, y, w, h, C.bg)
    UI.frame(x, y, w, h, title, C.accent)
    for i = 1, math.min(#lines, 3) do UI.write(x + 2, y + i, lines[i], C.text) end
    local ty = y + h - 4
    -- track
    UI.fill(x + 2, ty, track, 1, C.panel)
    UI.fill(x + 2 + zoneStart - 1, ty, zone, 1, opts.zoneColour or C.ok)
    UI.write(x + 2 + pos - 1, ty, "|", C.text, (pos >= zoneStart and pos < zoneStart + zone)
      and (opts.zoneColour or C.ok) or C.panel)
    UI.write(x + 2, y + h - 2, "space to commit   q abort", C.faint)
    UI.endFrame()
    local ev = { os.pullEvent() }
    if ev[1] == "timer" and ev[2] == timer then
      pos = pos + dir
      if pos >= track then pos, dir = track, -1 end
      if pos <= 1 then pos, dir = 1, 1 end
      timer = os.startTimer(speed)
    elseif ev[1] == "key" then
      local n = keyname(ev[2])
      if n == "space" or n == "enter" then
        local hit = (pos >= zoneStart and pos < zoneStart + zone)
        local off = 0
        if not hit then
          off = math.min(math.abs(pos - zoneStart), math.abs(pos - (zoneStart + zone - 1))) / track
        end
        return hit, off
      elseif n == "back" then
        return nil, 0
      end
    elseif ev[1] == "char" and string.lower(ev[2]) == "q" then
      return nil, 0
    end
  end
end

--------------------------------------------------------------------- sound

local NOTES = { harp = "harp", bass = "bass", snare = "snare", hat = "hat",
  bell = "bell", pling = "pling", didgeridoo = "didgeridoo", basedrum = "basedrum" }

function UI.note(inst, pitch, vol)
  if not UI.speaker then return end
  pcall(UI.speaker.playNote, NOTES[inst] or "harp", vol or 1, pitch or 12)
end

local SFX = {
  select    = { { "hat", 8, 0.35 } },
  confirm   = { { "pling", 14, 0.5 } },
  deny      = { { "bass", 2, 0.6 } },
  hurt      = { { "basedrum", 1, 1 }, { "snare", 4, 0.7 } },
  crack     = { { "snare", 0, 1 }, { "basedrum", 3, 1 } },
  heal      = { { "bell", 16, 0.5 }, { "bell", 20, 0.4 } },
  alarm     = { { "pling", 22, 1 }, { "pling", 18, 1 } },
  descend   = { { "didgeridoo", 2, 1 }, { "bass", 0, 1 } },
  loot      = { { "pling", 10, 0.5 }, { "pling", 17, 0.5 } },
  death     = { { "bass", 6, 1 }, { "bass", 3, 1 }, { "bass", 0, 1 } },
  beat      = { { "basedrum", 6, 0.4 } },

  jump      = { { "hat", 12, 0.4 } },
  land      = { { "basedrum", 4, 0.6 } },
  landhard  = { { "basedrum", 0, 1 }, { "snare", 2, 0.9 } },
  slide     = { { "hat", 3, 0.5 }, { "snare", 1, 0.3 } },
  mine      = { { "basedrum", 8, 0.7 }, { "hat", 5, 0.35 } },
  breakout  = { { "snare", 6, 0.8 }, { "bass", 9, 0.6 } },
  bitten    = { { "snare", 2, 1 }, { "basedrum", 0, 1 }, { "bass", 1, 0.9 } },
  clawed    = { { "snare", 5, 1 }, { "bass", 3, 0.8 } },
  swing     = { { "hat", 9, 0.5 } },
  miss      = { { "hat", 2, 0.3 } },
  kill      = { { "bass", 5, 0.8 }, { "bell", 12, 0.5 } },
  bleedbad  = { { "bass", 0, 0.7 }, { "bass", 0, 0.5 } },
  drug      = { { "bell", 22, 0.4 }, { "bell", 24, 0.3 } },
  overdose  = { { "bass", 8, 1 }, { "bass", 4, 1 }, { "bass", 1, 1 } },
  step      = { { "hat", 6, 0.15 } },
}

function UI.sfx(name)
  local seq = SFX[name]
  if not seq or not UI.speaker then return end
  for i = 1, #seq do
    pcall(UI.speaker.playNote, seq[i][1], seq[i][3], seq[i][2])
  end
end

CU.ui = UI
return UI

end
