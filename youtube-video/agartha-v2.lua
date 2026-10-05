-- Agartha V2: maximum-quality 10 FPS encode.
-- Media lives in a GitHub Release instead of repository history. This avoids
-- bloating the git repository with ~0.5 GB of binary video data.
local base = settings.get("agartha.v2_base_url")
  or "https://github.com/Chazammm/atm10-cc-doom/releases/download/agartha-v2/"

-- CC:Tweaked follows HTTP redirects by default, so GitHub release assets can
-- be streamed directly through the existing HTTP player.
shell.run("/playlist.lua", base, "agartha-v2-part", "50")
