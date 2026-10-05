# YouTube/music-video playback on ATM10 8.2 / CC:Tweaked

This folder adds a practical video + audio setup without changing the existing DOOM files.

## Why this method

CC:Tweaked cannot decode YouTube/MP4 directly. A reliable route is to convert the video on a normal PC to Sanjuuni's **32vid** format. 32vid can contain both video and 48 kHz audio, and the bundled mini player can stream it from an HTTP URL while drawing to an Advanced Monitor and playing audio through a Speaker.

The vendored `32vid-player-mini.lua` comes from MCJack123/sanjuuni and is MIT licensed.

## In Minecraft

Build/connect:
- Advanced Computer
- Advanced Monitor (one connected multiblock monitor wall is fine)
- Speaker

Install:

```lua
wget run https://raw.githubusercontent.com/Chazammm/atm10-cc-doom/main/youtube-video/install.lua
```

Then run:

```text
videoinfo
```

It prints the exact monitor width/height Sanjuuni should target at text scale 0.5.

## Convert the video on Windows

1. Install/download Sanjuuni 0.5 for Windows.
2. Obtain an MP4 copy of media you have permission to download/use.
3. Put the MP4 next to `sanjuuni.exe`.
4. Use the command printed by `videoinfo`, for example:

```powershell
.\sanjuuni.exe -i "input.mp4" -3 -d -cans -W100 -H38 -o "musicvideo.32vid"
```

Replace 100x38 with the dimensions printed in your world.

## Hosting

The player needs a direct HTTP/HTTPS URL to the `.32vid` file.

For small files (<100 MB), a normal public GitHub repo raw URL can work. For larger music videos, use a GitHub Release asset or another host that provides direct binary downloads.

## Play

```text
video https://example.com/musicvideo.32vid
```

To store the URL:

```text
settings set musicvideo.url https://example.com/musicvideo.32vid
video
```

The installer writes `/video.lua`, so the `video` command remains available after the CC computer reboots.

## Your requested YouTube video

Requested source:
https://www.youtube.com/watch?v=V_SBUmn8O-U

The repo intentionally does not redistribute the actual YouTube media file. Convert/upload a copy you are allowed to use, then point `video` at the resulting direct `.32vid` URL.
