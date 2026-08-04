-- WRITE-OFF / lib/util.lua
-- Math, string, table and RNG helpers. No dependencies.

return function(CU)

local U = {}

--------------------------------------------------------------------- numbers

function U.clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

function U.round(v, places)
  local m = 10 ^ (places or 0)
  return math.floor(v * m + 0.5) / m
end

function U.lerp(a, b, t) return a + (b - a) * t end

function U.approach(v, target, step)
  if v < target then return math.min(target, v + step) end
  if v > target then return math.max(target, v - step) end
  return v
end

function U.sign(v)
  if v > 0 then return 1 elseif v < 0 then return -1 end
  return 0
end

-- maps v from range [a,b] onto [c,d], clamped
function U.remap(v, a, b, c, d)
  if b == a then return c end
  local t = U.clamp((v - a) / (b - a), 0, 1)
  return c + (d - c) * t
end

--------------------------------------------------------------------- rng
-- Deterministic xorshift-ish generator so a run can be reproduced from a seed.
-- Lua 5.1 has no bitops, so this uses modular arithmetic on doubles.

local Rng = {}
Rng.__index = Rng

function U.newRng(seed)
  local r = setmetatable({}, Rng)
  r.s = math.floor(math.abs(seed or 1)) % 2147483647
  if r.s == 0 then r.s = 12345 end
  for _ = 1, 8 do r:raw() end
  return r
end

function Rng:raw()
  -- Park-Miller minimal standard, kept inside double precision
  self.s = (self.s * 16807) % 2147483647
  return self.s
end

function Rng:float()          return (self:raw() - 1) / 2147483646 end
function Rng:int(a, b)
  if not b then a, b = 1, a end
  if b < a then a, b = b, a end
  return a + math.floor(self:float() * (b - a + 1) - 1e-12)
end
function Rng:range(a, b)      return a + self:float() * (b - a) end
function Rng:chance(p)        return self:float() < p end

