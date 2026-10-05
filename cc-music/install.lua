-- CC-Music one-line installer for CC:Tweaked / ATM10 8.2
local BASE = "https://raw.githubusercontent.com/Chazammm/atm10-cc-doom/cc-music-player/cc-music/"
local DIR = "/ccmusic"

local function get(url)
  local h, err = http.get(url, nil, true)
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

print("")
print("CC-Music installed.")
print("Run: music")
print("Remote: /ccmusic/remote.lua")
print("Tracks are streamed from Di33le/CC-Music on GitHub.")
