-- WRITE-OFF / lib/render.lua
-- Draws the map. Rock is a filled block, not a hash, so the cave reads at a glance.

return function(CU)

local U = CU.util
local D = CU.data
local Tl = CU.tiles
local M = CU.mapgen
local UI = CU.ui
local R = {}

--------------------------------------------------------------------- blit codes

local HEX = {
  [colors.white] = "0", [colors.orange] = "1", [colors.magenta] = "2",
  [colors.lightBlue] = "3", [colors.yellow] = "4", [colors.lime] = "5",
  [colors.pink] = "6", [colors.gray] = "7", [colors.lightGray] = "8",
  [colors.cyan] = "9", [colors.purple] = "a", [colors.blue] = "b",
  [colors.brown] = "c", [colors.green] = "d", [colors.red] = "e",
  [colors.black] = "f",
}
local function hex(c) return HEX[c] or "0" end
R.hex = hex

--------------------------------------------------------------------- tile looks

-- glyph, foreground, background
local function look(glyph, fg, bg) return { glyph, fg, bg } end

local BLOOD_GLYPH = { [1] = ".", [2] = ",", [3] = ":" }

local LIT = {
  [" "] = look(" ", colors.black,     colors.black),
  ["#"] = look(" ", colors.gray,      colors.gray),
  ["%"] = look(".", colors.lightGray, colors.brown),
  ["o"] = look(".", colors.lightGray, colors.gray),
  ["^"] = look("^", colors.orange,    colors.gray),
  ['"'] = look(",", colors.lime,      colors.green),
  ["~"] = look("~", colors.lightBlue, colors.blue),
  ["="] = look("=", colors.brown,     colors.black),
  ["|"] = look("|", colors.brown,     colors.black),
  ["H"] = look("H", colors.lightGray, colors.black),
  ["+"] = look("+", colors.lightGray, colors.black),

  -- the way down and the way out, marked so you cannot miss them
  ["V"] = look("v", colors.white,     colors.cyan),
  ["A"] = look("^", colors.black,     colors.yellow),

  -- containers are solid blocks of colour, not letters
  ["c"] = look("=", colors.white,     colors.brown),      -- crate
  ["l"] = look("|", colors.black,     colors.lightGray),  -- locker
  ["t"] = look("=", colors.black,     colors.cyan),       -- tool chest
  ["m"] = look("+", colors.white,     colors.red),        -- med box
  ["b"] = look("x", colors.white,     colors.purple),     -- body
  ["d"] = look(",", colors.lightGray, colors.black),      -- debris
  ["g"] = look("*", colors.lime,      colors.green),      -- growth
  ["h"] = look("#", colors.black,     colors.yellow),     -- sealed cache

  -- traps. the impaler only shows its warning light when you are close enough
  -- to see it, and it blinks, so it is easy to miss and easy to regret.
  ["I"] = look(" ", colors.black,     colors.black),
  ["J"] = look("^", colors.black,     colors.lightGray),
  ["K"] = look("v", colors.white,     colors.gray),

  -- pods
  ["B"] = look(" ", colors.lightGray, colors.lightGray),  -- hull
  ["D"] = look("]", colors.yellow,    colors.gray),       -- door
  ["T"] = look(" ", colors.black,     colors.black),      -- a person stands here
  ["Z"] = look("z", colors.white,     colors.blue),       -- thermostat
  ["Y"] = look("=", colors.white,     colors.lightBlue),  -- shower

  -- fixtures
  ["W"] = look("=", colors.white,     colors.brown),      -- workbench
  ["C"] = look("!", colors.yellow,    colors.blue),       -- charge post
  ["P"] = look("=", colors.lightBlue, colors.white),      -- life pod
  ["S"] = look("~", colors.white,     colors.lightBlue),  -- spring
  ["F"] = look("^", colors.red,       colors.orange),     -- heater
  ["X"] = look("#", colors.black,     colors.yellow),     -- the cargo
  ["n"] = look("=", colors.black,     colors.white),      -- paper
}

-- Remembered, but out of the light. Shapes stay, fills go, so lit and unlit
-- never look the same.
local DIM_GLYPH = {
  ["#"] = ":", ["%"] = ":", ["o"] = ":", ["^"] = "^", ['"'] = ",", ["~"] = "~",
  ["c"] = "o", ["l"] = "o", ["t"] = "o", ["m"] = "+", ["b"] = "x", ["d"] = ",",
  ["g"] = "*", ["h"] = "o",
  ["W"] = "=", ["C"] = "=", ["P"] = "o", ["S"] = "~", ["F"] = "=", ["X"] = "#",
  ["n"] = "=", ["V"] = "v", ["A"] = "^",
  ["B"] = "#", ["D"] = "]", ["T"] = "&", ["Z"] = "z", ["Y"] = "=",
  ["I"] = " ", ["J"] = "^", ["K"] = "v",
}
local DIM = {}
for ch, l in pairs(LIT) do
  DIM[ch] = look(DIM_GLYPH[ch] or l[1], colors.gray, colors.black)
