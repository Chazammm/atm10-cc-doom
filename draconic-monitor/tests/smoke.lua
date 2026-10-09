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
print = originalPrint
print("Mock scan + selftest: PASS")
