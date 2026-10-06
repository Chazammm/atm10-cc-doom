-- 60-second V4 direct-cell-optimizer comparison sample.
local base = "https://github.com/Chazammm/atm10-cc-doom/releases/download/agartha-v4-test/"
local api = "https://api.github.com/repos/Chazammm/atm10-cc-doom/releases/tags/agartha-v4-test"
local h, err = http.get(api, {["Accept"]="application/vnd.github+json"})
if not h then
  printError("V4 test release is not uploaded yet: " .. tostring(err))
  return
end
local body = h.readAll()
h.close()
local ok, rel = pcall(textutils.unserializeJSON, body)
if not ok or type(rel) ~= "table" then
  printError("Could not read V4 test release.")
  return
end
print("V4 experiment: 60 seconds, 20 FPS, direct 2x3-cell optimisation.")
print("Compare fine edges, faces, gradients and crawling/noise against V3.")
local oldTouch = settings.get("musicvideo.touch_controls")
settings.set("musicvideo.touch_controls", false)
local okRun = shell.run("/playlist.lua", base, "agartha-v4-test-part", "2")
if oldTouch == nil then settings.unset("musicvideo.touch_controls")
else settings.set("musicvideo.touch_controls", oldTouch) end
if not okRun then error("V4 test playback failed.") end
