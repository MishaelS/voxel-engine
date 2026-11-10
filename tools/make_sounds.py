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
  mob/<mob>/sayN, hurtN, deathN (pig, cow, sheep, chicken, wolf, zombie,
  skeleton, spider, creeper, slime), mob/creeper/fuse, mob/slime/bigN,
  smallN, random/explodeN, bow, bowhit, break,
  note/harp, bass, bd, snare, hat (note blocks; the game changes the pitch),
  ambient/rainN, ambient/thunderN, random/fuse
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
    # Door: a wooden creak opening, a knock closing.
    x = t(0.5)
    creak = np.sin(2 * np.pi * (160 + 90 * np.sin(2 * np.pi * 2.3 * x)) * x) * (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * 29 * x)))
    write(os.path.join(root, "door", "open.wav"), lowpass(creak + 0.3 * noise(0.5), 1500) * env(0.5, 0.04, 0.3))
    write(os.path.join(root, "door", "close.wav"), MATERIALS["wood"](1.8))
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

    mobs(root)


def voice(seconds, f0, f1, cutoff, buzz=1.0, vibrato=0.0, rate=6.0):
    """A sawtooth voice gliding from f0 to f1 Hz, filtered: animal calls."""
    x = t(seconds)
    freq = f0 + (f1 - f0) * x / seconds
    freq = freq * (1 + vibrato * np.sin(2 * np.pi * rate * x))
    phase = np.cumsum(freq) / RATE
    saw = 2 * (phase % 1.0) - 1
    return lowpass(saw * buzz + 0.15 * noise(seconds), cutoff)


def fade(signal, attack=0.02, release=0.08):
    n = len(signal)
    x = np.arange(n) / RATE
    return signal * np.minimum(x / attack, 1.0) * np.minimum((n / RATE - x) / release, 1.0)


def mobs(root):
    def out(mob, name, signal):
        write(os.path.join(root, "mob", mob, name + ".wav"), signal)

    for k in range(1, 4):
        j = rng.uniform(0.9, 1.1)
        # Pig: short nasal grunts.
        out("pig", f"say{k}", fade(voice(0.3, 180 * j, 130 * j, 900, vibrato=0.15, rate=30), 0.01, 0.1))
        out("pig", f"hurt{k}", fade(voice(0.35, 420 * j, 300 * j, 1600, vibrato=0.1, rate=25), 0.01, 0.1))
        # Cow: long low moo.
        out("cow", f"say{k}", fade(voice(1.1, 120 * j, 95 * j, 700, vibrato=0.03), 0.15, 0.4))
        out("cow", f"hurt{k}", fade(voice(0.5, 160 * j, 120 * j, 900), 0.03, 0.2))
        # Sheep: bleating baa.
        out("sheep", f"say{k}", fade(voice(0.7, 330 * j, 300 * j, 1800, vibrato=0.06, rate=18), 0.03, 0.2))
        # Chicken: clucks.
        cluck = np.zeros(int(RATE * 0.6))
        for c in range(3):
            piece = fade(voice(0.08, 900 * j, 700 * j, 3000), 0.003, 0.03)
            start = int(RATE * (0.05 + c * rng.uniform(0.12, 0.18)))
            cluck[start:start + len(piece)] += piece[: len(cluck) - start]
        out("chicken", f"say{k}", cluck)
        out("chicken", f"hurt{k}", fade(voice(0.2, 1400 * j, 1000 * j, 4000), 0.005, 0.06))
        # Wolf: bark, whine.
        out("wolf", f"say{k}", fade(voice(0.18, 500 * j, 300 * j, 1500), 0.005, 0.08))
        out("wolf", f"hurt{k}", fade(voice(0.4, 900 * j, 700 * j, 2500, vibrato=0.04), 0.02, 0.15))
        # Zombie: groans.
        out("zombie", f"say{k}", fade(voice(1.0, 90 * j, 70 * j, 500, vibrato=0.08, rate=4) + 0.4 * lowpass(noise(1.0), 400), 0.2, 0.4))
        out("zombie", f"hurt{k}", fade(voice(0.35, 140 * j, 100 * j, 700), 0.01, 0.12))
        # Skeleton: rattling bones.
        bones = sum(np.roll(np.pad(highpass(noise(0.03), 1500) * env(0.03, 0.001, 0.008), (0, int(RATE * 0.45))),
                            int(RATE * rng.uniform(0, 0.4))) for _ in range(9))
        out("skeleton", f"say{k}", bones)
        out("skeleton", f"hurt{k}", bones[: int(RATE * 0.25)])
        # Spider: hissy chitter.
        out("spider", f"say{k}", fade(highpass(noise(0.5), 2500) * (0.6 + 0.4 * np.sin(2 * np.pi * 35 * t(0.5))), 0.03, 0.15))
        out("spider", f"hurt{k}", fade(highpass(noise(0.25), 2000), 0.005, 0.1))
        # Creeper: a dry rasp when hurt.
        out("creeper", f"hurt{k}", fade(highpass(lowpass(noise(0.3), 3000), 600), 0.005, 0.12))
        # Slime: squelches.
        out("slime", f"big{k}", fade(lowpass(noise(0.3), 400) + 0.8 * voice(0.3, 160 * j, 60 * j, 300), 0.005, 0.15))
        out("slime", f"small{k}", fade(lowpass(noise(0.2), 800) + 0.8 * voice(0.2, 320 * j, 140 * j, 600), 0.005, 0.1))
        # Explosion: a deep rumbling boom.
        boom = lowpass(noise(2.0), 300) * env(2.0, 0.005, 0.45) + 0.6 * lowpass(noise(2.0), 2000) * env(2.0, 0.002, 0.08)
        write(os.path.join(root, "random", f"explode{k}.wav"), boom)
    for mob, base in [("pig", 200), ("cow", 110), ("sheep", 280), ("chicken", 1100), ("wolf", 600), ("zombie", 80),
                      ("spider", 0), ("creeper", 0), ("skeleton", 0)]:
        if base:
            out(mob, "death", fade(voice(0.8, base * 1.3, base * 0.6, base * 6, vibrato=0.05), 0.02, 0.3))
        else:
            out(mob, "death", fade(highpass(noise(0.6), 900) * env(0.6, 0.005, 0.25), 0.005, 0.2))
    out("creeper", "fuse", fade(highpass(noise(1.5), 3000) * np.minimum(t(1.5) / 0.3, 1.0), 0.05, 0.1))
    x = t(0.4)
    write(os.path.join(root, "random", "bow.wav"),
          np.sin(2 * np.pi * (220 + 200 * np.exp(-x * 20)) * x) * env(0.4, 0.002, 0.08) + 0.3 * highpass(noise(0.4), 3000) * env(0.4, 0.002, 0.05))
    write(os.path.join(root, "random", "bowhit.wav"), MATERIALS["wood"](0.8))
    for k in range(1, 4):
        j = rng.uniform(0.9, 1.1)
        out("sheep", f"hurt{k}", fade(voice(0.4, 380 * j, 330 * j, 2000, vibrato=0.08, rate=20), 0.02, 0.12))
        out("slime", f"hurt{k}", fade(lowpass(noise(0.25), 600) + 0.8 * voice(0.25, 240 * j, 90 * j, 450), 0.005, 0.1))
    out("sheep", "death", fade(voice(0.8, 360, 200, 1800, vibrato=0.08, rate=16), 0.02, 0.3))
    out("slime", "death", fade(lowpass(noise(0.4), 500) + 0.8 * voice(0.4, 200, 50, 350), 0.005, 0.2))
    # Something wearing out and breaking: a sharp crack.
    write(os.path.join(root, "random", "break.wav"),
          highpass(noise(0.25), 1500) * env(0.25, 0.001, 0.04)
          + 0.6 * np.sin(2 * np.pi * 900 * t(0.25)) * env(0.25, 0.001, 0.02))
    notes(root)
    weather(root)



