"""Writes scene.rml: Mitra, FieldOS's site-buddy mascot, as a Rive scene.

Mitra ("friend" in Hindi and Telugu) is a young site engineer: amber hard
hat, hi-vis vest, a pencil in the pocket and a tape measure on the belt.
Each mood is a looping animation; a view model number `mood` picks one
(the order of MOODS below):

     0 idle      1 wave      2 talk       3 think     4 celebrate
     5 thumbsUp  6 listen    7 sleep      8 oops      9 worried
    10 surprised 11 point   12 measure   13 hammer   14 money
    15 checklist 16 chai

A second state machine layer blinks on its own, whatever the mood.

Every mood keys every animated property (unchanged ones at the rest pose):
Rive holds a property at its last value when the new state's timeline
doesn't key it, so without that a raised arm would stay raised.

    python3 make_scene.py && rive . --verify       # build + check
    python3 render_frames.py                       # the app's animations
"""
from __future__ import annotations

import math
import os
from pathlib import Path

PI = math.pi

# The brand's navy and safety amber, warm skin, and the props.
NAVY, NAVY_DEEP, NAVY_LIGHT = "FF112A4A", "FF0B1D35", "FF2B4A73"
AMBER, AMBER_DARK, AMBER_LIGHT = "FFF5A524", "FFD6860E", "FFFFC95C"
SKIN, SKIN_LIGHT, SKIN_DARK = "FFE7A67C", "FFF6C39C", "FFC98761"
HAIR = "FF2B1B14"
WHITE, SILVER_DARK = "FFFFFFFF", "FFB9C6D4"
IRIS, IRIS_LIGHT = "FF4A2C1E", "FF7A4A2E"
MOUTH, TONGUE = "FF5E1A22", "FFE86A6A"
BOOT, BOOT_LIGHT = "FF5B3A29", "FF7E5440"
TROUSER = "FF34405A"
BROW = "FF3B2416"
BLUSH = "88FF8A80"
SHADOW = "40112A4A"
CHAI, GLASS = "FFC07A3A", "AAFFFFFF"
GREEN, RED, BLUE = "FF1E8E5A", "FFE0573C", "FF3D8BFD"
STEEL, WOOD = "FF8FA3B8", "FFB0753C"

_next = [10]


def nid() -> str:
    _next[0] += 1
    return f"0:{_next[0]}"


# --- markup helpers ---------------------------------------------------------

def attrs(**kw) -> str:
    out = []
    for k, v in kw.items():
        if v is None:
            continue
        if isinstance(v, bool):
            v = "true" if v else "false"
        out.append(f'{k}="{v}"')
    return " ".join(out)


def solid(c: str, name: str = "Fill") -> str:
    return f'<Fill name="{name}"><SolidColor colorValue="{c}" name="C"/></Fill>'


def lin(x1, y1, x2, y2, stops) -> str:
    s = "".join(f'<GradientStop colorValue="{c}" position="{p}"/>' for p, c in stops)
    return (f'<Fill name="Fill"><LinearGradient startX="{x1}" startY="{y1}" endX="{x2}" endY="{y2}" name="G">'
            f"{s}</LinearGradient></Fill>")


def rad(cx, cy, r, stops) -> str:
    s = "".join(f'<GradientStop colorValue="{c}" position="{p}"/>' for p, c in stops)
    return (f'<Fill name="Fill"><RadialGradient startX="{cx}" startY="{cy}" endX="{cx + r}" endY="{cy}" name="G">'
            f"{s}</RadialGradient></Fill>")


def shade(c: str, strength: float, ox: float, oy: float) -> str:
    """An inner shadow: the colour gathers on the edge away from (ox, oy)."""
    return (f'<Fill fillRule="clockwise" name="Shade"><SolidColor colorValue="{c}" name="C"/>'
            f'<Feather strength="{strength}" inner="true" offsetX="{ox}" offsetY="{oy}" name="F"/></Fill>')


def line(c: str, w: float) -> str:
    return (f'<Stroke thickness="{w}" cap="round" join="round" name="Stroke">'
            f'<SolidColor colorValue="{c}" name="C"/></Stroke>')


def E(w, h) -> str:
    return f'<Ellipse width="{w}" height="{h}" name="Path"/>'


def R(w, h, r=0, ox=0.5, oy=0.5, corners: tuple | None = None) -> str:
    if corners:
        tl, tr, br, bl = corners
        return (f'<Rectangle {attrs(width=w, height=h, originX=ox, originY=oy, linkCornerRadius=False)} '
                f'cornerRadiusTL="{tl}" cornerRadiusTR="{tr}" cornerRadiusBR="{br}" cornerRadiusBL="{bl}" name="Path"/>')
    return f'<Rectangle {attrs(width=w, height=h, cornerRadiusTL=r, originX=ox, originY=oy)} name="Path"/>'


def P(verts: list[str], closed=True) -> str:
    return f'<PointsPath {attrs(isClosed=closed, isClockwise=True)} name="Path">{"".join(verts)}</PointsPath>'


def sv(x, y, r=None) -> str:
    return f"<StraightVertex {attrs(x=x, y=y, radius=r)}/>"


def cv(x, y, rot, dist) -> str:
    return f'<CubicMirroredVertex x="{x}" y="{y}" rotation="{rot}" distance="{dist}"/>'


def dv(x, y, inr, ind, outr, outd) -> str:
    return (f'<CubicDetachedVertex x="{x}" y="{y}" inRotation="{inr}" inDistance="{ind}" '
            f'outRotation="{outr}" outDistance="{outd}"/>')


def shape(name, geom, paints, x=0, y=0, sid=None, rot=None, op=None) -> str:
    i = f' id="{sid}"' if sid else ""
    return f'<Shape {attrs(x=x, y=y, rotation=rot, opacity=op)} name="{name}"{i}>{geom}{paints}</Shape>'


def clip_to(geom: str) -> str:
    """Clips everything in the enclosing node to `geom` (drawn nowhere)."""
    cid = nid()
    return f'<Shape name="Clip Shape" id="{cid}">{geom}</Shape><ClippingShape sourceId="{cid}" name="Clip"/>'


