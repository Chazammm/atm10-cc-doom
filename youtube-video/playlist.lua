-- Play numbered 32vid files sequentially from one HTTP base URL.
-- Usage: playlist <base-url> [prefix] [count]
local args = { ... }
local base = args[1]
local prefix = args[2] or "agartha-part"
local count = tonumber(args[3]) or 13

if not base or base == "" then
  error("Usage: playlist <base-url> [prefix] [count]")
end
if base:sub(-1) ~= "/" then base = base .. "/" end

local function clearSession()
  settings.unset("musicvideo.session_active")
  settings.unset("musicvideo.session_start")
  settings.unset("musicvideo.session_frame")
end

clearSession()
settings.set("musicvideo.session_active", true)
settings.set("musicvideo.session_frame", 0)

local ok, err = xpcall(function()
  for i = 1, count do
    local url = base .. prefix .. ("%02d"):format(i) .. ".32vid"
    print(("Playing part %d/%d"):format(i, count))
    -- Keep the monitor contents and, more importantly, one global A/V clock
    -- across all parts. Late video frames are dropped rather than letting the
    -- picture drift behind the continuously-buffered audio.
    local ran = shell.run("/video.lua", url, "keep")
    if not ran then error("Playback failed on part " .. i) end
  end
end, debug.traceback)

clearSession()
if not ok then error(err, 0) end
