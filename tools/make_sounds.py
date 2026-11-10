"""Generates the game's placeholder sound effects (assets/sounds/*.wav):
short synthesized sounds in the spirit of the classic game's, made from
filtered noise and decaying tones, so the sound system has something to
play. Replace any file with a real recording (same name, any length) and
the game uses it.

Groups (each with a few variants, picked at random):
  dig/<material>N   - breaking and placing blocks
  step/<material>N  - footsteps (also the hit while breaking)
  random/pop, click, glassN, fizz, eatN, splash, burp
  damage/hurtN
  chest/open, chest/close, liquid/water, liquid/lava, liquid/lavapop,
  ambient/caveN
Materials: stone, wood, gravel, grass, sand, cloth, snow.

Usage: python3 tools/make_sounds.py assets/sounds
Needs numpy.
"""
import os
import struct
import sys
import wave

import numpy as np

RATE = 22050
rng = np.random.default_rng(1)


def write(path, signal):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    peak = np.max(np.abs(signal)) or 1.0
    data = np.clip(signal / peak * 0.85, -1, 1)
    with wave.open(path, "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(b"".join(struct.pack("<h", int(v * 32767)) for v in data))


def t(seconds):
    return np.arange(int(RATE * seconds)) / RATE


def envelope(n, attack=0.004, decay=0.08):
    x = np.arange(n) / RATE
    return np.minimum(x / attack, 1.0) * np.exp(-x / decay)


def env(seconds, attack, decay):
    """Envelope with exactly as many samples as noise(seconds) / t(seconds)."""
    return envelope(int(RATE * seconds), attack, decay)


def lowpass(signal, cutoff):
    # One-pole low-pass, run twice for a softer slope.
    a = np.exp(-2 * np.pi * cutoff / RATE)
    for _ in range(2):
        out = np.zeros_like(signal)
        acc = 0.0
        for i, v in enumerate(signal):
            acc = (1 - a) * v + a * acc
            out[i] = acc
        signal = out
    return signal


def highpass(signal, cutoff):
    return signal - lowpass(signal, cutoff)


def noise(seconds):
    return rng.uniform(-1, 1, int(RATE * seconds))


def grains(seconds, count, grain=0.006, cutoff=3000):
    """Many tiny clicks: gravel, snow crunch."""
    n = int(RATE * seconds)
    out = np.zeros(n)
    for _ in range(count):
        start = int(rng.uniform(0, 0.75) * n)
        g = noise(grain) * envelope(int(RATE * grain), 0.0005, grain / 3)
        out[start:start + len(g)] += g[: n - start] * rng.uniform(0.3, 1.0)
    return lowpass(out, cutoff)


MATERIALS = {
    # material: function(length scale) -> signal
    "stone": lambda s: highpass(lowpass(noise(0.18 * s), 2600), 300) * env(0.18 * s, 0.002, 0.035 * s)
        + 0.6 * np.sin(2 * np.pi * rng.uniform(380, 520) * t(0.18 * s)) * env(0.18 * s, 0.001, 0.02 * s),
    "wood": lambda s: lowpass(noise(0.2 * s), 1200) * env(0.2 * s, 0.002, 0.05 * s)
        + 0.9 * np.sin(2 * np.pi * rng.uniform(140, 210) * t(0.2 * s)) * env(0.2 * s, 0.002, 0.06 * s),
    "gravel": lambda s: grains(0.25 * s, int(40 * s), cutoff=3500) * env(0.25 * s, 0.01, 0.12 * s),
    "grass": lambda s: highpass(lowpass(noise(0.22 * s), 5000), 1200) * env(0.22 * s, 0.02, 0.07 * s),
    "sand": lambda s: lowpass(noise(0.26 * s), 1800) * env(0.26 * s, 0.03, 0.09 * s),
    "cloth": lambda s: lowpass(noise(0.22 * s), 700) * env(0.22 * s, 0.03, 0.07 * s),
    "snow": lambda s: grains(0.25 * s, int(25 * s), grain=0.01, cutoff=1800) * env(0.25 * s, 0.02, 0.1 * s),
}


def main(root):
    for material, make in MATERIALS.items():
        for k in range(1, 5):
            write(os.path.join(root, "dig", f"{material}{k}.wav"), make(1.3))
            write(os.path.join(root, "step", f"{material}{k}.wav"), make(0.7))
    # Pop: a quick rising blip (picking up an item).
    x = t(0.09)
    write(os.path.join(root, "random", "pop.wav"),
          np.sin(2 * np.pi * (600 + 2200 * x) * x) * envelope(len(x), 0.002, 0.03))
    # Click: a short tick (menu buttons).
    x = t(0.04)
    write(os.path.join(root, "random", "click.wav"),
          (np.sin(2 * np.pi * 1800 * x) + 0.5 * noise(0.04)) * envelope(len(x), 0.0005, 0.008))
    # Glass: bright rings and a shatter.
    for k in range(1, 4):
        x = t(0.5)
        ring = sum(np.sin(2 * np.pi * f * x) * rng.uniform(0.3, 1.0) for f in rng.uniform(2500, 6000, 5))
        write(os.path.join(root, "random", f"glass{k}.wav"),
              (0.6 * ring + highpass(noise(0.5), 3000)) * envelope(len(x), 0.001, 0.09))
    # Fizz: hissing (lava meets water).
    x = t(0.6)
    write(os.path.join(root, "random", "fizz.wav"), highpass(noise(0.6), 2500) * envelope(len(x), 0.02, 0.2))
    # Eating: soft crunchy bites.
    for k in range(1, 4):
        write(os.path.join(root, "random", f"eat{k}.wav"),
              grains(0.18, 18, grain=0.008, cutoff=2200) * env(0.18, 0.005, 0.06))
    write(os.path.join(root, "random", "burp.wav"),
          lowpass(noise(0.35), 300) * np.sin(2 * np.pi * 90 * t(0.35)) * env(0.35, 0.02, 0.12))
    # Splash: noise burst falling in pitch.
    x = t(0.5)
    write(os.path.join(root, "random", "splash.wav"), lowpass(noise(0.5), 2500) * envelope(len(x), 0.005, 0.15))
    # Fire: crackling pops; ignite: a quick scratch and whoosh.
    x = t(1.2)
    crackle = grains(1.2, 60, grain=0.004, cutoff=4000) + 0.3 * lowpass(noise(1.2), 400)
    write(os.path.join(root, "fire", "fire.wav"), crackle * np.minimum(x / 0.1, 1.0) * np.minimum((1.2 - x) / 0.2, 1.0))
    x = t(0.35)
    write(os.path.join(root, "fire", "ignite.wav"),
          (highpass(noise(0.35), 2000) * env(0.35, 0.002, 0.03) + lowpass(noise(0.35), 900) * env(0.35, 0.03, 0.12)))
    # Chest: a wooden creak opening, a thump closing.
    x = t(0.45)
    creak = np.sin(2 * np.pi * (220 + 120 * np.sin(2 * np.pi * 3 * x)) * x) * (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * 37 * x)))
    write(os.path.join(root, "chest", "open.wav"), lowpass(creak + 0.4 * noise(0.45), 1800) * env(0.45, 0.05, 0.25))
    write(os.path.join(root, "chest", "close.wav"), MATERIALS["wood"](1.6))
    # Flowing water: a soft babble; lava: a low bubbling; lava pop: a blip.
    x = t(1.5)
    babble = lowpass(noise(1.5), 900) * (0.6 + 0.4 * np.sin(2 * np.pi * 3.1 * x) * np.sin(2 * np.pi * 1.7 * x))
    write(os.path.join(root, "liquid", "water.wav"), babble * np.minimum(x / 0.3, 1.0) * np.minimum((1.5 - x) / 0.4, 1.0))
    bubbles = np.zeros(len(x))
    for _ in range(14):
        start = int(rng.uniform(0, 1.3) * RATE)
        f = rng.uniform(60, 140)
        b = np.sin(2 * np.pi * f * t(0.12) * (1 + 2 * t(0.12))) * env(0.12, 0.005, 0.04)
        bubbles[start:start + len(b)] += b[: len(x) - start]
    write(os.path.join(root, "liquid", "lava.wav"), lowpass(bubbles + 0.2 * noise(1.5), 600))
    x = t(0.12)
    write(os.path.join(root, "liquid", "lavapop.wav"), np.sin(2 * np.pi * (300 - 900 * x) * x) * env(0.12, 0.002, 0.03))
    # Cave: low, eerie tones that slowly swell and fade.
    for k in range(1, 4):
        x = t(4.0)
        base = rng.uniform(55, 90)
        tone = sum(np.sin(2 * np.pi * base * m * x + rng.uniform(0, 6)) / m for m in (1, 1.5, 2.01, 3.03))
        swell = np.sin(np.pi * x / 4.0) ** 2
        write(os.path.join(root, "ambient", f"cave{k}.wav"), (tone + 0.3 * lowpass(noise(4.0), 300)) * swell)
    # Hurt: a short low grunt.
    for k in range(1, 4):
        x = t(0.25)
        f = rng.uniform(160, 220)
        write(os.path.join(root, "damage", f"hurt{k}.wav"),
              (np.sign(np.sin(2 * np.pi * f * (1 - 0.4 * x) * x)) * 0.5 + lowpass(noise(0.25), 800))
              * envelope(len(x), 0.005, 0.08))


if __name__ == "__main__":
    main(sys.argv[1])
