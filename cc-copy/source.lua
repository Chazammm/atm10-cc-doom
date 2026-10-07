-- CC:Tweaked source exporter for computers you control.
local PROTOCOL = "cc-copy.v1"
local CHUNK = 6000

local args = { ... }
local receiverId = tonumber(args[1])
local root = shell.resolve(args[2] or "/")
local label = args[3] or os.getComputerLabel() or ("computer-" .. os.getComputerID())

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

local function norm(path)
    path = fs.combine("/", path or "")
    if path ~= "/" then path = path:gsub("/+$", "") end
    return path
end

local function excluded(path)
    path = norm(path)
    return path == "/rom"
        or path:sub(1, 5) == "/rom/"
        or path == "/cc-copy"
        or path:sub(1, 9) == "/cc-copy/"
        or fs.getName(path) == ".settings"
end

local function isCode(path)
    if fs.isDir(path) then return false end
    local name = fs.getName(path):lower()
    return name:match("%.lua$") ~= nil or name == "startup"
end

local function relative(path)
    path, root = norm(path), norm(root)
    if root == "/" then return path:gsub("^/", "") end
    return path:sub(#root + 2)
end

local function scan(dir, files)
    if excluded(dir) then return end
    for _, name in ipairs(fs.list(dir)) do
        local path = fs.combine(dir, name)
        if not excluded(path) then
            if fs.isDir(path) then
                scan(path, files)
            elseif isCode(path) and (fs.getSize(path) or 0) <= 512 * 1024 then
                files[#files + 1] = { path = relative(path), size = fs.getSize(path) or 0 }
            end
        end
    end
end

local function sendLarge(target, kind, nonce, data)
    local total = math.max(1, math.ceil(#data / CHUNK))
    for i = 1, total do
        local first = (i - 1) * CHUNK + 1
        rednet.send(target, {
            op = kind .. "_chunk",
            nonce = nonce,
            index = i,
            total = total,
            data = data:sub(first, first + CHUNK - 1),
        }, PROTOCOL)
    end
end

if not receiverId then
    print("Computer ID: " .. os.getComputerID())
    print("Usage: copy-source <receiver-id> [root] [label]")
    return
end
if not fs.exists(root) or not fs.isDir(root) then error("Invalid root: " .. root, 0) end
if openModems() == 0 then error("No modem attached.", 0) end

local files = {}
scan(root, files)
table.sort(files, function(a,b) return a.path < b.path end)
local allowed = {}
for _, item in ipairs(files) do allowed[item.path] = true end

print("CC Copy source READY")
print("Source ID : " .. os.getComputerID())
print("Receiver  : " .. receiverId)
print("Root      : " .. root)
print("Files     : " .. #files)
print("Ctrl+T stops sharing.")

while true do
    local sender, msg = rednet.receive(PROTOCOL)
    if sender == receiverId and type(msg) == "table" and type(msg.nonce) == "string" then
        if msg.op == "manifest" then
            sendLarge(sender, "manifest", msg.nonce, textutils.serialize({
                computer_id = os.getComputerID(),
                label = label,
                root = root,
                files = files,
            }, { compact = true }))
        elseif msg.op == "get" then
            local rel = tostring(msg.path or "")
            if not allowed[rel] then
                rednet.send(sender, { op="error", nonce=msg.nonce, error="not shared" }, PROTOCOL)
            else
                local full = fs.combine(root, rel)
                local h = fs.open(full, "rb")
                if not h then
                    rednet.send(sender, { op="error", nonce=msg.nonce, error="cannot open" }, PROTOCOL)
                else
                    local data = h.readAll()
                    h.close()
                    sendLarge(sender, "file", msg.nonce, data)
                end
            end
        end
    end
end