function Rng:pick(t)
  if #t == 0 then return nil end
  return t[self:int(1, #t)]
end

-- t = { {w=3, ...}, {w=1, ...} }  or  { {weight=..}, ... }
function Rng:weighted(t)
  local total = 0
  for i = 1, #t do total = total + (t[i].w or t[i].weight or 1) end
  if total <= 0 then return nil end
  local roll = self:float() * total
  for i = 1, #t do
    roll = roll - (t[i].w or t[i].weight or 1)
    if roll <= 0 then return t[i] end
  end
  return t[#t]
end

function Rng:shuffle(t)
  for i = #t, 2, -1 do
    local j = self:int(1, i)
    t[i], t[j] = t[j], t[i]
  end
  return t
end

-- normal-ish distribution via three rolls, mean 0, roughly +/-1
function Rng:bell()
  return (self:float() + self:float() + self:float()) / 1.5 - 1
end

function Rng:vary(base, spread)
  return base + base * spread * self:bell()
end

--------------------------------------------------------------------- strings

function U.pad(s, n, ch)
  s = tostring(s)
  ch = ch or " "
  while #s < n do s = s .. ch end
  return s
end

function U.padl(s, n, ch)
  s = tostring(s)
  ch = ch or " "
  while #s < n do s = ch .. s end
  return s
end

function U.trunc(s, n)
  s = tostring(s)
  if #s <= n then return s end
  if n <= 1 then return string.sub(s, 1, n) end
  return string.sub(s, 1, n - 1) .. "."
end

function U.center(s, n)
  s = U.trunc(s, n)
  local left = math.floor((n - #s) / 2)
  return string.rep(" ", left) .. s .. string.rep(" ", n - #s - left)
end

-- greedy word wrap, returns array of lines
function U.wrap(text, width)
  local out = {}
  if width < 4 then width = 4 end
  for rawline in (tostring(text) .. "\n"):gmatch("([^\n]*)\n") do
    if rawline == "" then
      out[#out + 1] = ""
    else
      local line = ""
      for word in rawline:gmatch("%S+") do
        if line == "" then
          line = word
        elseif #line + 1 + #word <= width then
          line = line .. " " .. word
        else
          out[#out + 1] = line
          line = word
        end
        -- a single word longer than the line gets hard split
        while #line > width do
          out[#out + 1] = string.sub(line, 1, width)
          line = string.sub(line, width + 1)
        end
      end
      out[#out + 1] = line
    end
  end
  -- drop the trailing artefact from the sentinel newline
  if out[#out] == "" and #out > 1 then table.remove(out) end
  return out
end

function U.cap(s)
  s = tostring(s)
  return s:sub(1, 1):upper() .. s:sub(2)
end

function U.fmt1(v) return string.format("%.1f", v) end
function U.fmt2(v) return string.format("%.2f", v) end

-- seconds -> H:MM:SS or MM:SS
function U.clock(sec, forceHours)
  sec = math.max(0, math.floor(sec))
  local h = math.floor(sec / 3600)
  local m = math.floor((sec % 3600) / 60)
  local s = sec % 60
  if h > 0 or forceHours then
    return string.format("%d:%02d:%02d", h, m, s)
  end
  return string.format("%02d:%02d", m, s)
end

-- seconds -> "4m 20s" style, short
function U.dur(sec)
  sec = math.max(0, math.floor(sec))
  if sec < 60 then return sec .. "s" end
  local m = math.floor(sec / 60)
  if m < 60 then
    local r = sec % 60
    if r == 0 then return m .. "m" end
    return m .. "m " .. r .. "s"
  end
  return string.format("%dh %02dm", math.floor(m / 60), m % 60)
end

--------------------------------------------------------------------- tables

function U.copy(t)
  if type(t) ~= "table" then return t end
  local out = {}
  for k, v in pairs(t) do out[k] = U.copy(v) end
  return out
end

function U.merge(base, extra)
  local out = U.copy(base)
  if extra then
    for k, v in pairs(extra) do out[k] = U.copy(v) end
  end
  return out
end

function U.count(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end

function U.keys(t)
  local out = {}
  for k in pairs(t) do out[#out + 1] = k end
  table.sort(out, function(a, b) return tostring(a) < tostring(b) end)
  return out
end

function U.find(list, fn)
  for i = 1, #list do
    if fn(list[i], i) then return list[i], i end
  end
  return nil
end

function U.filter(list, fn)
  local out = {}
  for i = 1, #list do
    if fn(list[i], i) then out[#out + 1] = list[i] end
  end
  return out
end

function U.map(list, fn)
  local out = {}
  for i = 1, #list do out[i] = fn(list[i], i) end
  return out
end

function U.removeValue(list, value)
  for i = #list, 1, -1 do
    if list[i] == value then table.remove(list, i); return true end
  end
  return false
end

function U.contains(list, value)
  for i = 1, #list do if list[i] == value then return true end end
  return false
end

function U.sum(list, key)
  local n = 0
  for i = 1, #list do
    n = n + (key and (list[i][key] or 0) or list[i])
  end
  return n
end

--------------------------------------------------------------------- misc

-- 0..1 -> a short ASCII gauge, used where colour is unavailable
function U.gauge(frac, width)
  frac = U.clamp(frac, 0, 1)
  local filled = math.floor(frac * width + 0.5)
  return string.rep("#", filled) .. string.rep(".", width - filled)
end

function U.plural(n, one, many)
  if n == 1 then return one end
  return many or (one .. "s")
end

function U.ordinal(n)
  local last, last2 = n % 10, n % 100
  if last2 >= 11 and last2 <= 13 then return n .. "th" end
  if last == 1 then return n .. "st" end
  if last == 2 then return n .. "nd" end
  if last == 3 then return n .. "rd" end
  return n .. "th"
end

-- roman numerals for stratum headings
local ROMAN = { {1000,"M"},{900,"CM"},{500,"D"},{400,"CD"},{100,"C"},{90,"XC"},
                {50,"L"},{40,"XL"},{10,"X"},{9,"IX"},{5,"V"},{4,"IV"},{1,"I"} }
function U.roman(n)
  local out = ""
  for i = 1, #ROMAN do
    while n >= ROMAN[i][1] do
      out = out .. ROMAN[i][2]
      n = n - ROMAN[i][1]
    end
  end
  return out
end

CU.util = U
return U

end
