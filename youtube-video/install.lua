local base = "https://raw.githubusercontent.com/Chazammm/atm10-cc-doom/main/youtube-video/"
local files = {
  ["player.lua"] = "/video.lua",
  ["monitorinfo.lua"] = "/videoinfo.lua",
  ["lib/32vid-player-mini.lua"] = "/video-lib/32vid-player-mini.lua",
}

if not http then error("HTTP API is disabled on this server.") end
if not fs.exists("/video-lib") then fs.makeDir("/video-lib") end

for remote, localPath in pairs(files) do
  print("Installing " .. localPath)
  local h, err = http.get(base .. remote)
  if not h then error(err or ("Failed to download " .. remote)) end
  local data = h.readAll()
  h.close()

  local f = fs.open(localPath, "w")
  f.write(data)
  f.close()
end

print("")
print("Installed.")
print("Run: videoinfo")
print("Then: video <direct .32vid URL>")
