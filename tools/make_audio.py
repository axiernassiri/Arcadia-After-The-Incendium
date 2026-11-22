#!/usr/bin/env python3
"""Synthesise Arcadia's sounds and music into assets/audio/*.wav (no samples, no downloads).

  music_peace.wav   a slow ambient loop (64 s): soft pads and a plucked arpeggio in A minor
  music_war.wav     a darker loop (48 s) in D minor with a low drum pulse
  click.wav  open.wav  event.wav  war.wav  battle.wav  doom.wav   short effects

Both music tracks loop seamlessly (their echo tails wrap round to the start).
Usage: python tools/make_audio.py      Needs: numpy.
"""
import os
import wave

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "audio")
SR = 22050
RNG = np.random.default_rng(4289)


def t_axis(sec):
    return np.arange(int(SR * sec)) / SR


def note(name):
    names = {"C": -9, "C#": -8, "D": -7, "D#": -6, "E": -5, "F": -4, "F#": -3, "G": -2, "G#": -1, "A": 0, "A#": 1, "B": 2}
    pitch, octave = name[:-1], int(name[-1])
    return 440.0 * 2 ** ((names[pitch] + 12 * (octave - 4)) / 12)


def env(n, attack, release, sustain_level=1.0):
    e = np.full(n, sustain_level)
    a = max(1, int(SR * attack))
    r = max(1, int(SR * release))
    e[:a] = np.linspace(0, sustain_level, a)
    e[-r:] *= np.linspace(1, 0, r)
    return e


def lowpass(x, k):
    """A simple smoothing filter (moving average k samples)."""
    if k <= 1:
        return x
    c = np.cumsum(np.concatenate([np.zeros(k), x]))
    return (c[k:] - c[:-k]) / k


def echo(x, delays, gain, loop=False):
    """A cheap reverb: feedback taps. With loop=True the tail wraps round, so a loop stays seamless."""
    y = x.copy()
    for _ in range(3):
        for d in delays:
            n = int(SR * d)
            y = y + gain * (np.roll(y, n) if loop else np.concatenate([np.zeros(n), y[:-n]]))
        gain *= 0.5
    return y


def pad(freq, sec, detune=0.004):
    t = t_axis(sec)
    x = np.zeros_like(t)
    for k, (mult, amp) in enumerate([(1, 1.0), (2, 0.35), (3, 0.15), (0.5, 0.4)]):
        for d in (-detune, detune):
            x += amp * np.sin(2 * np.pi * freq * mult * (1 + d) * t + k)
    lfo = 0.85 + 0.15 * np.sin(2 * np.pi * 0.11 * t)
    return x * lfo


def pluck(freq, sec=1.6):
    t = t_axis(sec)
    x = np.sin(2 * np.pi * freq * t) + 0.3 * np.sin(2 * np.pi * freq * 2 * t) + 0.1 * np.sin(2 * np.pi * freq * 3 * t)
    return x * np.exp(-t * 3.2)


def drum(sec=0.9, f0=110, f1=45, noise=0.25):
    t = t_axis(sec)
    f = f1 + (f0 - f1) * np.exp(-t * 18)
    ph = 2 * np.pi * np.cumsum(f) / SR
    x = np.sin(ph) * np.exp(-t * 5.5)
    x += noise * lowpass(RNG.standard_normal(len(t)), 6) * np.exp(-t * 25)
    return x


def place(buf, clip, at):
    i = int(SR * at) % len(buf)
    end = i + len(clip)
    if end <= len(buf):
        buf[i:end] += clip
    else:   # wrap round the loop
        k = len(buf) - i
        buf[i:] += clip[:k]
        buf[:end - len(buf)] += clip[k:]


def normalise(x, peak=0.85):
    return x / (np.abs(x).max() + 1e-9) * peak


def write(name, x):
    os.makedirs(OUT, exist_ok=True)
    data = (np.clip(x, -1, 1) * 32767).astype(np.int16)
    with wave.open(os.path.join(OUT, name), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())
    print(f"wrote assets/audio/{name} ({len(x) / SR:.1f} s)")


