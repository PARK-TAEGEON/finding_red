"""Synthesize the slice's sound effects (original, procedurally generated -> free to use).

Writes media/sfx/<Key>.wav and .ogg for every key in src/shared/Config/Audio.luau.
Usage: python3 tools/sfx/make_sfx.py   (needs numpy; ffmpeg for .ogg)
"""
import os
import subprocess
import wave

import numpy as np

SR = 44100
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "media", "sfx")
rng = np.random.default_rng(7)


def t(sec):
    return np.arange(int(SR * sec)) / SR


def env(n, attack=0.002, decay=0.1):
    x = np.arange(n) / SR
    a = np.clip(x / max(attack, 1e-6), 0, 1)
    return a * np.exp(-x / decay)


def noise(sec):
    return rng.uniform(-1, 1, int(SR * sec))


def lowpass(x, cutoff):
    # one-pole low-pass
    alpha = 1 - np.exp(-2 * np.pi * cutoff / SR)
    y = np.empty_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc += alpha * (v - acc)
        y[i] = acc
    return y


def highpass(x, cutoff):
    return x - lowpass(x, cutoff)


def tone(freq, sec, kind="sine"):
    x = t(sec)
    f = np.full_like(x, freq) if np.isscalar(freq) else freq
    phase = 2 * np.pi * np.cumsum(f) / SR
    if kind == "square":
        return np.sign(np.sin(phase))
    if kind == "tri":
        return 2 / np.pi * np.arcsin(np.sin(phase))
    return np.sin(phase)


def sweep(f0, f1, sec):
    return np.geomspace(f0, f1, int(SR * sec))


def pad(x, sec):
    return np.concatenate([x, np.zeros(int(SR * sec))])


def mix(*parts):
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[: len(p)] += p
    return out


def seq(*parts, gap=0.0):
    out = []
    for p in parts:
        out.append(p)
        if gap:
            out.append(np.zeros(int(SR * gap)))
    return np.concatenate(out)


def norm(x, peak=0.9):
    m = np.max(np.abs(x)) or 1
    return x / m * peak


# --- effects --------------------------------------------------------------------
def pistol():
    crack = highpass(noise(0.25), 900) * env(int(SR * 0.25), 0.001, 0.04)
    thump = tone(sweep(180, 60, 0.18), 0.18) * env(int(SR * 0.18), 0.001, 0.05)
    return norm(mix(crack, 0.9 * thump))


def sniper():
    crack = highpass(noise(0.6), 600) * env(int(SR * 0.6), 0.001, 0.09)
    boom = tone(sweep(140, 40, 0.5), 0.5) * env(int(SR * 0.5), 0.001, 0.14)
    tail = lowpass(noise(0.9), 500) * env(int(SR * 0.9), 0.05, 0.3) * 0.4
    return norm(mix(crack, boom, tail))


def bat_swing():
    n = noise(0.3)
    sw = np.sin(np.linspace(0, np.pi, len(n)))
    return norm(lowpass(highpass(n, 300), 2500) * sw * 0.8, 0.6)


def bat_hit():
    thud = tone(sweep(220, 80, 0.15), 0.15) * env(int(SR * 0.15), 0.001, 0.05)
    crack = highpass(noise(0.08), 1500) * env(int(SR * 0.08), 0.001, 0.015)
    return norm(mix(thud, crack))


def click(freq=2200, sec=0.03):
    return tone(freq, sec, "square") * env(int(SR * sec), 0.0005, 0.006)


def reload_():
    return norm(seq(click(1800), np.zeros(int(SR * 0.18)), click(1400, 0.04), np.zeros(int(SR * 0.12)), click(2600)), 0.7)


def dry_fire():
    return norm(click(3000, 0.025), 0.6)


def hit_marker():
    return norm(tone(1900, 0.06) * env(int(SR * 0.06), 0.001, 0.02), 0.6)


def red_death():
    pew = tone(sweep(1200, 200, 0.25), 0.25, "tri") * env(int(SR * 0.25), 0.002, 0.2)
    pop = lowpass(noise(0.1), 1200) * env(int(SR * 0.1), 0.001, 0.03)
    return norm(seq(pew, pop))


