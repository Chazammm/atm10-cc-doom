-- CC-Music one-line installer for CC:Tweaked / ATM10 8.2
local BASE = "https://raw.githubusercontent.com/Chazammm/atm10-cc-doom/cc-music-player/cc-music/"
local CACHE = "?v=3.1.0"
local DIR = "/ccmusic"

local function get(url)
  local h, err = http.get(url .. CACHE, { ["Cache-Control"] = "no-cache" }, true)
  if not h then error("Download failed: " .. tostring(err), 0) end
  local data = h.readAll()
  h.close()
  return data
end

if not http then error("HTTP API is disabled in CC:Tweaked.", 0) end
if not fs.exists(DIR) then fs.makeDir(DIR) end

local files = {
  {"player.lua", DIR .. "/player.lua"},
  {"remote.lua", DIR .. "/remote.lua"},
  {"stereosetup.lua", DIR .. "/stereosetup.lua"},
  {"diagnostics.lua", DIR .. "/diagnostics.lua"},
  {"README.md", DIR .. "/README.md"},
}

for i = 1, #files do
  local src, dst = files[i][1], files[i][2]
  write(("Downloading %s ... "):format(src))
  local ok, data = pcall(get, BASE .. src)
  if not ok then print("FAILED"); error(data, 0) end
  local f = assert(fs.open(dst, "wb"))
  f.write(data)
  f.close()
  print("OK")
end

local launcher = [[
local path = "/ccmusic/player.lua"
if not fs.exists(path) then
  printError("CC-Music is not installed. Run the installer again.")
  return
end
shell.run(path, ...)
]]
local f = assert(fs.open("/music.lua", "w"))
f.write(launcher)
f.close()

local stereoLauncher = [[
local path = "/ccmusic/stereosetup.lua"
if not fs.exists(path) then
  printError("CC-Music stereo setup is not installed. Run the installer again.")
  return
end
shell.run(path, ...)
]]
local sf = assert(fs.open("/music-stereo.lua", "w"))
sf.write(stereoLauncher)
sf.close()

local infoLauncher = [[
local path = "/ccmusic/diagnostics.lua"
if not fs.exists(path) then
  printError("CC-Music diagnostics are not installed. Run the installer again.")
  return
end
shell.run(path, ...)
]]
local inf = assert(fs.open("/music-info.lua", "w"))
inf.write(infoLauncher)
inf.close()

print("")
print("CC-Music 3.1 installed.")
print("Run: music")
print("Stereo setup: music-stereo")
print("Diagnostics: music-info")
print("Remote: /ccmusic/remote.lua")
print("Recommended monitor: 8 wide x 5 high at text scale 0.5 (164x67 cells)")
print("Tracks are streamed from your cc-music-library-v1 GitHub release.")
