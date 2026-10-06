# CC-Music 3.0 for ATM10 8.2 / CC:Tweaked

A large-monitor music player for CC:Tweaked, built around the `Di33le/CC-Music` library and extended with true stereo support.

## Highlights

- Dynamically indexes every `.sqsh` track in `Di33le/CC-Music`.
- Backward-compatible `SQSH1` mono playback.
- New streaming `SQSH2` true-stereo container with interleaved LEFT/RIGHT DFPWM blocks.
- Native 48 kHz DFPWM passthrough mode to avoid an unnecessary lossy DFPWM decode/re-encode cycle.
- HQ 24 kHz -> 48 kHz resampling for the legacy Di33le library.
- True synchronized LEFT/RIGHT speaker routing with balance control and automatic mono fallback.
- Reuses the Agartha/video stereo mapping automatically when CC-Music has no separate mapping.
- Audio Profile A mastering for newly converted music: SoXR 48 kHz, neutral 16 kHz low-pass and limiter headroom.
- Real 16-band Goertzel visualizer based on the actual audio.
- Synchronized LRC lyrics.
- Up-next queue, durations, play/pause, previous/next, shuffle, loop and volume.
- Advanced Monitor touch controls.
- Keyboard search.
- Optional Rednet remote.
- GitHub library cache and stream retries.
- Dirty-line framebuffer rendering to reduce monitor traffic.
- Mid-buffer interruption logic for responsive pause/volume changes.

## Optimal in-game build

### Best monitor size

**8 blocks wide x 6 blocks high** is the optimal layout for this player.

At text scale `0.5` this is approximately:

```
164 x 81 CC character cells
```

Why 8x6 is better for music than the 8x5 video wall:

- the music UI does not need a 16:9 video aspect ratio;
- the extra vertical block gives the visualizer substantially more height;
- the queue gains roughly 14 extra visible rows;
- lyrics, transport controls and volume do not need to compete for vertical space;
- 8 blocks gives the queue enough horizontal room for track names and durations.

**8x5 / 164x67 still works very well**, but if you are building a dedicated wall for CC-Music, use **8 wide x 6 high**.

Recommended physical setup:

```
[ LEFT SPEAKER ]   [ 8 x 6 ADVANCED MONITOR ]   [ RIGHT SPEAKER ]
                          |
                   Advanced Computer
```

Connect the monitor and speakers to the same computer through wired modems/network cable.

## Install

From the CC:Tweaked computer:

```
wget run https://raw.githubusercontent.com/Chazammm/atm10-cc-doom/cc-music-player/cc-music/install.lua
```

Then:

```
music
```

For stereo setup:

```
music-stereo
```

If the Agartha video player already has LEFT/RIGHT speakers configured, `music-stereo` can reuse those names.

## Audio modes

### SQSH1

Legacy format:

- one DFPWM channel;
- existing Di33le tracks are normally 24 kHz mono;
- CC-Music resamples them to 48 kHz;
- mono is sent to attached speakers in sync.

### SQSH2

CC-Music 3.0 stereo format:

- two independent DFPWM channels;
- 48 kHz;
- LEFT and RIGHT are stored as alternating fixed-size blocks;
- the player streams and submits both speaker buffers on the same sample boundary;
- if the configured stereo pair disappears, playback falls back to mono instead of crashing.

The header looks like:

```
SQSH2
rate=48000
channels=2
lyrics=<bytes>
audio=<bytes per channel>
block=8192

<lyrics>
<L block 1><R block 1><L block 2><R block 2>...
```

## Best sound

Native 48 kHz files can use DFPWM passthrough. The player expands each stored DFPWM decision to the extreme PCM values CC:Tweaked expects, so its internal encoder reproduces the original DFPWM decisions instead of introducing another normal decode/re-encode loss.

The included converter uses the same neutral mastering direction selected for the Agartha project:

