"""Generates every sound effect and music loop for Nine Banners as .wav files.

No downloaded samples: each sound is built from sine waves, noise and envelopes,
so the whole soundtrack is reproducible and license-free.

    python tools/gen_audio.py      (from the game folder; needs numpy)
"""
import os
import wave
import numpy as np

SR = 32000
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio")
rng = np.random.default_rng(7)


def t_axis(d):
    return np.linspace(0, d, int(SR * d), endpoint=False)


def env(n, a=0.005, r=0.2, curve=4.0):
    t = np.linspace(0, 1, n)
    att = int(SR * a)
    e = np.exp(-curve * t / max(r, 1e-3) * (n / SR))
    if att > 0:
        e[:att] *= np.linspace(0, 1, att)
    return e


def tone(freq, d, kind="sine", decay=6.0, att=0.004, harm=None):
    t = t_axis(d)
    if harm is None:
        harm = [(1, 1.0)]
    s = np.zeros_like(t)
    for mult, amp in harm:
        s += amp * np.sin(2 * np.pi * freq * mult * t)
    e = np.exp(-decay * t)
    a = int(SR * att)
    if a:
        e[:a] *= np.linspace(0, 1, a)
    return s * e


def pluck(freq, d=1.2, bright=0.5):
    # soft marimba / kalimba-ish pluck
    return tone(freq, d, decay=4.5, harm=[(1, 1.0), (2.0, 0.25 * bright), (3.01, 0.12 * bright), (4.2, 0.05 * bright)])


def noise(d, color=0.0):
    n = rng.standard_normal(int(SR * d))
    if color > 0:  # simple low-pass for brown-ish noise
        out = np.zeros_like(n)
        acc = 0.0
        k = 1.0 - color
        for i in range(len(n)):
            acc = acc * color + n[i] * k
            out[i] = acc
        n = out / (np.max(np.abs(out)) + 1e-9)
    return n


def lowpass(x, alpha):
    y = np.zeros_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc += alpha * (x[i] - acc)
        y[i] = acc
    return y


def mix(*parts):
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[: len(p)] += p
    return out


def at(sig, offset, total=None):
    pad = np.zeros(int(SR * offset))
    s = np.concatenate([pad, sig])
    if total:
        n = int(SR * total)
        s = np.pad(s, (0, max(0, n - len(s))))[:n]
    return s


def save(name, sig, gain=0.8):
    sig = np.asarray(sig, dtype=np.float64)
    peak = np.max(np.abs(sig)) + 1e-9
    sig = sig / peak * gain
    # tiny fade to kill clicks
    f = min(200, len(sig) // 4)
    sig[:f] *= np.linspace(0, 1, f)
    sig[-f:] *= np.linspace(1, 0, f)
    data = (sig * 32767).astype(np.int16)
    os.makedirs(OUT, exist_ok=True)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())
    print("wrote", name, round(len(sig) / SR, 2), "s")


def note(n):
    # MIDI note -> Hz
    return 440.0 * 2 ** ((n - 69) / 12)


# ---------------------------------------------------------------- UI
def wood_tick(freq=900, d=0.08):
    n = noise(d) * env(int(SR * d), r=0.02, curve=60)
    return lowpass(n, 0.35) * 0.6 + tone(freq, d, decay=55) * 0.5


save("click", wood_tick(780), 0.55)
save("hover", tone(1500, 0.05, decay=80) * 0.4 + lowpass(noise(0.05), 0.2) * env(int(SR * 0.05), r=0.01, curve=80) * 0.2, 0.25)

# paper: filtered noise swish with a rising then falling envelope
d = 0.32
t = t_axis(d)
sw = noise(d) * np.sin(np.pi * t / d) ** 2
save("paper", lowpass(sw, 0.25) + lowpass(sw, 0.06) * 0.6, 0.5)

# pencil scratch
d = 0.45
sc = noise(d)
mod = 0.5 + 0.5 * np.sin(2 * np.pi * 11 * t_axis(d))
save("scratch", (sc - lowpass(sc, 0.2)) * mod * env(len(sc), r=0.4, curve=2), 0.3)

# dice rattle: a burst of random wooden ticks slowing down
parts = []
tt = 0.0
gap = 0.035
while tt < 0.75:
    parts.append(at(wood_tick(rng.uniform(600, 1300), 0.06) * rng.uniform(0.4, 1.0), tt, 0.95))
    tt += gap
    gap *= 1.12
save("dice", mix(*parts), 0.6)
save("dice_land", mix(wood_tick(520, 0.12), at(wood_tick(700, 0.08) * 0.4, 0.07)), 0.7)

# coin: two bright pings
save("coin", mix(tone(2093, 0.5, decay=9, harm=[(1, 1), (2.7, 0.3)]), at(tone(2637, 0.6, decay=8, harm=[(1, 1), (2.7, 0.3)]), 0.07)), 0.45)

# build: wooden thunks + chime
thunks = mix(*[at(lowpass(noise(0.15), 0.08) * env(int(SR * 0.15), r=0.05, curve=30) + tone(110 + 20 * i, 0.15, decay=25), 0.12 * i) for i in range(3)])
save("build", mix(thunks, at(pluck(note(79), 1.0, 1.0) * 0.5, 0.38), at(pluck(note(84), 1.0, 1.0) * 0.4, 0.46)), 0.7)

# footstep
save("step", lowpass(noise(0.09), 0.12) * env(int(SR * 0.09), r=0.03, curve=40) + tone(140, 0.09, decay=40) * 0.6, 0.35)

