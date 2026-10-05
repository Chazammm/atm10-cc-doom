# Agartha V2 media

Maximum-quality encode for the 143x81 monitor wall.

Profile:
- 10 FPS
- 143x81 CC character cells
- 286x243 semigraphics source raster
- 16-colour palette stabilised in 0.5 s windows
- ordered 8x8 dithering
- ANS-compressed combined 32vid
- exact continuous 48 kHz mono DFPWM stream
- 0.5 s audio prefetch across file boundaries
- 50 parts; largest part is about 11.1 MB, below CC:Tweaked's common 16 MiB HTTP download cap

Upload `agartha-v2-part01.32vid` through `agartha-v2-part50.32vid` into this folder.

Then reinstall the scripts and run:

```
agartha-v2
```

The V2 player defaults to `musicvideo.audio_mode=passthrough`, which preserves the original DFPWM bits through CC:Tweaked's server-side audio re-encoder and avoids the extra Lua decode/re-encode pass.
