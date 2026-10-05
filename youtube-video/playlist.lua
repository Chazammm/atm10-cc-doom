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

for i = 1, count do
  local url = base .. prefix .. ("%02d"):format(i) .. ".32vid"
  print(("Playing part %d/%d"):format(i, count))
  local ok = shell.run("/video.lua", url)
  if not ok then error("Playback failed on part " .. i) end
end
