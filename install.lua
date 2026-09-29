-- ATM10 / CC:Tweaked DOOM installer
-- Installs the patched DOOM-CC runtime into /doomcc and creates /doomrun.
-- WAD is NOT stored on disk: doom.lua downloads doom1.wad into RAM at launch.

local BASE = "https://raw.githubusercontent.com/Chazammm/atm10-cc-doom/main/"
local DIR = "doomcc"

local files = {
  {src = "doom.lua",                          dst = DIR .. "/doom.lua",           binary = false},
  {src = "vendor/doomcc/pixelbox_lite.lua",  dst = DIR .. "/pixelbox_lite.lua",  binary = false},
  {src = "vendor/doomcc/rvdoom.elf",          dst = DIR .. "/rvdoom.elf",         binary = true},
  {src = "vendor/doomcc/.doomrc",             dst = DIR .. "/.doomrc",            binary = false},
}

local function download(url, path, binary)
  print("Downloading " .. path .. " ...")
  local h, err = http.get(url, nil, true)
  if not h then error("Download failed for " .. path .. ": " .. tostring(err)) end
  local data = h.readAll()
  h.close()
  if type(data) ~= "string" or #data == 0 then
    error("Empty download for " .. path)
  end
  local f = fs.open(path, binary and "wb" or "w")
  if not f then error("Cannot write " .. path) end
  f.write(data)
  f.close()
  print(("  OK (%d bytes)"):format(#data))
end

term.clear()
term.setCursorPos(1,1)
print("ATM10 DOOM INSTALLER")
print("====================")
print("")
print("Free space: " .. tostring(fs.getFreeSpace("/")))
print("")

if not fs.exists(DIR) then fs.makeDir(DIR) end

for _, item in ipairs(files) do
  if fs.exists(item.dst) then fs.delete(item.dst) end
  download(BASE .. item.src, item.dst, item.binary)
end

local launcher = [[
local old = shell.dir()
local ok, err

local function restore()
  pcall(function() shell.setDir(old) end)
end

local success, msg = xpcall(function()
  shell.setDir("doomcc")
  ok = shell.run("doom.lua")
end, function(e)
  return tostring(e)
end)

restore()

if not success then
  printError(msg)
elseif ok == false then
  printError("DOOM exited with an error.")
end
]]

if fs.exists("doomrun") then fs.delete("doomrun") end
local lf = fs.open("doomrun", "w")
lf.write(launcher)
lf.close()

print("")
print("================================")
print("INSTALL COMPLETE")
print("================================")
print("")
print("Installed runtime in /" .. DIR)
print("Created launcher: doomrun")
print("")
print("Run:")
print("  doomrun")
print("")
print("On first launch the 4 MiB shareware WAD")
print("is downloaded to RAM only.")
