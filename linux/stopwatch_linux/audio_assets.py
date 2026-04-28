"""Synthesize firework + toggle sounds.

Approximates the three macOS system sounds the original app plays:
- pop.wav    ~ /System/Library/Sounds/Pop.aiff   (small firework / period hit)
- bottle.wav ~ /System/Library/Sounds/Bottle.aiff (grand firework / daily hit)
- glass.wav  ~ /System/Library/Sounds/Glass.aiff (toggle click)

We can't redistribute Apple's audio files, so each sound is built from pure
math (sines, exponential envelopes, a touch of noise) at runtime and cached
under ~/.local/share/stopwatch-menubar/sounds/. Delete that dir to
regenerate (e.g. after tweaking the synthesis below).
"""
from __future__ import annotations

import math
import random
import struct
import wave
from pathlib import Path
from typing import Callable, Optional

from .storage import DATA_DIR, ensure_dirs


SAMPLE_RATE = 44100

POP = "pop.wav"
BOTTLE = "bottle.wav"
GLASS = "glass.wav"

_SOUNDS_DIR = DATA_DIR / "sounds"


# ---------- WAV writer ----------

def _write_wav(path: Path, samples: list[float]) -> None:
    """Write 16-bit mono PCM WAV from float samples in [-1, 1]."""
    ensure_dirs()
    path.parent.mkdir(parents=True, exist_ok=True)
    # Soft-clip to avoid harshness on transients
    clipped = [max(-1.0, min(1.0, s)) for s in samples]
    payload = b"".join(struct.pack("<h", int(s * 32767)) for s in clipped)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SAMPLE_RATE)
        w.writeframes(payload)


# ---------- Synthesis ----------

def _normalize(samples: list[float], peak: float = 0.7) -> list[float]:
    m = max((abs(s) for s in samples), default=0.0)
    if m == 0:
        return samples
    scale = peak / m
    return [s * scale for s in samples]


def _synth_pop(duration: float = 0.16) -> list[float]:
    """Light bubble-pop: pitch sweep from ~1500Hz down to 400Hz with a brief
    noise transient and a warm low-frequency thump for body."""
    rng = random.Random(42)
    n = int(duration * SAMPLE_RATE)
    out = []
    for i in range(n):
        t = i / SAMPLE_RATE
        freq = 1500 * math.exp(-t * 18) + 400
        tone = math.sin(2 * math.pi * freq * t) * 0.55
        noise = (rng.random() - 0.5) * 0.35 if t < 0.025 else 0.0
        body = math.sin(2 * math.pi * 180 * t) * 0.18 * math.exp(-t * 22)
        env = math.exp(-t * 22)
        out.append((tone + noise + body) * env)
    return _normalize(out, peak=0.7)


def _synth_bottle(duration: float = 0.55) -> list[float]:
    """Champagne-cork pop: low transient + rising 'whoop' tail.

    The macOS `Bottle.aiff` has a distinct rising pitch after the initial
    pop — that 'whoop' is what makes it feel celebratory rather than just
    percussive. Recreated here as a sine that ramps from ~400Hz to ~750Hz
    over the first ~0.25s, with the original burst decaying behind it.
    """
    rng = random.Random(7)
    n = int(duration * SAMPLE_RATE)
    out = []
    for i in range(n):
        t = i / SAMPLE_RATE
        # Initial percussive thump (low frequency, decays fast)
        thump_freq = 220 * math.exp(-t * 9) + 90
        thump = math.sin(2 * math.pi * thump_freq * t) * 0.6 * math.exp(-t * 10)
        # Rising whoop tail
        whoop_progress = min(1.0, t / 0.28)
        whoop_freq = 400 + 350 * whoop_progress
        # Tail envelope: fades in over 50ms, then exponential decay
        if t < 0.05:
            tail_env = t / 0.05 * 0.5
        else:
            tail_env = 0.5 * math.exp(-(t - 0.05) * 4.5)
        whoop = math.sin(2 * math.pi * whoop_freq * t) * tail_env
        # Soft noise on the attack
        noise = (rng.random() - 0.5) * 0.28 * math.exp(-t * 45)
        out.append(thump + whoop + noise)
    return _normalize(out, peak=0.75)


def _synth_glass(duration: float = 0.32) -> list[float]:
    """Metallic chime: fundamental + two inharmonic partials, smooth envelope.

    Inharmonic ratios (2.756, 5.404) approximate a clinking-glass timbre
    rather than a clean musical pitch.
    """
    n = int(duration * SAMPLE_RATE)
    base = 1700.0
    out = []
    for i in range(n):
        t = i / SAMPLE_RATE
        f1 = math.sin(2 * math.pi * base * t)
        f2 = math.sin(2 * math.pi * base * 2.756 * t) * 0.32
        f3 = math.sin(2 * math.pi * base * 5.404 * t) * 0.10
        if t < 0.006:
            env = t / 0.006
        else:
            env = math.exp(-(t - 0.006) * 7.5)
        out.append((f1 + f2 + f3) * env * 0.5)
    return _normalize(out, peak=0.6)


# ---------- Public API ----------

_GENERATORS: dict[str, Callable[[], list[float]]] = {
    POP: _synth_pop,
    BOTTLE: _synth_bottle,
    GLASS: _synth_glass,
}


def get_sound_path(name: str) -> Optional[Path]:
    """Return the WAV path for `name`, synthesizing it on first use."""
    if name not in _GENERATORS:
        return None
    path = _SOUNDS_DIR / name
    if not path.exists():
        _write_wav(path, _GENERATORS[name]())
    return path


def regenerate_all() -> None:
    """Force re-synthesis of every sound (useful after tuning the math)."""
    for name, gen in _GENERATORS.items():
        _write_wav(_SOUNDS_DIR / name, gen())