- 20 Hz high-pass/DC cleanup;
- SoXR resampling to 48 kHz at precision 33;
- neutral 16 kHz low-pass;
- float32 stereo staging before channel split;
- -1 dB limiter headroom;
- optional measured two-pass EBU loudness normalization;
- true channel separation for stereo sources.

Converter:

```
cc-music/tools/convert_to_sqsh48.py
```

Windows example:

```powershell
python tools\convert_to_sqsh48.py "C:\Music\CCMusic" --output sqsh48
```

Stereo sources are written as SQSH2. Mono sources remain SQSH1 to avoid wasting twice the storage.

Optional loudness normalization:

```powershell
python tools\convert_to_sqsh48.py "C:\Music\CCMusic" --output sqsh48 --normalize
```

Force mono:

```powershell
python tools\convert_to_sqsh48.py "C:\Music\CCMusic" --output sqsh48 --mono
```

Force SQSH2 even for a mono source:

```powershell
python tools\convert_to_sqsh48.py "C:\Music\CCMusic" --output sqsh48 --force-stereo
```

A same-named `.lrc` file is embedded automatically.

## Settings

Important settings:

```
ccmusic.repo                Di33le/CC-Music
ccmusic.branch              main
ccmusic.volume              1.0
ccmusic.shuffle             true
ccmusic.loop                all
ccmusic.text_scale          0.5
ccmusic.chunk_bytes         0
ccmusic.hq_resampler        true
ccmusic.legacy_resampler    sinc8
ccmusic.ui_fps              8
ccmusic.start_track         Sundress

ccmusic.audio_mode          auto
ccmusic.left_speaker
ccmusic.right_speaker
ccmusic.balance             0.0
ccmusic.passthrough_48k     true
ccmusic.stereo_chunk_bytes  8192
```

`ccmusic.audio_mode`:

- `auto`: true stereo for SQSH2 when the configured pair is present; otherwise mono fallback.
- `stereo`: request stereo whenever a pair is available.
- `mono`: always downmix stereo files.

Balance ranges from `-1.0` (left) to `+1.0` (right).

## Controls

### Touch

Use the on-screen previous, play/pause, next, shuffle, loop, audio-routing and volume controls. Queue rows are directly touchable.

### Keyboard

- `Space`: play/pause
- `Left`: previous/restart
- `Right`: next
- `Up/Down`: volume
- `S`: shuffle
- `L`: loop mode
- `A`: cycle audio routing (`AUTO -> STEREO -> MONO`)
- `F`: search
- `Esc`: exit search
- `Enter`: play first search result
- `Ctrl+T`: shutdown

### Remote

The Rednet remote also shows the active channel mode/sample rate and supports `A` to change audio routing remotely.

## Efficiency changes in 3.0

- Native 48 kHz DFPWM playback uses reusable passthrough buffers.
- Legacy 24 kHz tracks now default to a six-multiply Blackman-windowed sinc half-step interpolator (`sinc8`) instead of cubic interpolation; `cubic` and `linear` remain available as fallbacks.
- Only the last analysis window is decoded for the visualizer during passthrough, avoiding huge temporary PCM tables.
- LEFT/RIGHT buffers are submitted in the same scheduler slice.
- Mono multi-speaker playback also submits all speaker buffers concurrently.
- Speaker hot-unplug during stereo playback falls back to mono for the remaining samples instead of restarting the song.
- Dirty-line monitor rendering remains enabled, while the default visualizer/UI refresh is now 8 Hz.

## Important limitation

The current public `Di33le/CC-Music` files are legacy mono material. A player cannot reconstruct true stereo information after it has already been discarded.

So:

- old SQSH1 tracks benefit from the improved player, resampler and synchronized multi-speaker output;
- **true stereo requires SQSH2 files converted from original stereo MP3/FLAC/WAV/etc. sources**.

That is a source-data limitation, not a CC:Tweaked stereo limitation.
