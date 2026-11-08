"""Procedural, royalty-free background music for the FieldOS videos.
Everything is synthesised here, so there is no licence to clear.
usage: python3 music.py out.wav seconds [mood]   mood: drive | calm"""
import sys, numpy as np, soundfile as sf
from scipy.signal import butter, sosfilt, fftconvolve

SR = 44100
out, secs = sys.argv[1], float(sys.argv[2])
mood = sys.argv[3] if len(sys.argv) > 3 else 'drive'
bpm = 104 if mood == 'drive' else 88
beat = 60 / bpm
n = int(SR * (secs + 2))
rng = np.random.default_rng(7)

def midi(m): return 440 * 2 ** ((m - 69) / 12)
def env(length, a, r):
    t = np.arange(length) / SR
    e = np.minimum(1, t / max(a, 1e-4)) * np.exp(-t / r)
    return e
def lp(x, f, order=2):
    return sosfilt(butter(order, f, 'low', fs=SR, output='sos'), x)
def hp(x, f, order=2):
    return sosfilt(butter(order, f, 'high', fs=SR, output='sos'), x)

# D major: I  V  vi  IV  (D A Bm G)
chords = [[62, 66, 69, 74], [57, 61, 64, 69], [59, 62, 66, 71], [55, 59, 62, 67]]
bass = [38, 33, 35, 31]
bar = 4 * beat
pad = np.zeros(n); arp = np.zeros(n); bs = np.zeros(n); drums = np.zeros(n)
t_all = np.arange(n) / SR
nbars = int(secs / bar) + 2
for b in range(nbars):
    c = chords[b % 4]; s = int(b * bar * SR); L = int(bar * SR)
    if s >= n: break
    L = min(L, n - s); t = np.arange(L) / SR
    # warm pad: detuned saws, slow attack
    p = np.zeros(L)
    for m in c:
        for det in (-0.07, 0.0, 0.07):
            f = midi(m + det)
            p += 2 * ((t * f + rng.random()) % 1) - 1
    p = lp(p, 1400 if mood == 'drive' else 900) * np.minimum(1, t / 0.4) * np.minimum(1, (L / SR - t) / 0.3 + 0.0001)
    pad[s:s + L] += p * 0.035
    # bass: root on 1 and the "and" of 3
    for off in ((0, 1.5 * beat), (2.5 * beat, 1.4 * beat)) if mood == 'drive' else ((0, 3.8 * beat),):
        o = s + int(off[0] * SR); l = min(int(off[1] * SR), n - o)
        if l <= 0: continue
        tt = np.arange(l) / SR; f = midi(bass[b % 4])
        x = np.sin(2 * np.pi * f * tt) + 0.3 * np.sin(4 * np.pi * f * tt)
        bs[o:o + l] += x * env(l, 0.01, 0.9) * 0.28
    # pluck arpeggio in 8ths
    steps = 8 if mood == 'drive' else 4
    pattern = [0, 2, 1, 3, 2, 1, 3, 2]
    for k in range(steps):
        o = s + int(k * bar / steps * SR); l = min(int(0.6 * SR), n - o)
        if l <= 0: continue
        tt = np.arange(l) / SR; f = midi(c[pattern[k % 8]] + 12)
        x = np.sin(2 * np.pi * f * tt) + 0.25 * np.sin(4 * np.pi * f * tt) + 0.1 * np.sin(6 * np.pi * f * tt)
        arp[o:o + l] += lp(x, 3000) * env(l, 0.002, 0.18) * 0.06
    # drums
    if mood == 'drive' or b % 2 == 0:
        for k in range(4):
            o = s + int(k * beat * SR); l = min(int(0.35 * SR), n - o)
            if l <= 0: continue
            tt = np.arange(l) / SR
            f = 55 + 90 * np.exp(-tt * 30)
            kick = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-tt * 9)
            drums[o:o + l] += kick * (0.5 if mood == 'drive' else 0.3)
            if mood == 'drive':
                o2 = o + int(beat / 2 * SR); l2 = min(int(0.06 * SR), n - o2)
                if l2 > 0:
                    drums[o2:o2 + l2] += lp(hp(rng.standard_normal(l2), 7000), 11000) * np.exp(-np.arange(l2) / SR * 70) * 0.05
            if k in (1, 3):
                l3 = min(int(0.25 * SR), n - o)
                clap = lp(hp(rng.standard_normal(l3), 1200), 6000) * np.exp(-np.arange(l3) / SR * 22)
                drums[o:o + l3] += clap * (0.06 if mood == 'drive' else 0.03)

# arrangement: drums and arp come in after the first bar; everything fades at the end
intro = np.clip(t_all / (bar), 0, 1)
mix = pad + bs * np.clip(t_all / (bar * 0.5), 0, 1) + (arp + drums) * intro
ir = rng.standard_normal(int(1.8 * SR)) * np.exp(-np.arange(int(1.8 * SR)) / SR * 3.2)
wet = fftconvolve(pad + arp, ir)[:n] * 0.012
mix = mix + wet
mix = mix[: int(SR * secs)]
fade = int(SR * 2.5)
mix[-fade:] *= np.linspace(1, 0, fade) ** 1.5
mix[: int(SR * 0.3)] *= np.linspace(0, 1, int(SR * 0.3))
mix = mix / np.max(np.abs(mix)) * 0.89
stereo = np.stack([mix, np.roll(mix, 220) * 0.98], axis=1)
sf.write(out, stereo, SR)
