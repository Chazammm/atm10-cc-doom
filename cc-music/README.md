# CC-Music Player for ATM10 8.2 / CC:Tweaked

A large-monitor SQSH music player designed around the `Di33le/CC-Music` library.

## What it does

- Dynamically indexes every `.sqsh` track in `https://github.com/Di33le/CC-Music`.
- Parses the real `SQSH1` container (`rate`, `lyrics`, `audio`).
- Decodes DFPWM and plays native 48 kHz tracks directly; legacy 24 kHz tracks use the HQ resampler.
- Plays through all attached speakers in sync.
- Large black/blue Advanced Monitor UI inspired by the supplied screenshot.
- Real audio-reactive 16-band Goertzel visualizer (not a random animation).
- Synchronized lyrics when present.
- Up-next queue, track durations, play/pause, previous/next, shuffle, loop modes and volume.
- Touch controls on Advanced Monitors.
- Keyboard controls and search (`F`).
- Optional Rednet pocket-computer remote.
- GitHub index cache for resilience.
- Dirty-line framebuffer rendering to reduce monitor traffic.
- Mid-buffer pause/volume interrupts keep the remainder of the decoded PCM chunk instead of blindly skipping it.

## Recommended in-game build

For the closest result to the screenshot:

- 1 Advanced Computer
- 1 large Advanced Monitor wall, ideally 8 x 6 blocks
- 2-4 Speakers (more is fine)
- Wired Modems + Networking Cable so the computer sees the whole monitor and all speakers
- Optional wireless/wired modem for `remote.lua`

The monitor and speakers only need to be visible as CC:Tweaked peripherals; the player discovers them automatically.

## Install

Put these files on the Advanced Computer:

- `player.lua`
- optionally `startup.lua`

You can drag-and-drop `player.lua` into an open CC:Tweaked computer terminal window.

Run:

```text
player
```

If `startup.lua` is present, rebooting the computer starts the player automatically.

For a remote, put `remote.lua` on another Computer or Advanced Pocket Computer with a modem and run:

```text
remote
```

## Controls

### Monitor touch

Touch the visible buttons for previous, pause/play, next, shuffle, loop and volume. Touch any visible queue entry to play it. `[U]` and `[D]` in the queue header scroll the list.

### Keyboard

- `Space`: play/pause
- `Left`: previous/restart
- `Right`: next
- `Up/Down`: volume
- `S`: shuffle
- `L`: loop mode (`ALL -> ONE -> OFF`)
- `F`: search mode
- `Esc`: exit search
- `Enter`: play first search match
- `Ctrl+T`: clean shutdown

## Settings

The player uses CC:Tweaked's `settings` API. Defaults:

```text
ccmusic.repo       Di33le/CC-Music
ccmusic.branch     main
ccmusic.volume     1.0
ccmusic.shuffle    true
ccmusic.loop       all
ccmusic.text_scale 0.5
ccmusic.chunk_bytes 0      # automatic: max safe buffer for the track rate
ccmusic.hq_resampler true
ccmusic.ui_fps     6
ccmusic.start_track Sundress
```

Example from the CC shell:

```text
set ccmusic.ui_fps 8
set ccmusic.chunk_bytes 0
set ccmusic.hq_resampler true
set ccmusic.start_track Mercury
reboot
```

`ccmusic.chunk_bytes 0` is recommended. The player automatically uses the largest safe DFPWM block for the source rate: 8 KiB for 24 kHz tracks (which become 131072 PCM samples after 2x resampling) and 16 KiB for native 48 kHz tracks. This matches CC:Tweaked's speaker buffer ceiling and minimizes stutter.

## Notes

The player streams one selected SQSH file at a time and does **not** copy the entire music repository onto the computer's limited virtual disk.

Track durations shown before a track has been opened are estimated from GitHub file size. Once a track's SQSH header is read, the exact audio duration replaces that estimate.

The visualizer uses a short Goertzel analysis window over the actual decoded audio at 16 logarithmically spaced frequencies. It is intentionally much lighter than a full FFT while still being genuinely audio reactive.

## Best possible sound: native 48 kHz source conversion

The files currently in `Di33le/CC-Music` are legacy 24 kHz SQSH/DFPWM files. No player-side resampler can recreate information which was discarded before those files were encoded.

For the highest quality, convert your legally obtained MP3/WAV/FLAC/M4A/etc. originals directly to **48 kHz mono DFPWM**. A batch converter is included:

```text
cc-music/tools/convert_to_sqsh48.py
```

It requires Python 3.9+ and FFmpeg 5.1+.

Windows example:

```powershell
python tools\convert_to_sqsh48.py "C:\Music\CCMusic" --output sqsh48
```

Optional moderate loudness normalization:

```powershell
python tools\convert_to_sqsh48.py "C:\Music\CCMusic" --output sqsh48 --normalize
```

If a same-named `.lrc` file exists next to a track, the converter embeds the synchronized lyrics into SQSH1.

Native 48 kHz SQSH files are played directly by the player, without upsampling.
