# Marketing videos and store screenshots

Builds the Play promo, the Instagram reels and the video guide as
[HyperFrames](https://hyperframes.heygen.com) compositions (HTML + GSAP,
rendered to MP4), using real app screens from `../store_screenshots/`.
Everything is free and runs offline once set up.

- `build_video.py spec.json` — voiceover per scene (Kokoro TTS), scene
  timings from the voiceover, music from `music.py`, ducked under the voice
  with ffmpeg, then `hyperframes render`.
- `music.py` — procedural background music, so there is nothing to license.
- `specs/*.json` — one file per video: scenes, on-screen text, voiceover
  lines and highlight boxes (in 1080×2160 screenshot pixels).
- Scene types: `hook`, `logo`, `phone` (a real screen, with highlights,
  taps and an optional Mitra peeking in), `chat` (Ask FieldOS typed out live:
  question, answer, confirm card, Save), `chaos` (WhatsApp messages piling
  up), `stat` (a number counting up), `mitra` (Mitra with a speech bubble),
  `chapter` and `cta`. `"caption_style": "bold"` gives big Reels-style
  captions. A scene with no `vo` lasts `min` seconds (the Telugu and Hindi
  reels are music only, with on-screen text).
- `mitra_sheets.py` — Mitra's animations from the app as sprite sheets.
- `peek.js <project dir> <out.png> t1 t2 …` — a contact sheet of frames,
  to check a composition before the slow render.
- `store_screenshots.js <out>` — the 8 Play Store screenshots in English,
  Hindi and Telugu (each with the app itself in that language), and the
  1024×500 feature graphic.

## Setup (once, in a working folder outside the repo)

```
npm i hyperframes@0.9.23 gsap@3.15.0 @fontsource/inter @fontsource/noto-sans-devanagari @fontsource/noto-sans-telugu playwright
pip install kokoro-onnx soundfile scipy
```

Next to the scripts, create:

- `assets/`: `gsap.min.js`, the Inter and Noto `.woff2` files from the
  `@fontsource` packages, `shots/en|hi|te/*.png` from the screenshot test
  (below), and `python3 mitra_sheets.py`.

App screens, from `fieldos_mobile/`:

```
flutter test tool/store_screenshots/screenshots_test.dart          # English
SHOTS_LANG=hi INDIC_FONTS_DIR=<dir> SHOTS_DIR=build/store_screenshots_hi flutter test tool/store_screenshots/screenshots_test.dart
SHOTS_LANG=te INDIC_FONTS_DIR=<dir> SHOTS_DIR=build/store_screenshots_te flutter test tool/store_screenshots/screenshots_test.dart
```

`INDIC_FONTS_DIR` holds Noto Sans Devanagari and Telugu as `.ttf` (the
test engine has no system fonts; convert the `@fontsource` woff2 files with
fontTools). `SHOTS_TOUR_SEEN=1` hides the tour invite on Home.
- `tts/`: `kokoro-q8.onnx` (Kokoro-82M, Apache-2.0; the npm package
  `kokoro-q8-shards` has it in 6 parts to concatenate) and `voices.npz`
  (Kokoro voice vectors, for example from the `kokoro-local-runtime` npm
  package, saved as an npz of `(N, 1, 256)` float32 arrays).

Write "Field O S", "D P R" and "G P S" in voiceover lines so the voice
spells them out; captions turn them back into FieldOS, DPR and GPS.
