-- ATM10 DOOM wireless controller for CC:Tweaked
-- Run on an Advanced Pocket Computer (or another Advanced Computer)
-- with a wireless modem.

local PROTOCOL = "atm10-doom-control"

local function findWireless()
    for _, name in ipairs(peripheral.getNames()) do
        if peripheral.getType(name) == "modem" then
            local m = peripheral.wrap(name)
            if m and m.isWireless and m.isWireless() then
                return name
            end
        end
    end
end

local modem = findWireless()
if not modem then
    error("No wireless modem found. Equip/connect a Wireless Modem first.", 0)
end

if not rednet.isOpen(modem) then rednet.open(modem) end

term.clear()
term.setCursorPos(1,1)
print("DOOM CONTROLLER")
print("Searching for DOOM...")

local target = rednet.lookup(PROTOCOL)
if not target then
    print("")
    print("No DOOM host found.")
    write("DOOM computer ID: ")
    target = tonumber(read())
    if not target then error("Invalid computer ID", 0) end
end

local function sendKey(key, down)
    rednet.send(target, {
        type = "doom_key",
        key = key,
        down = down and true or false,
    }, PROTOCOL)
end

local buttons = {}

local function addButton(label, x1, y1, x2, y2, key, color)
    buttons[#buttons+1] = {
        label=label, x1=x1, y1=y1, x2=x2, y2=y2, key=key,
        color=color or colors.gray
    }
end

local w,h = term.getSize()

-- D-pad.
addButton("^",       5, 5, 9, 7, keys.up,    colors.green)
addButton("<",       1, 8, 5,10, keys.left,  colors.green)
addButton("v",       5, 8, 9,10, keys.down,  colors.green)
addButton(">",       9, 8,13,10, keys.right, colors.green)

-- Action buttons.
local ax1 = math.max(15, w-8)
addButton("FIRE", ax1, 5, w, 7, keys.leftCtrl,  colors.red)
addButton("USE",  ax1, 8, w,10, keys.space,     colors.orange)
addButton("RUN",  ax1,11, w,13, keys.rightShift,colors.blue)

-- Menu/confirm.
addButton("MENU", 1, math.max(14,h-3), 7, math.max(16,h-1), keys.escape, colors.purple)
addButton("OK",   9, math.max(14,h-3),15, math.max(16,h-1), keys.enter,  colors.lime)

local function centerText(x1,x2,y,s)
    local x = math.floor((x1+x2-#s)/2)
    term.setCursorPos(math.max(x1,x), y)
    term.write(s)
end

local function draw()
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()

    term.setCursorPos(1,1)
    term.write("DOOM Controller -> ID "..target)
    term.setCursorPos(1,2)
    term.setTextColor(colors.lightGray)
    term.write("Keyboard also works: arrows/Ctrl/Space")

    for _,b in ipairs(buttons) do
        paintutils.drawFilledBox(b.x1,b.y1,b.x2,b.y2,b.color)
        term.setTextColor(colors.white)
        term.setBackgroundColor(b.color)
        centerText(b.x1,b.x2,math.floor((b.y1+b.y2)/2),b.label)
    end

    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.gray)
    term.setCursorPos(1,h)
    term.write("Ctrl+T exits controller")
end

local function hit(x,y)
    for _,b in ipairs(buttons) do
        if x>=b.x1 and x<=b.x2 and y>=b.y1 and y<=b.y2 then
            return b
        end
    end
end

draw()

local heldMouseKey = nil

while true do
    local ev,a,b,c = os.pullEvent()

    if ev == "key" then
        sendKey(a, true)

    elseif ev == "key_up" then
        sendKey(a, false)

    elseif ev == "mouse_click" then
        local btn = hit(b,c)
        if btn then
            if heldMouseKey and heldMouseKey ~= btn.key then
                sendKey(heldMouseKey, false)
            end
            heldMouseKey = btn.key
            sendKey(btn.key, true)
        end

    elseif ev == "mouse_up" then
        if heldMouseKey then
            sendKey(heldMouseKey, false)
            heldMouseKey = nil
        end

    elseif ev == "term_resize" then
        w,h = term.getSize()
        draw()
    end
end
