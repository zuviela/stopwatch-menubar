"""Play the toggle click sound.

Uses our synthesized glass-chime WAV (a soft metallic ping that mimics the
macOS NSSound 'Glass'). Falls back silently when no audio player is found.
"""
from __future__ import annotations

import shutil
import subprocess

from . import audio_assets


def _player() -> list[str] | None:
    if shutil.which("paplay"):
        return ["paplay"]
    if shutil.which("aplay"):
        return ["aplay", "-q"]
    if shutil.which("canberra-gtk-play"):
        return ["canberra-gtk-play", "-f"]
    return None


_PLAYER_CMD = _player()


def play_toggle() -> None:
    if _PLAYER_CMD is None:
        return
    path = audio_assets.get_sound_path(audio_assets.GLASS)
    if path is None:
        return
    try:
        subprocess.Popen(
            [*_PLAYER_CMD, str(path)],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except (FileNotFoundError, OSError):
        pass
