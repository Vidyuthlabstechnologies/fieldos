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
- `store_screenshots.js <out>` — the 8 Play Store screenshots with English,
  Hindi and Telugu captions.

## Setup (once, in a working folder outside the repo)

```
npm i hyperframes@0.9.23 gsap@3.15.0 @fontsource/inter @fontsource/noto-sans-devanagari @fontsource/noto-sans-telugu playwright
pip install kokoro-onnx soundfile scipy
```

Next to the scripts, create:

- `assets/`: `gsap.min.js`, the Inter and Noto `.woff2` files from the
  `@fontsource` packages, and `shots/*.png` from
  `flutter test tool/store_screenshots/screenshots_test.dart`.
- `tts/`: `kokoro-q8.onnx` (Kokoro-82M, Apache-2.0; the npm package
  `kokoro-q8-shards` has it in 6 parts to concatenate) and `voices.npz`
  (Kokoro voice vectors, for example from the `kokoro-local-runtime` npm
  package, saved as an npz of `(N, 1, 256)` float32 arrays).

Write "Field O S", "D P R" and "G P S" in voiceover lines so the voice
spells them out; captions turn them back into FieldOS, DPR and GPS.