def node(name, children, x=0, y=0, sid=None, rot=None, op=None, sx=None, sy=None) -> str:
    a = attrs(x=x, y=y, rotation=rot, opacity=op, scaleX=sx, scaleY=sy)
    i = f' id="{sid}"' if sid else ""
    return f'<Node {a} name="{name}"{i}>{"".join(children)}</Node>'


# Animated nodes: key -> rest pose of the properties the moods key.
REST: dict[str, dict[str, float]] = {}
IDS: dict[str, str] = {}


def anim(key: str, name: str, children: list[str], x=0.0, y=0.0, keyed=(), **rest: float) -> str:
    """A node the moods animate: `rest` (plus x/y named in `keyed`) are keyed."""
    sid = nid()
    IDS[key] = sid
    pose = dict(rest)
    if "x" in keyed:
        pose["x"] = x
    if "y" in keyed:
        pose["y"] = y
    REST[key] = pose
    return node(name, children, x=x, y=y, sid=sid, rot=rest.get("rotation"), op=rest.get("opacity"),
                sx=rest.get("scaleX"), sy=rest.get("scaleY"))


# --- the character ----------------------------------------------------------

def eye(side: int) -> str:
    k = "l" if side < 0 else "r"
    return node(f"Eye {k.upper()}", [
        anim(f"lid_{k}", f"Lid {k.upper()}", [
            shape("Lash", R(40, 4, 2), solid(BROW), y=-1),
            shape("Lid", R(44, 46, 0, oy=1), lin(0, -46, 0, 0, [(0, "FFF2BB93"), (1, "FFEDB289")])),
        ], y=-22, keyed=("y",)),
        anim(f"look_{k}", f"Look {k.upper()}", [
            shape("Glint S", E(4, 4), solid(WHITE), x=-6, y=6),
            shape("Glint", E(8, 8), solid(WHITE), x=5, y=-6),
            shape("Pupil", E(11, 12), solid("FF120A06")),
            shape("Iris", E(21, 23), rad(-3, -4, 14, [(0, IRIS_LIGHT), (1, IRIS)])),
        ], keyed=("x", "y")),
        shape("Sclera", E(34, 40), rad(-4, -8, 26, [(0, WHITE), (0.75, WHITE), (1, "FFE4E9F0")])),
        clip_to(E(34, 40)),
    ], x=side * 33)


GRIN = [sv(-20, -2, 4), sv(20, -2, 4), cv(0, 18, PI, 14)]
TICK = [sv(-6, 0), sv(-2, 4), sv(6, -5)]


def mouths() -> str:
    return node("Mouth", [
        anim("m_smile", "Smile", [shape("Smile", P([sv(-16, 0), cv(0, 9, PI, 10), sv(16, 0)], closed=False),
                                        line(MOUTH, 5))], opacity=1.0),
        anim("m_grin", "Grin", [
            shape("Tongue", E(20, 10), solid(TONGUE), y=12),
            shape("Teeth", R(30, 7, 3), solid(WHITE), y=1),
            shape("Inside", P(GRIN), solid(MOUTH)),
            clip_to(P(GRIN)),
        ], opacity=0.0),
        anim("m_o", "O", [
            shape("Tongue", E(12, 6), solid(TONGUE), y=6),
            shape("Open", E(18, 22), solid(MOUTH)),
        ], y=4, keyed=("y",), opacity=0.0, scaleY=1.0),
        anim("m_frown", "Frown", [shape("Frown", P([sv(-14, 8), cv(0, 0, 0, 9), sv(14, 8)], closed=False),
                                        line(MOUTH, 5))], opacity=0.0),
        anim("m_wavy", "Wavy", [shape("Wavy", P([sv(-16, 4), cv(-8, 0, 0, 4), cv(0, 5, 0, 4), cv(8, 0, 0, 4),
                                                 sv(16, 4)], closed=False), line(MOUTH, 4))], opacity=0.0),
        anim("m_flat", "Flat", [shape("Flat", P([sv(-10, 3), sv(10, 1)], closed=False), line(MOUTH, 5))],
             opacity=0.0),
        anim("m_tongue", "Tongue Out", [shape("Tip", E(10, 12), solid(TONGUE), x=12, y=8)], opacity=0.0),
    ], y=-26)


def hat() -> str:
    dome = P([dv(-86, 0, 0, 0, -PI / 2, 46), cv(0, -84, 0, 48), dv(86, 0, -PI / 2, 46, 0, 0)])
    return anim("hat", "Hat", [
        shape("Shine", E(36, 16), solid("66FFFFFF"), x=-36, y=-62, rot=-0.55),
        shape("Badge", R(30, 7, 3.5), solid(WHITE), y=-28),
        shape("Ridge", R(22, 78, 11), lin(0, -40, 0, 40, [(0, AMBER_LIGHT), (1, AMBER_DARK)]), y=-42),
        shape("Band", R(170, 10), solid(AMBER_DARK), y=-7),
        shape("Dome", dome, lin(0, -84, 0, 0, [(0, AMBER_LIGHT), (0.55, AMBER), (1, AMBER_DARK)])
              + shade("55B86A00", 10, -8, -10)),
        shape("Brim", R(206, 20, 10), lin(0, -10, 0, 10, [(0, AMBER_LIGHT), (1, AMBER_DARK)])),
        shape("Brim Shadow", E(170, 16), solid("33000000"), y=12),
    ], y=-108, keyed=("y",), rotation=0.0)