end
DIM[" "] = look(" ", colors.black, colors.black)
DIM["V"] = look("v", colors.cyan, colors.black)
DIM["A"] = look("^", colors.yellow, colors.black)
DIM["m"] = look("+", colors.red, colors.black)
DIM["T"] = look(" ", colors.black, colors.black)
DIM["D"] = look("]", colors.yellow, colors.black)

R.LIT, R.DIM = LIT, DIM

--------------------------------------------------------------------- creatures

local CREATURE_GLYPH = {
  shalecrawler = { "s", colors.lightGray },
  grit_tick    = { "t", colors.brown },
  bloat_tick   = { "T", colors.brown },
  wallgnaw     = { "w", colors.orange },
  barrowback   = { "B", colors.red },
  elder_barrowback = { "B", colors.magenta },
  rimestrider  = { "r", colors.lightBlue },
  palefly      = { "f", colors.white },
  facet        = { "F", colors.cyan },
  cinderling   = { "c", colors.orange },
  meter_reader = { "R", colors.yellow },
}
R.CREATURE_GLYPH = CREATURE_GLYPH

--------------------------------------------------------------------- viewport

function R.camera(g, vw, vh)
  local map = g.map
  local cx = U.clamp(g.x - math.floor(vw / 2), 1, math.max(1, map.w - vw + 1))
  -- centre on the chest, not the feet, so the figure sits in the middle
  local cy = U.clamp((g.y - 1) - math.floor(vh / 2), 1, math.max(1, map.h - vh + 1))
  return cx, cy
end

--[[
  The player is drawn as the same figure as the medical screen: head, two arms,
  two legs, each cell coloured by the condition of that limb. A healthy scavenger
  is green all over. A bad landing turns the legs orange and then red, and you can
  read your own state off the map without opening anything.

  Physically the body is one tile wide and two tall. The arms and legs stick out
  into neighbouring cells and are simply not drawn when there is rock there, which
  is also what pressing against a wall looks like.
]]
local FIGURE = {
  { dx =  0, dy = -2, limb = "head",    glyph = "o" },
  { dx = -1, dy = -1, limb = "larm",    glyph = "/" },
  { dx =  0, dy = -1, limb = "thorax",  glyph = "|" },
  { dx =  1, dy = -1, limb = "rarm",    glyph = "\\" },
  { dx = -1, dy =  0, limb = "lleg",    glyph = "/" },
  { dx =  1, dy =  0, limb = "rleg",    glyph = "\\" },
}

-- Lays a three by three figure into `cells`, anchored at the feet. Limb cells
-- that would sit inside rock are skipped, which is also what pressing against
-- a wall looks like.
function R.addFigure(cells, map, fx, fy, colourFor)
  local legsShown = 0
  for _, part in ipairs(FIGURE) do
    local x, y = fx + part.dx, fy + part.dy
    if Tl.passable(M.get(map, x, y)) or part.dx == 0 then
      cells[x .. "," .. y] = { glyph = part.glyph, colour = colourFor(part.limb) }
      if part.limb == "lleg" or part.limb == "rleg" then legsShown = legsShown + 1 end
    end
  end
  if legsShown == 0 then
    cells[fx .. "," .. fy] = { glyph = "|", colour = colourFor("lleg") }
  end
  return cells
end

local HUE = {
  white = colors.white, yellow = colors.yellow, red = colors.red,
  green = colors.lime, lightBlue = colors.lightBlue, purple = colors.magenta,
  orange = colors.orange, cyan = colors.cyan,
}

-- Everything person shaped on the map: you, the traders in their pods, and
-- anything hostile that walks upright.
function R.figureCells(g)
  local map = g.map
  local S = CU.screens
  local cells = {}

  for _, pod in ipairs(map.pods or {}) do
    local t = pod.trader
    if t and not t.hostile and pod.traderX then
      local def = D.trader(t.id)
      local col = HUE[def.hue or "white"] or colors.white
      R.addFigure(cells, map, pod.traderX, pod.y2 - 1, function() return col end)
    end
  end

  for _, e in ipairs(map.entities) do
    local def = D.CREATURES[e.id]
    if def and def.humanoid and not e.dead then
      local col = HUE[def.hue or "red"] or colors.red
      R.addFigure(cells, map, e.x, e.y, function() return col end)
    end
  end

  R.addFigure(cells, map, g.x, g.y, function(limb)
    return S and S.limbColour(g.body, limb) or colors.lime
  end)
  return cells
