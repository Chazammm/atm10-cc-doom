-- ATM10 / CC:Tweaked monitor video launcher
-- Streams a Sanjuuni .32vid file to an Advanced Monitor and CC:Tweaked speaker.
local args = { ... }
local source = args[1] or settings.get("musicvideo.url")

if not source or source == "" then
  print("Usage: video <URL-or-file.32vid>")
  print("Or: settings set musicvideo.url <URL>")
  return
end

local monitor = peripheral.find("monitor")
if not monitor then error("No monitor found. Connect an Advanced Monitor to this computer.") end

local speaker = peripheral.find("speaker")
if not speaker then error("No speaker found. Connect a CC:Tweaked Speaker.") end

local scale = tonumber(settings.get("musicvideo.scale")) or 0.5
monitor.setTextScale(scale)
local w, h = monitor.getSize()

local old = term.current()
print(("Monitor ready: %dx%d chars @ scale %.1f"):format(w, h, scale))
print("Starting 32vid stream...")

local function cleanup()
  term.redirect(old)
end

local ok, err = xpcall(function()
  term.redirect(monitor)
  monitor.setBackgroundColor(colors.black)
  monitor.setTextColor(colors.white)
  monitor.clear()
  monitor.setCursorPos(1, 1)

  local ran = shell.run("/video-lib/32vid-player-mini.lua", source)
  if not ran then error("32vid player exited with an error.") end
end, debug.traceback)

cleanup()
if not ok then
  printError(err)
end
