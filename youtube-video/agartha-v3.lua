-- Agartha V3: 20 FPS / 164x67 / optional true stereo.
local base = settings.get("agartha.v3_base_url")
  or "https://github.com/Chazammm/atm10-cc-doom/releases/download/agartha-v3/"

local monitor = peripheral.find("monitor")
if not monitor then error("No monitor found.") end
monitor.setTextScale(0.5)
local w, h = monitor.getSize()
if w ~= 164 or h ~= 67 then
  printError(("Agartha V3 is encoded for a 164x67 monitor, but this monitor is %dx%d."):format(w, h))
  print("Use an 8-wide x 5-high Advanced Monitor wall at text scale 0.5.")
  return
end

local api = "https://api.github.com/repos/Chazammm/atm10-cc-doom/releases/tags/agartha-v3"
local response, err = http.get(api, {
  ["Accept"] = "application/vnd.github+json",
  ["X-GitHub-Api-Version"] = "2022-11-28",
})
if not response then
  printError("Agartha V3 release is not available yet: " .. tostring(err))
  return
end

local body = response.readAll()
response.close()
local ok, release = pcall(textutils.unserializeJSON, body)
if not ok or type(release) ~= "table" or type(release.assets) ~= "table" then
  printError("Could not read the Agartha V3 GitHub release.")
  return
end

local present, count, maxPart = {}, 0, 0
for _, asset in ipairs(release.assets) do
  if asset.state == "uploaded" and type(asset.name) == "string" then
    local n = tonumber(asset.name:match("^agartha%-v3%-part(%d+)%.32vid$"))
    if n then
      if not present[n] then count = count + 1 end
      present[n] = true
      if n > maxPart then maxPart = n end
    end
  end
end

if count == 0 then
  printError("Agartha V3 media has not been uploaded yet.")
  return
end
for i = 1, maxPart do
  if not present[i] then
    printError(("Agartha V3 upload is incomplete: missing part %02d."):format(i))
    print(("Currently %d part(s) are ready."):format(count))
    return
  end
end

local left = settings.get("musicvideo.left_speaker")
local right = settings.get("musicvideo.right_speaker")
if left and right and peripheral.isPresent(left) and peripheral.isPresent(right) then
  print(("Agartha V3: %d parts | 20 FPS | stereo"):format(maxPart))
else
  print(("Agartha V3: %d parts | 20 FPS | mono fallback"):format(maxPart))
  print("For true stereo connect two speakers and run: stereosetup")
end

shell.run("/playlist.lua", base, "agartha-v3-part", tostring(maxPart))
