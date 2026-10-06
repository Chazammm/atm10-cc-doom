#!/usr/bin/env python3
"""
CC-Music 3.0 converter.

Converts legally obtained source audio to:
  * SQSH1: 48 kHz mono DFPWM for mono sources (or --mono)
  * SQSH2: 48 kHz true-stereo DFPWM for stereo sources\n\nAudio Profile A+ uses a 20 Hz DC/sub-bass cut, a high-quality 128-tap SWR\nresampler, the selected neutral 16 kHz low-pass, float32 stereo staging and\n-1 dB limiter headroom.

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


def base_filter() -> str:
    # Profile A+ for DFPWM.
    #
    # Gyan's Windows "essentials" build deliberately does not include libsoxr.
    # Use FFmpeg's built-in SWR engine with a much larger filter instead. This
    # remains completely self-contained and is excellent for an offline
    # 44.1/48 kHz -> 48 kHz music conversion before the final DFPWM stage.
    return ",".join([
        "highpass=f=20:p=2",
        "aresample=48000:resampler=swr:filter_size=128:phase_shift=10:exact_rational=1:linear_interp=0:cutoff=0.97",
        "lowpass=f=16000:p=2",
    ])


def loudnorm_measure(ffmpeg: str, src: Path, target_i: float, target_tp: float, target_lra: float) -> dict[str, str]:
    filt = (
        base_filter()
        + f",loudnorm=I={target_i}:TP={target_tp}:LRA={target_lra}:print_format=json"
    )
    p = run([
        ffmpeg, "-hide_banner", "-loglevel", "info", "-i", str(src),
        "-map", "0:a:0", "-vn", "-ac", "2", "-ar", "48000",
        "-af", filt, "-f", "null", "-"
    ])
    if p.returncode != 0:
        raise RuntimeError(p.stderr.strip() or "Loudness analysis failed")

    import json
    import re

    matches = re.findall(r"\{\s*\"input_i\".*?\}", p.stderr, flags=re.S)
    if not matches:
        raise RuntimeError("Could not parse FFmpeg loudnorm analysis")
    data = json.loads(matches[-1])
    required = ["input_i", "input_tp", "input_lra", "input_thresh", "target_offset"]
    if any(k not in data for k in required):
        raise RuntimeError("Incomplete loudnorm analysis")
    return {k: str(data[k]) for k in required}


def mastering_filter(
    ffmpeg: str,
    src: Path,
    normalize: bool,
    target_i: float = -16.0,
    target_tp: float = -1.5,
    target_lra: float = 11.0,
) -> str:
    chain = base_filter()
    if normalize:
        m = loudnorm_measure(ffmpeg, src, target_i, target_tp, target_lra)
        chain += (
            f",loudnorm=I={target_i}:TP={target_tp}:LRA={target_lra}"
            f":measured_I={m['input_i']}"
            f":measured_TP={m['input_tp']}"
            f":measured_LRA={m['input_lra']}"
            f":measured_thresh={m['input_thresh']}"
            f":offset={m['target_offset']}"
            f":linear=true:print_format=summary"
        )
    # Do not auto-raise gain in the limiter. It is only a final overshoot guard.
    chain += ",alimiter=limit=0.891250938:level=false"
    return chain

def encode_mono(ffmpeg: str, src: Path, raw: Path, normalize: bool) -> None:
    cmd = [
        ffmpeg, "-hide_banner", "-loglevel", "error", "-y",
        "-i", str(src), "-map", "0:a:0", "-vn",
        "-ac", "1",
        "-af", mastering_filter(ffmpeg, src, normalize),
        "-c:a", "dfpwm", "-f", "dfpwm", str(raw),
    ]
    p = run(cmd)
    if p.returncode != 0:
        raise RuntimeError(p.stderr.strip() or "Mono DFPWM conversion failed")


def encode_stereo(ffmpeg: str, src: Path, left: Path, right: Path, normalize: bool) -> None:
    with tempfile.TemporaryDirectory(prefix="ccmusic_stereo_") as td:
        prepared = Path(td) / "prepared.wav"

        # Decode and master once in 32-bit float, then split. This avoids an
        # unnecessary 16-bit quantisation stage before the final DFPWM encode.
        # -ac 2 also gives a well-defined stereo layout for --force-stereo.
        prep = [
            ffmpeg, "-hide_banner", "-loglevel", "error", "-y",
            "-i", str(src), "-map", "0:a:0", "-vn",
            "-ac", "2",
            "-af", mastering_filter(ffmpeg, src, normalize),
            "-c:a", "pcm_f32le", str(prepared),
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



def _part_path(dst: Path, index: int) -> Path:
    return dst.with_name(f"{dst.stem}.part{index:03d}{dst.suffix}")


def _sqsh1_header(audio_bytes: int, lyric_bytes: int) -> bytes:
    return (
        b"SQSH1\n"
        b"rate=48000\n"
        + f"lyrics={lyric_bytes}\n".encode("ascii")
        + f"audio={audio_bytes}\n\n".encode("ascii")
    )


def _sqsh2_header(audio_bytes: int, lyric_bytes: int, block: int) -> bytes:
    return (
        b"SQSH2\n"
        b"rate=48000\n"
        b"channels=2\n"
        + f"lyrics={lyric_bytes}\n".encode("ascii")
        + f"audio={audio_bytes}\n".encode("ascii")
        + f"block={block}\n\n".encode("ascii")
    )


def write_sqsh1(dst: Path, audio: bytes, lyrics: bytes, max_file_bytes: int = 0) -> list[Path]:
    header = _sqsh1_header(len(audio), len(lyrics))
    if max_file_bytes <= 0 or len(header) + len(lyrics) + len(audio) <= max_file_bytes:
        dst.write_bytes(header + lyrics + audio)
        return [dst]

    # Keep non-final boundaries aligned to a large DFPWM block. The player can
    # continue decoder state across parts, so this is primarily for clean I/O.
    probe = len(_sqsh1_header(10**12, len(lyrics))) + len(lyrics)
    payload_cap = max_file_bytes - probe
    payload_cap = (payload_cap // 16384) * 16384
    if payload_cap < 16384:
        raise RuntimeError("HTTP part target is too small for SQSH1")

    paths: list[Path] = []
    for part_no, off in enumerate(range(0, len(audio), payload_cap), 1):
        chunk = audio[off:off + payload_cap]
        path = _part_path(dst, part_no)
        path.write_bytes(_sqsh1_header(len(chunk), len(lyrics)) + lyrics + chunk)
        paths.append(path)
    return paths


def write_sqsh2(
    dst: Path,
    left: bytes,
    right: bytes,
    lyrics: bytes,
    block: int,
    max_file_bytes: int = 0,
) -> list[Path]:
    if len(left) != len(right):
        raise RuntimeError(f"Stereo channel lengths differ: L={len(left)} R={len(right)}")

    header = _sqsh2_header(len(left), len(lyrics), block)
    full_size = len(header) + len(lyrics) + len(left) + len(right)

    if max_file_bytes <= 0 or full_size <= max_file_bytes:
        with dst.open("wb") as out:
            out.write(header)
            out.write(lyrics)
            for off in range(0, len(left), block):
                out.write(left[off:off + block])
                out.write(right[off:off + block])
        return [dst]

    # Pick a per-channel payload that leaves header/lyrics room and is aligned
    # to SQSH2's interleave block. This keeps every generated asset below the
    # CC:Tweaked HTTP ceiling without altering or shortening the track.
    probe = len(_sqsh2_header(10**12, len(lyrics), block)) + len(lyrics)
    per_channel_cap = (max_file_bytes - probe) // 2
    per_channel_cap = (per_channel_cap // block) * block
    if per_channel_cap < block:
        raise RuntimeError("HTTP part target is too small for one SQSH2 block")

    paths: list[Path] = []
    part_no = 1
    for off in range(0, len(left), per_channel_cap):
        lpart = left[off:off + per_channel_cap]
        rpart = right[off:off + per_channel_cap]
        path = _part_path(dst, part_no)
        with path.open("wb") as out:
            out.write(_sqsh2_header(len(lpart), len(lyrics), block))
            out.write(lyrics)
            for sub in range(0, len(lpart), block):
                out.write(lpart[sub:sub + block])
                out.write(rpart[sub:sub + block])
        if path.stat().st_size > max_file_bytes:
            raise RuntimeError(
                f"Generated HTTP part is still too large: {path.name} "
                f"({path.stat().st_size / 1024 / 1024:.2f} MiB)"
            )
        paths.append(path)
        part_no += 1
    return paths


def convert_one(
    ffmpeg: str,
    ffprobe: str,
    src: Path,
    dst: Path,
    normalize: bool,
    force_mono: bool,
    force_stereo: bool,
    block: int,
    max_file_bytes: int,
) -> tuple[str, int, int, list[Path]]:
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
            paths = write_sqsh2(dst, left, right, lyrics, block, max_file_bytes)
            return "SQSH2 stereo", len(left), len(lyrics), paths

        raw = td_path / "mono.dfpwm"
        encode_mono(ffmpeg, src, raw, normalize)
        audio = raw.read_bytes()
        paths = write_sqsh1(dst, audio, lyrics, max_file_bytes)
        return "SQSH1 mono", len(audio), len(lyrics), paths


def main() -> int:
    ap = argparse.ArgumentParser(
        description="Convert source audio to CC-Music 3.0 SQSH1/SQSH2 at native 48 kHz DFPWM."
    )
    ap.add_argument("input", type=Path, help="Folder containing source audio")
    ap.add_argument("--output", "-o", type=Path, default=Path("sqsh48"), help="Output folder")
    ap.add_argument("--normalize", action="store_true", help="Apply measured two-pass EBU loudness normalization")
    ap.add_argument("--overwrite", action="store_true", help="Replace existing .sqsh files")
    group = ap.add_mutually_exclusive_group()
    group.add_argument("--mono", action="store_true", help="Force all sources to SQSH1 mono")
    group.add_argument("--force-stereo", action="store_true", help="Write SQSH2 even for mono sources")
    ap.add_argument("--block", type=int, default=8192, help="SQSH2 bytes per channel block (1024..16384)")
    ap.add_argument("--max-file-bytes", type=int, default=0, help="Auto-split generated SQSH files below this size; 0 disables")
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
    print("Mastering: Profile A+ / SWR 128-tap / 20 Hz HP / 16 kHz LP / -1 dB limiter")
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
            mode, bytes_per_channel, lyrics, paths = convert_one(
                ffmpeg, ffprobe, src, dst, args.normalize,
                args.mono, args.force_stereo, args.block, args.max_file_bytes,
            )
            seconds = bytes_per_channel * 8 / 48000
            print(
                f"              OK -> {dst} | {mode} | {seconds:.1f}s | "
                f"{bytes_per_channel/1024:.1f} KiB/channel"
                + (f" | {lyrics} B lyrics" if lyrics else "")
                + (f" | {len(paths)} HTTP parts" if len(paths) > 1 else "")
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
