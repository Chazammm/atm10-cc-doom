-- Show the usable target size for Sanjuuni.
local monitor = peripheral.find("monitor")
if not monitor then error("No monitor found.") end

local scale = tonumber(settings.get("musicvideo.scale")) or 0.5
monitor.setTextScale(scale)
local w, h = monitor.getSize()

print(("Monitor target: %dx%d character cells"):format(w, h))
print(("Text scale: %.1f"):format(scale))
print("")
print("Sanjuuni uses 2x3 image pixels per CC character cell.")
print(("Sanjuuni source size for a full-screen video: %dx%d pixels"):format(w * 2, h * 3))
print("")
print("Recommended Sanjuuni command:")
print(('sanjuuni.exe -i "input.mp4" -3 -d -cans -W%d -H%d -o "musicvideo.32vid"'):format(w * 2, h * 3))
