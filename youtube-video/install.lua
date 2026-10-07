local base = "https://raw.githubusercontent.com/Chazammm/atm10-cc-doom/main/youtube-video/"
local cacheBust = "?v=20261007-v4-cleanseek"
local files = {
  ["player.lua"] = "/video.lua",
  ["playlist.lua"] = "/playlist.lua",
  ["agartha.lua"] = "/agartha.lua",
  ["agartha-v2.lua"] = "/agartha-v2.lua",
  ["agartha-v3.lua"] = "/agartha-v3.lua",
  ["agartha-v3-player.lua"] = "/agartha-v3-player.lua",
  ["agartha-v4.lua"] = "/agartha-v4.lua",
  ["agartha-v4-player.lua"] = "/agartha-v4-player.lua",
  ["monitorinfo.lua"] = "/videoinfo.lua",
  ["videobench.lua"] = "/videobench.lua",
  ["videobench20.lua"] = "/videobench20.lua",
  ["stereosetup.lua"] = "/stereosetup.lua",
  ["v4test.lua"] = "/v4test.lua",
  ["v4quality.lua"] = "/v4quality.lua",
  ["audiotest.lua"] = "/audiotest.lua",
  ["lib/32vid-player-mini.lua"] = "/video-lib/32vid-player-mini.lua",
  ["lib/32vid-player-fast.lua"] = "/video-lib/32vid-player-fast.lua",
  ["lib/v3-index.lua"] = "/video-lib/v3-index.lua",
  ["lib/v4-index.lua"] = "/video-lib/v4-index.lua",
}

if not http then error("HTTP API is disabled on this server.") end
if not fs.exists("/video-lib") then fs.makeDir("/video-lib") end

for remote, localPath in pairs(files) do
  print("Installing " .. localPath)
  local h, err = http.get(base .. remote .. cacheBust, { ["Cache-Control"] = "no-cache" })
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
settings.set("musicvideo.adaptive_fps", settings.get("musicvideo.adaptive_fps") ~= false)
-- Touch OSD is a core V3/V4 feature. Reset stale 'false' left behind by old
-- V4 quality-test builds.
settings.set("musicvideo.touch_controls", true)
settings.save()

print("")
print("Installed maximum-quality player.")
print("Run: videoinfo")
print("Run: video <direct .32vid URL>")
print("Run: agartha        -- current 4 FPS media")
print("Run: agartha-v2     -- 10 FPS legacy max-quality media")
print("Run: agartha-v3     -- V3.1 touch/prefetch/stereo")
print("Run: agartha-v3 resume -- resume saved position")
print("Run: agartha-v4     -- FINAL direct-cell V4 + Audio Profile A")
print("Run: agartha-v4 resume -- resume V4 saved position")
print("V4 controls: tap monitor once; use the clean progress bar to seek anywhere")
print("Run: videobench     -- normal V2 benchmark")
print("Run: videobench20   -- 20 FPS ceiling stress test")
print("Run: stereosetup    -- optional true stereo with 2 speakers")
print("Run: v4test         -- 60s experimental image-quality sample")
print("Run: v4quality      -- clean V4 quality-test command")
print("Run: audiotest a/b/c -- compare three DFPWM audio profiles")
print("Optional diagnostics: settings set musicvideo.stats true")
