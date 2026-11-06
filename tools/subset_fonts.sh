#!/usr/bin/env bash
# Rebuilds the brand font files the phone app bundles
# (fieldos_mobile/assets/fonts/Inter-*.otf) from a full Inter install.
#
# The app uses Inter for Latin text only. Telugu, Hindi and other Indian
# scripts fall back to the phone's own Noto fonts, so the subset keeps the
# APK small (about 70 KB a weight instead of 600 KB).
#
#   pip install fonttools
#   tools/subset_fonts.sh /usr/share/fonts/opentype/inter
set -euo pipefail

SRC=${1:-/usr/share/fonts/opentype/inter}
OUT="$(cd "$(dirname "$0")/.." && pwd)/fieldos_mobile/assets/fonts"
mkdir -p "$OUT"
for w in Regular Medium SemiBold Bold; do
  pyftsubset "$SRC/Inter-$w.otf" \
    --unicodes="U+0020-007E,U+00A0-00FF,U+0131,U+0152-0153,U+02C6,U+02DA,U+02DC,U+2000-206F,U+20B9,U+20AC,U+2122,U+2190-2199,U+2212,U+2215,U+2248,U+2260,U+2264,U+2265,U+00D7,U+00F7,U+25CF,U+2713,U+2714" \
    --layout-features='kern,liga,calt,tnum,case,ss01,cv11' \
    --output-file="$OUT/Inter-$w.otf"
  echo "wrote $OUT/Inter-$w.otf"
done
