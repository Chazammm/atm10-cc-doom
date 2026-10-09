-- Draconic Energy Monitor v2 - CC:Tweaked / ATM10 (Minecraft 1.21.1)
-- One file, three modes: sender, display, local.
-- Safe/read-only: never changes energy transfer rates or core configuration.
local VERSION = 2
local PROTOCOL = "draconic.monitor.v2"
local HEARTBEAT_MS = 5000
local SAMPLE_SECONDS = 1
local HISTORY_MAX = 240

local scriptPath = shell and shell.getRunningProgram and shell.getRunningProgram() or "draconic.lua"
local configPath = fs.combine(fs.getDir(scriptPath), "draconic.cfg")
local unpack = table.unpack or unpack

local function finite(value)
    return type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
end

local function clamp(value, lo, hi)
    return math.max(lo, math.min(hi, value))
end

local function nowMs()
    return os.epoch("utc")
end

local function methodsFor(name)
    if not name or not peripheral.isPresent(name) then return {} end
    local ok, methods = pcall(peripheral.getMethods, name)
    if not ok or type(methods) ~= "table" then return {} end
    local lookup = {}
    for _, method in ipairs(methods) do lookup[method] = true end
    return lookup
end

local function energyMethodPair(methods)
    if methods.getEnergyStored and methods.getMaxEnergyStored then
        return "getEnergyStored", "getMaxEnergyStored"
    end
    if methods.getEnergy and methods.getEnergyCapacity then
        return "getEnergy", "getEnergyCapacity"
    end
    return nil
end