end

-- Draws the map into the region (x, y, w, h) of the current frame.
function R.drawMap(g, x, y, w, h)
  local map = g.map
  local cx, cy = R.camera(g, w, h)
  g.camX, g.camY = cx, cy

  local lr = g.lightR or 4
  local lrv = g.lightRv or 3
  local px, py = g.x, g.y - 1
  local figure = R.figureCells(g)
  local blink = (g.blink or 0) % 2 == 0
  local pod = M.podAt(map, g.x, g.y)      -- a pod you are inside is lit throughout

  -- entity lookup for this frame
  local ents = {}
  for _, e in ipairs(map.entities) do
    if not e.dead then ents[e.x .. "," .. e.y] = e end
  end

  for row = 0, h - 1 do
    local my = cy + row
    local text, fg, bg = {}, {}, {}
    local seenRow = map.seen[my]
    local mapRow = (my >= 1 and my <= map.h) and map.rows[my] or nil
    for col = 0, w - 1 do
      local mx = cx + col
      local glyph, f, b = " ", colors.black, colors.black
      if mapRow and mx >= 1 and mx <= map.w then
        local ch = mapRow:sub(mx, mx)
        local dx, dy = mx - px, my - py
        local lit = (dx * dx) + (dy * 2.1) * (dy * 2.1) <= lr * lr
        if pod and mx >= pod.x1 and mx <= pod.x2 and my >= pod.y1 and my <= pod.y2 then
          lit = true
        end
        local wasSeen = seenRow and seenRow[mx]
        if lit then
          local l = LIT[ch] or LIT[" "]
          glyph, f, b = l[1], l[2], l[3]
        elseif wasSeen then
          local l = DIM[ch] or DIM[" "]
          glyph, f, b = l[1], l[2], l[3]
        end
        -- the impaler gives itself away with a light, two tiles out, blinking
        if ch == "I" then
          local near = math.abs(mx - px) <= 2 and math.abs(my - py) <= 2
          if near and blink then
            glyph, f, b = "*", colors.red, colors.black
          elseif near then
            glyph, f, b = ".", colors.gray, colors.black
          else
            glyph, f, b = " ", colors.black, colors.black
          end
        end

        if lit or wasSeen then
          -- blood you have left behind, and cracks in anything you are mining
          local td = Tl.get(ch)
          local bareGround = Tl.passable(ch) and not (td.prop or td.fixture
                              or td.shaft or td.hatch or td.climb)
          local bl = M.bloodAt(map, mx, my)
          if bl > 0 and bareGround then
            if bl >= 4 then
              glyph, f, b = " ", colors.red, colors.red
            else
              glyph = BLOOD_GLYPH[math.floor(bl)] or "."
              f = lit and colors.red or colors.gray
            end
          end
          local dug = M.digAt(map, mx, my)
          if dug > 0 then
            local total = Tl.digCost(ch) or 100
            local frac = dug / total
            glyph = frac > 0.66 and "x" or (frac > 0.33 and "," or ".")
            f = colors.lightGray
          end
        end

        local e = ents[mx .. "," .. my]
        if e and (lit or wasSeen) then
          local cdef = D.CREATURES[e.id]
          if not (cdef and cdef.humanoid) then
            local cg = CREATURE_GLYPH[e.id] or { "?", colors.red }
            glyph = cg[1]
            f = lit and cg[2] or colors.gray
          end
        end
        local fig = figure[mx .. "," .. my]
        if fig then
          glyph = fig.glyph
          f = fig.colour
        end
      end
      text[#text + 1] = glyph
      fg[#fg + 1] = hex(f)
      bg[#bg + 1] = hex(b)
    end
    UI.blitLine(x, y + row, table.concat(text), table.concat(fg), table.concat(bg))
  end

  -- mark the edges beside the player so a drop is never a surprise
  R.drawEdgeMarks(g, x, y, w, h, cx, cy)
end

function R.drawEdgeMarks(g, x, y, w, h, cx, cy)
  local P = CU.phys
  for _, dx in ipairs({ -1, 1 }) do
    local pv = P.edgePreview(g, dx)
    if pv.kind == "drop" then
      local sx = x + (g.x + dx - cx)
      local sy = y + (g.y + 1 - cy)
      if sx >= x and sx < x + w and sy >= y and sy < y + h then
        local col = UI.c.ok
        if pv.effective >= 3 then col = UI.c.warn end
        if pv.effective >= 30 then col = UI.c.crit end
        UI.write(sx, sy, "v", col)
      end
    end
  end
end

CU.render = R
return R

end
