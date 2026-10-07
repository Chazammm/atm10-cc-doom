-- CC-Music Pocket/Computer Remote
local PROTOCOL = "ccmusic.v2"
local VERSION = "3.6.2"

local function nowMs()
    if os.epoch then return os.epoch("utc") end
    return math.floor(os.clock() * 1000)
end

local function openModems()
    local opened = 0
    for _, name in ipairs(peripheral.getNames()) do
        if peripheral.getType(name) == "modem" then
            if not rednet.isOpen(name) then pcall(rednet.open, name) end
            if rednet.isOpen(name) then opened = opened + 1 end
        end
    end
    return opened
end

if openModems() == 0 then error("Attach a wired or wireless modem first.", 0) end

local playerId = nil
local status = nil
local lastSeen = 0

local function fmtTime(seconds)
    seconds = math.max(0, math.floor((seconds or 0) + 0.5))
    return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function send(op, value)
    local msg = { op = op }
    if op == "volume" or op == "seek_rel" or op == "seek" then msg.value = value end
    if playerId then rednet.send(playerId, msg, PROTOCOL) else rednet.broadcast(msg, PROTOCOL) end
end

local function discover()
    rednet.broadcast({ op = "discover", remote = VERSION }, PROTOCOL)
end

local function draw()
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    local w, h = term.getSize()
    term.setCursorPos(1, 1)
    term.setBackgroundColor(colors.blue)
    term.clearLine()
    term.setCursorPos(2, 1)
    term.setTextColor(colors.white)
    term.write("CC-MUSIC REMOTE")

    term.setBackgroundColor(colors.black)
    if status and nowMs() - lastSeen < 6000 then
        local title = tostring(status.title or "Stopped")
        if #title > w - 2 then title = title:sub(1, w - 3) .. ">" end
        term.setCursorPos(2, 3); term.setTextColor(colors.yellow); term.write(title)
        term.setCursorPos(2, 5); term.setTextColor(colors.lightGray)
        term.write(fmtTime(status.position) .. " / " .. fmtTime(status.duration))
        term.setCursorPos(2, 6)
        term.write(string.format("VOL %d%%  %s", math.floor((status.volume or 0) * 100 + 0.5), tostring(status.loop or "all"):upper()))
        term.setCursorPos(2, 7)
        term.write((status.shuffle and "SHUFFLE  " or "ORDER    ") .. tostring(status.speakers or 0) .. " spk")
        term.setCursorPos(2, 8)
        local audio = tostring(status.audio_mode or "MONO")
        local rate = tonumber(status.source_rate) or 0
        if rate > 0 then audio = audio .. " " .. tostring(math.floor(rate / 1000 + 0.5)) .. "k" end
        if tonumber(status.output_boost or 1) > 1 then audio = audio .. " X" .. tostring(status.output_boost) end
        if status.passthrough then audio = audio .. " DIRECT" end
        term.write(audio:sub(1, math.max(1, w - 2)))
        if h >= 10 then
            term.setCursorPos(2, 9)
            term.setTextColor(colors.gray)
            local vizLine = "VIZ " .. tostring(status.viz_mode or "classic"):upper()
            if status.favorite then vizLine = vizLine .. "  *FAV" end
            if tonumber(status.queue_count or 0) > 0 then vizLine = vizLine .. "  Q:" .. tostring(status.queue_count) end
            term.write(vizLine:sub(1, math.max(1, w - 2)))
        end
        if status.error and h >= 10 then
            term.setCursorPos(2, 10)
            term.setTextColor(colors.red)
            term.write(tostring(status.error):sub(1, w - 2))
        end
    else
        term.setCursorPos(2, 3); term.setTextColor(colors.orange); term.write("Searching for player...")
    end

    local help = {
        "SPACE  Play/Pause",
        "LEFT   Previous",
        "RIGHT  Next",
        "UP/DN  Volume",
        "S/L    Shuffle/Loop",
        "A      Audio mode",
        "R      Speaker boost",
        "V      Visualizer",
        "J/K    -10s / +10s",
        "B      Favorite",
        "Q      Quit",
    }
    local y = math.max(11, h - #help + 1)
    term.setTextColor(colors.white)
    for i = 1, #help do
        local row = y + i - 1
        if row <= h then
            term.setCursorPos(2, row)
            term.write(help[i]:sub(1, math.max(1, w - 2)))
        end
    end
end

discover()
local poll = os.startTimer(1)
draw()

while true do
    local ev, a, b, c = os.pullEventRaw()
    if ev == "rednet_message" and c == PROTOCOL and type(b) == "table" and b.op == "status" then
        playerId, status, lastSeen = a, b, nowMs()
        draw()
    elseif ev == "timer" and a == poll then
        if playerId then send("status") else discover() end
        poll = os.startTimer(1)
        draw()
    elseif ev == "key" then
        if a == keys.q then break
        elseif a == keys.space then send("toggle")
        elseif a == keys.left then send("prev")
        elseif a == keys.right then send("next")
        elseif a == keys.up then send("volume", math.min(1, (status and status.volume or 0.5) + 0.05))
        elseif a == keys.down then send("volume", math.max(0, (status and status.volume or 0.5) - 0.05))
        elseif a == keys.s then send("shuffle")
        elseif a == keys.l then send("loop")
        elseif a == keys.a then send("audio_mode")
        elseif a == keys.r then send("output_boost")
        elseif a == keys.v then send("viz_mode")
        elseif a == keys.j then send("seek_rel", -10)
        elseif a == keys.k then send("seek_rel", 10)
        elseif a == keys.b then send("favorite") end
    elseif ev == "terminate" then
        break
    end
end

term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.clear()
term.setCursorPos(1, 1)