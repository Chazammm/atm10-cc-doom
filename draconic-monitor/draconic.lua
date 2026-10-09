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
    elseif #devices.storages == 0 then
        print("WARNUNG: Kein Energy Pylon/Storage sichtbar.")
        print("Wired Modem DIREKT an die Pylon-Basis setzen,")
        print("Modem per Rechtsklick als Peripheral verbinden.")
        print("Danach 'peripherals' und 'draconic.lua scan' pruefen.")
    end
    if #devices.detectors == 0 then
        print("INFO: Energy Detector ist OPTIONAL.")
        print("Draconic Pylons koennen IN/OUT direkt melden.")
        print("Falls Detector gewuenscht: eigenes Wired Modem anschliessen.")
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
        local coreMethods = methodsFor(cfg.storage)
        if coreMethods.getInputPerTick and coreMethods.getOutputPerTick then
            print("Native Draconic-IN/OUT-Methoden vorhanden.")
            print("Energy Detector fuer Core-Messung nicht erforderlich.")
        else
            cfg.detectorIn = promptChoice(
                "Optional: Energy Detector in der EINGANGSLEITUNG:", dev.detectors, true)
            local outChoices = {}
            for _, item in ipairs(dev.detectors) do
                if item.name ~= cfg.detectorIn then outChoices[#outChoices + 1] = item end
            end
            cfg.detectorOut = promptChoice(
                "Optional: Energy Detector in der AUSGANGSLEITUNG:", outChoices, true)
            print("")
            print("IN/OUT eines Detectors ergibt sich aus der VERKABELUNG.")
            print("Detectoren messen nur Leitungen, die durch sie laufen.")
        end
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
        local availableMethods = methodsFor(config.storage)
        local storedMethod, capacityMethod = energyMethodPair(availableMethods)
        if not storedMethod then
            return nil, "Core/Pylon nicht verbunden: " .. tostring(config.storage)
        end
        local energy = readNumber(config.storage, storedMethod)
        local capacity = readNumber(config.storage, capacityMethod)
        if energy == nil or capacity == nil or capacity <= 0 or energy < 0 then
            return nil, "Core liefert keine gueltigen Energiewerte."
        end

        local at = nowMs()
        local calculatedNet
        if reader.lastEnergy ~= nil and reader.lastAt and at > reader.lastAt then
            local dtTicks = (at - reader.lastAt) / 50
            if dtTicks > 0 then calculatedNet = (energy - reader.lastEnergy) / dtTicks end
        end
        reader.lastEnergy, reader.lastAt = energy, at

        -- Native Draconic Energy Pylon API reports aggregate core transfer,
        -- including separate input/output, even for crystal-based networks.
        local nativeIn = availableMethods.getInputPerTick
            and readNumber(config.storage, "getInputPerTick") or nil
        local nativeOut = availableMethods.getOutputPerTick
            and readNumber(config.storage, "getOutputPerTick") or nil
        local nativeNet = availableMethods.getTransferPerTick
            and readNumber(config.storage, "getTransferPerTick") or nil

        local input, output, inputSource, outputSource
        if nativeIn ~= nil and nativeIn >= 0 then
            input, inputSource = nativeIn, "pylon"
        elseif config.detectorIn then
            local v = readNumber(config.detectorIn, "getTransferRate")
            if v ~= nil then input, inputSource = math.max(0, v), "detector" end
        end
        if nativeOut ~= nil and nativeOut >= 0 then
            output, outputSource = nativeOut, "pylon"
        elseif config.detectorOut then
            local v = readNumber(config.detectorOut, "getTransferRate")
            if v ~= nil then output, outputSource = math.max(0, v), "detector" end
        end

        -- Prefer the true per-tick core metric over sampled storage delta.
        -- Delta can be imprecise on very large Tier-8 cores.
        local net = nativeNet
        local netSource = "pylon"
        if net == nil and nativeIn ~= nil and nativeOut ~= nil then
            net = nativeIn - nativeOut
        end
        if net == nil then
            net = calculatedNet
            netSource = "delta"
        end

        return {
            app = PROTOCOL, version = VERSION, source = os.getComputerID(),
            stored = energy, capacity = capacity,
            input = input, output = output, net = net,
            inputSource = inputSource, outputSource = outputSource,
            netSource = netSource,
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

-- Premium monitor dashboard, designed for 8x5 multiblock monitors at scale 0.5.
-- Only the display changes: the v2 Rednet packet format is unchanged.
local function newDashboard(config)
    local history = {}
    local state = { latest = nil, receivedAt = 0, sender = nil }
    local surface, hostKind, screenW, screenH

    local function append(packet)
        history[#history + 1] = packet.stored
        while #history > HISTORY_MAX do table.remove(history, 1) end
    end

    local function receive(packet, sender)
        if not validPacket(packet) then return end
        if state.sender ~= nil and state.sender ~= sender then history = {} end
        state.latest, state.sender, state.receivedAt = packet, sender, nowMs()
        append(packet)
    end

    local function refreshSurface()
        local onMonitor = config.monitor and peripheral.isPresent(config.monitor)
        local kind = onMonitor and "monitor" or "terminal"
        local host = onMonitor and peripheral.wrap(config.monitor) or term.current()
        if onMonitor and host.setTextScale then pcall(host.setTextScale, 0.5) end
        local w, h = host.getSize()
        if surface == nil or kind ~= hostKind or w ~= screenW or h ~= screenH then
            hostKind, screenW, screenH = kind, w, h
            if window and window.create then
                surface = window.create(host, 1, 1, w, h, false)
            else
                surface = host
            end
        end
        return w, h
    end

    local function writeAt(x, y, message, fg, bg)
        local w, h = screenW, screenH
        x, y = math.floor(x), math.floor(y)
        if y < 1 or y > h or x > w then return end
        message = tostring(message or "")
        if x < 1 then
            message = message:sub(2 - x)
            x = 1
        end
        message = message:sub(1, w - x + 1)
        if message == "" then return end
        surface.setTextColor(fg or colors.white)
        surface.setBackgroundColor(bg or colors.black)
        surface.setCursorPos(x, y)
        surface.write(message)
    end

    local function centered(x, width, y, message, fg, bg)
        message = tostring(message or "")
        if width <= 0 then return end
        if #message > width then message = message:sub(1, width) end
        writeAt(x + math.floor((width - #message) / 2), y, message, fg, bg)
    end

    local function rule(x, y, width, color, char)
        if width > 0 then
            writeAt(x, y, string.rep(char or "-", width), color or colors.gray)
        end
    end

    local function panel(x, y, width, height, title, accent)
        if width < 5 or height < 3 then return end
        accent = accent or colors.purple
        rule(x, y, width, accent)
        rule(x, y + height - 1, width, accent)
        for yy = y + 1, y + height - 2 do
            writeAt(x, yy, "|", accent)
            writeAt(x + width - 1, yy, "|", accent)
        end
        writeAt(x, y, "+", accent)
        writeAt(x + width - 1, y, "+", accent)
        writeAt(x, y + height - 1, "+", accent)
        writeAt(x + width - 1, y + height - 1, "+", accent)
        if title and width > #title + 6 then
            writeAt(x + 2, y, " " .. title .. " ", colors.white, colors.black)
        end
    end

    local function fillBar(x, y, width, progress, color)
        if width <= 0 then return end
        local amount = clamp(math.floor(width * clamp(progress, 0, 1) + 0.5), 0, width)
        if amount > 0 then
            writeAt(x, y, string.rep(" ", amount), colors.white, color)
        end
        if amount < width then
            writeAt(x + amount, y, string.rep(" ", width - amount),
                colors.white, colors.gray)
        end
    end

    local function percentLabel(n)
        if n >= 1 then return ("%.2f%%"):format(n) end
        if n >= 0.01 then return ("%.4f%%"):format(n) end
        if n >= 0.000001 then return ("%.7f%%"):format(n) end
        if n > 0 then return ("%.2e%%"):format(n) end
        return "0.00%"
    end

    local function levelColor(pct)
        if pct < 5 then return colors.red end
        if pct < 25 then return colors.orange end
        if pct < 65 then return colors.yellow end
        return colors.lime
    end

    local digits = {
        ["0"] = { "###", "# #", "###" },
        ["1"] = { " ##", "  #", "  #" },
        ["2"] = { "###", " ##", "## " },
        ["3"] = { "###", " ##", "###" },
        ["4"] = { "# #", "###", "  #" },
        ["5"] = { "###", "## ", "###" },
        ["6"] = { "###", "## ", "###" },
        ["7"] = { "###", "  #", "  #" },
        ["8"] = { "###", "###", "###" },
        ["9"] = { "###", "###", "  #" },
        ["."] = { "   ", "   ", " # " },
        ["-"] = { "   ", "###", "   " },
        ["+"] = { " # ", "###", " # " },
        ["k"] = { "# #", "## ", "# #" },
        ["M"] = { "# #", "###", "# #" },
        ["G"] = { "###", "#  ", "###" },
        ["T"] = { "###", " # ", " # " },
        ["P"] = { "###", "###", "#  " },
        ["E"] = { "###", "## ", "###" },
    }

    local function bigNumber(x, y, message, color, width)
        message = tostring(message)
        local cellWidth = 4
        if #message * cellWidth > width then
            writeAt(x, y + 1, message, color)
            return
        end
        for row = 1, 3 do
            local parts = {}
            for index = 1, #message do
                local char = message:sub(index, index)
                local glyph = digits[char]
                parts[#parts + 1] = (glyph and glyph[row] or "   ") .. " "
            end
            writeAt(x, y + row - 1, table.concat(parts), color)
        end
    end

    local function graph(x, y, width, height)
        if height < 5 or width < 18 then return end
        if #history < 2 then
            centered(x, width, y + math.floor(height / 2),
                "Gathering history samples...", colors.gray)
            return
        end

        -- Graph the ACTUAL stored OP, not rounded %. This preserves visible
        -- variation when a Tier-8 core is only 0.000001% full.
        local labelWidth = math.min(14, math.max(9, math.floor(width * 0.16)))
        local plotX = x + labelWidth
        local plotW = width - labelWidth - 1
        if plotW < 5 then return end
        local n = math.min(#history, plotW)
        local first = #history - n + 1
        local minimum, maximum = history[first], history[first]
        for i = first + 1, #history do
            minimum = math.min(minimum, history[i])
            maximum = math.max(maximum, history[i])
        end
        local range = maximum - minimum
        local margin = math.max(range * 0.15, math.abs(maximum) * 1e-12, 1)
        local lower = math.max(0, minimum - margin)
        local upper = maximum + margin
        if upper <= lower then upper = lower + 1 end

        local middle = math.floor(height / 2)
        for yy = 0, height - 1 do
            if yy == 0 or yy == middle or yy == height - 1 then
                rule(plotX, y + yy, plotW, colors.gray, ".")
            end
        end
        writeAt(x, y, formatEnergy(upper) .. " OP", colors.lightBlue)
        writeAt(x, y + middle, formatEnergy((lower + upper) / 2), colors.gray)
        writeAt(x, y + height - 1, formatEnergy(lower) .. " OP", colors.lightBlue)

        local previousY
        for i = 1, n do
            local v = history[first + i - 1]
            local fraction = clamp((v - lower) / (upper - lower), 0, 1)
            local pointY = y + height - 1
                - math.floor(fraction * (height - 1) + 0.5)
            local pointX = plotX + plotW - n + i - 1

            -- Short vertical strokes connect consecutive samples.
            if previousY and math.abs(previousY - pointY) > 1 then
                local y1, y2 = math.min(previousY, pointY), math.max(previousY, pointY)
                for vy = y1 + 1, y2 - 1 do
                    writeAt(pointX, vy, "|", colors.blue)
                end
            end
            writeAt(pointX, pointY, i == n and "@" or "*",
                i == n and colors.yellow or colors.cyan)
            previousY = pointY
        end
    end

    local function compact(w, h, online)
        centered(1, w, 1, "DRACONIC // ENERGY CORE", colors.orange)
        rule(1, 2, w, colors.purple)
        if not online then
            centered(1, w, 4, "OFFLINE - waiting for sender", colors.red)
            return
        end
        local p = state.latest
        local pct = clamp(100 * p.stored / p.capacity, 0, 100)
        writeAt(2, 4, "STORED  " .. formatEnergy(p.stored) .. " OP", colors.yellow)
        writeAt(2, 5, "MAX     " .. formatEnergy(p.capacity) .. " OP", colors.lightGray)
        writeAt(2, 6, "CHARGE  " .. percentLabel(pct), levelColor(pct))
        if h >= 7 then fillBar(2, 7, w - 3, pct / 100, levelColor(pct)) end
        if h >= 9 then
            writeAt(2, 9, "IN  " .. (p.input ~= nil
                and ("+" .. formatEnergy(p.input) .. " OP/t") or "--"), colors.lime)
        end
        if h >= 10 then
            writeAt(2, 10, "OUT " .. (p.output ~= nil
                and ("-" .. formatEnergy(p.output) .. " OP/t") or "--"), colors.red)
        end
        if h >= 11 then
            writeAt(2, 11, "NET " .. (p.net ~= nil
                and ((p.net >= 0 and "+" or "") .. formatEnergy(p.net) .. " OP/t")
                or "--"), p.net ~= nil and (p.net < 0 and colors.red or colors.lime)
                or colors.gray)
        end
        if h >= 13 then
            writeAt(2, h, "ONLINE | Sender #" .. tostring(state.sender), colors.lime)
        end
    end

    local function draw()
        local w, h = refreshSurface()
        if surface.setVisible then surface.setVisible(false) end
        surface.setBackgroundColor(colors.black)
        surface.setTextColor(colors.white)
        surface.clear()
        if surface.setCursorBlink then surface.setCursorBlink(false) end

        local online = state.latest ~= nil
            and (nowMs() - state.receivedAt < HEARTBEAT_MS)

        if w < 72 or h < 28 then
            compact(w, h, online)
        else
            -- 8x5 monitor, scale 0.5: a broad two-column upper section
            -- and an equally broad live stored-energy history.
            writeAt(1, 1, string.rep(" ", w), colors.white, colors.purple)
            writeAt(3, 1, " DRACONIC // ENERGY CONTROL CENTER ",
                colors.white, colors.purple)
            writeAt(w - 10, 1, online and " ONLINE  " or " OFFLINE ",
                online and colors.lime or colors.red, colors.black)
            rule(1, 2, w, colors.orange, "=")
            writeAt(3, 3, "TIER VIII   /   OP TELEMETRY", colors.cyan)
            writeAt(w - 23, 3, "LIVE ENERGY NETWORK", colors.lightGray)

            local topY = 5
            local panelH = math.max(16, math.floor((h - 10) * 0.48))
            panelH = math.min(panelH, h - 17)
            local leftW = math.floor(w * 0.57)
            local rightX = leftW + 2
            local rightW = w - rightX + 1
            local historyY = topY + panelH + 1
            local historyH = h - historyY - 2

            panel(1, topY, leftW, panelH, " ENERGY RESERVOIR ", colors.purple)
            panel(rightX, topY, rightW, panelH, " LIVE POWER FLOW ", colors.orange)
            panel(1, historyY, w, historyH, " OP HISTORY / AUTO ZOOM ",
                colors.purple)

            if not online then
                centered(2, leftW - 2, topY + 5,
                    "NO LIVE TELEMETRY", colors.red)
                centered(2, leftW - 2, topY + 7,
                    "Waiting for sender...", colors.gray)
                centered(rightX + 1, rightW - 2, topY + 6,
                    "CORE LINK OFFLINE", colors.red)
                if state.sender then
                    writeAt(4, topY + 10,
                        "Last sender: #" .. tostring(state.sender), colors.gray)
                end
            else
                local p = state.latest
                local pct = clamp(100 * p.stored / p.capacity, 0, 100)
                local accent = levelColor(pct)
                writeAt(4, topY + 2, "STORED OP", colors.cyan)
                bigNumber(4, topY + 4, formatEnergy(p.stored), colors.yellow,
                    leftW - 8)
                writeAt(4, topY + 8, "CAPACITY: " .. formatEnergy(p.capacity) .. " OP",
                    colors.lightGray)
                writeAt(4, topY + 10, "CHARGE: " .. percentLabel(pct), accent)
                fillBar(4, topY + 12, leftW - 7, pct / 100, accent)
                if pct > 0 and pct < 1 then
                    writeAt(4, topY + 13, "MICRO CHARGE / BELOW BAR RESOLUTION",
                        colors.orange)
                elseif pct <= 5 then
                    writeAt(4, topY + 13, "LOW RESERVE", colors.red)
                end

                local rx = rightX + 3
                writeAt(rx, topY + 2, "ENERGY INPUT", colors.lime)
                writeAt(rx, topY + 3, p.input ~= nil
                    and ("+" .. formatEnergy(p.input) .. " OP/t")
                    or "-- unavailable", p.input ~= nil and colors.lime or colors.gray)
                rule(rx, topY + 5, rightW - 6, colors.gray)

                writeAt(rx, topY + 6, "ENERGY OUTPUT", colors.red)
                writeAt(rx, topY + 7, p.output ~= nil
                    and ("-" .. formatEnergy(p.output) .. " OP/t")
                    or "-- unavailable", p.output ~= nil and colors.red or colors.gray)
                rule(rx, topY + 9, rightW - 6, colors.gray)

                writeAt(rx, topY + 10, "NET TRANSFER", colors.cyan)
                local netColor = p.net ~= nil and
                    (p.net < 0 and colors.red or colors.lime) or colors.gray
                writeAt(rx, topY + 11, p.net ~= nil
                    and ((p.net >= 0 and "+" or "") .. formatEnergy(p.net) .. " OP/t")
                    or "-- measuring", netColor)

                if historyH >= 7 then
                    graph(3, historyY + 2, w - 6, historyH - 4)
                end
            end

            local ioSource = online and
                ((state.latest.inputSource == "pylon"
                  or state.latest.outputSource == "pylon") and "PYLON" or
                 (state.latest.inputSource or state.latest.outputSource
                    or "NOT AVAILABLE")) or "---"
            writeAt(2, h - 1, "SYSTEM STATUS", colors.orange)
            writeAt(18, h - 1,
                (online and "CONNECTED  " or "DISCONNECTED  ")
                .. " | SOURCE: " .. tostring(ioSource)
                .. " | SENDER #" .. tostring(state.sender or "?"),
                online and colors.lime or colors.red)
            writeAt(2, h, "DRACONIC EVOLUTION  /  CC:TWEAKED  /  v2.1",
                colors.lightGray)
            writeAt(w - 17, h, "CORE LINK " .. (online and "ACTIVE" or "LOST"),
                online and colors.cyan or colors.red)
        end

        if surface.setVisible then surface.setVisible(true) end
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
if args[1] == "selftest" then
    local good = {
        app = PROTOCOL, version = VERSION, stored = 500,
        capacity = 1000, input = 0, output = 20, net = -10
    }
    assert(validPacket(good), "valid packet")
    assert(not validPacket({ app = PROTOCOL, version = VERSION,
        stored = 5, capacity = 0 }), "zero capacity")
    assert(not validPacket({ app = PROTOCOL, version = VERSION,
        stored = 50, capacity = 20 }), "over capacity")
    assert(not validPacket({ app = "other", version = VERSION,
        stored = 5, capacity = 10 }), "wrong protocol")
    assert(not validPacket({ app = PROTOCOL, version = VERSION,
        stored = 5, capacity = 10, input = 0 / 0 }), "NaN rate")
    assert(formatEnergy(0) == "0", "zero formatting")
    assert(formatEnergy(1500) == "1.50k", "kilo formatting")
    assert(clamp(200, 0, 100) == 100, "clamping")
    print("Draconic Monitor selftest: PASS")
elseif args[1] == "scan" then
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
