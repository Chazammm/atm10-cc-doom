-- CC:Tweaked receiver + GitHub uploader.
-- The source computer must explicitly run copy-source and whitelist this computer ID.
local PROTOCOL = "cc-copy.v1"
local REPO = "Chazammm/atm10-cc-doom"
local BRANCH = "main"
local API_BASE = "https://api.github.com/repos/" .. REPO .. "/contents/"
local TIMEOUT = 12

local args = { ... }

local function openModems()
    local count = 0
    for _, name in ipairs(peripheral.getNames()) do
        if peripheral.hasType(name, "modem") then
            if not rednet.isOpen(name) then rednet.open(name) end
            count = count + 1
        end
    end
    return count
end

local function b64(data)
    local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    local out = {}
    for i = 1, #data, 3 do
        local a = data:byte(i) or 0
        local b = data:byte(i + 1) or 0
        local c = data:byte(i + 2) or 0
        local n = a * 65536 + b * 256 + c
        local i1 = math.floor(n / 262144) % 64 + 1
        local i2 = math.floor(n / 4096) % 64 + 1
        local i3 = math.floor(n / 64) % 64 + 1
        local i4 = n % 64 + 1
        out[#out + 1] = chars:sub(i1, i1)
        out[#out + 1] = chars:sub(i2, i2)
        out[#out + 1] = i + 1 <= #data and chars:sub(i3, i3) or "="
        out[#out + 1] = i + 2 <= #data and chars:sub(i4, i4) or "="
    end
    return table.concat(out)
end

local function urlPath(path)
    return (tostring(path):gsub("([^%w%-%._~/])", function(c)
        return string.format("%%%02X", string.byte(c))
    end))
end

local function safeLabel(s)
    s = tostring(s or ""):gsub("[^%w%._%-]+", "-"):gsub("%-+", "-")
    s = s:gsub("^%-+", ""):gsub("%-+$", "")
    return s ~= "" and s:sub(1, 48) or "computer"
end

local function nonce()
    local t = os.epoch and os.epoch("utc") or math.floor(os.clock() * 100000)
    return tostring(os.getComputerID()) .. "-" .. tostring(t) .. "-" .. tostring(math.random(100000,999999))
end

local function receiveLarge(sourceId, kind, id)
    local parts, total = {}, nil
    while true do
        local sender, msg = rednet.receive(PROTOCOL, TIMEOUT)
        if not sender then return nil, "timeout waiting for " .. kind end
        if sender == sourceId and type(msg) == "table" and msg.nonce == id then
            if msg.op == "error" then return nil, tostring(msg.error or "source error") end
            if msg.op == kind .. "_chunk" then
                local index = tonumber(msg.index)
                total = tonumber(msg.total) or total
                if index and type(msg.data) == "string" then parts[index] = msg.data end
                if total then
                    local complete = true
                    for i = 1, total do
                        if not parts[i] then complete = false break end
                    end
                    if complete then return table.concat(parts) end
                end
            end
        end
    end
end

local function requestLarge(sourceId, op, extra, kind)
    for attempt = 1, 3 do
        local id = nonce()
        local msg = { op = op, nonce = id }
        if extra then for k,v in pairs(extra) do msg[k] = v end end
        rednet.send(sourceId, msg, PROTOCOL)
        local data, err = receiveLarge(sourceId, kind, id)
        if data then return data end
        if attempt == 3 then return nil, err end
        sleep(0.25 * attempt)
    end
end

local function githubPut(token, path, content, message)
    local payload = textutils.serializeJSON({
        message = message,
        content = b64(content),
        branch = BRANCH,
    })
    local h, err, failed = http.post({
        url = API_BASE .. urlPath(path),
        body = payload,
        method = "PUT",
        headers = {
            ["Accept"] = "application/vnd.github+json",
            ["Authorization"] = "Bearer " .. token,
            ["X-GitHub-Api-Version"] = "2022-11-28",
            ["Content-Type"] = "application/json",
            ["User-Agent"] = "CC-Tweaked-Program-Copier/1.0",
        },
        timeout = 30,
    })
    if not h then
        local detail = tostring(err or "request failed")
        if failed then
            local code = failed.getResponseCode and failed.getResponseCode() or "?"
            local body = failed.readAll and failed.readAll() or ""
            failed.close()
            detail = "HTTP " .. tostring(code) .. ": " .. body
        end
        return false, detail
    end
    local code = h.getResponseCode and h.getResponseCode() or 0
    local body = h.readAll()
    h.close()
    if code ~= 200 and code ~= 201 then return false, "HTTP " .. code .. ": " .. body end
    return true
end

if not args[1] or args[1] == "help" then
    print("CC Copy -> GitHub")
    print("This computer ID: " .. os.getComputerID())
    print("")
    print("Usage: copy-github <source-id>")
    print("")
    print("On source first:")
    print("  copy-source " .. os.getComputerID() .. " / [label]")
    return
end

local sourceId = tonumber(args[1])
if not sourceId then error("Invalid source computer ID.", 0) end
if openModems() == 0 then error("No modem attached.", 0) end
if not http then error("HTTP API is disabled.", 0) end

print("GitHub token is used only for this run and is not saved.")
print("Use a fine-grained token limited to " .. REPO)
print("Permission: Contents -> Read and write")
write("Token: ")
local token = tostring(read("*") or ""):gsub("%s+", "")
if token == "" then error("No token entered.", 0) end

math.randomseed((os.epoch and os.epoch("utc") or os.clock()*100000) + os.getComputerID())

write("Requesting manifest from " .. sourceId .. " ... ")
local raw, err = requestLarge(sourceId, "manifest", nil, "manifest")
if not raw then print("FAILED"); error(err or "No response", 0) end
local manifest = textutils.unserialize(raw)
if type(manifest) ~= "table" or type(manifest.files) ~= "table" then
    print("FAILED")
    error("Invalid source manifest.", 0)
end
print("OK")

local stamp = os.date("!%Y-%m-%d_%H-%M-%S")
local ms = os.epoch and os.epoch("utc") % 1000 or 0
local base = string.format(
    "copied-programs/computer-%d-%s/%s-%03d",
    tonumber(manifest.computer_id) or sourceId,
    safeLabel(manifest.label),
    stamp,
    ms
)

print("Destination: " .. base)
print("Files: " .. #manifest.files)
print("")

local meta = textutils.serializeJSON({
    source_computer_id = manifest.computer_id or sourceId,
    source_label = manifest.label,
    source_root = manifest.root,
    copied_utc = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    file_count = #manifest.files,
}, true) or "{}"

local ok, uploadErr = githubPut(token, base .. "/_snapshot.json", meta, "Add CC computer snapshot metadata")
if not ok then error(uploadErr, 0) end

local uploaded, failedCount = 0, 0
for i, item in ipairs(manifest.files) do
    local rel = tostring(item.path or "")
    write(string.format("[%d/%d] %s ... ", i, #manifest.files, rel))
    if rel:find("..", 1, true) or rel:sub(1,1) == "/" then
        print("SKIPPED unsafe path")
        failedCount = failedCount + 1
    else
        local data, transferErr = requestLarge(sourceId, "get", { path = rel }, "file")
        if not data then
            print("TRANSFER FAILED")
            printError(transferErr or "unknown error")
            failedCount = failedCount + 1
        else
            local success, ghErr = githubPut(
                token,
                base .. "/" .. rel,
                data,
                "Copy " .. rel .. " from CC computer " .. sourceId
            )
            if success then
                print("OK")
                uploaded = uploaded + 1
            else
                print("GITHUB FAILED")
                printError(ghErr)
                failedCount = failedCount + 1
            end
        end
    end
end

token = nil
print("")
print("Uploaded: " .. uploaded)
print("Failed  : " .. failedCount)
print("GitHub path: " .. base)
