-- CC:Tweaked: computer backup to GitHub
-- Run manually ON the computer you are backing up, with its owner's permission.
-- No remote access, claim bypass or automatic startup behaviour.
local OWNER = "Chazammm"
local REPO = "atm10-cc-doom"
local BRANCH = "main"
local DESTINATION = "copied-programs"
local MAX_FILE_SIZE = 768 * 1024 -- conservative per-file HTTP size limit (768 KiB)

if not http then
  printError("HTTP ist auf diesem Computer deaktiviert.")
  return
end

local allowed, reason = http.checkURL("https://api.github.com")
if not allowed then
  printError("GitHub-API nicht erreichbar: " .. tostring(reason))
  return
end

local okBase, builtInBase64 = pcall(require, "cc.base64")
local function encodeBase64(data)
  if okBase and builtInBase64 and builtInBase64.encode then
    return builtInBase64.encode(data)
  end

  -- Fallback for older CC:Tweaked releases.
  local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
  local out = {}
  for i = 1, #data, 3 do
    local a, b, c = data:byte(i, i + 2)
    local n = a * 65536 + (b or 0) * 256 + (c or 0)
    local x = math.floor(n / 262144) % 64 + 1
    local y = math.floor(n / 4096) % 64 + 1
    local z = math.floor(n / 64) % 64 + 1
    local w = n % 64 + 1
    out[#out + 1] = chars:sub(x, x)
    out[#out + 1] = chars:sub(y, y)
    out[#out + 1] = b and chars:sub(z, z) or "="
    out[#out + 1] = c and chars:sub(w, w) or "="
    if i % 3000 == 1 then sleep(0) end
  end
  return table.concat(out)
end

local function encodeSegment(s)
  return (s:gsub("([^%w%-%._~])", function(c)
    return string.format("%%%02X", c:byte())
  end))
end

local function encodePath(path)
  local parts = {}
  for part in path:gmatch("[^/]+") do
    parts[#parts + 1] = encodeSegment(part)
  end
  return table.concat(parts, "/")
end

-- Only the computer's own HDD is collected. /rom, /disk, and other
-- peripheral mounts are not copied.
local files = {}
local function scan(dir)
  for _, name in ipairs(fs.list(dir)) do
    local full = fs.combine(dir, name)
    if fs.getDrive(full) == "hdd" then
      if fs.isDir(full) then
        local before = #files
        scan(full)
        if #files == before then
          files[#files + 1] = {
            path = fs.combine(full, ".gitkeep"):gsub("^/", ""),
            size = 0,
            placeholder = true,
          }
        end
      else
        files[#files + 1] = {
          path = full:gsub("^/", ""),
          size = fs.getSize(full),
        }
      end
    end
  end
end

local scanned, scanError = pcall(scan, "/")
if not scanned then
  printError("Dateisuche fehlgeschlagen: " .. tostring(scanError))
  return
end
table.sort(files, function(a, b) return a.path < b.path end)

if #files == 0 then
  print("Keine Dateien auf dieser Festplatte gefunden.")
  return
end

term.clear()
term.setCursorPos(1, 1)
print("CC:Tweaked -> GitHub-Backup")
print("Repository: " .. OWNER .. "/" .. REPO)
print("ACHTUNG: Dieses Repository ist OEFFENTLICH!")
print("Dateien mit Passwoertern/Keys NICHT hochladen.")
print("")
print("Dateiliste (auch Unterordner):")
local preview = {}
local tooLarge = 0
for _, file in ipairs(files) do
  local marker = ""
  if file.size > MAX_FILE_SIZE then
    marker = " [ZU GROSS - SKIP]"
    tooLarge = tooLarge + 1
  elseif file.placeholder then
    marker = " [LEERER ORDNER]"
  end
  preview[#preview + 1] = file.path .. marker
end
textutils.pagedPrint(table.concat(preview, "\n"))
print("")
print("Gefunden: " .. #files .. " Eintraege; zu gross: " .. tooLarge)
print("ROM und externe Disketten sind ausgeschlossen.")
print("")

local defaultName = "computer-" .. tostring(os.getComputerID())
print("Backup-Name, Enter fuer " .. defaultName .. ":")
write("> ")
local name = read()
if name == "" then name = defaultName end
if #name > 64 or not name:match("^[%w_%-]+$") then
  printError("Name nur aus A-Z, 0-9, _ und - (max. 64 Zeichen).")
  return
end

local prefix = DESTINATION .. "/" .. name
print("Ziel: " .. prefix .. "/")
print("Alle angezeigten Dateien koennen danach")
print("oeffentlich auf GitHub gelesen werden.")
write("Wirklich hochladen? Tippe JA: ")
if read() ~= "JA" then
  print("Abgebrochen. Keine Dateien hochgeladen.")
  return
end

print("Fine-grained GitHub-Token eingeben.")
print("Nur Repo " .. REPO .. ", Contents: Read/Write.")
print("Token wird NICHT gespeichert.")
write("Token: ")
local token = read("*")
if not token or token == "" then
  printError("Kein Token eingegeben.")
  return
end

local function apiRequest(method, url, body)
  local request = {
    url = url,
    method = method,
    headers = {
      ["Authorization"] = "Bearer " .. token,
      ["Accept"] = "application/vnd.github+json",
      ["Content-Type"] = "application/json",
      ["User-Agent"] = "CC-Tweaked-Computer-Backup",
      ["X-GitHub-Api-Version"] = "2022-11-28",
    },
    timeout = 30,
  }
  if body then request.body = body end

  local queued, err = http.request(request)
  if not queued then return nil, tostring(err) end

  while true do
    local event, requestedUrl, data, failureResponse = os.pullEvent()
    if requestedUrl == url then
      local response = nil
      local networkError = nil
      if event == "http_success" then
        response = data
      elseif event == "http_failure" then
        response = failureResponse
        networkError = tostring(data)
      end
      if response then
        local status = response.getResponseCode()
        local payload = response.readAll() or ""
        response.close()
        return status, payload
      elseif networkError then
        return nil, networkError
      end
    end
  end
end

local function errorMessage(body)
  local decoded = textutils.unserialiseJSON(body or "")
  if type(decoded) == "table" and type(decoded.message) == "string" then
    return decoded.message
  end
  return "Unbekannte API-Antwort"
end

local successCount, failedCount, skippedCount = 0, 0, 0
for index, file in ipairs(files) do
  if file.size > MAX_FILE_SIZE then
    skippedCount = skippedCount + 1
    print("[SKIP] " .. file.path .. " (zu gross)")
  else
    print(("[%d/%d] %s"):format(index, #files, file.path))
    local content
    if file.placeholder then
      content = ""
    else
      local handle, err = fs.open("/" .. file.path, "rb")
      if not handle then
        printError("  Lesefehler: " .. tostring(err))
        failedCount = failedCount + 1
      else
        content = handle.readAll()
        handle.close()
        if content == nil then
          printError("  Datei konnte nicht gelesen werden.")
          failedCount = failedCount + 1
        end
      end
    end

    if content ~= nil then
      local path = prefix .. "/" .. file.path
      local url = "https://api.github.com/repos/" .. OWNER .. "/" .. REPO
        .. "/contents/" .. encodePath(path)

      local status, response = apiRequest("GET", url)
      local existingSha = nil
      local proceed = true
      if status == 200 then
        local object = textutils.unserialiseJSON(response)
        existingSha = type(object) == "table" and object.sha or nil
        if not existingSha then
          printError("  Vorhandene Datei hat keine SHA.")
          proceed = false
        end
      elseif status ~= 404 then
        printError("  GitHub-Abfrage: " .. tostring(status or response))
        if status then printError("  " .. errorMessage(response)) end
        proceed = false
      end

      if proceed then
        local payload = {
          message = "Backup " .. name .. ": " .. file.path,
          content = encodeBase64(content),
          branch = BRANCH,
        }
        if existingSha then payload.sha = existingSha end
        local code, answer = apiRequest("PUT", url, textutils.serialiseJSON(payload))
        if code == 200 or code == 201 then
          successCount = successCount + 1
          print("  OK")
        else
          failedCount = failedCount + 1
          printError("  Upload fehlgeschlagen: " .. tostring(code or answer))
          if code then printError("  " .. errorMessage(answer)) end
          if code == 401 or code == 403 then
            printError("Authentifizierung/Rate-Limit: Abbruch.")
            break
          end
        end
      else
        failedCount = failedCount + 1
        if status == 401 or status == 403 then
          printError("Authentifizierung/Rate-Limit: Abbruch.")
          break
        end
      end
    end
  end
end

token = nil
print("")
print("Backup fertig. OK: " .. successCount ..
  " | Fehler: " .. failedCount .. " | Uebersprungen: " .. skippedCount)
print("https://github.com/" .. OWNER .. "/" .. REPO ..
  "/tree/" .. BRANCH .. "/" .. prefix)
print("Bei Fehlern mit demselben Namen erneut starten.")