# combat
hit = mix(lowpass(noise(0.25), 0.15) * env(int(SR * 0.25), r=0.06, curve=25), tone(90, 0.3, decay=12) * 1.2, tone(60, 0.3, decay=9) * 0.8)
save("hit", hit, 0.85)
d = 0.35
wh = noise(d) * np.sin(np.pi * t_axis(d) / d) ** 3
save("whoosh", lowpass(wh, 0.12) - lowpass(wh, 0.02), 0.6)
save("block", mix(tone(320, 0.4, decay=10, harm=[(1, 1), (2.4, 0.5), (3.9, 0.3)]), lowpass(noise(0.1), 0.3) * env(int(SR * 0.1), r=0.02, curve=50)), 0.6)

# results
save("success", mix(*[at(pluck(note(n), 1.2, 0.8), i * 0.09) for i, n in enumerate([67, 71, 74, 79])]), 0.6)
save("fail", mix(at(pluck(note(64), 1.0, 0.3), 0), at(pluck(note(60), 1.3, 0.3), 0.16), at(tone(note(48), 1.0, decay=4) * 0.4, 0.16)), 0.55)
save("levelup", mix(*[at(pluck(note(n), 1.6, 1.0), i * 0.07) for i, n in enumerate([60, 64, 67, 72, 76, 79, 84])]), 0.6)
save("stamp", mix(lowpass(noise(0.2), 0.1) * env(int(SR * 0.2), r=0.04, curve=35), tone(75, 0.25, decay=18) * 1.4), 0.8)

# bells
def bell(freq, d=3.0):
    return tone(freq, d, decay=1.6, harm=[(1, 1.0), (2.0, 0.5), (2.76, 0.35), (5.4, 0.15), (8.9, 0.06)])


save("bell_day", mix(bell(note(57)), at(bell(note(64)) * 0.6, 0.25)), 0.5)
save("bell_week", mix(bell(note(55)), at(bell(note(59)) * 0.7, 0.2), at(bell(note(62)) * 0.7, 0.4), at(bell(note(67)) * 0.8, 0.6)), 0.5)
save("whisper", lowpass(noise(1.2), 0.05) * np.sin(np.pi * t_axis(1.2) / 1.2) ** 2, 0.25)


# ---------------------------------------------------------------- music
def music_loop(bpm, bars, chords, melody_fn, name, pad_gain=0.22, gain=0.5):
    beat = 60.0 / bpm
    total = beat * 4 * bars
    n = int(SR * total)
    out = np.zeros(n + SR * 3)
    for b in range(bars):
        root = chords[b % len(chords)]
        # soft pad: three detuned sines with slow swell
        d = beat * 4
        tt = t_axis(d + 1.0)
        sw = np.sin(np.pi * np.clip(tt / (d + 1.0), 0, 1)) ** 1.5
        pad = np.zeros_like(tt)
        for iv in (0, 7, 12, 16):
            f = note(root + iv)
            pad += np.sin(2 * np.pi * f * tt) + 0.5 * np.sin(2 * np.pi * f * 1.003 * tt)
        start = int(SR * b * d)
        out[start:start + len(pad)] += pad * sw * pad_gain / 4
        # bass pluck on beats 1 and 3
        for k in (0, 2):
            s = pluck(note(root - 12), 1.4, 0.2) * 0.6
            p = int(SR * (b * d + k * beat))
            out[p:p + len(s)] += s
        for (when, mnote, vel) in melody_fn(b, root):
            s = pluck(note(mnote), 1.3, 0.9) * vel
            p = int(SR * (b * d + when * beat))
            out[p:p + len(s)] += s
    # wrap the tail into the start so the loop is seamless
    tail = out[n:]
    out = out[:n]
    out[: len(tail)] += tail
    save(name, out, gain)


PENTA = [0, 2, 4, 7, 9, 12, 14, 16]


def calm_melody(bar, root):
    r = np.random.default_rng(bar * 31 + 5)
    notes = []
    pos = 0.0
    while pos < 4.0:
        if r.random() < 0.62:
            notes.append((pos, root + 12 + PENTA[r.integers(0, len(PENTA))], 0.35 + 0.25 * r.random()))
        pos += [0.5, 1.0, 1.5][r.integers(0, 3)]
    return notes


music_loop(84, 16, [60, 57, 53, 55, 60, 57, 62, 55], calm_melody, "music_world", 0.25, 0.42)


def tense_melody(bar, root):
    r = np.random.default_rng(bar * 17 + 2)
    notes = []
    for k in range(8):
        if r.random() < 0.55:
            notes.append((k * 0.5, root + 12 + [0, 3, 5, 7, 10, 12][r.integers(0, 6)], 0.3 + 0.2 * r.random()))
    return notes


# combat: minor, faster, with a low drum on every beat
def combat_loop():
    bpm = 112
    beat = 60.0 / bpm
    bars = 8
    music_loop(bpm, bars, [45, 45, 41, 43], tense_melody, "music_combat_raw", 0.18, 0.4)


combat_loop()
# add drums to the combat loop
import wave as _w
with _w.open(os.path.join(OUT, "music_combat_raw.wav")) as f:
    raw = np.frombuffer(f.readframes(f.getnframes()), dtype=np.int16).astype(np.float64) / 32767
beat = 60.0 / 112
drum = mix(lowpass(noise(0.25), 0.05) * env(int(SR * 0.25), r=0.05, curve=25), tone(55, 0.3, decay=14) * 1.5)
for k in range(int(len(raw) / SR / beat)):
    p = int(SR * k * beat)
    seg = drum * (1.0 if k % 2 == 0 else 0.55)
    end = min(len(raw), p + len(seg))
    raw[p:end] += seg[: end - p] * 0.35
os.remove(os.path.join(OUT, "music_combat_raw.wav"))
save("music_combat", raw, 0.45)