def head_fx() -> list[str]:
    def z(k, x, y, s):
        return anim(k, f"Z {k}", [shape("Z", P([sv(-s, -s), sv(s, -s), sv(-s, s), sv(s, s)], closed=False),
                                        line(NAVY_LIGHT, 4))], x=x, y=y, keyed=("y",), opacity=0.0)

    def wave(k, r):
        a = 0.9
        arc = P([sv(round(r * math.cos(-a), 2), round(r * math.sin(-a), 2)), cv(r, 0, PI / 2, round(r * 0.55, 2)),
                 sv(round(r * math.cos(a), 2), round(r * math.sin(a), 2))], closed=False)
        return anim(k, f"Wave {k}", [shape("Arc", arc, line(AMBER_DARK, 4))], opacity=0.0)

    bulb = node("Bulb", [
        anim("bulb_glow", "Glow", [shape("Glow", E(34, 34), solid("66FFE066"))], opacity=0.0),
        shape("Base", R(10, 8, 2), solid(STEEL), y=11),
        shape("Glass", E(18, 18), rad(-3, -3, 12, [(0, "FFFFF6C0"), (1, AMBER_LIGHT)])),
    ], y=-2)
    outline = "33112A4A"
    return [
        anim("fx_thought", "Thought", [
            bulb,
            shape("Cloud", E(60, 46), solid(WHITE) + line(outline, 2.5)),
            shape("Dot 2", E(16, 16), solid(WHITE) + line(outline, 2), x=-30, y=36),
            shape("Dot 1", E(9, 9), solid(WHITE) + line(outline, 2), x=-44, y=52),
        ], x=104, y=-168, opacity=0.0),
        anim("fx_bang", "Bang", [
            shape("Dot", E(10, 10), solid(RED), y=18),
            shape("Bar", R(10, 28, 5), solid(RED), y=-6),
        ], x=98, y=-160, opacity=0.0, scaleX=0.4, scaleY=0.4),
        anim("fx_sweat", "Sweat", [
            shape("Drop", P([sv(0, -12), cv(7, 4, PI / 2, 5), cv(0, 10, PI, 4), cv(-7, 4, -PI / 2, 5)]),
                  solid("FF9CD3F5") + line("FF5AA9DB", 1.5)),
        ], x=80, y=-110, keyed=("y",), opacity=0.0),
        node("Zzz", [z("z1", 0, 0, 6), z("z2", 18, -26, 8), z("z3", 40, -56, 10)], x=100, y=-136),
        node("Waves", [wave("w1", 14), wave("w2", 26)], x=112, y=-58),
    ]


def face() -> str:
    def brow(k, x):
        return anim(f"brow_{k}", f"Brow {k.upper()}", [shape("Brow", R(26, 7, 3.5), solid(BROW))],
                    x=x, y=-98, keyed=("y",), rotation=0.0)

    happy_arc = P([sv(-13, 5), cv(0, -6, 0, 8), sv(13, 5)], closed=False)
    return node("Face", [
        # The brows' keyed y values are from the old hat line; this lifts
        # them all out from under the brim at once.
        node("Brows", [brow("l", -33), brow("r", 33)], y=7),
        anim("eyes_blink", "Eyes Blink", [
            anim("eyes_big", "Eyes Big", [
                anim("eyes_open", "Eyes Open", [eye(-1), eye(1)], opacity=1.0),
                anim("eyes_happy", "Eyes Happy", [
                    shape("Arc L", happy_arc, line(BROW, 5), x=-33),
                    shape("Arc R", happy_arc, line(BROW, 5), x=33),
                ], opacity=0.0),
            ], scaleX=1.0, scaleY=1.0),
        ], y=-66, scaleY=1.0),
        mouths(),
        shape("Nose", E(16, 11), rad(-3, -3, 10, [(0, SKIN_LIGHT), (1, SKIN_DARK)]), y=-46),
        anim("blush", "Blush", [
            shape("Cheek L", E(26, 15), rad(0, 0, 13, [(0, BLUSH), (1, "00FF8A80")]), x=-54),
            shape("Cheek R", E(26, 15), rad(0, 0, 13, [(0, BLUSH), (1, "00FF8A80")]), x=54),
        ], y=-36, opacity=0.7),
    ])


def head() -> str:
    return anim("head", "Head", [
        *head_fx(),
        hat(),
        face(),
        shape("Hair L", E(30, 26), solid(HAIR), x=-74, y=-104, rot=0.4),
        shape("Hair R", E(30, 26), solid(HAIR), x=74, y=-104, rot=-0.4),
        shape("Ear L", E(22, 30), solid(SKIN_DARK), x=-86, y=-58),
        shape("Ear R", E(22, 30), solid(SKIN_DARK), x=86, y=-58),
        shape("Skin", E(172, 160), rad(-28, -34, 120, [(0, SKIN_LIGHT), (0.6, SKIN), (1, SKIN_DARK)])
              + shade("66B3714C", 16, -10, -14), y=-62),
        shape("Neck", R(34, 26, 10), solid(SKIN_DARK), y=6),
    ], y=-88, keyed=("y",), rotation=0.0)


def hand_props_r() -> list[str]:
    hammer = node("Hammer", [
        shape("Head", R(34, 14, 3), lin(0, -7, 0, 7, [(0, "FFB8C6D4"), (1, STEEL)]), x=4, y=-30),
        shape("Handle", R(8, 46, 4), lin(-4, 0, 4, 0, [(0, "FFD08A4A"), (1, WOOD)]), y=-6),
    ])
    chai = node("Chai", [
        shape("Rim", R(24, 3, 1.5), solid("CCFFFFFF"), y=-14),
        shape("Tea", P([sv(-11, -10), sv(11, -10), sv(8, 12, 2), sv(-8, 12, 2)]),
              lin(0, -10, 0, 12, [(0, "FFD8954E"), (1, CHAI)])),
        shape("Glass", P([sv(-12, -15), sv(12, -15), sv(9, 14, 3), sv(-9, 14, 3)]),
              solid(GLASS) + line("99B9C6D4", 1.5)),
    ], y=-14)
    pencil = node("Pencil", [
        shape("Tip", P([sv(-3, 0), sv(3, 0), sv(0, 8)]), solid(BROW), y=16),
        shape("Body", R(6, 30, 1), solid(AMBER_LIGHT), y=2),
    ], rot=0.5)
    tape = node("Tape Case", [
        shape("Hub", E(10, 10), solid(NAVY_DEEP)),
        shape("Case", R(28, 26, 7), lin(0, -13, 0, 13, [(0, AMBER_LIGHT), (1, AMBER_DARK)])),
    ], x=-4)
    return [
        anim("p_hammer", "Hammer", [hammer], opacity=0.0),
        anim("p_chai", "Chai", [chai], opacity=0.0),
        anim("p_thumb", "Thumb", [shape("Thumb", R(13, 26, 6.5), solid(SKIN) + line(SKIN_DARK, 1.5), x=3, y=-16)], opacity=0.0),
        anim("p_point", "Point", [shape("Finger", R(26, 10, 5, ox=0), solid(SKIN), x=4, y=-2)], opacity=0.0),
        anim("p_pencil", "Pencil", [pencil], opacity=0.0),
        anim("p_tape", "Tape Case", [tape], opacity=0.0),
    ]


