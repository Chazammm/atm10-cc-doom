-- Optional CC-Music autostart
local path = "/ccmusic/player.lua"
if not fs.exists(path) then
  printError("CC-Music not installed. Run the GitHub installer first.")
  return
end
shell.run(path)
