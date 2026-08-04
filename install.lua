-- WRITE-OFF installer
--
-- Put this on pastebin once. After that, updating the game is just running it
-- again. It reads a manifest from wherever you are hosting the files and pulls
-- down everything listed in it, so adding new modules later needs no change here.
--
--   pastebin get <code> wget-writeoff
--   wget-writeoff
--
-- Usage:
--   wget-writeoff              install or update, then offer to play
--   wget-writeoff update       install or update and stop
--   wget-writeoff check        list what would change, write nothing

--------------------------------------------------------------------- config

-- Where the files live. Must end in a slash. For a GitHub repo this is the raw
-- URL of the folder holding writeoff.lua, manifest.txt and lib/.
--
--   https://raw.githubusercontent.com/<user>/<repo>/main/
--
-- You do not have to edit this. Pass the URL once and it is remembered:
--
--   wget-writeoff https://raw.githubusercontent.com/you/writeoff/main/
--
local DEFAULT_BASE = "https://raw.githubusercontent.com/CHANGE-ME/writeoff/main/"

local DEST = "/writeoff"
local SAVES = "/writeoff-data"
local SOURCE_FILE = "/writeoff-source.txt"

local BASE          -- resolved below, before anything is fetched

-- If the manifest cannot be fetched, fall back to this list.
local FALLBACK = {
  "writeoff.lua",
  "lib/util.lua", "lib/ui.lua", "lib/data.lua", "lib/tiles.lua", "lib/body.lua",
  "lib/fall.lua", "lib/inv.lua", "lib/mapgen.lua", "lib/phys.lua", "lib/render.lua",
  "lib/combat.lua", "lib/run.lua", "lib/screens.lua", "lib/save.lua",
}

--------------------------------------------------------------------- plumbing

local args = { ... }

local mode, given = "install", nil
for _, a in ipairs(args) do
  local s = tostring(a)
  if s:match("^https?://") then
    given = s
    if given:sub(-1) ~= "/" then given = given .. "/" end
  else
    mode = s:lower()
  end
end

local function colour(c)
  if term.isColour and term.isColour() then term.setTextColour(c) end
end

local function say(text, c)
  colour(c or colours.white)
  print(text)
  colour(colours.white)
end

local function fetch(path)
  local url = BASE .. path
  local ok, handle = pcall(http.get, url)
  if not ok or not handle then return nil, "could not reach " .. url end
  local body = handle.readAll()
  handle.close()
  if not body or #body == 0 then return nil, "empty response for " .. path end
  return body
end

local function readLocal(path)
  if not fs.exists(path) then return nil end
  local f = fs.open(path, "r")
  if not f then return nil end
  local body = f.readAll()
  f.close()
  return body
end

local function writeLocal(path, body)
  local dir = fs.getDir(path)
  if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
  local f = fs.open(path, "w")
  if not f then return false end
  f.write(body)
  f.close()
  return true
end

local function parseManifest(text)
  local list = {}
  for line in (text .. "\n"):gmatch("(.-)\r?\n") do
    line = line:match("^%s*(.-)%s*$")
    if line ~= "" and line:sub(1, 1) ~= "#" then list[#list + 1] = line end
  end
  return list
end

--------------------------------------------------------------------- checks

local function readLocalRaw(path)
  if not fs.exists(path) then return nil end
  local f = fs.open(path, "r")
  if not f then return nil end
  local body = f.readAll()
  f.close()
  return body
end

-- given on the command line, then remembered from last time, then the default
BASE = given
if not BASE then
  local saved = readLocalRaw(SOURCE_FILE)
  if saved then BASE = saved:match("^%s*(.-)%s*$") end
end
if not BASE or BASE == "" then BASE = DEFAULT_BASE end
if BASE:sub(-1) ~= "/" then BASE = BASE .. "/" end

if not http then
  say("This computer has no HTTP access.", colours.red)
  say("Enable it in the ComputerCraft config, or use the offline bundle.")
  return
end

if BASE:find("CHANGE%-ME") then
  say("The installer has not been pointed at anything yet.", colours.red)
  print("")
  say("Give it the raw URL of the folder holding writeoff.lua,")
  say("manifest.txt and lib/. It will remember it. For GitHub:")
  print("")
  say("  wget-writeoff https://raw.githubusercontent.com/you/writeoff/main/",
    colours.yellow)
  print("")
  return
end

--------------------------------------------------------------------- go

say("WRITE-OFF installer", colours.yellow)
say("source: " .. BASE, colours.lightGrey)
print("")

local files
local manifest = fetch("manifest.txt")
if manifest then
  files = parseManifest(manifest)
  say("manifest lists " .. #files .. " files", colours.lightGrey)
else
  files = FALLBACK
  say("no manifest, using the built in list of " .. #files, colours.lightGrey)
end

local fetched, changed, unchanged, failed = {}, 0, 0, {}

for i, path in ipairs(files) do
  term.write("  " .. path .. " ")
  local body, err = fetch(path)
  if not body then
    say("failed", colours.red)
    failed[#failed + 1] = path .. ": " .. tostring(err)
  else
    local old = readLocal(DEST .. "/" .. path)
    if old == body then
      unchanged = unchanged + 1
      say("unchanged", colours.grey)
    else
      changed = changed + 1
      say(old and "updated" or "new", old and colours.yellow or colours.lime)
    end
    fetched[path] = body
  end
end

print("")

if #failed > 0 then
  say(#failed .. " file" .. (#failed == 1 and "" or "s") .. " could not be fetched:",
    colours.red)
  for _, f in ipairs(failed) do say("  " .. f, colours.red) end
  say("Nothing has been written. Fix the source and run again.", colours.red)
  return
end

if mode == "check" then
  say(changed .. " would change, " .. unchanged .. " already current.", colours.yellow)
  return
end

if changed == 0 then
  say("Already up to date.", colours.lime)
else
  -- everything downloaded cleanly, so it is safe to write
  local wrote = 0
  for _, path in ipairs(files) do
    if writeLocal(DEST .. "/" .. path, fetched[path]) then
      wrote = wrote + 1
    else
      say("could not write " .. path, colours.red)
    end
  end
  say("Wrote " .. wrote .. " files to " .. DEST, colours.lime)
end

do
  local f = fs.open(SOURCE_FILE, "w")
  if f then f.write(BASE); f.close() end
end

if fs.exists(SAVES) then
  say("Your ledger and any saved run in " .. SAVES .. " were left alone.",
    colours.lightGrey)
end

print("")
say("Run it with:  " .. DEST .. "/writeoff", colours.yellow)

if mode ~= "update" and shell then
  print("")
  write("Play now? (y/n) ")
  while true do
    local _, key = os.pullEvent("char")
    if key == "y" or key == "Y" then
      print("")
      shell.run(DEST .. "/writeoff")
      return
    elseif key == "n" or key == "N" then
      print("")
      return
    end
  end
end