def clipboard() -> str:
    return anim("p_clipboard", "Clipboard", [
        node("Board", [
            anim("t3", "Tick 3", [shape("T", P(TICK, closed=False), line(GREEN, 3))], y=12, opacity=0.0),
            anim("t2", "Tick 2", [shape("T", P(TICK, closed=False), line(GREEN, 3))], opacity=0.0),
            anim("t1", "Tick 1", [shape("T", P(TICK, closed=False), line(GREEN, 3))], y=-12, opacity=0.0),
            shape("Line 3", P([sv(4, 12), sv(14, 12)], closed=False), line("33112A4A", 2)),
            shape("Line 2", P([sv(4, 0), sv(14, 0)], closed=False), line("33112A4A", 2)),
            shape("Line 1", P([sv(4, -12), sv(14, -12)], closed=False), line("33112A4A", 2)),
            shape("Clip", R(16, 7, 2), solid(STEEL), y=-24),
            shape("Paper", R(40, 46, 3), solid(WHITE), y=2),
            shape("Board", R(46, 56, 5), solid(WOOD)),
        ], x=18, y=-6, rot=0.6),
    ], opacity=0.0)


def arm(side: int) -> str:
    k = "r" if side > 0 else "l"
    props = hand_props_r() if side > 0 else [clipboard()]
    hand = anim(f"hand_{k}", f"Hand {k.upper()}", [
        *props,
        shape("Mitt", E(28, 28), rad(-4, -5, 18, [(0, SKIN_LIGHT), (1, SKIN)])),
    ], y=54, rotation=0.0)
    return anim(f"arm_{k}", f"Arm {k.upper()}", [
        hand,
        shape("Cuff", R(30, 8, 4), solid(NAVY_DEEP), y=40),
        shape("Sleeve", R(30, 52, 15, oy=0.1), lin(-15, 0, 15, 0, [(0, NAVY_LIGHT), (1, NAVY)])),
    ], x=side * 60, y=-74, rotation=round(-0.28 * side, 2))


def rupee() -> list[str]:
    # The ₹ sign drawn as strokes (no font needed).
    c = AMBER_DARK
    return [
        shape("R Top", P([sv(-7, -9), sv(7, -9)], closed=False), line(c, 3)),
        shape("R Mid", P([sv(-7, -3), sv(7, -3)], closed=False), line(c, 3)),
        shape("R Bowl", P([sv(-7, -9), cv(1, -5, PI / 2, 4), sv(-6, 0), sv(6, 10)], closed=False), line(c, 3)),
    ]


def torso() -> str:
    ticks = ('<Stroke thickness="9" name="Ticks"><SolidColor colorValue="66112A4A" name="C"/>'
             '<DashPath name="D"><Dash length="1.5" name="On"/><Dash length="8" name="Off"/></DashPath></Stroke>')
    tape = anim("tape", "Tape", [shape("Tape", R(222, 9, 1, ox=1), solid(AMBER_LIGHT) + ticks)],
                x=100, y=-60, opacity=0.0, scaleX=0.2)
    coin = anim("fx_coin", "Coin", [
        *rupee(),
        shape("Coin", E(36, 36), rad(-6, -6, 24, [(0, "FFFFE9A8"), (0.7, AMBER), (1, AMBER_DARK)])),
    ], x=104, y=-150, keyed=("y",), opacity=0.0, scaleX=1.0)
    impact = anim("fx_impact", "Impact", [
        shape("Spark", '<Star width="40" height="40" points="6" innerRadius="0.35" cornerRadius="1" name="Path"/>',
              solid(AMBER_LIGHT)),
    ], x=118, y=6, opacity=0.0, scaleX=0.5, scaleY=0.5)
    stripe = lin(0, -4, 0, 4, [(0, WHITE), (1, SILVER_DARK)])
    return anim("torso", "Torso", [
        coin, impact, tape,
        arm(1), arm(-1),
        head(),
        shape("Belt Tape", R(16, 14, 4), solid(AMBER_DARK), x=42, y=-4),
        shape("Belt", R(118, 8, 3), solid(NAVY_DEEP), y=-2),
        shape("Pencil", R(5, 22, 1), solid(AMBER_LIGHT), x=-30, y=-56),
        shape("Pocket", R(26, 16, 4), solid(AMBER_DARK), x=-30, y=-44),
        shape("Stripe 2", R(116, 8), stripe, y=-18),
        shape("Stripe 1", R(116, 8), stripe, y=-38),
        shape("Zip", R(4, 76), solid(AMBER_DARK), y=-36),
        shape("Vest", R(116, 78, corners=(14, 14, 18, 18)),
              lin(0, -39, 0, 39, [(0, AMBER_LIGHT), (1, AMBER)]) + shade("44B86A00", 8, -6, -6), y=-36),
        shape("Collar", P([sv(-24, 0), sv(0, 18), sv(24, 0)]), solid(NAVY_DEEP), y=-84),
        shape("Shirt", R(126, 96, 38), lin(0, -48, 0, 48, [(0, NAVY_LIGHT), (1, NAVY)]), y=-42),
    ], rotation=0.0)


def legs() -> str:
    def leg(side):
        return node(f"Leg {side}", [
            shape("Toe", E(24, 12), solid(BOOT_LIGHT), x=side * 14, y=52),
            shape("Boot", R(46, 24, corners=(10, 10, 6, 6)), lin(0, -12, 0, 12, [(0, BOOT_LIGHT), (1, BOOT)]),
                  x=side * 4, y=50),
            shape("Trouser", R(34, 48, 8), solid(TROUSER), y=20),
        ], x=side * 24)
    return node("Legs", [leg(-1), leg(1)])


def confetti() -> str:
    bits = [(-150, -10, AMBER, 0.4), (-110, 30, BLUE, -0.6), (-60, -30, GREEN, 0.9), (60, -40, RED, -0.3),
            (110, 10, AMBER, 0.7), (150, -20, BLUE, -0.9), (-130, 70, RED, 0.2), (130, 60, GREEN, -0.5),
            (-30, -60, BLUE, 0.3), (30, -10, AMBER, -0.7)]
    return anim("fx_confetti", "Confetti", [
        shape(f"Bit {i}", R(10, 5, 1), solid(c), x=x, y=y, rot=r) for i, (x, y, c, r) in enumerate(bits)
    ], x=200, y=70, keyed=("y",), opacity=0.0, rotation=0.0)