local function enumerate()
    local all, storages, detectors, monitors, modems = {}, {}, {}, {}, {}
    for _, name in ipairs(peripheral.getNames()) do
        local methods = methodsFor(name)
        local types = { peripheral.getType(name) }
        local info = { name = name, methods = methods, types = types }
        all[#all + 1] = info
        if energyMethodPair(methods) then storages[#storages + 1] = info end
        if methods.getTransferRate and
            (peripheral.hasType(name, "energy_detector")
             or peripheral.hasType(name, "energyDetector")) then
            detectors[#detectors + 1] = info
        end
        if peripheral.hasType(name, "monitor") then monitors[#monitors + 1] = info end
        if peripheral.hasType(name, "modem") then modems[#modems + 1] = info end
    end
    table.sort(all, function(a, b) return a.name < b.name end)
    local function sort(items)
        table.sort(items, function(a, b) return a.name < b.name end)
    end
    sort(storages); sort(detectors); sort(monitors); sort(modems)
    return {
        all = all, storages = storages, detectors = detectors,
        monitors = monitors, modems = modems
    }
end

local function diagnostic()
    print("== Draconic Monitor: Peripheral-Scan ==")
    local devices = enumerate()
    for _, info in ipairs(devices.all) do
        local methods = {}
        for method in pairs(info.methods) do methods[#methods + 1] = method end
        table.sort(methods)
        print("")
        print(info.name .. " [" .. table.concat(info.types, ", ") .. "]")
        print("  " .. table.concat(methods, ", "))
    end
    print("")
    print(("Storage: %d | Detector: %d | Monitor: %d | Modem: %d")
        :format(#devices.storages, #devices.detectors,
                #devices.monitors, #devices.modems))
    if #devices.all == 0 then
        print("Keine Peripherals gefunden. Wired-Modem am Block aktivieren.")
    end
end

local function promptChoice(title, items, optional)
    print("")
    print(title)
    if optional then print("  0) Keiner / deaktiviert") end
    for i, item in ipairs(items) do
        print(("  %d) %s"):format(i, item.name))
    end
    if #items == 0 then
        if optional then return nil end
        error("Kein passendes Peripheral. Bitte 'draconic scan' pruefen.", 0)
    end
    while true do
        write("Auswahl" .. (optional and " (Enter=0)" or "") .. ": ")
        local input = read()
        if optional and (input == "" or input == "0") then return nil end
        local n = tonumber(input)
        if n and n == math.floor(n) and items[n] then
            return items[n].name
        end
        print("Ungueltige Auswahl.")
    end
end

local function saveConfig(config)
    local handle, err = fs.open(configPath, "w")
    if not handle then error("Konfiguration nicht schreibbar: " .. tostring(err), 0) end
    handle.write(textutils.serialize(config))
    handle.close()
end

local function loadConfig()
    if not fs.exists(configPath) then return nil end
    local handle = fs.open(configPath, "r")
    if not handle then return nil end
    local raw = handle.readAll()
    handle.close()
    local ok, config = pcall(textutils.unserialize, raw)
    if ok and type(config) == "table"
        and (config.mode == "sender" or config.mode == "display" or config.mode == "local") then
        return config
    end
    return nil
end

local function installStartup()
    print("")
    write("Autostart installieren? Vorhandene startup wird gesichert (ja/NEIN): ")
    if read():lower() ~= "ja" then return end

    if fs.exists("startup") then
        local i = 1
        local backup = "startup.draconic-backup-" .. i
        while fs.exists(backup) do
            i = i + 1
            backup = "startup.draconic-backup-" .. i
        end
        local ok, err = pcall(fs.move, "startup", backup)
        if not ok then
            printError("Konnte startup nicht sichern: " .. tostring(err))
            return
        end
        print("Alte startup gesichert als: " .. backup)
    end

    local handle, err = fs.open("startup", "w")
    if not handle then
        printError("Konnte startup nicht schreiben: " .. tostring(err))
        return
    end
    handle.write("shell.run(" .. string.format("%q", "/" .. scriptPath:gsub("^/", "")) .. ")\n")
    handle.close()
    print("Autostart eingerichtet. Neustart mit 'reboot'.")
end

local function setup()
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1, 1)
    print("DRACONIC ENERGY MONITOR v2")
    print("Einrichtung fuer diesen Computer")
    local dev = enumerate()
    print("")
    print("1) Sender: liest Core und sendet per Rednet")
    print("2) Display: empfaengt auf einem Monitor")
    print("3) Lokal: liest Core und zeichnet Monitor")
    local choice
    repeat
        write("Modus [1-3]: ")
        choice = tonumber(read())
    until choice == 1 or choice == 2 or choice == 3
    local cfg = { version = VERSION, mode = ({ "sender", "display", "local" })[choice] }

    if cfg.mode ~= "display" then
        cfg.storage = promptChoice("Core/Pylon als Energiespeicher:", dev.storages)
        cfg.detectorIn = promptChoice(
            "Optional: Energy Detector in der EINGANGSLEITUNG:", dev.detectors, true)
        local outChoices = {}
        for _, item in ipairs(dev.detectors) do
            if item.name ~= cfg.detectorIn then outChoices[#outChoices + 1] = item end
        end
        cfg.detectorOut = promptChoice(
            "Optional: Energy Detector in der AUSGANGSLEITUNG:", outChoices, true)
        print("")
        print("Wichtig: IN/OUT ergibt sich aus der VERKABELUNG.")
        print("Detectoren messen nur Leitungen, die wirklich durch sie laufen.")
    end

    if cfg.mode ~= "sender" then
        cfg.monitor = promptChoice("Monitor fuer Dashboard:", dev.monitors, true)
        print("Ohne Monitor wird das Computer-Terminal verwendet.")
    end

    if cfg.mode ~= "local" then
        if #dev.modems == 0 then
            error("Kein Modem gefunden. Modem anschliessen und Setup neu starten.", 0)
        end
        if cfg.mode == "display" then
            print("")
            print("Computer-ID des Senders (auf Sender: id).")
            print("Leer lassen = alle Sender akzeptieren (weniger sicher).")
            write("Sender-ID: ")
            local sender = read()
            if sender ~= "" then
                cfg.senderId = tonumber(sender)
                if not cfg.senderId or cfg.senderId < 0
                    or cfg.senderId ~= math.floor(cfg.senderId) then
                    error("Sender-ID muss eine ganze positive Zahl sein.", 0)
                end
            end
        end
    end
    saveConfig(cfg)
    print("")
    print("Konfiguration gespeichert: " .. configPath)
    installStartup()
    print("Start: " .. scriptPath)
end

local function openModems()
    local count = 0
    for _, name in ipairs(peripheral.getNames()) do
        if peripheral.hasType(name, "modem") then
            local ok = pcall(rednet.open, name)
            if ok then count = count + 1 end
        end
    end
    return count > 0
end

local SUFFIX = {
    { 1e18, "E" }, { 1e15, "P" }, { 1e12, "T" },
    { 1e9, "G" }, { 1e6, "M" }, { 1e3, "k" }
}
local function formatEnergy(number)
    if not finite(number) then return "--" end
    local abs = math.abs(number)
    for _, item in ipairs(SUFFIX) do
        if abs >= item[1] then return ("%.2f%s"):format(number / item[1], item[2]) end
    end
    return ("%.0f"):format(number)
end

local function readNumber(name, method)
    local ok, result = pcall(peripheral.call, name, method)
    if ok and finite(result) then return result end
    return nil
end

local function newReader(config)
    local reader = { lastEnergy = nil, lastAt = nil }
    function reader.sample()
        local pair = energyMethodPair(methodsFor(config.storage))
        if not pair then
            return nil, "Core/Pylon nicht verbunden: " .. tostring(config.storage)
        end
        local energy = readNumber(config.storage, pair)
        local capacity = readNumber(config.storage, pair == "getEnergyStored"
            and "getMaxEnergyStored" or "getEnergyCapacity")
        if not energy or not capacity or capacity <= 0 or energy < 0 then
            return nil, "Core liefert keine gueltigen Energiewerte."
        end
        local at = nowMs()
        local net = nil
        if reader.lastEnergy and reader.lastAt and at > reader.lastAt then
            local dtTicks = (at - reader.lastAt) / 50
            if dtTicks > 0 then net = (energy - reader.lastEnergy) / dtTicks end
        end
        reader.lastEnergy, reader.lastAt = energy, at
        local input, output
        if config.detectorIn then
            input = readNumber(config.detectorIn, "getTransferRate")
            if input then input = math.max(0, input) end
        end
        if config.detectorOut then
            output = readNumber(config.detectorOut, "getTransferRate")
            if output then output = math.max(0, output) end
        end
        return {
            app = PROTOCOL, version = VERSION, source = os.getComputerID(),
            stored = energy, capacity = capacity,
            input = input, output = output, net = net,
            measuredInput = input ~= nil, measuredOutput = output ~= nil,
            sampleAt = at
        }
    end
    return reader
end

local function validPacket(message)
    if type(message) ~= "table" or message.app ~= PROTOCOL
        or message.version ~= VERSION then return false end
    if not finite(message.stored) or not finite(message.capacity)
        or message.capacity <= 0 or message.stored < 0 then return false end
    if message.stored > message.capacity * 1.001 then return false end
    for _, key in ipairs({ "input", "output", "net" }) do
        local v = message[key]
        if v ~= nil and not finite(v) then return false end
    end
    if message.input and message.input < 0 then return false end
    if message.output and message.output < 0 then return false end
    return true
end

local function windowSurface(config)
    if config.monitor and peripheral.isPresent(config.monitor) then
        local m = peripheral.wrap(config.monitor)
        if m and m.setTextScale then
            pcall(m.setTextScale, 0.5)
            return m
        end
    end
    return term.current()
end

local function newDashboard(config)
    local surface = windowSurface(config)
    local history = {}
    local state = { latest = nil, receivedAt = 0, sender = nil }
    local previousW, previousH = -1, -1

    local function append(packet)
        history[#history + 1] = clamp(100 * packet.stored / packet.capacity, 0, 100)
        while #history > HISTORY_MAX do table.remove(history, 1) end
    end

    local function receive(packet, sender)
        if not validPacket(packet) then return end
        if state.sender and state.sender ~= sender then
            history = {}
        end
        state.latest = packet
        state.sender = sender
        state.receivedAt = nowMs()
        append(packet)
    end

    local function writeAt(x, y, text, fg, bg)
        local w, h = surface.getSize()
        if y < 1 or y > h or x > w then return end
        text = tostring(text or "")
        if x < 1 then
            text = text:sub(2 - x)
            x = 1
        end
        text = text:sub(1, w - x + 1)
        if #text == 0 then return end
        if fg then surface.setTextColor(fg) end
        if bg then surface.setBackgroundColor(bg) end
        surface.setCursorPos(x, y)
        surface.write(text)
    end

    local function drawBar(x, y, width, fraction)
        width = math.max(0, width)
        if width == 0 then return end
        local used = clamp(math.floor(clamp(fraction, 0, 1) * width + 0.5), 0, width)
        writeAt(x, y, string.rep(" ", used), nil, colors.lime)
        writeAt(x + used, y, string.rep(" ", width - used), nil, colors.gray)
        surface.setBackgroundColor(colors.black)
    end

    local function graph(top, bottom, w)
        local gh = bottom - top + 1
        if gh < 2 or w < 8 or #history == 0 then return end
        local n = math.min(#history, w)
        local start = #history - n + 1
        local lower, upper = 100, 0
        for i = start, #history do
            lower = math.min(lower, history[i])
            upper = math.max(upper, history[i])
        end
        -- Zoom around recent values instead of drawing every bar from 0%.
        -- Explicit min/max labels ensure the graph is not misleading.
        local margin = math.max((upper - lower) * 0.1, 0.2)
        lower = clamp(lower - margin, 0, 100)
        upper = clamp(upper + margin, 0, 100)
        if upper <= lower then upper = lower + 0.1 end
        for x = 1, n do
            local p = history[start + x - 1]
            local height = clamp(math.floor((p - lower) / (upper - lower) * gh + 0.5), 0, gh)
            for dy = 0, height - 1 do
                writeAt(w - n + x, bottom - dy, " ", nil, colors.cyan)
            end
        end
        surface.setBackgroundColor(colors.black)
        writeAt(1, top, ("%.2f%%"):format(upper), colors.yellow)
        writeAt(1, bottom, ("%.2f%%"):format(lower), colors.yellow)
    end

    local function draw()
        if config.monitor and not peripheral.isPresent(config.monitor) then
            surface = term.current()
        elseif config.monitor and peripheral.isPresent(config.monitor)
            and surface == term.current() then
            surface = windowSurface(config)
        end
        local w, h = surface.getSize()
        if w ~= previousW or h ~= previousH then
            previousW, previousH = w, h
        end
        surface.setBackgroundColor(colors.black)
        surface.setTextColor(colors.white)
        surface.clear()
        local online = state.latest and nowMs() - state.receivedAt < HEARTBEAT_MS
        writeAt(1, 1, " DRACONIC | ENERGY CORE ", colors.orange)
        writeAt(math.max(1, w - 9), 1, online and " ONLINE " or " OFFLINE ",
            online and colors.lime or colors.red)
        if h < 9 or w < 20 then
            writeAt(1, 3, "Monitor zu klein!", colors.red)
            writeAt(1, 4, "Bitte vergroessern.", colors.gray)
            return
        end
        writeAt(1, 2, string.rep("-", w), colors.purple)
        if not online then
            writeAt(2, 4, "KEINE AKTUELLEN DATEN", colors.red)
            writeAt(2, 6, "Warte auf Sender/Core...", colors.lightGray)
            if state.sender then writeAt(2, 8, "Letzter Sender: #" .. state.sender, colors.gray) end
            return
        end
        local p = state.latest
        local percent = clamp(100 * p.stored / p.capacity, 0, 100)
        writeAt(2, 3, "GESPEICHERT", colors.cyan)
        writeAt(2, 4, formatEnergy(p.stored) .. " FE", colors.yellow)
        writeAt(2, 5, "MAX: " .. formatEnergy(p.capacity) .. " FE", colors.gray)
        writeAt(2, 6, ("Fuellstand: %.3f%%"):format(percent), colors.white)
        drawBar(2, 7, math.max(0, w - 3), percent / 100)

        if h >= 11 then
            writeAt(2, 9, "IN : " .. (p.input and ("+" .. formatEnergy(p.input) .. " FE/t")
                or "-- (kein Sensor)"), p.input and colors.lime or colors.gray)
            writeAt(2, 10, "OUT: " .. (p.output and ("-" .. formatEnergy(p.output) .. " FE/t")
                or "-- (kein Sensor)"), p.output and colors.red or colors.gray)
            local label = p.net and
                ((p.net >= 0 and "+" or "") .. formatEnergy(p.net) .. " FE/t")
                or "-- (erste Messung)"
            writeAt(2, 11, "NET: " .. label, p.net and (p.net >= 0 and colors.lime or colors.red) or colors.gray)
        end
        if h >= 17 then
            writeAt(2, 13, "VERLAUF  | Fuellstand (%)", colors.cyan)
            graph(15, h - 2, w)
        elseif h >= 13 then
            writeAt(2, h - 1, "Verlauf: groesseren Monitor nutzen", colors.gray)
        end
        writeAt(2, h, "Quelle #" .. tostring(state.sender or p.source or os.getComputerID())
            .. " | IN/OUT=Sensor | NET=Delta", colors.lightGray)
    end

    return { receive = receive, draw = draw }
end

local function runSender(config)
    if not openModems() then error("Kein Rednet-Modem verfuegbar.", 0) end
    local reader = newReader(config)
    print("Draconic Sender v2 | Computer #" .. os.getComputerID())
    print("Core: " .. tostring(config.storage))
    print("Rednet-Protokoll: " .. PROTOCOL)
    print("Ctrl+T zum Beenden.")
    while true do
        local packet, err = reader.sample()
        if packet then
            rednet.broadcast(packet, PROTOCOL)
            term.setCursorPos(1, 5)
            term.clearLine()
            print(("%.3f%% | %s FE | NET %s FE/t   ")
                :format(100 * packet.stored / packet.capacity,
                    formatEnergy(packet.stored), formatEnergy(packet.net)))
            term.clearLine()
            print("IN: " .. formatEnergy(packet.input) .. " | OUT: " .. formatEnergy(packet.output))
        else
            term.setCursorPos(1, 5)
            term.clearLine()
            printError("Leseproblem: " .. tostring(err))
        end
        sleep(SAMPLE_SECONDS)
    end
end

local function runDisplay(config)
    if not openModems() then error("Kein Rednet-Modem verfuegbar.", 0) end
    local dash = newDashboard(config)
    print("Draconic Display v2 | Ctrl+T zum Beenden.")
    dash.draw()
    while true do
        local sender, message = rednet.receive(PROTOCOL, 0.5)
        if sender and (not config.senderId or config.senderId == sender) then
            dash.receive(message, sender)
        end
        dash.draw()
    end
end

local function runLocal(config)
    local reader = newReader(config)
    local dash = newDashboard(config)
    print("Draconic Local v2 | Ctrl+T zum Beenden.")
    while true do
        local packet, err = reader.sample()
        if packet then
            dash.receive(packet, os.getComputerID())
        else
            term.setCursorPos(1, 4)
            term.clearLine()
            printError("Leseproblem: " .. tostring(err))
        end
        dash.draw()
        sleep(SAMPLE_SECONDS)
    end
end

local args = { ... }
if args[1] == "scan" then
    diagnostic()
elseif args[1] == "setup" then
    setup()
else
    local config = loadConfig()
    if not config then
        print("Keine gueltige Konfiguration gefunden.")
        print("Starte 'draconic setup' oder benutze die Einrichtung jetzt.")
        setup()
        config = loadConfig()
    end
    if not config then error("Einrichtung fehlgeschlagen.", 0) end
    if config.mode == "sender" then
        runSender(config)
    elseif config.mode == "display" then
        runDisplay(config)
    elseif config.mode == "local" then
        runLocal(config)
    end
end
