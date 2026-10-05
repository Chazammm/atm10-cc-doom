# ATM10 8.2 / CC:Tweaked video playback

This folder contains the video/audio player for the 143x81 Advanced Monitor wall plus the Agartha profiles. It does not modify the DOOM setup.

## Install

Connect an Advanced Computer, one connected Advanced Monitor wall, and a CC:Tweaked Speaker, then run:

```
wget run https://raw.githubusercontent.com/Chazammm/atm10-cc-doom/main/youtube-video/install.lua
```

Commands installed at the computer root:

- `video <URL-or-file.32vid>` - play one combined 32vid.
- `agartha` - original 4 FPS media.
- `agartha-v2` - maximum-quality 10 FPS media.
- `videoinfo` - show the monitor cell/raster dimensions.

## Maximum-quality player

`32vid-player-fast.lua` is the preferred player. It keeps the old Sanjuuni mini player as a compatibility fallback.

It adds:

- late-frame dropping instead of allowing video to drift behind audio;
- decode-ahead and timer-based presentation;
- changed-row and changed-palette rendering;
- one continuous A/V clock across playlist parts;
- speaker backpressure handling;
- optional DFPWM passthrough mode. Because CC:Tweaked re-encodes `playAudio` PCM to DFPWM internally, the passthrough mode maps each stored DFPWM bit directly to a full-scale PCM sign value. This preserves the stored DFPWM bitstream through the server encoder and avoids a Lua DFPWM decode followed by a second lossy encode.

Useful settings:

```
settings set musicvideo.audio_mode passthrough
settings set musicvideo.drop_late_frames true
settings set musicvideo.drop_factor 1.0
settings set musicvideo.diff_rows true
settings set musicvideo.stats true
settings save
```

## Agartha V2

V2 is built specifically for the detected 143x81 monitor at text scale 0.5:

- 10 FPS;
- 143x81 CC cells / 286x243 semigraphics raster;
- aspect-ratio-preserving 16:9 letterbox;
- adaptive 16-colour palette stabilised over 0.5-second windows;
- 8x8 ordered dithering for temporal stability;
- per-frame ANS video compression;
- exact continuous 48 kHz mono DFPWM;
- 0.5 s of next-part audio prefetched at each boundary;
- 50 independently valid 32vid parts, each under about 11.1 MB.

The files belong in `youtube-video/media-v2/` and are named `agartha-v2-part01.32vid` through `agartha-v2-part50.32vid`.

Once those files are uploaded, reinstall the scripts and run:

```
agartha-v2
```

The original 4 FPS media remains in `youtube-video/media/`, so it continues to work as a fallback.