def music_peace():
    length = 64.0
    buf = np.zeros(int(SR * length))
    chords = [["A2", "E3", "A3", "C4", "E4"], ["F2", "C3", "F3", "A3", "C4"],
              ["C3", "G3", "C4", "E4", "G4"], ["G2", "D3", "G3", "B3", "D4"]]
    bar = 8.0
    for rep in range(2):
        for i, ch in enumerate(chords):
            start = (rep * 4 + i) * bar
            for nm in ch:
                p = pad(note(nm), bar + 2.0) * env(int(SR * (bar + 2.0)), 2.5, 3.0) * 0.06
                place(buf, p, start)
            # a slow, wandering arpeggio over the chord
            tones = [note(n) * 2 for n in ch[2:]]
            for k in range(8):
                if RNG.random() < 0.7:
                    place(buf, pluck(tones[int(RNG.integers(len(tones)))]) * 0.09, start + k * 1.0 + RNG.random() * 0.15)
    buf = echo(buf, [0.37, 0.61, 0.89], 0.28, loop=True)
    write("music_peace.wav", normalise(buf, 0.6))


def music_war():
    length = 48.0
    buf = np.zeros(int(SR * length))
    chords = [["D2", "A2", "D3", "F3"], ["A#1", "F2", "A#2", "D3"], ["C2", "G2", "C3", "E3"], ["A1", "E2", "A2", "C#3"]]
    bar = 6.0
    for rep in range(2):
        for i, ch in enumerate(chords):
            start = (rep * 4 + i) * bar
            for nm in ch:
                p = pad(note(nm), bar + 1.5, 0.007) * env(int(SR * (bar + 1.5)), 1.0, 2.0) * 0.07
                place(buf, p, start)
    for k in range(int(length / 0.75)):   # a march pulse: strong-weak
        strong = k % 4 == 0
        place(buf, drum(0.8, 95 if strong else 80, 42) * (0.5 if strong else 0.25), k * 0.75)
    buf = echo(buf, [0.29, 0.53], 0.22, loop=True)
    write("music_war.wav", normalise(buf, 0.6))


def effects():
    # click: a short wooden tick
    t = t_axis(0.05)
    write("click.wav", normalise((np.sin(2 * np.pi * 1700 * t) * 0.5 + lowpass(RNG.standard_normal(len(t)), 3) * 0.5) * np.exp(-t * 120), 0.5))
    # open: a soft paper swish
    t = t_axis(0.25)
    sw = lowpass(RNG.standard_normal(len(t)), 9) * np.sin(np.pi * t / 0.25) ** 2
    write("open.wav", normalise(sw, 0.35))
    # event: two bell strikes
    buf = np.zeros(int(SR * 2.6))
    for f, at in ((note("E5"), 0.0), (note("B5"), 0.35)):
        tt = t_axis(2.2)
        bell = sum(a * np.sin(2 * np.pi * f * m * tt) * np.exp(-tt * d) for m, a, d in ((1, 1, 2.2), (2.76, 0.5, 3.5), (5.4, 0.25, 5.0)))
        place(buf, bell, at)
    write("event.wav", normalise(echo(buf, [0.23], 0.2), 0.6))
    # war: two war drums and a low brass chord
    buf = np.zeros(int(SR * 2.4))
    place(buf, drum(1.2, 120, 40, 0.4), 0.0)
    place(buf, drum(1.2, 120, 40, 0.4), 0.45)
    tt = t_axis(1.8)
    brass = sum(np.sign(np.sin(2 * np.pi * note(n) * tt)) * 0.2 for n in ("D3", "A3", "D4"))
    place(buf, lowpass(brass, 12) * env(len(tt), 0.15, 0.8) * 0.6, 0.5)
    write("war.wav", normalise(buf, 0.8))
    # battle: a ragged volley of drums and noise
    buf = np.zeros(int(SR * 1.6))
    for k in range(5):
        place(buf, drum(0.6, 140, 55, 0.8) * (0.6 + 0.4 * RNG.random()), k * 0.18 + RNG.random() * 0.05)
    write("battle.wav", normalise(buf, 0.7))
    # doom: a deep rising drone with a beating tremolo (the Black Moon, the Eschaton)
    tt = t_axis(4.0)
    drone = np.sin(2 * np.pi * 55 * tt) + np.sin(2 * np.pi * 55.7 * tt) + 0.5 * np.sin(2 * np.pi * 82.4 * tt)
    drone += 0.4 * lowpass(RNG.standard_normal(len(tt)), 40)
    drone *= (0.6 + 0.4 * np.sin(2 * np.pi * 3.0 * tt)) * env(len(tt), 1.5, 1.2)
    write("doom.wav", normalise(drone, 0.8))


if __name__ == "__main__":
    effects()
    music_peace()
    music_war()