def sparkles() -> str:
    def star(x, y, s):
        return shape("Spark", f'<Star width="{s}" height="{s}" points="4" innerRadius="0.36" cornerRadius="1" '
                              f'name="Path"/>', solid(AMBER), x=x, y=y)
    return anim("fx_sparkles", "Sparkles", [star(-150, -40, 30), star(150, -70, 24), star(156, 40, 18),
                                             star(-146, 60, 18)],
                x=200, y=170, opacity=0.0, scaleX=0.6, scaleY=0.6)


def scene_tree() -> str:
    rig = anim("rig", "Rig", [torso(), legs()], x=200, y=316, keyed=("x", "y"), scaleX=1.0, scaleY=1.0)
    shadow = anim("shadow", "Shadow", [shape("Shadow", E(170, 20), solid(SHADOW))], x=200, y=378,
                  scaleX=1.0, opacity=1.0)
    return confetti() + sparkles() + rig + shadow


# --- motion -----------------------------------------------------------------

EASE = '<CubicEaseInterpolator x1="0.42" y1="0" x2="0.58" y2="1"/>'
EASE_OUT = '<CubicEaseInterpolator x1="0.15" y1="0.6" x2="0.35" y2="1"/>'


def track(prop: str, keys: list[tuple]) -> str:
    out = []
    for i, k in enumerate(keys):
        f, v = k[0], k[1]
        kind = k[2] if len(k) > 2 else "ease"
        if i == len(keys) - 1 or kind == "linear":
            out.append(f'<KeyFrameDouble value="{v:.4f}" frame="{f}" interpolationType="linear"/>')
        elif kind == "hold":
            out.append(f'<KeyFrameDouble value="{v:.4f}" frame="{f}" interpolationType="hold"/>')
        else:
            curve = EASE_OUT if kind == "out" else EASE
            out.append(f'<KeyFrameDouble value="{v:.4f}" frame="{f}" interpolationType="cubic">{curve}</KeyFrameDouble>')
    return f'<KeyedProperty property="{prop}">{"".join(out)}</KeyedProperty>'


def animation(name: str, aid: str, d: int, motion: dict) -> str:
    unknown = set(motion) - set(REST)
    assert not unknown, f"{name}: unknown nodes {unknown}"
    objs = []
    for key, props in REST.items():
        if key == "eyes_blink":
            continue  # the blink layer owns it
        bad = set(motion.get(key, {})) - set(props)
        assert not bad, f"{name}: {key} doesn't key {bad}"
        tracks = []
        for prop, rest in props.items():
            keys = motion.get(key, {}).get(prop)
            if keys is None:
                keys = [(0, rest), (d, rest)]
            elif isinstance(keys, (int, float)):
                keys = [(0, keys), (d, keys)]
            tracks.append(track(prop, keys))
        objs.append(f'<KeyedObject objectId="{IDS[key]}">{"".join(tracks)}</KeyedObject>')
    return (f'<LinearAnimation loopValue="loop" duration="{d}" name="{name}" id="{aid}">'
            f'{"".join(objs)}</LinearAnimation>')


def osc(d: int, a: float, b: float, n: int = 1) -> list[tuple]:
    """a -> b -> a, n times over d frames."""
    step = d / (2 * n)
    return [(round(i * step), a if i % 2 == 0 else b) for i in range(2 * n + 1)]


def rigy(d: int, depth: float, n: int = 1) -> list[tuple]:
    return osc(d, 316, 316 - depth, n)


def mouth(which: str) -> dict:
    out = {m: {"opacity": 0.0} for m in ("m_smile", "m_grin", "m_o", "m_frown", "m_wavy", "m_flat")}
    out[which] = {"opacity": 1.0}
    return out


def merge(*parts: dict) -> dict:
    out: dict = {}
    for p in parts:
        for k, v in p.items():
            out.setdefault(k, {}).update(v)
    return out


def brows(l_rot=0.0, r_rot=0.0, y=-98.0, ry=None) -> dict:
    return {"brow_l": {"rotation": l_rot, "y": y}, "brow_r": {"rotation": r_rot, "y": ry if ry is not None else y}}


def look(x: float, y: float) -> dict:
    return {"look_l": {"x": x, "y": y}, "look_r": {"x": x, "y": y}}


def lids(y: float) -> dict:
    return {"lid_l": {"y": y}, "lid_r": {"y": y}}


GLANCE = [(0, 0), (50, 0, "hold"), (60, 5), (110, 5, "hold"), (120, -5), (180, -5, "hold"), (190, 0), (240, 0)]

