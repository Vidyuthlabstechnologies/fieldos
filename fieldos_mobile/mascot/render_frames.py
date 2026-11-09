"""Renders every Mitra mood to a looping animated WebP for the app.

The app plays these instead of the .riv: a .riv published from a free Rive
workspace carries a Rive splash watermark, and pre-rendered frames also
spare the app Rive's native runtime. The scene in scene.rml stays the
source of truth; run this again after changing make_scene.py.

The CLI's captures are opaque, so each frame is rendered on black and on
white and the alpha recovered from the difference:
    alpha = 255 - (white - black),  colour = black / alpha.

Run from this folder (needs the Rive CLI and Pillow):
    python3 render_frames.py            # every mood
    python3 render_frames.py wave talk  # just these
"""
from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageChops

import make_scene

HERE = Path(__file__).resolve().parent
OUT = HERE.parent / "assets" / "mascot"
TMP = HERE / "build" / "frames"
FPS = 20
SIZE = 256  # px per frame; shown at up to ~128 dp, so sharp at 2x


def capture(backdrop: str, moods: list[tuple[int, str, int]]) -> None:
    env = dict(os.environ, MITRA_BACKDROP=backdrop)
    subprocess.run([sys.executable, "make_scene.py"], cwd=HERE, check=True, env=env, capture_output=True)
    lines = []
    for index, name, frames in moods:
        d = TMP / backdrop / name
        d.mkdir(parents=True, exist_ok=True)
        # A fresh state machine per mood, then let the 200 ms blend from
        # idle finish before the first frame.
        lines += ["reload", f"data mood={index}", "advance 0.3s"]
        for f in range(frames):
            lines += [f"screenshot {d / f'{f:03d}.png'}", f"advance {1 / FPS:.5f}s"]
    lines.append("quit")
    res = subprocess.run(["rive", ".", "--commands", f"--scale={SIZE / 400}"], cwd=HERE, input="\n".join(lines),
                         text=True, capture_output=True)
    errors = [l for l in res.stdout.splitlines() if l.startswith("err")]
    if res.returncode != 0 or errors:
        raise SystemExit(f"rive failed: {errors[:5] or res.stderr[-2000:]}")


def matte(black: Image.Image, white: Image.Image) -> Image.Image:
    black, white = black.convert("RGB"), white.convert("RGB")
    alpha = ImageChops.subtract(white, black).convert("L").point(lambda v: 255 - v)
    # Un-premultiply: the black-backed colour is colour * alpha.
    rgba = Image.new("RGBA", black.size)
    pb, pa, po = black.load(), alpha.load(), rgba.load()
    w, h = black.size
    for y in range(h):
        for x in range(w):
            a = pa[x, y]
            if a == 0:
                po[x, y] = (0, 0, 0, 0)
            else:
                r, g, b = pb[x, y]
                po[x, y] = (min(255, r * 255 // a), min(255, g * 255 // a), min(255, b * 255 // a), a)
    return rgba


def main() -> None:
    wanted = set(sys.argv[1:])
    moods = [(i, name, max(1, round(d / 60 * FPS))) for i, (name, d, _) in enumerate(make_scene.MOODS)
             if not wanted or name in wanted]
    OUT.mkdir(parents=True, exist_ok=True)
    for bg in ("FF000000", "FFFFFFFF"):
        capture(bg, moods)
    subprocess.run([sys.executable, "make_scene.py"], cwd=HERE, check=True, capture_output=True)
    for _, name, frames in moods:
        imgs = [matte(Image.open(TMP / "FF000000" / name / f"{f:03d}.png"),
                      Image.open(TMP / "FFFFFFFF" / name / f"{f:03d}.png")) for f in range(frames)]
        out = OUT / f"mitra_{name}.webp"
        imgs[0].save(out, save_all=True, append_images=imgs[1:], duration=1000 // FPS, loop=0,
                     quality=88, method=6, alpha_quality=100)
        imgs[0].save(OUT / f"mitra_{name}.png", optimize=True)  # the still
        print(f"{name}: {frames} frames, {out.stat().st_size // 1024} KB")


if __name__ == "__main__":
    main()
