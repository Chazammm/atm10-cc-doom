-- CC-Music stereo setup for CC:Tweaked.
local names = {}
for _, name in ipairs(peripheral.getNames()) do
    if peripheral.hasType(name, "speaker") then names[#names + 1] = name end
end
table.sort(names)

print(("CC-Music Stereo Setup - %d speaker(s) found"):format(#names))
if #names < 2 then
    printError("True stereo needs at least two connected speakers.")
    print("Mono playback will continue to work with one speaker.")
    return
end

local function beep(name, pitch)
    local s = peripheral.wrap(name)
    if s and s.playNote then pcall(s.playNote, "pling", 1.0, pitch or 12) end
end

local videoLeft = settings.get("musicvideo.left_speaker")
local videoRight = settings.get("musicvideo.right_speaker")
if videoLeft and videoRight and videoLeft ~= videoRight
    and peripheral.isPresent(videoLeft) and peripheral.isPresent(videoRight)
    and peripheral.hasType(videoLeft, "speaker") and peripheral.hasType(videoRight, "speaker") then
    print("")
    print("Existing video stereo pair found:")
    print("LEFT : " .. videoLeft)
    print("RIGHT: " .. videoRight)
    write("Reuse this pair for CC-Music? [Y/n] ")
    local answer = read():lower()
    if answer == "" or answer == "y" or answer == "yes" then
        settings.set("ccmusic.left_speaker", videoLeft)
        settings.set("ccmusic.right_speaker", videoRight)
        settings.set("ccmusic.audio_mode", "auto")
        settings.save()
        print("Saved. Testing LEFT then RIGHT...")
        beep(videoLeft, 8); sleep(0.5); beep(videoRight, 16)
        print("Done. Restart 'music' if it is currently running.")
        return
    end
end

print("")
for i, name in ipairs(names) do print(("%d) %s"):format(i, name)) end

local function choose(label, pitch)
    while true do
        write(label .. " speaker number: ")
        local n = tonumber(read())
        if n and names[n] then
            beep(names[n], pitch)
            print(("Selected %s -> %s"):format(label, names[n]))
            return names[n]
        end
        printError("Enter one of the numbers above.")
    end
end

print("")
print("Stand in front of the monitor while assigning the physical speakers.")
local left = choose("LEFT", 8)
local right = choose("RIGHT", 16)
if left == right then
    printError("Left and right must be different speakers.")
    return
end

settings.set("ccmusic.left_speaker", left)
settings.set("ccmusic.right_speaker", right)
settings.set("ccmusic.audio_mode", "auto")
settings.save()

print("")
print("Stereo configured:")
print("LEFT : " .. left)
print("RIGHT: " .. right)
print("Testing LEFT then RIGHT...")
beep(left, 8); sleep(0.5); beep(right, 16)
print("")
print("SQSH2 tracks will now play in true stereo.")
print("Legacy SQSH1 tracks remain mono and are mirrored to attached speakers.")
print("Restart 'music' if the player is currently running.")
