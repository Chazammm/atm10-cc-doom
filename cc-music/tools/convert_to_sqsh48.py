#!/usr/bin/env python3
"""
Batch-convert legally obtained source audio to CC-Music SQSH1 at native 48 kHz DFPWM.

Requirements:
  - Python 3.9+
  - FFmpeg 5.1+ with the dfpwm encoder enabled

Examples:
  python tools/convert_to_sqsh48.py "C:\\Users\\you\\Music\\CCMusic"
  python tools/convert_to_sqsh48.py ./source_audio --output ./converted --normalize

The script never downloads music. It converts files already present on your computer.
If a matching .lrc file exists beside a song, it is embedded into SQSH1.
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

SUPPORTED = {".mp3", ".wav", ".flac", ".ogg", ".opus", ".m4a", ".aac", ".wma", ".aiff", ".aif"}


def run(cmd: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)


def require_ffmpeg() -> str:
    exe = shutil.which("ffmpeg")
    if not exe:
        raise SystemExit(
            "FFmpeg was not found in PATH. Install FFmpeg 5.1+ and reopen the terminal."
        )

    enc = run([exe, "-hide_banner", "-encoders"])
    if enc.returncode != 0 or "dfpwm" not in (enc.stdout + enc.stderr).lower():
        raise SystemExit(
            "This FFmpeg build does not contain the DFPWM encoder. "
            "Use a current full FFmpeg build (5.1 or newer)."
        )
    return exe


def convert_one(ffmpeg: str, src: Path, dst: Path, normalize: bool) -> tuple[int, int]:
    dst.parent.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory(prefix="ccmusic_") as td:
        raw = Path(td) / "audio.dfpwm"

        cmd = [
            ffmpeg,
            "-hide_banner",
            "-loglevel", "error",
            "-y",
            "-i", str(src),
            "-map", "0:a:0",
            "-vn",
            "-ac", "1",
            "-ar", "48000",
        ]

        if normalize:
            # Moderate loudness normalization. True peak headroom reduces clipping when
            # Minecraft/CC:Tweaked re-encodes the 8-bit PCM stream internally.
            cmd += ["-af", "loudnorm=I=-16:TP=-1.5:LRA=11"]

        cmd += [
            "-c:a", "dfpwm",
            "-f", "dfpwm",
            str(raw),
        ]

        p = run(cmd)
        if p.returncode != 0:
            raise RuntimeError(p.stderr.strip() or "FFmpeg conversion failed")

        audio = raw.read_bytes()

    lyric_path = src.with_suffix(".lrc")
    lyrics = lyric_path.read_bytes() if lyric_path.exists() else b""

    header = (
        b"SQSH1\n"
        b"rate=48000\n"
        + f"lyrics={len(lyrics)}\n".encode("ascii")
        + f"audio={len(audio)}\n\n".encode("ascii")
    )
    dst.write_bytes(header + lyrics + audio)
    return len(audio), len(lyrics)


def main() -> int:
    ap = argparse.ArgumentParser(
        description="Convert a folder of source audio to 48 kHz DFPWM SQSH1 for CC-Music."
    )
    ap.add_argument("input", type=Path, help="Folder containing source audio")
    ap.add_argument(
        "--output", "-o", type=Path, default=Path("sqsh48"),
        help="Output folder (default: ./sqsh48)"
    )
    ap.add_argument(
        "--normalize", action="store_true",
        help="Apply moderate EBU-style loudness normalization"
    )
    ap.add_argument(
        "--overwrite", action="store_true",
        help="Replace existing .sqsh files"
    )
    args = ap.parse_args()

    if not args.input.is_dir():
        raise SystemExit(f"Input folder does not exist: {args.input}")

    ffmpeg = require_ffmpeg()

    sources = sorted(
        p for p in args.input.rglob("*")
        if p.is_file() and p.suffix.lower() in SUPPORTED
    )
    if not sources:
        raise SystemExit("No supported audio files found.")

    print(f"Found {len(sources)} source tracks.")
    print("Encoding: mono / 48 kHz / DFPWM1a / SQSH1")
    print()

    ok = 0
    failed = 0

    for idx, src in enumerate(sources, 1):
        rel = src.relative_to(args.input)
        dst = (args.output / rel).with_suffix(".sqsh")

        if dst.exists() and not args.overwrite:
            print(f"[{idx:>3}/{len(sources)}] SKIP  {src.name}")
            continue

        print(f"[{idx:>3}/{len(sources)}] ENCODE {src.name}")
        try:
            audio_bytes, lyric_bytes = convert_one(ffmpeg, src, dst, args.normalize)
            seconds = audio_bytes * 8 / 48000
            print(
                f"              OK -> {dst} "
                f"({seconds:.1f}s, {audio_bytes/1024:.1f} KiB audio"
                + (f", {lyric_bytes} B lyrics" if lyric_bytes else "")
                + ")"
            )
            ok += 1
        except Exception as exc:
            print(f"              FAILED: {exc}", file=sys.stderr)
            failed += 1

    print()
    print(f"Finished: {ok} converted, {failed} failed.")
    if failed:
        return 1

    print("These SQSH files are already native 48 kHz; CC-Music will skip resampling.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
