# CC-Music 3.6.2 for ATM10 8.2 / CC:Tweaked

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

CC-Music 3.6.2 stereo format:

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
ccmusic.ui_fps              12
ccmusic.viz_slice_bytes      1024
ccmusic.viz_mode             classic
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


## Visualizer pipeline in 3.2

The spectrum is no longer updated only once per large audio buffer.

- 48 kHz DFPWM is scheduled in 512-byte visualizer slices (~85 ms / ~11.7 updates per second).
- The monitor defaults to 12 UI frames per second.
- Bars use fast attack and slower release smoothing.
- Each band has a short peak-hold marker with gradual falloff.
- The dotted ring reacts primarily to bass energy, with a smaller RMS contribution.
- Dirty-line framebuffer rendering is still used, so unchanged queue/UI rows are not retransmitted to the monitor.

The audio bitstream itself is unchanged: native 48 kHz SQSH2 still uses the DIRECT DFPWM path.


## Visualizer modes in 3.3

Cycle modes with the on-screen `VIZ:...` button or keyboard `V`.

- `CLASSIC`: bass-reactive dotted ring, centered rainbow spectrum, peak-hold markers.
- `MIRROR`: true stereo visualization. LEFT and RIGHT are analyzed independently and grow away from the center.
- `METER`: full-height bottom-up equalizer with peak markers for maximum readability at distance.

Additional UI polish:
- clearer `CC-MUSIC` header;
- first queued track is highlighted as the real "next" track;
- queue header shows total library size;
- compact Now Playing metadata row with duration, SQSH format and active visualizer mode.

The visualizer changes do not alter the 48 kHz DIRECT audio bitstream.


## Transport and touch polish in 3.4

The 8x5 monitor UI now behaves more like a real media player:

- the progress bar is touch-seekable;
- dedicated `-10` and `+10` touch buttons were added;
- `J` and `K` seek backward/forward by 10 seconds;
- the title in the top bar scrolls smoothly when it is too long;
- the progress playhead is highlighted separately from the filled portion;
- transport buttons and mode buttons are split across two rows for easier touch use;
- the compact Now Playing row shows current time, duration, SQSH format and visualizer mode;
- Rednet remote also supports `J/K` seeking.

SQSH2 seeking is aligned to a valid interleaved audio-block boundary so LEFT/RIGHT stay synchronized. Long segmented albums continue to behave as one logical track.


## Library UX and persistence in 3.5

- Resume after restart is enabled by default. CC-Music stores the logical track and playback position about every five seconds and resumes from that point on the next launch.
- The `FAV` button toggles the current track as a favorite. Favorite tracks are marked with `*` in the queue.
- `FAVS` toggles a favorites-only library view. Favorites are stored locally in `/ccmusic/favorites.json`.
- `Q+` arms one-shot "Play next" mode. Tap any track in the right-hand list and it is inserted ahead of the normal shuffle/order sequence. Queued entries are shown in orange with a `Q` marker.
- `SET` opens an on-screen settings panel with visualizer, audio routing, shuffle, loop, restart-resume and favorites-view controls.
- Keyboard shortcuts: `B` favorite current track, `G` favorites view, `N` arm Play Next, `M` settings, `Esc` closes settings.
- The Rednet remote shows favorite/manual-queue status and `B` toggles the current favorite.

Resume, favorites and the manual queue are player-side features and do not change the SQSH2 48 kHz DIRECT audio path.


## Performance hardening and new visualizers in 3.6

Audio smoothness is now prioritised more aggressively without giving up the 12 FPS UI.

- The default DFPWM visualizer/audio scheduling slice is now 1024 bytes at 48 kHz (~171 ms), doubling the per-call speaker buffer versus 3.5.x.
- CC-Music measures render cost continuously. If a frame becomes expensive, it temporarily enters `SAFE` mode: UI rendering drops to at most 8 FPS and audio slices grow again for more playback headroom.
- Paused playback and the settings screen also render at a reduced rate because there is no benefit in spending the full frame budget there.
- Spectral work is mode-aware: CLASSIC/METER/ORBIT use one mono spectrum analysis, MIRROR uses two true stereo analyses, while WAVE and VU skip the expensive spectrum pass entirely.
- Dirty-row monitor blitting remains enabled.

Visualizer cycle:
`CLASSIC -> MIRROR -> METER -> WAVE -> ORBIT -> VU -> CLASSIC`

New modes:
- `WAVE`: dual stereo oscilloscope with independent L/R zero lines.
- `ORBIT`: radial frequency spectrum around a bass-reactive core.
- `VU`: large L/R level meters plus stereo-balance indicator. This is also the cheapest visualizer mode computationally.

The audio format and output path are unchanged: SQSH2 48 kHz stereo still uses DIRECT playback.

CC:Tweaked speakers buffer a single `playAudio` call at a time, so larger chunks are generally more resistant to server/computer lag. The 3.6 defaults are a compromise between that recommendation and responsive visualization.


## Speaker boost in 3.6.2

The monitor volume row includes a `BOOST:X1` button. Tap it to cycle:

`X1 -> X2 -> X3 -> X1`

CC:Tweaked accepts speaker stream volume up to 3. The player's normal volume slider remains 0-100%, and the boost multiplies that value before sending it to the speaker, clamped to 3. For example, 100% at X3 sends volume 3, while 50% at X3 sends 1.5.

Minecraft primarily uses values above 1 to extend the audible distance rather than making a nearby speaker dramatically louder. This is therefore intended as a range boost for larger rooms/bases.

Changing boost interrupts and immediately resumes the current audio buffer so Minecraft applies the new stream volume/range reliably. Keyboard `R` and the Rednet remote also cycle the boost.