MOODS: list[tuple[str, int, dict]] = [
    ("idle", 240, merge(mouth("m_smile"), {
        "rig": {"y": rigy(240, 3, 2), "scaleY": osc(240, 1.0, 1.015, 2)},
        "head": {"rotation": [(0, 0.0), (60, 0.04), (120, 0.0), (180, -0.03), (240, 0.0)]},
        "arm_r": {"rotation": osc(240, -0.28, -0.22, 2)},
        "arm_l": {"rotation": osc(240, 0.28, 0.22, 2)},
        "look_l": {"x": GLANCE}, "look_r": {"x": GLANCE},
    })),
    ("wave", 72, merge(mouth("m_grin"), brows(y=-102), {
        "rig": {"y": rigy(72, 4, 2)},
        "arm_r": {"rotation": osc(72, -2.45, -2.95, 3)},
        "hand_r": {"rotation": osc(72, 0.1, -0.25, 3)},
        "head": {"rotation": osc(72, 0.08, 0.12)},
        "hat": {"rotation": osc(72, 0.0, 0.04)},
        "blush": {"opacity": 1.0},
    })),
    ("talk", 48, merge(mouth("m_o"), {
        "m_grin": {"opacity": [(0, 0), (11, 0, "hold"), (12, 1), (23, 1, "hold"), (24, 0), (36, 0, "hold"),
                               (37, 1), (47, 1, "hold"), (48, 0)]},
        "m_o": {"opacity": [(0, 1), (11, 1, "hold"), (12, 0), (23, 0, "hold"), (24, 1), (36, 1, "hold"),
                            (37, 0), (47, 0, "hold"), (48, 1)],
                "scaleY": [(0, 0.5), (6, 1.1), (12, 0.6), (24, 0.5), (30, 0.9), (36, 0.5), (48, 0.5)]},
        "rig": {"y": rigy(48, 2, 2)},
        "arm_l": {"rotation": [(0, 0.28), (12, 0.75), (24, 0.5), (36, 0.8), (48, 0.28)]},
        "hand_l": {"rotation": osc(48, 0.0, -0.4, 2)},
        "head": {"rotation": osc(48, -0.03, 0.04, 2)},
        "brow_l": {"y": osc(48, -98, -102, 2)}, "brow_r": {"y": osc(48, -98, -102, 2)},
    })),
    ("think", 180, merge(mouth("m_flat"), look(4, -7), brows(0.15, -0.25, -100, -104), {
        "rig": {"y": rigy(180, 2)},
        "arm_r": {"rotation": 2.0},
        "hand_r": {"rotation": -0.4},
        "head": {"rotation": [(0, -0.08), (90, -0.13), (180, -0.08)]},
        "fx_thought": {"opacity": [(0, 0), (30, 1), (180, 1)]},
        "bulb_glow": {"opacity": [(0, 0), (100, 0, "hold"), (110, 1), (140, 0.6), (160, 1), (180, 0)]},
        "torso": {"rotation": -0.03},
    })),
    ("celebrate", 72, merge(mouth("m_grin"), brows(y=-104), {
        "eyes_open": {"opacity": 0.0}, "eyes_happy": {"opacity": 1.0},
        "rig": {"y": [(0, 316, "out"), (18, 282), (34, 316, "linear"), (40, 320), (50, 316), (72, 316)],
                "scaleY": [(0, 0.94), (10, 1.05), (34, 1.0), (40, 0.92), (52, 1.0), (72, 0.94)],
                "scaleX": [(0, 1.05), (10, 0.97), (34, 1.0), (40, 1.06), (52, 1.0), (72, 1.05)]},
        "hat": {"y": [(0, -108), (20, -118), (38, -104), (50, -108), (72, -108)],
                "rotation": [(0, 0), (20, -0.08), (40, 0.05), (72, 0)]},
        "arm_r": {"rotation": osc(72, -2.7, -3.0, 2)},
        "arm_l": {"rotation": osc(72, 2.7, 3.0, 2)},
        "shadow": {"scaleX": [(0, 1.05), (18, 0.75), (34, 1.0), (40, 1.08), (72, 1.05)],
                   "opacity": [(0, 1), (18, 0.6), (34, 1), (72, 1)]},
        "fx_confetti": {"opacity": [(0, 1), (60, 1), (72, 0)], "y": [(0, 40, "linear"), (72, 140)],
                        "rotation": [(0, 0, "linear"), (72, 0.3)]},
        "fx_sparkles": {"opacity": [(0, 1), (36, 0.5), (72, 1)], "scaleX": osc(72, 0.85, 1.1),
                        "scaleY": osc(72, 0.85, 1.1)},
        "blush": {"opacity": 1.0},
    })),
    ("thumbsUp", 72, merge(mouth("m_grin"), {
        "lid_l": {"y": [(0, -22), (20, -22, "hold"), (24, 22), (48, 22, "hold"), (52, -22), (72, -22)]},
        "brow_l": {"y": [(0, -98), (20, -98), (24, -92), (48, -92), (52, -98), (72, -98)]},
        "rig": {"y": rigy(72, 5)},
        "arm_r": {"rotation": osc(72, -2.15, -2.35)},
        "hand_r": {"rotation": 2.4},
        "p_thumb": {"opacity": 1.0},
        "head": {"rotation": osc(72, 0.06, 0.1)},
        "fx_sparkles": {"opacity": [(0, 0), (20, 0.9), (52, 0.9), (72, 0)], "scaleX": 0.7, "scaleY": 0.7},
        "blush": {"opacity": 1.0},
    })),
    ("listen", 120, merge(mouth("m_smile"), look(6, 0), brows(0, -0.15, -100, -104), {
        "rig": {"y": rigy(120, 2)},
        "arm_r": {"rotation": -2.79},
        "hand_r": {"rotation": -0.5},
        "head": {"rotation": osc(120, 0.12, 0.16)},
        "w1": {"opacity": [(0, 0), (20, 1), (60, 0), (80, 1), (120, 0)]},
        "w2": {"opacity": [(0, 0), (10, 0), (40, 1), (80, 0), (100, 1), (120, 0)]},
    })),
    ("sleep", 240, merge(mouth("m_o"), lids(22), brows(y=-94), {
        "m_o": {"opacity": 1.0, "scaleY": osc(240, 0.35, 0.55, 2)},
        "rig": {"y": osc(240, 318, 314, 2), "scaleY": osc(240, 0.99, 1.02, 2)},
        "head": {"rotation": osc(240, 0.16, 0.2, 2), "y": -86},
        "hat": {"rotation": 0.08, "y": -104},
        "arm_r": {"rotation": -0.12}, "arm_l": {"rotation": 0.12},
        "z1": {"opacity": [(0, 0), (20, 1), (80, 0), (240, 0)], "y": [(0, 10, "linear"), (80, -10), (240, -10)]},
        "z2": {"opacity": [(0, 0), (60, 0), (80, 1), (140, 0), (240, 0)],
               "y": [(0, -16, "linear"), (60, -16, "linear"), (140, -36), (240, -36)]},
        "z3": {"opacity": [(0, 0), (120, 0), (140, 1), (200, 0), (240, 0)],
               "y": [(0, -46, "linear"), (120, -46, "linear"), (200, -66), (240, -66)]},
        "shadow": {"scaleX": osc(240, 1.0, 0.97, 2)},
    })),
    ("oops", 120, merge(mouth("m_frown"), look(0, 5), brows(-0.3, 0.3, -100), lids(-8), {
        "rig": {"y": rigy(120, 2), "scaleY": 0.98},
        "head": {"rotation": osc(120, -0.08, -0.12), "y": -84},
        "hat": {"rotation": -0.1, "y": -104},
        "arm_r": {"rotation": -0.08}, "arm_l": {"rotation": 0.08},
        "torso": {"rotation": 0.02},
        "fx_sweat": {"opacity": [(0, 0), (20, 1), (100, 1), (120, 0)], "y": [(0, -116, "linear"), (120, -96)]},
        "blush": {"opacity": 0.3},
    })),
    ("worried", 60, merge(mouth("m_wavy"), brows(-0.32, 0.32, -102), {
        "rig": {"x": [(0, 200), (5, 202), (10, 198), (15, 202), (20, 200), (60, 200)], "y": rigy(60, 2)},
        "look_l": {"x": osc(60, -4, 4, 2)}, "look_r": {"x": osc(60, -4, 4, 2)},
        "eyes_big": {"scaleX": 1.08, "scaleY": 1.08},
        "arm_r": {"rotation": osc(60, -0.6, -0.75, 2)}, "arm_l": {"rotation": osc(60, 0.6, 0.75, 2)},
        "fx_sweat": {"opacity": 1.0, "y": osc(60, -114, -110, 2)},
    })),
    ("surprised", 72, merge(mouth("m_o"), brows(y=-110), {
        "m_o": {"opacity": 1.0, "scaleY": [(0, 0.6), (8, 1.25), (72, 1.15)]},
        "eyes_big": {"scaleX": [(0, 1.0), (8, 1.18), (72, 1.12)], "scaleY": [(0, 1.0), (8, 1.18), (72, 1.12)]},
        "rig": {"y": [(0, 316, "out"), (10, 300), (24, 316), (30, 318), (40, 316), (72, 316)]},
        "hat": {"y": [(0, -108, "out"), (8, -126), (26, -110), (34, -108), (72, -108)],
                "rotation": [(0, 0), (8, 0.1), (26, -0.03), (40, 0), (72, 0)]},
        "arm_r": {"rotation": [(0, -0.28), (10, -1.2), (72, -1.1)]},
        "arm_l": {"rotation": [(0, 0.28), (10, 1.2), (72, 1.1)]},
        "fx_bang": {"opacity": [(0, 0), (6, 1), (72, 1)],
                    "scaleX": [(0, 0.4, "out"), (10, 1.15), (18, 1.0), (72, 1.0)],
                    "scaleY": [(0, 0.4, "out"), (10, 1.15), (18, 1.0), (72, 1.0)]},
    })),
    ("point", 90, merge(mouth("m_grin"), look(7, -1), brows(0, 0, -101), {
        "rig": {"y": rigy(90, 3)},
        "arm_r": {"rotation": osc(90, -1.62, -1.78)},
        "hand_r": {"rotation": 1.55},
        "p_point": {"opacity": 1.0},
        "head": {"rotation": 0.07},
        "torso": {"rotation": 0.04},
    })),
    ("measure", 150, merge(mouth("m_flat"), brows(0.1, -0.1, -96), {
        "m_tongue": {"opacity": 1.0},
        "rig": {"y": rigy(150, 2)},
        "arm_r": {"rotation": [(0, -1.25), (60, -1.4), (90, -1.4), (150, -1.25)]},
        "arm_l": {"rotation": [(0, 0.9), (60, 1.38), (90, 1.38), (150, 0.9)]},
        "hand_r": {"rotation": 1.3},
        "p_tape": {"opacity": 1.0},
        "tape": {"opacity": 1.0, "scaleX": [(0, 0.15), (60, 1.0), (90, 1.0), (150, 0.15)]},
        "look_l": {"x": [(0, 5), (60, -6), (90, -6), (150, 5)], "y": 4},
        "look_r": {"x": [(0, 5), (60, -6), (90, -6), (150, 5)], "y": 4},
    })),
    ("hammer", 40, merge(mouth("m_flat"), lids(-6), brows(0.2, -0.2, -94), look(5, 6), {
        "rig": {"y": [(0, 316), (14, 316), (16, 319), (24, 316), (40, 316)]},
        "arm_r": {"rotation": [(0, -2.6), (12, -0.85, "linear"), (14, -0.75), (40, -2.6)]},
        "hand_r": {"rotation": 1.6},
        "p_hammer": {"opacity": 1.0},
        "head": {"rotation": [(0, 0.04), (14, 0.08), (40, 0.04)]},
        "fx_impact": {"opacity": [(0, 0), (13, 0, "hold"), (14, 1), (24, 0), (40, 0)],
                      "scaleX": [(0, 0.5), (14, 0.6), (22, 1.2), (40, 0.5)],
                      "scaleY": [(0, 0.5), (14, 0.6), (22, 1.2), (40, 0.5)]},
        "torso": {"rotation": [(0, -0.02), (14, 0.04), (40, -0.02)]},
    })),
    ("money", 90, merge(mouth("m_grin"), brows(y=-102), {
        "rig": {"y": rigy(90, 3)},
        "arm_r": {"rotation": [(0, -2.15), (12, -2.35), (30, -2.15), (90, -2.15)]},
        "fx_coin": {"opacity": 1.0,
                    "y": [(0, -150, "out"), (24, -214), (48, -150), (90, -150)],
                    "scaleX": [(0, 1.0, "linear"), (12, -1.0, "linear"), (24, 1.0, "linear"), (36, -1.0, "linear"),
                               (48, 1.0), (90, 1.0)]},
        "look_l": {"x": 4, "y": [(0, 0), (24, -9), (48, 0), (90, 0)]},
        "look_r": {"x": 4, "y": [(0, 0), (24, -9), (48, 0), (90, 0)]},
        "head": {"rotation": [(0, 0.04), (24, 0.0), (48, 0.06), (90, 0.04)]},
        "fx_sparkles": {"opacity": [(0, 0), (44, 0, "hold"), (48, 1), (80, 0), (90, 0)], "scaleX": 0.7,
                        "scaleY": 0.7},
    })),
    ("checklist", 150, merge(mouth("m_smile"), look(-4, 7), brows(0, 0, -97), {
        "rig": {"y": rigy(150, 2)},
        "arm_l": {"rotation": -0.62},
        "p_clipboard": {"opacity": 1.0},
        "arm_r": {"rotation": [(0, 0.55), (10, 0.75), (20, 0.55), (40, 0.55), (50, 0.75), (60, 0.55),
                               (80, 0.55), (90, 0.75), (100, 0.55), (150, 0.55)]},
        "hand_r": {"rotation": -0.6},
        "p_pencil": {"opacity": 1.0},
        "t1": {"opacity": [(0, 0), (16, 0, "hold"), (18, 1), (140, 1), (150, 0)]},
        "t2": {"opacity": [(0, 0), (56, 0, "hold"), (58, 1), (140, 1), (150, 0)]},
        "t3": {"opacity": [(0, 0), (96, 0, "hold"), (98, 1), (140, 1), (150, 0)]},
        "head": {"rotation": [(0, -0.05), (20, -0.02), (40, -0.05), (60, -0.02), (80, -0.05), (100, -0.02),
                              (150, -0.05)]},
    })),
    ("chai", 180, merge(mouth("m_smile"), {
        "eyes_open": {"opacity": [(0, 1), (40, 1, "hold"), (44, 0), (110, 0, "hold"), (114, 1), (180, 1)]},
        "eyes_happy": {"opacity": [(0, 0), (40, 0, "hold"), (44, 1), (110, 1, "hold"), (114, 0), (180, 0)]},
        "arm_r": {"rotation": [(0, 1.9), (40, 2.22), (110, 2.22), (150, 1.9), (180, 1.9)]},
        "hand_r": {"rotation": [(0, -1.9), (40, -2.1), (110, -2.1), (150, -1.9), (180, -1.9)]},
        "p_chai": {"opacity": 1.0},
        "head": {"rotation": [(0, 0.0), (40, -0.08), (110, -0.08), (150, 0.0), (180, 0.0)]},
        "blush": {"opacity": [(0, 0.7), (60, 1.0), (120, 1.0), (180, 0.7)]},
        "rig": {"y": rigy(180, 2)},
        "brow_l": {"y": -101}, "brow_r": {"y": -101},
    })),
]


