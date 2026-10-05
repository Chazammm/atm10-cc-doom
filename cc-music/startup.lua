-- Auto-start CC-Music.
-- Keep player.lua in the same directory as this startup.lua.
local running = shell.getRunningProgram and shell.getRunningProgram() or "startup.lua"
local dir = fs.getDir(running)
local path = fs.combine(dir, "player.lua")
if not fs.exists(path) then
    printError("CC-Music: player.lua not found next to startup.lua")
    return
end
shell.run(path)