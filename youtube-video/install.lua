local base = "https://raw.githubusercontent.com/Chazammm/atm10-cc-doom/main/youtube-video/"
local files = {
  ["player.lua"] = "/video.lua",
  ["playlist.lua"] = "/playlist.lua",
  ["agartha.lua"] = "/agartha.lua",
  ["monitorinfo.lua"] = "/videoinfo.lua",
  ["lib/32vid-player-mini.lua"] = "/video-lib/32vid-player-mini.lua",
  ["lib/32vid-player-fast.lua"] = "/video-lib/32vid-player-fast.lua",
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

-- Maximum-quality defaults. All can be changed with 'settings set ...'.
settings.set("musicvideo.audio_mode", settings.get("musicvideo.audio_mode") or "passthrough")
settings.set("musicvideo.drop_late_frames", settings.get("musicvideo.drop_late_frames") ~= false)
settings.set("musicvideo.drop_factor", tonumber(settings.get("musicvideo.drop_factor")) or 1.0)
settings.set("musicvideo.diff_rows", settings.get("musicvideo.diff_rows") ~= false)
settings.save()

print("")
print("Installed maximum-quality player.")
print("Run: videoinfo")
print("Run: video <direct .32vid URL>")
print("Run: agartha")
print("Optional diagnostics: settings set musicvideo.stats true")
