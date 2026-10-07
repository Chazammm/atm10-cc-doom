-- CC-Music 3.7 diagnostics / setup report.
local function yn(v) return v and "YES" or "NO" end

print("CC-Music 3.7.0 diagnostics")
print("------------------------")

local monitor, monitorName = peripheral.find("monitor", function(name) monitorName = name; return true end)
if monitor then
    pcall(monitor.setTextScale, 0.5)
    local w, h = monitor.getSize()
    print(("Monitor: %s  %dx%d cells @ 0.5"):format(tostring(monitorName or peripheral.getName(monitor)), w, h))
    if w == 164 and h == 81 then
        print("Layout : RECOMMENDED (8 wide x 6 high)")
    elseif w == 164 and h == 67 then
        print("Layout : SUPPORTED (8 wide x 5 high)")
    else
        print("Layout : supported, recommended 164x81 (8x6)")
    end
else
    print("Monitor: NOT FOUND")
end

local speakers = {}
for _, name in ipairs(peripheral.getNames()) do
    if peripheral.hasType(name, "speaker") then speakers[#speakers + 1] = name end
end
table.sort(speakers)
print(("Speakers: %d"):format(#speakers))

local left = settings.get("ccmusic.left_speaker") or settings.get("musicvideo.left_speaker")
local right = settings.get("ccmusic.right_speaker") or settings.get("musicvideo.right_speaker")
print("LEFT   : " .. tostring(left or "(not configured)"))
print("RIGHT  : " .. tostring(right or "(not configured)"))
local ready = left and right and left ~= right
    and peripheral.isPresent(left) and peripheral.isPresent(right)
    and peripheral.hasType(left, "speaker") and peripheral.hasType(right, "speaker")
print("Stereo : " .. yn(ready))
print("Mode   : " .. tostring(settings.get("ccmusic.audio_mode") or "auto"))
print("48k passthrough: " .. yn(settings.get("ccmusic.passthrough_48k") ~= false))

write("GitHub library HTTP: ")
local h, err = http.get("https://api.github.com/repos/Chazammm/atm10-cc-doom/releases/tags/cc-music-library-v1", {
    ["User-Agent"] = "CC-Music-Diagnostics/3.7",
    ["Accept"] = "application/vnd.github+json",
})
if h then
    h.close()
    print("OK")
else
    print("FAILED - " .. tostring(err))
end

print("")
if not ready and #speakers >= 2 then
    print("Run 'music-stereo' to assign LEFT and RIGHT.")
end
print("Run 'music' to start the player.")


print("")
if fs.exists("/ccmusic/session.json") then
    local h = fs.open("/ccmusic/session.json", "r")
    local raw = h and h.readAll() or ""
    if h then h.close() end
    local ok, data = pcall(textutils.unserializeJSON, raw)
    if ok and type(data) == "table" then
        print("Resume session: OK")
        print("  Track   : " .. tostring(data.track or "?"))
        print("  Position: " .. tostring(math.floor((tonumber(data.position) or 0) + 0.5)) .. "s")
    else
        print("Resume session: INVALID")
    end
else
    print("Resume session: not created yet")
end


print("")
local uiFps = settings.get("ccmusic.ui_fps") or 12
local vizSlice = settings.get("ccmusic.viz_slice_bytes") or 1024
local vizMode = settings.get("ccmusic.viz_mode") or "classic"
print("Performance:")
print("  UI FPS          : " .. tostring(uiFps))
print("  Visualizer slice: " .. tostring(vizSlice) .. " B")
print("  Visualizer mode : " .. tostring(vizMode):upper())
print("  Auto SAFE mode  : enabled in player")


local boost = settings.get("ccmusic.output_boost") or 1
print("Speaker boost: X" .. tostring(boost))


print("")
print("Lyrics:")
print("  Online fallback : " .. yn(settings.get("ccmusic.lyrics_online") ~= false))
print("  Cache folder    : /ccmusic/lyrics")

local remoteIds = tostring(settings.get("ccmusic.remote_ids") or "")
if remoteIds == "" then
    print("Remote ACL: OPEN (set ccmusic.remote_ids to restrict control)")
else
    print("Remote ACL: " .. remoteIds)
end
