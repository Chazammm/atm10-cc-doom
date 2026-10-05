-- Playlist for the converted Agartha upload.
local base = settings.get("agartha.base_url")
  or "https://raw.githubusercontent.com/Chazammm/atm10-cc-doom/main/youtube-video/media/"

shell.run("/playlist.lua", base, "agartha-part", "13")
