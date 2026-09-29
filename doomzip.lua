-- ============================================================
-- DOOM-CC 1.0 ZIP CONTENT PROBE
-- READ ONLY: downloads the 301 KB release ZIP into RAM only.
--
-- Purpose:
--   Inspect the modern DOOM-CC 1.0 release package before we
--   install anything. Shows file names + compressed/uncompressed
--   sizes so we know whether it fits your ~1 MB CC disk.
-- ============================================================

local ZIP_URL =
    "https://github.com/MCJack123/DOOM-CC/releases/download/1.0/DOOM-CC.zip"

local function u16le(s, p)
    local a, b = s:byte(p, p + 1)
    if not b then return nil end
    return a + b * 256
end

local function u32le(s, p)
    local a, b, c, d = s:byte(p, p + 3)
    if not d then return nil end
    return a + b * 256 + c * 65536 + d * 16777216
end

local function human(n)
    if n >= 1024 * 1024 then
        return string.format("%.2f MiB", n / 1024 / 1024)
    elseif n >= 1024 then
        return string.format("%.1f KiB", n / 1024)
    end
    return tostring(n) .. " B"
end

term.clear()
term.setCursorPos(1, 1)

print("DOOM-CC 1.0 ZIP PROBE")
print("=====================")
print("")
print("Disk free: " .. tostring(fs.getFreeSpace("/")))
print("")

local allowed, reason = http.checkURL(ZIP_URL)
print("Release URL allowed: " .. tostring(allowed))
if not allowed then
    printError(tostring(reason))
    return
end

print("Downloading ZIP into RAM...")
local h, err = http.get(ZIP_URL, nil, true)
if not h then
    printError("Download failed:")
    printError(tostring(err))
    print("")
    print("Send me this exact error.")
    return
end

local z = h.readAll()
h.close()

if type(z) ~= "string" then
    printError("No binary ZIP body returned.")
    return
end

print("[OK] ZIP size: " .. human(#z))
print("")

local eocd
local start = math.max(1, #z - 65557)
for p = #z - 21, start, -1 do
    if z:sub(p, p + 3) == "PK\5\6" then
        eocd = p
        break
    end
end

if not eocd then
    printError("Could not find ZIP central directory.")
    return
end

local entries = u16le(z, eocd + 10)
local cdSize  = u32le(z, eocd + 12)
local cdOff   = u32le(z, eocd + 16)

if not entries or not cdOff then
    printError("Invalid ZIP EOCD.")
    return
end

local p = cdOff + 1
local files = {}
local totalUncompressed = 0
local totalCompressed = 0

for i = 1, entries do
    if z:sub(p, p + 3) ~= "PK\1\2" then
        printError("Central directory parse failed at entry " .. i)
        printError("Position: " .. tostring(p))
        return
    end

    local method     = u16le(z, p + 10)
    local compSize   = u32le(z, p + 20)
    local uncompSize = u32le(z, p + 24)
    local nameLen    = u16le(z, p + 28)
    local extraLen   = u16le(z, p + 30)
    local commentLen = u16le(z, p + 32)

    if not commentLen then
        printError("Truncated ZIP entry.")
        return
    end

    local name = z:sub(p + 46, p + 46 + nameLen - 1)

    files[#files + 1] = {
        name = name,
        comp = compSize,
        uncomp = uncompSize,
        method = method,
    }

    totalCompressed = totalCompressed + compSize
    totalUncompressed = totalUncompressed + uncompSize

    p = p + 46 + nameLen + extraLen + commentLen
end

table.sort(files, function(a, b)
    return a.uncomp > b.uncomp
end)

print("Files in release: " .. tostring(#files))
print("Unpacked total:   " .. human(totalUncompressed))
print("Compressed data:  " .. human(totalCompressed))
print("")
print("Largest files:")
print("--------------")

for i, f in ipairs(files) do
    print(string.format("%7d  %s", f.uncomp, f.name))
end

print("")
print("Compression methods:")
local methods = {}
for _, f in ipairs(files) do
    methods[f.method] = (methods[f.method] or 0) + 1
end
for m, count in pairs(methods) do
    print(" method " .. tostring(m) .. ": " .. tostring(count) .. " files")
end

local out = fs.open("doom_zip_probe.txt", "w")
if out then
    out.writeLine("DOOM-CC 1.0 ZIP")
    out.writeLine("ZIP bytes: " .. tostring(#z))
    out.writeLine("Unpacked bytes: " .. tostring(totalUncompressed))
    out.writeLine("")
    for _, f in ipairs(files) do
        out.writeLine(
            tostring(f.uncomp) .. "\t" ..
            tostring(f.comp) .. "\t" ..
            tostring(f.method) .. "\t" ..
            f.name
        )
    end
    out.close()
    print("")
    print("Saved list as doom_zip_probe.txt")
end

print("")
if totalUncompressed < fs.getFreeSpace("/") then
    print("RESULT: Full release fits on local disk.")
else
    print("RESULT: Full release is bigger than free disk.")
    print("We can still keep large files in RAM.")
end
