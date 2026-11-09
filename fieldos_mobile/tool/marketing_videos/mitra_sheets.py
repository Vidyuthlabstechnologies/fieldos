"""Turns the app's Mitra animations (assets/mascot/mitra_*.webp) into sprite
sheets for the videos: 10 frames a row, 384 px a frame, plus meta.json.
build_video.py picks the frame from the timeline time, so renders are exact.

usage: python3 mitra_sheets.py   (writes assets/mitra_sheets/ and assets/mitra/)
"""
import glob, json, math, os, shutil
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, '..', '..', 'assets', 'mascot')
OUT = os.path.join(HERE, 'assets', 'mitra_sheets')
STILLS = os.path.join(HERE, 'assets', 'mitra')
S, COLS = 384, 10
os.makedirs(OUT, exist_ok=True)
os.makedirs(STILLS, exist_ok=True)
meta = {}
for f in sorted(glob.glob(os.path.join(SRC, 'mitra_*.webp'))):
    mood = os.path.basename(f)[6:-5]
    anim = Image.open(f)
    n = anim.n_frames
    rows = math.ceil(n / COLS)
    sheet = Image.new('RGBA', (COLS * S, rows * S))
    for i in range(n):
        anim.seek(i)
        sheet.paste(anim.convert('RGBA').resize((S, S), Image.LANCZOS), ((i % COLS) * S, (i // COLS) * S))
    sheet.save(os.path.join(OUT, f'{mood}.webp'), quality=92, method=4)
    meta[mood] = {'n': n, 'cols': COLS, 'rows': rows}
    shutil.copy(f[:-5] + '.png', STILLS)
json.dump(meta, open(os.path.join(OUT, 'meta.json'), 'w'))
print(', '.join(f'{m} ({v["n"]})' for m, v in meta.items()))
