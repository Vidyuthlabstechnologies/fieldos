"""Draws the FieldOS app icon and store graphics, and writes every size the
Android and iOS projects need. Run from the repo root:

    python3 tools/make_icons.py

Pure Pillow, no assets: an amber hard hat on deep navy. Re-run after
changing the colours or shapes below; it overwrites the generated files.
"""

import re
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

NAVY = (17, 42, 74)
AMBER = (245, 165, 36)
AMBER_DARK = (214, 134, 14)
WHITE = (255, 255, 255)

ROOT = Path(__file__).resolve().parent.parent
MOBILE = ROOT / "fieldos_mobile"
RES = MOBILE / "android/app/src/main/res"
IOS = MOBILE / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
IOS_LAUNCH = MOBILE / "ios/Runner/Assets.xcassets/LaunchImage.imageset"
SPLASH_FONT = MOBILE / "assets/fonts/Inter-Bold.otf"
STORE = ROOT / "docs/store"
FONT_BOLD = "/usr/share/fonts/opentype/inter/Inter-Bold.otf"
FONT_MEDIUM = "/usr/share/fonts/opentype/inter/Inter-Medium.otf"

SS = 4  # supersampling for smooth edges


def hard_hat(size: int, scale: float) -> Image.Image:
    """Transparent square with the hat centred; scale = hat width / size."""
    s = size * SS
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cx, cy = s / 2, s * 0.56
    w = s * scale
    r = w * 0.36  # dome radius
    # dome
    d.pieslice((cx - r, cy - r, cx + r, cy + r), 180, 360, fill=AMBER)
    # ridge down the middle of the dome
    rw = r * 0.22
    d.rounded_rectangle((cx - rw / 2, cy - r * 0.97, cx + rw / 2, cy), radius=rw / 2, fill=AMBER_DARK)
    # band at the base of the dome
    bh = r * 0.16
    d.rectangle((cx - r, cy - bh, cx + r, cy), fill=AMBER_DARK)
    # brim
    bw, brh = w / 2, r * 0.26
    d.rounded_rectangle((cx - bw, cy, cx + bw, cy + brh), radius=brh / 2, fill=AMBER)
    # a site-level line under the hat
    lw, lh, gap = w * 0.34, r * 0.1, r * 0.34
    d.rounded_rectangle((cx - lw, cy + brh + gap, cx + lw, cy + brh + gap + lh), radius=lh / 2, fill=WHITE)
    return img.resize((size, size), Image.LANCZOS)


