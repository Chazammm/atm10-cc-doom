-- ATM10 / CC:Tweaked monitor video launcher.
local args = { ... }
local source = args[1] or settings.get("musicvideo.url")
local endMode = args[2]

if not source or source == "" then
  print("Usage: video <URL-or-file.32vid> [keep]")
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
print("Starting optimised 32vid stream...")

local ok, err = xpcall(function()
  term.redirect(monitor)
  monitor.setBackgroundColor(colors.black)
  monitor.setTextColor(colors.white)
  monitor.clear()
  monitor.setCursorPos(1, 1)

  local ran = shell.run("/video-lib/32vid-player-fast.lua", source, endMode or "")
  if not ran then
    print("Fast player failed; trying compatibility player...")
    local fallback = shell.run("/video-lib/32vid-player-mini.lua", source)
    if not fallback then error("Both video players failed.") end
  end
end, debug.traceback)

term.redirect(old)
if not ok then error(err, 0) end
