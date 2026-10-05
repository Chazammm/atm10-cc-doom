# CC-Music Player for ATM10 8.2 / CC:Tweaked

A large-monitor SQSH music player designed around the `Di33le/CC-Music` library.

## What it does

- Dynamically indexes every `.sqsh` track in `https://github.com/Di33le/CC-Music`.
- Parses the real `SQSH1` container (`rate`, `lyrics`, `audio`).
- Decodes DFPWM and resamples 24 kHz audio to CC:Tweaked's 48 kHz speaker rate.
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
ccmusic.chunk_bytes 1024
ccmusic.ui_fps     6
ccmusic.start_track Sundress
```

Example from the CC shell:

```text
set ccmusic.ui_fps 8
set ccmusic.chunk_bytes 1536
set ccmusic.start_track Mercury
reboot
```

For ATM10, the defaults are deliberately conservative. Larger chunks reduce Lua/HTTP overhead but increase control latency; smaller chunks reduce latency but cost more CPU. `1024` is a good balance.

## Notes

The player streams one selected SQSH file at a time and does **not** copy the entire music repository onto the computer's limited virtual disk.

Track durations shown before a track has been opened are estimated from GitHub file size. Once a track's SQSH header is read, the exact audio duration replaces that estimate.

The visualizer uses a short Goertzel analysis window over the actual decoded audio at 16 logarithmically spaced frequencies. It is intentionally much lighter than a full FFT while still being genuinely audio reactive.