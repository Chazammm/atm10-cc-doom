-- Mocked CC:Tweaked API smoke test. Run with lua5.3 from repository root.
local originalPrint = print
local log = {}
print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do
        parts[#parts + 1] = tostring(select(i, ...))
    end
    log[#log + 1] = table.concat(parts, "\t")
end

shell = { getRunningProgram = function() return "draconic-monitor/draconic.lua" end }
fs = {
    getDir = function() return "draconic-monitor" end,
    combine = function(a, b) return a .. "/" .. b end
}
local names = { "left", "right", "top", "back" }
local types = {
    left = { "draconic_rf_storage", "energy_storage" },
    right = { "energy_detector" },
    top = { "monitor" },
    back = { "modem" }
}
local methodMap = {
    left = { "getEnergyStored", "getMaxEnergyStored" },
    right = { "getTransferRate", "getTransferRateLimit" },
    top = { "getSize", "setTextScale" },
    back = { "open", "isWireless" }
}
peripheral = {
    getNames = function() return names end,
    getMethods = function(name) return methodMap[name] end,
    isPresent = function(name) return methodMap[name] ~= nil end,
    hasType = function(name, wanted)
        for _, kind in ipairs(types[name] or {}) do
            if kind == wanted then return true end
        end
        return false
    end,
    getType = function(name) return table.unpack(types[name]) end
}

local chunk = assert(loadfile("draconic-monitor/draconic.lua"))
chunk("scan")
local result = table.concat(log, "\n")
assert(result:find("Storage: 1 | Detector: 1 | Monitor: 1 | Modem: 1", 1, true),
    "Unexpected peripheral scan result:\n" .. result)
chunk("selftest")
result = table.concat(log, "\n")
assert(result:find("Draconic Monitor selftest: PASS", 1, true),
    "No selftest success:\n" .. result)
-- Render the new dashboard without Minecraft, using mock CC:Tweaked APIs.
-- Check both a large 8x5-style monitor and a compact terminal.
local colorNames = {
    "white", "orange", "red", "yellow", "gray", "black", "cyan",
    "purple", "lightGray", "lightBlue", "lime", "blue", "magenta"
}
colors = {}
for i, name in ipairs(colorNames) do colors[name] = 2 ^ (i - 1) end

local currentScreen
local function newScreen(width, height)
    local cursorX, cursorY = 1, 1
    local writes = {}
    local screen = {}
    function screen.getSize() return width, height end
    function screen.setBackgroundColor(_) end
    function screen.setTextColor(_) end
    function screen.setCursorBlink(_) end
    function screen.setVisible(_) end
    function screen.clear()
        writes = {}
    end
    function screen.setCursorPos(x, y)
        assert(x == math.floor(x) and y == math.floor(y), "non-integer coordinates")
        cursorX, cursorY = x, y
    end
    function screen.write(value)
        value = tostring(value)
        assert(cursorX >= 1 and cursorX <= width, "bad cursor X")
        assert(cursorY >= 1 and cursorY <= height, "bad cursor Y")
        assert(cursorX + #value - 1 <= width, "write past screen width")
        writes[#writes + 1] = value
    end
    function screen.contents() return table.concat(writes, "\n") end
    return screen
end
term = { current = function() return currentScreen end }
window = { create = function(parent, x, y, width, height, visible)
    assert(width > 0 and height > 0, "invalid window size")
    return parent
end }
fs.exists = function(path) return path:find("draconic.cfg", 1, true) ~= nil end
fs.open = function()
    return { readAll = function() return "configuration" end, close = function() end }
end
textutils = { unserialize = function()
    return { version = 2, mode = "display" }
end }
os.epoch = function() return 123456789000 end
local receives = 0
rednet = {
    open = function() end,
    receive = function(protocol, timeout)
        assert(protocol == "draconic.monitor.v2", "protocol changed")
        receives = receives + 1
        if receives > 2 then error("DISPLAY_SMOKE_DONE", 0) end
        return 42, {
            app = "draconic.monitor.v2", version = 2, source = 42,
            stored = 3480000000000 - (receives * 52600),
            capacity = 9200000000000000000,
            input = 0, output = 52600, net = -52600,
            inputSource = "pylon", outputSource = "pylon",
            netSource = "pylon"
        }
    end
}

local function testDisplay(width, height)
    receives = 0
    currentScreen = newScreen(width, height)
    local ok, err = pcall(chunk)
    assert(not ok and tostring(err):find("DISPLAY_SMOKE_DONE", 1, true),
        "display crashed: " .. tostring(err))
    local rendered = currentScreen.contents()
    assert(rendered:find("OP/t", 1, true), "no OP/t reading shown")
    assert(rendered:find("3480000000000", 1, true) == nil,
        "unformatted large number")
    if width >= 72 and height >= 28 then
        assert(rendered:find("ENERGY CONTROL CENTER", 1, true),
            "premium header missing")
        assert(rendered:find("OP HISTORY", 1, true),
            "live history panel missing")
        assert(rendered:find("CORE LINK ACTIVE", 1, true),
            "online status missing")
    else
        assert(rendered:find("CHARGE", 1, true),
            "compact fallback missing")
    end
end
testDisplay(109, 43)
testDisplay(48, 17)
print = originalPrint
print("Mock scan + selftest + premium dashboard (109x43, 48x17): PASS")