def blink(aid: str) -> str:
    keys = [(0, 1.0), (180, 1.0), (185, 0.08), (191, 1.0), (300, 1.0), (305, 0.08), (310, 1.0), (315, 0.08),
            (321, 1.0), (360, 1.0)]
    return (f'<LinearAnimation loopValue="loop" duration="360" name="blink" id="{aid}">'
            f'<KeyedObject objectId="{IDS["eyes_blink"]}">{track("scaleY", keys)}</KeyedObject>'
            "</LinearAnimation>")


def _backdrop() -> str:
    # Only for render_frames.py's matting: the shipped scene is transparent.
    bg = os.environ.get("MITRA_BACKDROP")
    return solid(bg, "Backdrop") if bg else ""


def scene() -> str:
    tree = scene_tree()  # fills REST and IDS
    vm, vm_mood, vm_inst = nid(), nid(), nid()
    sm, mood_layer, blink_layer = nid(), nid(), nid()
    anim_ids = [nid() for _ in MOODS]
    state_ids = [nid() for _ in MOODS]
    blink_anim, blink_state = nid(), nid()

    def cond(n: int) -> str:
        return ('<TransitionViewModelCondition opValue="equal"><TransitionPropertyViewModelComparator>'
                f'<BindablePropertyNumber><DataBindContext sourcePathIds="{vm}-{vm_mood}" propertyKey="636"/>'
                f'</BindablePropertyNumber></TransitionPropertyViewModelComparator>'
                f'<TransitionValueNumberComparator value="{n}"/></TransitionViewModelCondition>')

    states = []
    for i, (sid, aid) in enumerate(zip(state_ids, anim_ids)):
        outs = "".join(f'<StateTransition stateToId="{state_ids[j]}" duration="200" enableEarlyExit="true">'
                       f"{cond(j)}</StateTransition>" for j in range(len(MOODS)) if j != i)
        states.append(f'<AnimationState x="{160 + (i % 6) * 180}" y="{(i // 6) * 160}" animationId="{aid}" '
                      f'id="{sid}">{outs}</AnimationState>')

    machine = "".join([
        f'<StateMachine name="Mitra" id="{sm}">',
        f'<StateMachineLayer name="Mood" id="{mood_layer}">',
        '<AnyState x="160" y="-160"/><ExitState x="520" y="-160"/>',
        f'<EntryState x="0" y="0"><StateTransition stateToId="{state_ids[0]}"/></EntryState>',
        "".join(states),
        "</StateMachineLayer>",
        f'<StateMachineLayer name="Blink" id="{blink_layer}">',
        '<AnyState x="160" y="-160"/><ExitState x="520" y="-160"/>',
        f'<EntryState x="0" y="0"><StateTransition stateToId="{blink_state}"/></EntryState>',
        f'<AnimationState x="200" y="0" animationId="{blink_anim}" id="{blink_state}"/>',
        "</StateMachineLayer>",
        "</StateMachine>",
    ])
    anims = "".join(animation(n, aid, d, m) for (n, d, m), aid in zip(MOODS, anim_ids)) + blink(blink_anim)
    artboard = (f'<Artboard defaultStateMachineId="{sm}" viewModelId="{vm}" viewModelInstanceId="{vm_inst}" '
                f'width="400" height="400" styleId="0:3" name="Mitra" id="0:2">'
                f'<LayoutComponentStyle name="Artboard Style" id="0:3"/>{_backdrop()}'
                f"{tree}{machine}{anims}</Artboard>")
    viewmodel = (f'<ViewModel defaultInstanceId="{vm_inst}" name="Mitra" id="{vm}">'
                 f'<ViewModelPropertyNumber name="mood" id="{vm_mood}"/>'
                 f'<ViewModelInstance exports="true" name="Default" id="{vm_inst}">'
                 f'<ViewModelInstanceNumber propertyValue="0" viewModelPropertyId="{vm_mood}"/>'
                 "</ViewModelInstance></ViewModel>")
    return f'<Rive version="1" kind="fragment">{artboard}{viewmodel}</Rive>\n'


if __name__ == "__main__":
    out = Path(__file__).with_name("scene.rml")
    out.write_text(scene())
    print(f"wrote {out}")
