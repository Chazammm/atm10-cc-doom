-- Benchmark the current V2 player on the first Agartha segment.
-- This measures the real ATM10 server/computer/monitor performance before we
-- decide whether a 20 FPS vanilla-CC V3 is feasible.
local url = "https://github.com/Chazammm/atm10-cc-doom/releases/download/agartha-v2/agartha-v2-part01.32vid"

local oldStats = settings.get("musicvideo.stats")
local oldDrop = settings.get("musicvideo.drop_late_frames")
local oldFactor = settings.get("musicvideo.drop_factor")
local oldDiff = settings.get("musicvideo.diff_rows")

settings.set("musicvideo.stats", true)
settings.set("musicvideo.drop_late_frames", true)
settings.set("musicvideo.drop_factor", 1.0)
settings.set("musicvideo.diff_rows", true)

print("Agartha V2 benchmark")
print("Playing part 01 only. Let it finish.")
print("At the end, send me the stats shown on this computer.")
print("")

local ok, err = pcall(function()
  shell.run("/video.lua", url)
end)

if oldStats == nil then settings.unset("musicvideo.stats") else settings.set("musicvideo.stats", oldStats) end
if oldDrop == nil then settings.unset("musicvideo.drop_late_frames") else settings.set("musicvideo.drop_late_frames", oldDrop) end
if oldFactor == nil then settings.unset("musicvideo.drop_factor") else settings.set("musicvideo.drop_factor", oldFactor) end
if oldDiff == nil then settings.unset("musicvideo.diff_rows") else settings.set("musicvideo.diff_rows", oldDiff) end

if not ok then error(err, 0) end
