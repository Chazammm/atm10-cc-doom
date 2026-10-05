-- Agartha V2: maximum-quality 10 FPS encode.
-- Media lives in a GitHub Release instead of repository history.
local base = settings.get("agartha.v2_base_url")
  or "https://github.com/Chazammm/atm10-cc-doom/releases/download/agartha-v2/"

-- Preflight the GitHub release so an unfinished upload produces a clear message
-- instead of a generic player stack trace.
local api = "https://api.github.com/repos/Chazammm/atm10-cc-doom/releases/404031214/assets?per_page=100"
local h, err = http.get(api, {
  ["Accept"] = "application/vnd.github+json",
  ["X-GitHub-Api-Version"] = "2022-11-28",
})

if h then
  local body = h.readAll()
  h.close()

  local ok, assets = pcall(textutils.unserializeJSON, body)
  if ok and type(assets) == "table" then
    local complete = 0
    local total = #assets
    for _, asset in ipairs(assets) do
      if asset.state == "uploaded" and
         type(asset.name) == "string" and
         asset.name:match("^agartha%-v2%-part%d%d%.32vid$") then
        complete = complete + 1
      end
    end

    if total < 50 or complete < 50 then
      printError(("Agartha V2 upload is not finished yet: %d/50 ready (%d assets visible)."):format(complete, total))
      print("Wait until the Windows uploader says: Upload complete.")
      print("Then run: agartha-v2")
      return
    end
  end
else
  print("Warning: could not check GitHub release readiness: " .. tostring(err))
  print("Trying playback anyway...")
end

-- CC:Tweaked follows HTTP redirects by default, so GitHub release assets can
-- be streamed directly through the existing HTTP player.
shell.run("/playlist.lua", base, "agartha-v2-part", "50")