def notes(root):
    """Note block instruments, all at F#4 (the game pitches them)."""
    f = 369.99
    x = t(1.2)
    harp = sum(np.sin(2 * np.pi * f * m * x) * np.exp(-x * (3 + 2 * m)) / m for m in (1, 2, 3, 4))
    write(os.path.join(root, "note", "harp.wav"), harp * env(1.2, 0.002, 0.6))
    bass = sum(np.sin(2 * np.pi * f / 4 * m * x) * np.exp(-x * (4 + m)) / m for m in (1, 2, 3))
    write(os.path.join(root, "note", "bass.wav"), bass * env(1.2, 0.003, 0.4))
    x = t(0.4)
    write(os.path.join(root, "note", "bd.wav"), np.sin(2 * np.pi * (60 + 120 * np.exp(-x * 30)) * x) * env(0.4, 0.002, 0.12))
    write(os.path.join(root, "note", "snare.wav"), (highpass(noise(0.4), 1200) + 0.4 * np.sin(2 * np.pi * 190 * x)) * env(0.4, 0.001, 0.07))
    x = t(0.15)
    write(os.path.join(root, "note", "hat.wav"), highpass(noise(0.15), 5000) * env(0.15, 0.001, 0.02))



def weather(root):
    """Rain pattering (many tiny drops), thunder (a crack, then a long low
    rumble) and a lit fuse's hiss."""
    for k in range(1, 5):
        drops = grains(1.2, 900, grain=0.003, cutoff=6000) + 0.5 * lowpass(noise(1.2), 1500)
        write(os.path.join(root, "ambient", f"rain{k}.wav"), drops * np.minimum(t(1.2) / 0.1, 1.0) * np.minimum((1.2 - t(1.2)) / 0.3, 1.0))
    for k in range(1, 4):
        x = t(5.0)
        crack = highpass(noise(5.0), 800) * np.exp(-x / 0.08)
        rumble = lowpass(noise(5.0), 120) * (np.minimum(x / 0.3, 1.0) * np.exp(-x / 1.6))
        rumble *= 1 + 0.6 * np.sin(2 * np.pi * rng.uniform(1.5, 3.0) * x)
        write(os.path.join(root, "ambient", f"thunder{k}.wav"), 0.5 * crack + rumble * 2.5)
    write(os.path.join(root, "random", "fuse.wav"), highpass(noise(1.5), 2500) * np.minimum(t(1.5) / 0.05, 1.0) * np.minimum((1.5 - t(1.5)) / 0.2, 1.0))


if __name__ == "__main__":
    main(sys.argv[1])
