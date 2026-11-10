"""Generates the game's background music (assets/music/*.mp3): calm, sparse
piano pieces in the spirit of the classic game's soundtrack, made from
scratch: slow chords in the left hand, a few soft melody notes from the
chord's pentatonic scale in the right hand, a quiet pad and reverb.
Each track is about two minutes; the game plays one every 10-20 minutes.
Replace them with any music (mp3 / ogg / wav in assets/music).

With --records DIR it makes the music discs' tracks instead (DIR/13.mp3,
DIR/cat.mp3, played by jukeboxes): our own pieces, not the classic ones -
"13" slow and dark in a minor key, "cat" brighter and quicker.

Usage: python3 tools/make_music.py assets/music
       python3 tools/make_music.py --records assets/records
Needs numpy, scipy and the `lame` mp3 encoder.
"""
import os
import struct
import subprocess
import sys
import tempfile
import wave

import numpy as np
from scipy.signal import fftconvolve

RATE = 32000

# Tracks: (name, seed, tempo bpm, chords as MIDI root notes and quality).
TRACKS = [
    ("calm1", 11, 66, [(48, "maj7"), (45, "min7"), (41, "maj7"), (43, "add9")]),
    ("calm2", 23, 58, [(45, "min7"), (41, "maj7"), (48, "add9"), (43, "sus2")]),
    ("calm3", 37, 62, [(50, "min7"), (43, "add9"), (48, "maj7"), (45, "min7")]),
]
# Music discs: (name, seed, tempo, chords).
RECORDS = [
    ("13", 113, 52, [(45, "min7"), (44, "sus2"), (41, "min7"), (40, "sus2")]),
    ("cat", 127, 92, [(48, "add9"), (43, "maj7"), (45, "min7"), (41, "add9")]),
]
CHORDS = {"maj7": [0, 4, 7, 11], "min7": [0, 3, 7, 10], "add9": [0, 4, 7, 14], "sus2": [0, 2, 7, 12]}
PENTATONIC = {"maj7": [0, 2, 4, 7, 9], "min7": [0, 3, 5, 7, 10], "add9": [0, 2, 4, 7, 9], "sus2": [0, 2, 5, 7, 9]}


def freq(midi):
    return 440.0 * 2 ** ((midi - 69) / 12)


def piano(midi, seconds, velocity, rng):
    """A soft piano-like note: harmonics decaying at different speeds."""
    n = int(RATE * seconds)
    t = np.arange(n) / RATE
    f = freq(midi)
    out = np.zeros(n)
    for h in range(1, 7):
        stretch = h * (1 + 0.0004 * h * h) # slight inharmonicity
        decay = 1.6 / (h ** 0.8) * (220 / max(f, 110)) ** 0.3
        out += np.sin(2 * np.pi * f * stretch * t + rng.uniform(0, 6)) * np.exp(-t / decay) / h ** 1.3
    attack = np.minimum(t / 0.004, 1.0)
    release = np.minimum((seconds - t) / 0.3, 1.0)
    return out * attack * np.clip(release, 0, 1) * velocity


def pad(midis, seconds):
    n = int(RATE * seconds)
    t = np.arange(n) / RATE
    swell = np.sin(np.pi * t / seconds) ** 2
    return sum(np.sin(2 * np.pi * freq(m) * t) for m in midis) * swell * 0.04


def add(buffer, signal, start):
    i = int(start * RATE)
    end = min(len(buffer), i + len(signal))
    if i < len(buffer):
        buffer[i:end] += signal[: end - i]


def render(seed, bpm, chords):
    rng = np.random.default_rng(seed)
    beat = 60.0 / bpm
    bars_per_chord = 2
    cycles = 4
    total = len(chords) * bars_per_chord * 4 * beat * cycles + 6.0
    music = np.zeros(int(RATE * total))
    time = 2.0
    for cycle in range(cycles):
        for root, quality in chords:
            notes = [root + i for i in CHORDS[quality]]
            span = bars_per_chord * 4 * beat
            # Left hand: the chord, gently broken, once per chord.
            for k, note in enumerate(notes[:3]):
                add(music, piano(note, span + 1.5, 0.35 - 0.05 * k, rng), time + k * beat * 0.5)
            add(music, pad([n + 12 for n in notes], span + 2.0), time)
            # Right hand: a few melody notes on the beats, many rests.
            scale = [root + 24 + i for i in PENTATONIC[quality]] + [root + 36 + i for i in PENTATONIC[quality][:2]]
            density = [0.15, 0.35, 0.45, 0.25][cycle]
            for b in range(bars_per_chord * 4):
                if rng.random() < density:
                    note = int(rng.choice(scale))
                    when = time + b * beat + (beat * 0.5 if rng.random() < 0.25 else 0.0)
                    add(music, piano(note, beat * rng.choice([2, 3, 4]), rng.uniform(0.18, 0.3), rng), when)
            time += span
    # Reverb: a decaying noise tail (a room), mixed in softly.
    tail = np.random.default_rng(seed + 1).uniform(-1, 1, int(RATE * 2.8)) * np.exp(-np.arange(int(RATE * 2.8)) / (RATE * 0.7))
    wet = fftconvolve(music, tail)[: len(music)]
    wet /= np.max(np.abs(wet)) or 1
    mixed = music / (np.max(np.abs(music)) or 1) * 0.8 + wet * 0.35
    fade = np.minimum(np.arange(len(mixed)) / (RATE * 2.0), 1.0) * np.minimum((len(mixed) - np.arange(len(mixed))) / (RATE * 4.0), 1.0)
    mixed *= fade
    return mixed / (np.max(np.abs(mixed)) or 1) * 0.7


def write_mp3(path, signal):
    with tempfile.TemporaryDirectory() as tmp:
        wav_path = os.path.join(tmp, "track.wav")
        with wave.open(wav_path, "wb") as out:
            out.setnchannels(1)
            out.setsampwidth(2)
            out.setframerate(RATE)
            out.writeframes((np.clip(signal, -1, 1) * 32767).astype("<i2").tobytes())
        subprocess.run(["lame", "--quiet", "-V", "5", wav_path, path], check=True)


def main(root):
    os.makedirs(root, exist_ok=True)
    for name, seed, bpm, chords in TRACKS:
        write_mp3(os.path.join(root, name + ".mp3"), render(seed, bpm, chords))
        print("wrote", name)


if __name__ == "__main__":
    if sys.argv[1] == "--records":
        os.makedirs(sys.argv[2], exist_ok=True)
        for name, seed, bpm, chords in RECORDS:
            write_mp3(os.path.join(sys.argv[2], name + ".mp3"), render(seed, bpm, chords))
            print("wrote", name)
    else:
        main(sys.argv[1])