def full_icon(size: int, rounded: bool = False) -> Image.Image:
    bg = Image.new("RGBA", (size * SS, size * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(bg)
    if rounded:
        d.rounded_rectangle((0, 0, size * SS - 1, size * SS - 1), radius=size * SS * 0.22, fill=NAVY)
    else:
        d.rectangle((0, 0, size * SS, size * SS), fill=NAVY)
    bg = bg.resize((size, size), Image.LANCZOS)
    bg.alpha_composite(hard_hat(size, 0.72))
    return bg


def android():
    legacy = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
    for density, px in legacy.items():
        out = RES / f"mipmap-{density}"
        out.mkdir(parents=True, exist_ok=True)
        full_icon(px, rounded=True).save(out / "ic_launcher.png")
        # adaptive foreground: 108dp canvas, art inside the 66dp safe zone
        fg = px * 108 // 48
        hard_hat(fg, 0.72 * 66 / 108).save(out / "ic_launcher_foreground.png")
    anydpi = RES / "mipmap-anydpi-v26"
    anydpi.mkdir(exist_ok=True)
    (anydpi / "ic_launcher.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@color/ic_launcher_background"/>\n'
        '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
        '    <monochrome android:drawable="@mipmap/ic_launcher_foreground"/>\n'
        "</adaptive-icon>\n"
    )
    (RES / "values/ic_launcher_background.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
        f'    <color name="ic_launcher_background">#{NAVY[0]:02X}{NAVY[1]:02X}{NAVY[2]:02X}</color>\n'
        "</resources>\n"
    )


def ios():
    for f in IOS.glob("Icon-App-*.png"):
        name = f.stem.replace("Icon-App-", "")  # e.g. 20x20@2x
        base, mult = name.split("@")
        px = round(float(base.split("x")[0]) * int(mult.rstrip("x")))
        # iOS rounds corners itself and rejects transparency
        full_icon(px).convert("RGB").save(f)


def splash_logo(f: float) -> Image.Image:
    """The hat over the wordmark, laid out exactly like the app's first
    Flutter frame (BrandSplash in lib/core/brand.dart: a 132 mark, a 12 gap,
    then "FieldOS" at 30 with a 1.1 line height), so nothing jumps when the
    app takes over from the native splash. f is pixels per dp."""
    w_dp, mark_dp, gap_dp, line_dp, font_dp = 160, 132, 12, 33, 30
    img = Image.new("RGBA", (round(w_dp * f), round((mark_dp + gap_dp + line_dp) * f)), (0, 0, 0, 0))
    mark = hard_hat(round(mark_dp * f), 0.72)
    img.alpha_composite(mark, (round((w_dp - mark_dp) / 2 * f), 0))
    font = ImageFont.truetype(str(SPLASH_FONT), round(font_dp * f))
    d = ImageDraw.Draw(img)
    word = [(c, WHITE) for c in "Field"] + [(c, AMBER) for c in "OS"]
    spacing = -0.5 * f  # the wordmark's letter spacing
    width = sum(font.getlength(c) for c, _ in word) + spacing * (len(word) - 1)
    x = (img.width - width) / 2
    # Inter's ascent share of a 1.1 line: 1.1 * 0.96875 / (0.96875 + 0.2412)
    baseline = (mark_dp + gap_dp + line_dp * 0.8807) * f
    for c, colour in word:
        d.text((x, baseline), c, font=font, fill=colour, anchor="ls")
        x += font.getlength(c) + spacing
    return img


def splash():
    """Native launch screens: navy with the hat and wordmark, shown until
    Flutter draws its first frame. Android 12+ draws its own splash from the
    launcher icon; values-v31 only sets its background to the same navy."""
    navy_hex = f"#{NAVY[0]:02X}{NAVY[1]:02X}{NAVY[2]:02X}"
    for density, f in {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}.items():
        out = RES / f"drawable-{density}"
        out.mkdir(parents=True, exist_ok=True)
        splash_logo(f).save(out / "splash_logo.png", optimize=True)
    (RES / "values/splash.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
        f'    <color name="splash_background">{navy_hex}</color>\n'
        "</resources>\n"
    )
    layers = (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        "<!-- Written by tools/make_icons.py. The launch screen up to Android 11:\n"
        "     navy with the hat and wordmark, like the app's first frame. -->\n"
        '<layer-list xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <item android:drawable="@color/splash_background" />\n'
        "    <item>\n"
        '        <bitmap android:gravity="center" android:src="@drawable/splash_logo" />\n'
        "    </item>\n"
        "</layer-list>\n"
    )
    for folder in ("drawable", "drawable-v21"):
        (RES / folder / "launch_background.xml").write_text(layers)
    for folder, parent in (("values-v31", "Theme.Light.NoTitleBar"), ("values-night-v31", "Theme.Black.NoTitleBar")):
        (RES / folder).mkdir(exist_ok=True)
        (RES / folder / "styles.xml").write_text(
            '<?xml version="1.0" encoding="utf-8"?>\n'
            "<!-- Written by tools/make_icons.py. Android 12+ shows its own splash\n"
            "     (the launcher icon, centred); this makes its background navy. -->\n"
            "<resources>\n"
            f'    <style name="LaunchTheme" parent="@android:style/{parent}">\n'
            '        <item name="android:windowBackground">@drawable/launch_background</item>\n'
            '        <item name="android:windowSplashScreenBackground">@color/splash_background</item>\n'
            "    </style>\n"
            "</resources>\n"
        )
    for f in (1, 2, 3):
        suffix = "" if f == 1 else f"@{f}x"
        splash_logo(f).save(IOS_LAUNCH / f"LaunchImage{suffix}.png", optimize=True)
    board = IOS_LAUNCH.parent.parent / "Base.lproj/LaunchScreen.storyboard"
    text = board.read_text()
    r, g, b = (round(c / 255, 4) for c in NAVY)
    text = re.sub(
        r'<color key="backgroundColor" red="[0-9.]+" green="[0-9.]+" blue="[0-9.]+" alpha="1"',
        f'<color key="backgroundColor" red="{r}" green="{g}" blue="{b}" alpha="1"',
        text,
    )
    logo = splash_logo(1)
    text = re.sub(r'<image name="LaunchImage" width="\d+" height="\d+"/>',
                  f'<image name="LaunchImage" width="{logo.width}" height="{logo.height}"/>', text)
    board.write_text(text)


def store():
    STORE.mkdir(parents=True, exist_ok=True)
    full_icon(512).convert("RGB").save(STORE / "play-icon-512.png")
    w, h = 1024, 500
    g = Image.new("RGB", (w, h), NAVY)
    g.paste(full_icon(300, rounded=True), (70, 100), full_icon(300, rounded=True))
    d = ImageDraw.Draw(g)
    d.text((420, 150), "FieldOS", font=ImageFont.truetype(FONT_BOLD, 104), fill=WHITE)
    d.text((424, 285), "Site diary & DPR for builders", font=ImageFont.truetype(FONT_MEDIUM, 36), fill=AMBER)
    d.text((424, 335), "Works offline. Speaks Telugu & Hindi.", font=ImageFont.truetype(FONT_MEDIUM, 30), fill=(200, 212, 228))
    g.save(STORE / "play-feature-graphic-1024x500.png")


if __name__ == "__main__":
    android()
    ios()
    splash()
    store()
    print("icons written")
