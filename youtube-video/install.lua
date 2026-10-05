local base = "https://raw.githubusercontent.com/Chazammm/atm10-cc-doom/main/youtube-video/"
local files = {
  ["player.lua"] = "/video/player.lua",
  ["monitorinfo.lua"] = "/video/monitorinfo.lua",
  ["lib/32vid-player-mini.lua"] = "/video/32vid-player-mini.lua",
}

if not http then error("HTTP API is disabled on this server.") end
if not fs.exists("/video") then fs.makeDir("/video") end

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

shell.setAlias("video", "/video/player.lua")
shell.setAlias("videoinfo", "/video/monitorinfo.lua")

print("")
print("Installed.")
print("Run: videoinfo")
print("Then: video <direct .32vid URL>")
