-- Agartha V4: final direct-cell image encoder + selected Audio Profile A.
local startMode = ({ ... })[1] or "start"
if startMode ~= "start" and startMode ~= "resume" then
  print("Usage: agartha-v4 [start|resume]")
  return
end

local EXPECTED_PARTS = 136
local base = settings.get("agartha.v4_base_url")
  or "https://github.com/Chazammm/atm10-cc-doom/releases/download/agartha-v4/"

local monitor = peripheral.find("monitor")
if not monitor then error("No monitor found.") end
monitor.setTextScale(0.5)
local w, h = monitor.getSize()
if w ~= 164 or h ~= 67 then
  printError(("Agartha V4 is encoded for a 164x67 monitor, but this monitor is %dx%d."):format(w, h))
  print("Use an 8-wide x 5-high Advanced Monitor wall at text scale 0.5.")
  return
end

local api = "https://api.github.com/repos/Chazammm/atm10-cc-doom/releases/tags/agartha-v4"
local response, err = http.get(api, {
  ["Accept"] = "application/vnd.github+json",
  ["X-GitHub-Api-Version"] = "2022-11-28",
})
if not response then
  printError("Agartha V4 release is not available yet: " .. tostring(err))
  return
end

local body = response.readAll()
response.close()
local ok, release = pcall(textutils.unserializeJSON, body)
if not ok or type(release) ~= "table" or type(release.id) ~= "number" then
  printError("Could not read the Agartha V4 GitHub release.")
  return
end

local assetsUrl = ("https://api.github.com/repos/Chazammm/atm10-cc-doom/releases/%d/assets?per_page=100"):format(release.id)
local pages, assets = 1, {}
while true do
  local url = assetsUrl .. "&page=" .. pages
  local ah, aerr = http.get(url, {
    ["Accept"] = "application/vnd.github+json",
    ["X-GitHub-Api-Version"] = "2022-11-28",
  })
  if not ah then
    printError("Could not list Agartha V4 release assets: " .. tostring(aerr))
    return
  end
  local abody = ah.readAll()
  ah.close()
  local aok, pageAssets = pcall(textutils.unserializeJSON, abody)
  if not aok or type(pageAssets) ~= "table" then
    printError("Could not parse Agartha V4 release assets.")
    return
  end
  for _, asset in ipairs(pageAssets) do assets[#assets + 1] = asset end
  if #pageAssets < 100 then break end
  pages = pages + 1
end

local present, count, maxPart = {}, 0, 0
for _, asset in ipairs(assets) do
  if asset.state == "uploaded" and type(asset.name) == "string" then
    local n = tonumber(asset.name:match("^agartha%-v4%-part(%d+)%.32vid$"))
    if n then
      if not present[n] then count = count + 1 end
      present[n] = true
      if n > maxPart then maxPart = n end
    end
  end
end

if count ~= EXPECTED_PARTS or maxPart ~= EXPECTED_PARTS then
  printError(("Agartha V4 upload is incomplete: %d/%d parts ready."):format(count, EXPECTED_PARTS))
  print("Wait until the Windows uploader says: Upload complete.")
  return
end
for i = 1, EXPECTED_PARTS do
  if not present[i] then
    printError(("Agartha V4 upload is incomplete: missing part %02d."):format(i))
    return
  end
end

local left = settings.get("musicvideo.left_speaker")
local right = settings.get("musicvideo.right_speaker")
local stereo = left and right and peripheral.isPresent(left) and peripheral.isPresent(right)
print(("Agartha V4: %d parts | 20 FPS | %s | Audio A"):format(EXPECTED_PARTS, stereo and "stereo" or "mono fallback"))
if not stereo then print("For true stereo connect two speakers and run: stereosetup") end

local saved = tonumber(settings.get("agartha.v4.resume_frame")) or 0
if saved > 0 and startMode == "start" then
  print(("Saved position: %.1f min. Use 'agartha-v4 resume' to continue there."):format(saved / 20 / 60))
end
shell.run("/agartha-v4-player.lua", base, startMode)