def penalty():
    buzz = tone(110, 0.45, "square") * env(int(SR * 0.45), 0.005, 0.4)
    buzz2 = tone(116, 0.45, "square") * env(int(SR * 0.45), 0.005, 0.4)
    return norm(lowpass(mix(buzz, buzz2), 1800), 0.7)


def alert():
    a = tone(880, 0.07, "square") * env(int(SR * 0.07), 0.002, 0.05)
    b = tone(1320, 0.1, "square") * env(int(SR * 0.1), 0.002, 0.07)
    return norm(lowpass(seq(a, b, gap=0.02), 4000), 0.55)


def white_attack():
    thud = tone(sweep(160, 70, 0.12), 0.12) * env(int(SR * 0.12), 0.001, 0.05)
    slap = lowpass(noise(0.06), 3000) * env(int(SR * 0.06), 0.001, 0.02)
    return norm(mix(thud, slap * 0.8))


def player_hurt():
    thud = tone(sweep(120, 55, 0.2), 0.2) * env(int(SR * 0.2), 0.001, 0.08)
    grit = lowpass(noise(0.2), 600) * env(int(SR * 0.2), 0.001, 0.06) * 0.5
    return norm(mix(thud, grit))


def downed():
    return norm(tone(sweep(440, 110, 0.8), 0.8, "tri") * env(int(SR * 0.8), 0.01, 0.6), 0.7)


def arpeggio(freqs, step=0.09, kind="tri", hold=0.25):
    out = np.zeros(int(SR * (step * len(freqs) + hold)))
    for i, f in enumerate(freqs):
        note = tone(f, hold, kind) * env(int(SR * hold), 0.003, hold / 2.5)
        s = int(SR * step * i)
        out[s : s + len(note)] += note
    return out


def revived():
    return norm(arpeggio([523, 659, 784, 1047]), 0.7)


def pickup():
    return norm(seq(tone(988, 0.06, "square") * env(int(SR * 0.06), 0.001, 0.05),
                    tone(1319, 0.14, "square") * env(int(SR * 0.14), 0.001, 0.1)), 0.5)


def countdown():
    return norm(tone(660, 0.15) * env(int(SR * 0.15), 0.002, 0.08), 0.7)


def stage_clear():
    lead = arpeggio([523, 659, 784, 1047, 1319], step=0.11, kind="square", hold=0.4)
    bass = arpeggio([131, 196, 262], step=0.18, kind="tri", hold=0.5)
    return norm(lowpass(mix(lead * 0.6, bass), 5000))


def stage_fail():
    return norm(lowpass(arpeggio([392, 330, 262, 196], step=0.2, kind="square", hold=0.45), 2500), 0.7)


def stamp():
    thunk = tone(sweep(260, 90, 0.18), 0.18) * env(int(SR * 0.18), 0.001, 0.05)
    slap = lowpass(noise(0.05), 2000) * env(int(SR * 0.05), 0.0005, 0.012)
    return norm(mix(thunk, slap))


EFFECTS = {
    "PistolShot": pistol, "SniperShot": sniper, "BatSwing": bat_swing, "BatHit": bat_hit,
    "Reload": reload_, "DryFire": dry_fire, "HitMarker": hit_marker, "RedDeath": red_death,
    "PenaltyKill": penalty, "Alert": alert, "WhiteAttack": white_attack, "PlayerHurt": player_hurt,
    "Downed": downed, "Revived": revived, "Pickup": pickup, "Countdown": countdown,
    "StageClear": stage_clear, "StageFail": stage_fail, "Stamp": stamp,
}


def write_wav(path, x):
    x = np.clip(x, -1, 1)
    fade = min(len(x), int(SR * 0.01))
    x[-fade:] *= np.linspace(1, 0, fade)
    data = (x * 32767).astype(np.int16)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())


def main():
    os.makedirs(OUT, exist_ok=True)
    for key, fn in EFFECTS.items():
        wav = os.path.join(OUT, key + ".wav")
        write_wav(wav, pad(fn(), 0.02))
        ogg = os.path.join(OUT, key + ".ogg")
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", wav, "-c:a", "libvorbis", "-q:a", "5", ogg], check=True)
        print("wrote", key)


if __name__ == "__main__":
    main()
