-- Interactive stereo setup for CC:Tweaked speakers.
local names = {}
for _, name in ipairs(peripheral.getNames()) do
    local types = { peripheral.getType(name) }
    for _, t in ipairs(types) do
        if t == "speaker" then
            names[#names + 1] = name
            break
        end
    end
end
table.sort(names)

print(("Found %d speaker(s)."):format(#names))
if #names < 2 then
    printError("True stereo needs at least two connected CC:Tweaked speakers.")
    print("V3 will still use its mono fallback with one speaker.")
    return
end

local function beep(name, pitch)
    local s = peripheral.wrap(name)
    if s and s.playNote then
        s.playNote("pling", 1.2, pitch or 12)
    end
end

for i, name in ipairs(names) do
    print(("%d) %s"):format(i, name))
end

local function choose(label)
    while true do
        write(label .. " speaker number: ")
        local n = tonumber(read())
        if n and names[n] then
            beep(names[n], label == "LEFT" and 8 or 16)
            print(("Selected %s -> %s"):format(label, names[n]))
            return names[n]
        end
        printError("Enter one of the numbers above.")
    end
end

print("")
print("Choose the physical speaker on the LEFT side of the screen.")
local left = choose("LEFT")
print("")
print("Choose the physical speaker on the RIGHT side of the screen.")
local right = choose("RIGHT")

if left == right then
    printError("Left and right must be different speakers.")
    return
end

settings.set("musicvideo.left_speaker", left)
settings.set("musicvideo.right_speaker", right)
settings.save()

print("")
print("Stereo configured.")
print("LEFT : " .. left)
print("RIGHT: " .. right)
print("")
print("Testing LEFT then RIGHT...")
beep(left, 8)
sleep(0.5)
beep(right, 16)
print("Done. V3 stereo media will use these two speakers automatically.")
