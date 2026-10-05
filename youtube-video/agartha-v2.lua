-- Agartha V2: maximum-quality 10 FPS encode.
local base = settings.get("agartha.v2_base_url")
  or "https://raw.githubusercontent.com/Chazammm/atm10-cc-doom/main/youtube-video/media-v2/"

-- V2 is 50 independent HTTP-safe parts. The playlist player keeps one global
-- media clock across parts and V2 pre-buffers 0.5 s of audio at each boundary.
shell.run("/playlist.lua", base, "agartha-v2-part", "50")
