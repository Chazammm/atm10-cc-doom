# ATM10 8.2 / CC:Tweaked video playback

This folder contains the monitor video/audio player and the Agartha profiles. It only uses CC:Tweaked features already present in ATM10; no extra Minecraft mod is required.

## Install

Connect an Advanced Computer, one connected Advanced Monitor wall, and at least one CC:Tweaked Speaker:

```
wget run https://raw.githubusercontent.com/Chazammm/atm10-cc-doom/main/youtube-video/install.lua
```

Main commands:

- `agartha-v3` - 20 FPS V3 for the final 8-wide x 5-high monitor wall.
- `stereosetup` - configure two normal CC:Tweaked speakers as LEFT/RIGHT.
- `agartha-v2` - legacy 10 FPS profile for the old 143x81 layout.
- `video <URL-or-file.32vid>` - play a single combined 32vid.
- `videoinfo` - show the monitor dimensions.
- `videobench20` - 20 FPS renderer stress test.

## V3

Agartha V3 was rebuilt from the original source for the final monitor geometry:

- 164x67 CC character cells at text scale 0.5;
- 328x201 semigraphics raster;
- 328x185 active 16:9-ish video area with symmetric 8-pixel letterbox bars;
- 20 real video frames per second;
- adaptive 16-colour palettes updated in short temporal windows with stable palette slots;
- low-strength fixed ordered dithering to retain gradients without the heavy crawling/noise of V2;
- per-frame ANS compression;
- 98,943 video frames;
- 86 HTTP-safe parts, all below CC:Tweaked/ATM10's 16 MiB per-request limit.

### Audio

V3 contains three continuous 48 kHz DFPWM audio streams:

- mono fallback;
- left channel;
- right channel.

With one speaker, the mono fallback is used automatically. With two speakers configured through `stereosetup`, V3 uses separate left/right audio. Legacy V1/V2 mono media is mirrored to both configured speakers instead of becoming silent.

Audio is prepared with high-quality 44.1 -> 48 kHz SoXR resampling, a gentle 16 kHz low-pass before the 1-bit DFPWM stage, limiter headroom, and FFmpeg's DFPWM1a encoder. The player uses DFPWM passthrough so CC:Tweaked's unavoidable internal encoder reproduces the stored bitstream rather than adding an extra lossy decode/re-encode stage.

## Player optimisations

`32vid-player-fast.lua` adds:

- audio backpressure handling;
- DFPWM passthrough;
- optional true two-speaker stereo;
- late-frame dropping to protect A/V sync;
- decode-ahead;
- timer-based 20 FPS presentation;
- row-diff rendering;
- palette-diff rendering;
- one continuous media clock across HTTP parts;
- symmetric crop/centering for older media;
- palette-safe repainting of unused monitor areas.

Useful settings:

```
settings set musicvideo.audio_mode passthrough
settings set musicvideo.drop_late_frames true
settings set musicvideo.drop_factor 1.0
settings set musicvideo.diff_rows true
settings save
```

For diagnostics:

```
settings set musicvideo.stats true
```

## Uploading V3

The V3 binary media is hosted as GitHub Release assets under tag `agartha-v3`, rather than being committed into Git history.

Download/extract all V3 packs into one folder, download `upload-v3.ps1`, then run:

```powershell
powershell -ExecutionPolicy Bypass -File .\upload-v3.ps1 -Source "C:\path\to\V3"
```

The uploader verifies all 86 parts, creates the release when necessary, and uploads in batches. It can safely be rerun after interruption.
