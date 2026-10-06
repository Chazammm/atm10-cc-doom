#!/usr/bin/env python3
"""
CC-Music 3.0 converter.

Converts legally obtained source audio to:
  * SQSH1: 48 kHz mono DFPWM for mono sources (or --mono)
  * SQSH2: 48 kHz true-stereo DFPWM for stereo sources

SQSH2 stores fixed-size LEFT/RIGHT DFPWM blocks interleaved so CC:Tweaked can
stream both channels in lockstep without buffering an entire song.

Requirements:
  - Python 3.9+
  - FFmpeg + FFprobe with the DFPWM encoder enabled

Example:
  python tools/convert_to_sqsh48.py "C:\\Music\\CCMusic" --output sqsh48
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


def require_tools() -> tuple[str, str]:
    ffmpeg = shutil.which("ffmpeg")
    ffprobe = shutil.which("ffprobe")
    if not ffmpeg or not ffprobe:
        raise SystemExit("FFmpeg/FFprobe were not found in PATH. Install a current full FFmpeg build.")

    enc = run([ffmpeg, "-hide_banner", "-encoders"])
    if enc.returncode != 0 or "dfpwm" not in (enc.stdout + enc.stderr).lower():
        raise SystemExit("This FFmpeg build does not contain the DFPWM encoder.")
    return ffmpeg, ffprobe


def probe_channels(ffprobe: str, src: Path) -> int:
    p = run([
        ffprobe, "-v", "error", "-select_streams", "a:0",
        "-show_entries", "stream=channels",
        "-of", "default=noprint_wrappers=1:nokey=1",
        str(src),
    ])
    if p.returncode != 0:
        raise RuntimeError(p.stderr.strip() or "ffprobe failed")
    try:
        return max(1, int(p.stdout.strip()))
    except ValueError as exc:
        raise RuntimeError("Could not determine source channel count") from exc


def profile_filter(normalize: bool) -> str:
    # Selected "Audio Profile A": neutral, retain useful treble but keep DFPWM
    # out of the very top octave where quantisation noise becomes objectionable.
    stages = [
        "aresample=48000:resampler=soxr:precision=28",
        "lowpass=f=16000",
    ]
    if normalize:
        stages.append("loudnorm=I=-16:TP=-1.5:LRA=11")
    stages.append("alimiter=limit=0.95")
    return ",".join(stages)


def encode_mono(ffmpeg: str, src: Path, raw: Path, normalize: bool) -> None:
    cmd = [
        ffmpeg, "-hide_banner", "-loglevel", "error", "-y",
        "-i", str(src), "-map", "0:a:0", "-vn",
        "-ac", "1", "-ar", "48000",
        "-af", profile_filter(normalize),
        "-c:a", "dfpwm", "-f", "dfpwm", str(raw),
    ]
    p = run(cmd)
    if p.returncode != 0:
        raise RuntimeError(p.stderr.strip() or "Mono DFPWM conversion failed")


def encode_stereo(ffmpeg: str, src: Path, left: Path, right: Path, normalize: bool) -> None:
    with tempfile.TemporaryDirectory(prefix="ccmusic_stereo_") as td:
        prepared = Path(td) / "prepared.wav"

        # Decode and master once, then split. -ac 2 also gives a well-defined
        # stereo layout when --force-stereo is used on a mono source.
        prep = [
            ffmpeg, "-hide_banner", "-loglevel", "error", "-y",
            "-i", str(src), "-map", "0:a:0", "-vn",
            "-ac", "2", "-ar", "48000",
            "-af", profile_filter(normalize),
            "-c:a", "pcm_s16le", str(prepared),
        ]
        p = run(prep)
        if p.returncode != 0:
            raise RuntimeError(p.stderr.strip() or "Stereo preparation failed")

        split = [
            ffmpeg, "-hide_banner", "-loglevel", "error", "-y",
            "-i", str(prepared),
            "-filter_complex", "[0:a]channelsplit=channel_layout=stereo[L][R]",
            "-map", "[L]", "-c:a", "dfpwm", "-f", "dfpwm", str(left),
            "-map", "[R]", "-c:a", "dfpwm", "-f", "dfpwm", str(right),
        ]
        p = run(split)
        if p.returncode != 0:
            raise RuntimeError(p.stderr.strip() or "Stereo DFPWM split failed")


def lyric_bytes(src: Path) -> bytes:
    path = src.with_suffix(".lrc")
    return path.read_bytes() if path.exists() else b""


def write_sqsh1(dst: Path, audio: bytes, lyrics: bytes) -> None:
    header = (
        b"SQSH1\n"
        b"rate=48000\n"
        + f"lyrics={len(lyrics)}\n".encode("ascii")
        + f"audio={len(audio)}\n\n".encode("ascii")
    )
    dst.write_bytes(header + lyrics + audio)


def write_sqsh2(dst: Path, left: bytes, right: bytes, lyrics: bytes, block: int) -> None:
    if len(left) != len(right):
        raise RuntimeError(f"Stereo channel lengths differ: L={len(left)} R={len(right)}")

    header = (
        b"SQSH2\n"
        b"rate=48000\n"
        b"channels=2\n"
        + f"lyrics={len(lyrics)}\n".encode("ascii")
        + f"audio={len(left)}\n".encode("ascii")
        + f"block={block}\n\n".encode("ascii")
    )

    with dst.open("wb") as out:
        out.write(header)
        out.write(lyrics)
        for off in range(0, len(left), block):
            out.write(left[off:off + block])
            out.write(right[off:off + block])


def convert_one(
    ffmpeg: str,
    ffprobe: str,
    src: Path,
    dst: Path,
    normalize: bool,
    force_mono: bool,
    force_stereo: bool,
    block: int,
) -> tuple[str, int, int]:
    dst.parent.mkdir(parents=True, exist_ok=True)
    channels = probe_channels(ffprobe, src)
    stereo = (channels >= 2 and not force_mono) or force_stereo
    lyrics = lyric_bytes(src)

    with tempfile.TemporaryDirectory(prefix="ccmusic_") as td:
        td_path = Path(td)
        if stereo:
            left_path, right_path = td_path / "left.dfpwm", td_path / "right.dfpwm"
            encode_stereo(ffmpeg, src, left_path, right_path, normalize)
            left, right = left_path.read_bytes(), right_path.read_bytes()
            write_sqsh2(dst, left, right, lyrics, block)
            return "SQSH2 stereo", len(left), len(lyrics)

        raw = td_path / "mono.dfpwm"
        encode_mono(ffmpeg, src, raw, normalize)
        audio = raw.read_bytes()
        write_sqsh1(dst, audio, lyrics)
        return "SQSH1 mono", len(audio), len(lyrics)


def main() -> int:
    ap = argparse.ArgumentParser(
        description="Convert source audio to CC-Music 3.0 SQSH1/SQSH2 at native 48 kHz DFPWM."
    )
    ap.add_argument("input", type=Path, help="Folder containing source audio")
    ap.add_argument("--output", "-o", type=Path, default=Path("sqsh48"), help="Output folder")
    ap.add_argument("--normalize", action="store_true", help="Apply EBU-style loudness normalization")
    ap.add_argument("--overwrite", action="store_true", help="Replace existing .sqsh files")
    group = ap.add_mutually_exclusive_group()
    group.add_argument("--mono", action="store_true", help="Force all sources to SQSH1 mono")
    group.add_argument("--force-stereo", action="store_true", help="Write SQSH2 even for mono sources")
    ap.add_argument("--block", type=int, default=8192, help="SQSH2 bytes per channel block (1024..16384)")
    args = ap.parse_args()

    if not args.input.is_dir():
        raise SystemExit(f"Input folder does not exist: {args.input}")
    if not 1024 <= args.block <= 16384:
        raise SystemExit("--block must be between 1024 and 16384")

    ffmpeg, ffprobe = require_tools()
    sources = sorted(
        p for p in args.input.rglob("*")
        if p.is_file() and p.suffix.lower() in SUPPORTED
    )
    if not sources:
        raise SystemExit("No supported audio files found.")

    print(f"Found {len(sources)} source tracks.")
    print("Mastering: Profile A / SoXR 48 kHz / 16 kHz low-pass / limiter")
    print("Stereo sources -> SQSH2 true stereo; mono sources -> SQSH1 mono.")
    print()

    ok = failed = 0
    for idx, src in enumerate(sources, 1):
        rel = src.relative_to(args.input)
        dst = (args.output / rel).with_suffix(".sqsh")
        if dst.exists() and not args.overwrite:
            print(f"[{idx:>3}/{len(sources)}] SKIP   {src.name}")
            continue

        print(f"[{idx:>3}/{len(sources)}] ENCODE {src.name}")
        try:
            mode, bytes_per_channel, lyrics = convert_one(
                ffmpeg, ffprobe, src, dst, args.normalize,
                args.mono, args.force_stereo, args.block,
            )
            seconds = bytes_per_channel * 8 / 48000
            print(
                f"              OK -> {dst} | {mode} | {seconds:.1f}s | "
                f"{bytes_per_channel/1024:.1f} KiB/channel"
                + (f" | {lyrics} B lyrics" if lyrics else "")
            )
            ok += 1
        except Exception as exc:
            print(f"              FAILED: {exc}", file=sys.stderr)
            failed += 1

    print()
    print(f"Finished: {ok} converted, {failed} failed.")
    if failed:
        return 1
    print("CC-Music 3.0 plays SQSH2 through the configured LEFT/RIGHT speaker pair.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
