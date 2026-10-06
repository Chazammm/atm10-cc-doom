-- Stress-test the exact current renderer at the vanilla-CC practical ceiling.
-- We reuse the V2 frames but present them at 20 FPS with audio muted. Since
-- these source frames are 100 ms apart, this is actually a conservative render
-- test: a true 20 FPS encode will usually change fewer pixels between frames.
local url = "https://github.com/Chazammm/atm10-cc-doom/releases/download/agartha-v2/agartha-v2-part01.32vid"

local keys = {
  "musicvideo.stats",
  "musicvideo.drop_late_frames",
  "musicvideo.drop_factor",
  "musicvideo.diff_rows",
  "musicvideo.fps_override",
  "musicvideo.mute",
}
local old = {}
for _, k in ipairs(keys) do old[k] = settings.get(k) end

settings.set("musicvideo.stats", true)
settings.set("musicvideo.drop_late_frames", true)
settings.set("musicvideo.drop_factor", 1.0)
settings.set("musicvideo.diff_rows", true)
settings.set("musicvideo.fps_override", 20)
settings.set("musicvideo.mute", true)

print("20 FPS vanilla-CC stress benchmark")
print("Part 01 will finish in about 50 seconds.")
print("Audio is muted intentionally.")
print("Send me the final stats.")
print("")

local ok, err = pcall(function()
  shell.run("/video.lua", url)
end)

for _, k in ipairs(keys) do
  if old[k] == nil then settings.unset(k) else settings.set(k, old[k]) end
end

if not ok then error(err, 0) end
