"""Builds one FieldOS marketing video as a HyperFrames project, then renders it.

usage: python3 build_video.py spec.json [--no-render]
(set up first: see README.md in this folder)

1. Voiceover per scene with Kokoro (offline, Apache-2.0 weights).
2. Scene timings from the voiceover lengths.
3. Procedural music (music.py), ducked under the voice with ffmpeg.
4. index.html: GSAP timeline, real app screenshots in a phone frame.
5. `hyperframes render` to MP4.
"""
import html, json, os, re, shutil, subprocess, sys
import numpy as np, soundfile as sf

ROOT = os.path.dirname(os.path.abspath(__file__))
ASSETS = os.path.join(ROOT, 'assets')
spec = json.load(open(sys.argv[1]))
render = '--no-render' not in sys.argv
W, H = spec['width'], spec['height']
PORTRAIT = H > W
name = spec['name']
proj = os.path.join(ROOT, 'projects', name)
os.makedirs(os.path.join(proj, 'assets'), exist_ok=True)
for f in os.listdir(ASSETS):
    src = os.path.join(ASSETS, f)
    if os.path.isfile(src):
        shutil.copy(src, os.path.join(proj, 'assets', f))
os.makedirs(os.path.join(proj, 'assets', 'shots'), exist_ok=True)
SR = 24000

# ---------- 1. voiceover ----------
_kokoro = None
def tts(text, voice, speed):
    global _kokoro
    if _kokoro is None:
        from kokoro_onnx import Kokoro
        _kokoro = Kokoro(os.path.join(ROOT, 'tts', 'kokoro-q8.onnx'), os.path.join(ROOT, 'tts', 'voices.npz'))
    s, sr = _kokoro.create(text, voice=voice, speed=speed, lang='en-us')
    assert sr == SR
    # trim leading/trailing silence
    a = np.abs(s); idx = np.where(a > 0.01)[0]
    return s[max(0, idx[0] - 600): idx[-1] + 2400] if len(idx) else s

voice = spec.get('voice', 'af_heart')
speed = spec.get('speed', 1.0)
scenes = spec['scenes']
t = 0.0
vo_track = []
for i, sc in enumerate(scenes):
    vo = sc.get('vo', '')
    lead = sc.get('lead', 0.35)
    dur_vo = 0.0
    if vo:
        cache = os.path.join(proj, f'vo_{i:02d}.wav')
        key = cache + '.txt'
        if not (os.path.exists(cache) and open(key).read() == f'{voice}|{speed}|{vo}'):
            sf.write(cache, tts(vo, voice, speed), SR)
            open(key, 'w').write(f'{voice}|{speed}|{vo}')
        audio, _ = sf.read(cache)
        dur_vo = len(audio) / SR
        vo_track.append((t + lead, audio))
    sc['start'] = round(t, 3)
    sc['dur'] = round(max(sc.get('min', 2.5), lead + dur_vo + sc.get('tail', 0.45)), 3)
    sc['vo_start'] = t + lead
    sc['vo_dur'] = dur_vo
    t += sc['dur']
TOTAL = round(t, 3)

# ---------- 2. audio mix ----------
voice_buf = np.zeros(int((TOTAL + 1) * SR))
for start, a in vo_track:
    s = int(start * SR); voice_buf[s:s + len(a)] += a
sf.write(os.path.join(proj, 'voice.wav'), voice_buf[: int(TOTAL * SR)], SR)
subprocess.run([sys.executable, os.path.join(ROOT, 'music.py'), os.path.join(proj, 'music.wav'), str(TOTAL), spec.get('mood', 'drive')], check=True)
music_db = spec.get('music_db', -12)
subprocess.run([
    'ffmpeg', '-y', '-loglevel', 'error', '-i', os.path.join(proj, 'voice.wav'), '-i', os.path.join(proj, 'music.wav'),
    '-filter_complex',
    '[0:a]aresample=44100,pan=stereo|c0=c0|c1=c0,loudnorm=I=-16:TP=-1.5:LRA=7,asplit=2[v][sc];'
    f'[1:a]aresample=44100,loudnorm=I=-16:TP=-1.5,volume={music_db}dB[m];'
    '[m][sc]sidechaincompress=threshold=0.04:ratio=4:attack=25:release=450[md];'
    '[v][md]amix=inputs=2:normalize=0,alimiter=limit=0.89[out]',
    '-map', '[out]', '-ar', '48000', os.path.join(proj, 'assets', 'mix.wav')], check=True)

# ---------- 3. composition ----------
NAVY, NAVY_DEEP, NAVY_SOFT, AMBER, AMBER_DARK = '#112A4A', '#0B1D35', '#2B4A73', '#F5A524', '#D6860E'

def esc(s): return html.escape(s, quote=True)

def helmet_svg(cls, size):
    return f'''<svg class="{cls}" width="{size}" height="{size}" viewBox="0 0 512 512">
  <path class="h-dome" d="M124 266 A132 132 0 0 1 388 266 Z" fill="{AMBER}"/>
  <rect class="h-band" x="124" y="262" width="264" height="22" fill="{AMBER_DARK}"/>
  <rect class="h-ridge" x="241" y="158" width="30" height="110" rx="15" fill="{AMBER_DARK}"/>
  <rect class="h-brim" x="72" y="286" width="368" height="36" rx="18" fill="{AMBER}"/>
  <rect class="h-line" x="131" y="366" width="250" height="13" rx="6.5" fill="#fff"/>
</svg>'''

def phone(shot, sid, screen_w):
    screen_h = screen_w * 2
    bez = round(screen_w * 0.035)
    status = round(screen_w * 0.075)
    copy = os.path.join(proj, 'assets', 'shots', f'{shot}.png')
    shutil.copy(os.path.join(ASSETS, 'shots', f'{shot}.png'), copy)
    return f'''<div class="phone" id="{sid}-phone" style="width:{screen_w + 2 * bez}px;height:{screen_h + status + 2 * bez}px;padding:{bez}px;border-radius:{round(screen_w * 0.13)}px">
  <div class="screen" style="border-radius:{round(screen_w * 0.095)}px">
    <div class="status" style="height:{status}px;font-size:{round(status * 0.42)}px;padding:0 {round(screen_w * 0.07)}px">
      <span>9:41</span><span class="si"><i></i><i></i><i></i><b></b></span>
    </div>
    <div class="shotwrap" style="height:{screen_h}px"><img id="{sid}-img" src="assets/shots/{shot}.png" style="width:{screen_w}px;height:{screen_h}px"/>
      <div class="hl" id="{sid}-hl"></div><div class="tap" id="{sid}-tap"></div></div>
  </div>
</div>'''

def chunks(text, maxlen):
    parts = re.split(r'(?<=[.,?!;:])\s+', text.strip())
    out = []
    for p in parts:
        words = p.split(); cur = ''
        for w in words:
            if len(cur) + len(w) + 1 > maxlen and cur:
                out.append(cur); cur = w
            else:
                cur = (cur + ' ' + w).strip()
        if cur: out.append(cur)
    return out

body = []
js = []
caps = []
SCREEN_W = 500 if PORTRAIT else 410
if spec.get('screen_w'): SCREEN_W = spec['screen_w']

for i, sc in enumerate(scenes):
    sid = f's{i}'
    st, du = sc['start'], sc['dur']
    typ = sc['type']
    inner = ''
    if typ == 'hook':
        lines = ''.join(f'<div class="hline{" last" if k == len(sc["lines"]) - 1 else ""}"><span id="{sid}-l{k}">{esc(l)}</span></div>' for k, l in enumerate(sc['lines']))
        inner = f'<div class="hook">{lines}<div class="uline" id="{sid}-u"></div></div>'
        for k in range(len(sc['lines'])):
            js.append(f'tl.fromTo("#{sid}-l{k}", {{yPercent:110}}, {{yPercent:0, duration:0.55, ease:"power3.out"}}, {st + 0.15 + k * 0.28:.3f});')
        js.append(f'tl.fromTo("#{sid}-u", {{scaleX:0}}, {{scaleX:1, duration:0.6, ease:"power2.inOut"}}, {st + 0.4 + len(sc["lines"]) * 0.28:.3f});')
    elif typ == 'logo':
        inner = f'''<div class="logo">{helmet_svg(f"{sid}-helm helm", 360 if not PORTRAIT else 420)}
  <div class="word" id="{sid}-word">Field<span>OS</span></div>
  <div class="tag" id="{sid}-tag">{esc(sc.get("tag", "Run every site from your phone."))}</div></div>'''
        b = st + 0.1
        js += [
            f'tl.fromTo(".{sid}-helm .h-dome", {{scale:0, transformOrigin:"50% 100%"}}, {{scale:1, duration:0.6, ease:"back.out(1.7)"}}, {b:.3f});',
            f'tl.fromTo(".{sid}-helm .h-ridge", {{scaleY:0, transformOrigin:"50% 100%"}}, {{scaleY:1, duration:0.4, ease:"power2.out"}}, {b + 0.3:.3f});',
            f'tl.fromTo(".{sid}-helm .h-band", {{scaleX:0, transformOrigin:"50% 50%"}}, {{scaleX:1, duration:0.4}}, {b + 0.3:.3f});',
            f'tl.fromTo(".{sid}-helm .h-brim", {{scaleX:0, transformOrigin:"50% 50%"}}, {{scaleX:1, duration:0.5, ease:"power3.out"}}, {b + 0.15:.3f});',
            f'tl.fromTo(".{sid}-helm .h-line", {{scaleX:0, transformOrigin:"0% 50%"}}, {{scaleX:1, duration:0.6, ease:"power2.inOut"}}, {b + 0.5:.3f});',
            f'tl.fromTo("#{sid}-word", {{opacity:0, y:40, scale:1.12}}, {{opacity:1, y:0, scale:1, duration:0.9, ease:"power3.out"}}, {b + 0.45:.3f});',
            f'tl.fromTo("#{sid}-tag", {{opacity:0, y:20}}, {{opacity:1, y:0, duration:0.6, ease:"power2.out"}}, {b + 0.95:.3f});',
        ]
    elif typ in ('phone', 'cta'):
        if typ == 'phone':
            kicker = f'<div class="kicker" id="{sid}-k">{esc(sc.get("kicker", ""))}</div>' if sc.get('kicker') else ''
            title = ''.join(f'<div class="tline{" last" if k == len(sc["title"]) - 1 else ""}"><span id="{sid}-t{k}">{esc(l)}</span></div>' for k, l in enumerate(sc['title']))
            sub = f'<div class="sub" id="{sid}-sub">{esc(sc.get("sub", ""))}</div>' if sc.get('sub') else ''
            bullets = ''.join(f'<li id="{sid}-b{k}"><i></i>{esc(b)}</li>' for k, b in enumerate(sc.get('bullets', [])))
            if bullets: bullets = f'<ul class="bul">{bullets}</ul>'
            side = 'left' if sc.get('side', 'left') == 'left' else 'right'
            inner = f'<div class="pscene {side}"><div class="copy">{kicker}{title}{sub}{bullets}</div><div class="stage">{phone(sc["shot"], sid, SCREEN_W)}</div></div>'
            js.append(f'tl.fromTo("#{sid}-phone", {{y:{H * 0.6:.0f}, rotate:{-6 if side == "left" else 6}}}, {{y:0, rotate:0, duration:0.9, ease:"power3.out"}}, {st + 0.05:.3f});')
            js.append(f'tl.fromTo("#{sid}-phone", {{scale:1}}, {{scale:1.035, duration:{du - 0.9:.3f}, ease:"none"}}, {st + 0.9:.3f});')
            if sc.get('kicker'):
                js.append(f'tl.fromTo("#{sid}-k", {{opacity:0, x:-30}}, {{opacity:1, x:0, duration:0.5}}, {st + 0.2:.3f});')
            for k in range(len(sc['title'])):
                js.append(f'tl.fromTo("#{sid}-t{k}", {{yPercent:110}}, {{yPercent:0, duration:0.6, ease:"power3.out"}}, {st + 0.3 + k * 0.16:.3f});')
            if sc.get('sub'):
                js.append(f'tl.fromTo("#{sid}-sub", {{opacity:0, y:24}}, {{opacity:1, y:0, duration:0.6}}, {st + 0.75:.3f});')
            for k, _ in enumerate(sc.get('bullets', [])):
                js.append(f'tl.fromTo("#{sid}-b{k}", {{opacity:0, x:-24}}, {{opacity:1, x:0, duration:0.45}}, {st + 1.0 + k * 0.35:.3f});')
            if sc.get('scroll'):
                js.append(f'tl.to("#{sid}-img", {{y:{-sc["scroll"] * SCREEN_W / 1080:.0f}, duration:1.4, ease:"power2.inOut"}}, {st + du * 0.45:.3f});')
            for k, hl in enumerate(sc.get('highlights', [])):
                x, y, w, h = [v * SCREEN_W / 1080 for v in hl['box']]
                at = st + hl.get('at', 1.3)
                js.append(f'tl.set("#{sid}-hl", {{left:{x:.1f}, top:{y:.1f}, width:{w:.1f}, height:{h:.1f}}}, {at - 0.01:.3f});')
                js.append(f'tl.fromTo("#{sid}-hl", {{opacity:0, scale:1.15}}, {{opacity:1, scale:1, duration:0.4, ease:"back.out(2)", immediateRender:false}}, {at:.3f});')
                js.append(f'tl.to("#{sid}-hl", {{opacity:0, duration:0.3}}, {at + hl.get("hold", 1.8):.3f});')
            for k, tp in enumerate(sc.get('taps', [])):
                x, y = [v * SCREEN_W / 1080 for v in tp['at_xy']]
                at = st + tp.get('at', 1.3)
                js.append(f'tl.set("#{sid}-tap", {{left:{x:.1f}, top:{y:.1f}}}, {at - 0.01:.3f});')
                js.append(f'tl.fromTo("#{sid}-tap", {{opacity:0.9, scale:0.3}}, {{opacity:0, scale:1.6, duration:0.7, ease:"power2.out", immediateRender:false}}, {at:.3f});')
        else:
            inner = f'''<div class="cta">{helmet_svg(f"{sid}-helm helm", 220)}
  <div class="ctitle" id="{sid}-ti">{esc(sc.get("title", "Try FieldOS free for 3 days"))}</div>
  <div class="csub" id="{sid}-su">{esc(sc.get("sub", "Run every site from your phone."))}</div>
  <div class="badge" id="{sid}-ba"><svg viewBox="0 0 24 24" width="54" height="54"><path d="M4 2.5v19l10-9.5z" fill="#34A853"/><path d="M4 2.5l10 9.5 3-3L5.2 2.1z" fill="#4285F4"/><path d="M4 21.5l10-9.5 3 3-11.8 6.9z" fill="#EA4335"/><path d="M17 9l3.6 2.1c.6.4.6 1.4 0 1.8L17 15l-3-3z" fill="#FBBC04"/></svg><div><small>GET IT ON</small><b>Google Play</b></div></div>
  <div class="cfoot" id="{sid}-fo">{esc(sc.get("foot", "Made in Hyderabad · English, हिंदी, తెలుగు"))}</div></div>'''
            js += [
                f'tl.fromTo(".{sid}-helm", {{scale:0.4, opacity:0}}, {{scale:1, opacity:1, duration:0.6, ease:"back.out(1.8)"}}, {st + 0.1:.3f});',
                f'tl.fromTo("#{sid}-ti", {{opacity:0, y:40}}, {{opacity:1, y:0, duration:0.6, ease:"power3.out"}}, {st + 0.35:.3f});',
                f'tl.fromTo("#{sid}-su", {{opacity:0, y:30}}, {{opacity:1, y:0, duration:0.6}}, {st + 0.6:.3f});',
                f'tl.fromTo("#{sid}-ba", {{opacity:0, scale:0.8}}, {{opacity:1, scale:1, duration:0.6, ease:"back.out(2)"}}, {st + 0.9:.3f});',
                f'tl.to("#{sid}-ba", {{scale:1.05, duration:0.5, yoyo:true, repeat:3, ease:"sine.inOut"}}, {st + 1.6:.3f});',
                f'tl.fromTo("#{sid}-fo", {{opacity:0}}, {{opacity:1, duration:0.6}}, {st + 1.2:.3f});',
            ]
    elif typ == 'chapter':
        inner = f'''<div class="chapter"><div class="cnum" id="{sid}-n">{esc(sc.get("num", ""))}</div>
  <div class="ctext" id="{sid}-c">{esc(sc["text"])}</div><div class="uline" id="{sid}-u"></div></div>'''
        js += [
            f'tl.fromTo("#{sid}-n", {{opacity:0, scale:0.6}}, {{opacity:1, scale:1, duration:0.5, ease:"back.out(2)"}}, {st + 0.1:.3f});',
            f'tl.fromTo("#{sid}-c", {{opacity:0, y:40}}, {{opacity:1, y:0, duration:0.6, ease:"power3.out"}}, {st + 0.25:.3f});',
            f'tl.fromTo("#{sid}-u", {{scaleX:0}}, {{scaleX:1, duration:0.6, ease:"power2.inOut"}}, {st + 0.5:.3f});',
        ]
    # scene-level in/out
    body.append(f'<section class="clip scene" id="{sid}" data-start="{st}" data-duration="{du}" data-track-index="1">{inner}</section>')
    if i > 0:
        js.append(f'tl.fromTo("#{sid}", {{opacity:0}}, {{opacity:1, duration:0.3}}, {st:.3f});')
    if i < len(scenes) - 1:
        js.append(f'tl.to("#{sid}", {{opacity:0, y:{-30 if PORTRAIT else 0}, duration:0.3}}, {st + du - 0.3:.3f});')
    # captions
    if spec.get('captions', True) and sc.get('vo') and sc.get('captions', True):
        parts = chunks(sc['vo'].replace('Field O S', 'FieldOS').replace('D P R', 'DPR').replace('G P S', 'GPS'), 34 if PORTRAIT else 52)
        total_chars = sum(len(p) for p in parts)
        ct = sc['vo_start']
        for k, p in enumerate(parts):
            d = sc['vo_dur'] * len(p) / total_chars
            caps.append(f'<div class="clip cap" data-start="{ct:.3f}" data-duration="{d:.3f}" data-track-index="3"><span>{esc(p)}</span></div>')
            ct += d

# progress bar for long-form video
progress = '<div class="progress" id="prog"></div>' if spec.get('progress') else ''
if progress:
    js.append(f'tl.fromTo("#prog", {{scaleX:0}}, {{scaleX:1, duration:{TOTAL}, ease:"none"}}, 0);')
brand_bug = ''
if spec.get('bug'):
    brand_bug = f'<div class="bug">{helmet_svg("bugh", 54)}<span>FieldOS</span></div>'

title_size = 104 if PORTRAIT else 84
css = f'''
@font-face{{font-family:Inter;font-weight:400;src:url(assets/inter-latin-400-normal.woff2)}}
@font-face{{font-family:Inter;font-weight:500;src:url(assets/inter-latin-500-normal.woff2)}}
@font-face{{font-family:Inter;font-weight:600;src:url(assets/inter-latin-600-normal.woff2)}}
@font-face{{font-family:Inter;font-weight:700;src:url(assets/inter-latin-700-normal.woff2)}}
@font-face{{font-family:Inter;font-weight:800;src:url(assets/inter-latin-800-normal.woff2)}}
@font-face{{font-family:Inter;font-weight:900;src:url(assets/inter-latin-900-normal.woff2)}}
@font-face{{font-family:Noto;font-weight:400;src:url(assets/noto-sans-devanagari-devanagari-400-normal.woff2)}}
@font-face{{font-family:Noto;font-weight:700;src:url(assets/noto-sans-devanagari-devanagari-700-normal.woff2)}}
@font-face{{font-family:NotoTe;font-weight:400;src:url(assets/noto-sans-telugu-telugu-400-normal.woff2)}}
@font-face{{font-family:NotoTe;font-weight:700;src:url(assets/noto-sans-telugu-telugu-700-normal.woff2)}}
*{{margin:0;padding:0;box-sizing:border-box}}
html,body{{width:{W}px;height:{H}px;overflow:hidden;background:{NAVY_DEEP}}}
#root{{width:{W}px;height:{H}px;position:relative;overflow:hidden;font-family:Inter,Noto,NotoTe,sans-serif;color:#fff;
  background:radial-gradient(120% 80% at {'50% 0%' if PORTRAIT else '20% 30%'}, {NAVY_SOFT} 0%, {NAVY} 45%, {NAVY_DEEP} 100%)}}
.grid{{position:absolute;inset:-200px;background-image:linear-gradient(rgba(255,255,255,.045) 2px,transparent 2px),linear-gradient(90deg,rgba(255,255,255,.045) 2px,transparent 2px);background-size:120px 120px}}
.glow{{position:absolute;width:{W * 0.7:.0f}px;height:{W * 0.7:.0f}px;border-radius:50%;background:radial-gradient(circle,rgba(245,165,36,.20),transparent 65%);
  {'right:-25%;top:30%' if PORTRAIT else 'right:-10%;top:-20%'}}}
.scene{{position:absolute;inset:0;display:flex;align-items:center;justify-content:center}}
.hook{{text-align:center;padding:0 80px}}
.hline,.tline{{overflow:hidden;line-height:1.12}}
.hline span,.tline span{{padding-bottom:0.16em}}
.hline span{{display:inline-block;font-weight:800;font-size:{100 if PORTRAIT else 100}px;letter-spacing:-.035em}}
.hline.last span{{color:{AMBER}}}
.uline{{height:12px;width:260px;background:{AMBER};border-radius:6px;margin:44px auto 0;transform-origin:0 50%}}
.logo{{display:flex;flex-direction:column;align-items:center}}
.word{{font-weight:900;font-size:{200 if PORTRAIT else 180}px;letter-spacing:-.03em;margin-top:-30px}}
.word span{{color:{AMBER}}}
.tag{{font-size:{54 if PORTRAIT else 48}px;font-weight:500;color:#C9D6E8;margin-top:10px}}
.pscene{{position:absolute;inset:0;display:flex;align-items:center;{'flex-direction:column;justify-content:flex-start;padding-top:150px' if PORTRAIT else 'justify-content:center;gap:110px'}}}
.pscene.right{{{'' if PORTRAIT else 'flex-direction:row-reverse'}}}
.copy{{{'text-align:center;width:960px;margin-bottom:56px' if PORTRAIT else 'width:760px'}}}
.kicker{{display:inline-block;font-weight:700;font-size:{30 if PORTRAIT else 26}px;letter-spacing:.14em;text-transform:uppercase;color:{NAVY_DEEP};background:{AMBER};padding:10px 22px;border-radius:999px;margin-bottom:28px}}
.tline span{{display:inline-block;font-weight:800;font-size:{title_size}px;letter-spacing:-.035em}}
.tline.last span{{color:{AMBER}}}
.sub{{font-size:{44 if PORTRAIT else 38}px;line-height:1.3;color:#C9D6E8;margin-top:24px;font-weight:500}}
.bul{{list-style:none;margin-top:36px}}
.bul li{{font-size:34px;font-weight:600;margin:16px 0;display:flex;align-items:center;gap:18px;color:#E6EEF8}}
.bul li i{{width:18px;height:18px;border-radius:50%;background:{AMBER};flex:none}}
.phone{{background:#0A0F18;box-shadow:0 40px 120px rgba(0,0,0,.55),0 0 0 3px rgba(255,255,255,.08) inset;position:relative}}
.screen{{overflow:hidden;background:#F4F6F9;height:100%;position:relative}}
.status{{background:{NAVY};display:flex;justify-content:space-between;align-items:center;color:#fff;font-weight:600}}
.si{{display:flex;gap:6px;align-items:center}} .si i{{width:7px;height:14px;background:#fff;border-radius:2px;display:block}} .si i:nth-child(1){{height:8px}} .si i:nth-child(2){{height:11px}} .si b{{width:26px;height:13px;border:2px solid #fff;border-radius:3px;margin-left:6px;background:linear-gradient(90deg,#fff 70%,transparent 70%)}}
.shotwrap{{position:relative;overflow:hidden}}
.shotwrap img{{display:block;position:absolute;left:0;top:0}}
.hl{{position:absolute;opacity:0;border:5px solid {AMBER};border-radius:18px;box-shadow:0 0 0 2000px rgba(11,29,53,.28),0 0 30px rgba(245,165,36,.6)}}
.tap{{position:absolute;opacity:0;width:90px;height:90px;margin:-45px 0 0 -45px;border-radius:50%;background:rgba(245,165,36,.55);border:4px solid #fff}}
.cta{{display:flex;flex-direction:column;align-items:center;text-align:center;padding:0 60px}}
.ctitle{{font-weight:800;font-size:{84 if PORTRAIT else 92}px;text-wrap:balance;letter-spacing:-.03em;margin-top:10px;line-height:1.08}}
.csub{{font-size:{46 if PORTRAIT else 42}px;color:{AMBER};font-weight:600;margin-top:22px}}
.badge{{margin-top:60px;display:flex;align-items:center;gap:22px;background:#000;border:3px solid #9AA6B5;border-radius:22px;padding:22px 44px 22px 34px;text-align:left}}
.badge small{{display:block;font-size:22px;letter-spacing:.06em;color:#E0E6EE}} .badge b{{font-size:52px;font-weight:600;letter-spacing:-.01em}}
.cfoot{{margin-top:48px;font-size:32px;color:#9FB2CC}}
.chapter{{text-align:center}} .cnum{{display:inline-flex;width:130px;height:130px;border-radius:50%;background:{AMBER};color:{NAVY_DEEP};font-weight:900;font-size:64px;align-items:center;justify-content:center}}
.ctext{{font-weight:800;font-size:{100 if PORTRAIT else 96}px;letter-spacing:-.03em;margin-top:34px}}
.cap{{position:absolute;left:0;right:0;{'bottom:360px' if PORTRAIT else 'bottom:46px'};display:flex;justify-content:center;z-index:20}}
.cap span{{background:rgba(6,14,26,.82);color:#fff;font-weight:600;font-size:{44 if PORTRAIT else 36}px;padding:12px 28px;border-radius:16px;max-width:{W - 120}px;text-align:center;line-height:1.25}}
.progress{{position:absolute;left:0;bottom:0;height:8px;width:100%;background:{AMBER};transform-origin:0 50%;z-index:30}}
.bug{{position:absolute;{'top:60px;left:60px' if PORTRAIT else 'top:40px;left:48px'};display:flex;align-items:center;gap:10px;font-weight:800;font-size:30px;z-index:25;opacity:.92}}
'''

doc = f'''<!doctype html>
<html lang="en" data-resolution="{'portrait' if PORTRAIT else 'landscape'}">
<head><meta charset="UTF-8"/><meta name="viewport" content="width={W}, height={H}"/>
<script src="assets/gsap.min.js"></script>
<style>{css}</style></head>
<body>
<div id="root" data-composition-id="main" data-start="0" data-duration="{TOTAL}" data-width="{W}" data-height="{H}">
  <div class="grid" id="grid"></div><div class="glow" id="glow"></div>
  {brand_bug}
  {''.join(body)}
  {''.join(caps)}
  {progress}
  <audio id="mix" class="clip" src="assets/mix.wav" data-start="0" data-duration="{TOTAL}" data-track-index="0"></audio>
</div>
<script>
window.__timelines = window.__timelines || {{}};
const tl = gsap.timeline({{ paused: true }});
tl.fromTo("#grid", {{x:0, y:0}}, {{x:-120, y:-120, duration:{TOTAL}, ease:"none"}}, 0);
tl.fromTo("#glow", {{scale:0.9, opacity:0.7}}, {{scale:1.15, opacity:1, duration:{TOTAL}, ease:"sine.inOut"}}, 0);
{chr(10).join(js)}
tl.set({{}}, {{}}, {TOTAL});
window.__timelines["main"] = tl;
tl.seek(0);
</script>
</body></html>'''
open(os.path.join(proj, 'index.html'), 'w').write(doc)
json.dump({'id': name, 'name': name}, open(os.path.join(proj, 'meta.json'), 'w'))
json.dump({'paths': {'blocks': 'compositions', 'components': 'compositions/components', 'assets': 'assets'}, 'media': {'autoProxy': True}}, open(os.path.join(proj, 'hyperframes.json'), 'w'))
print(f'{name}: {TOTAL}s, {len(scenes)} scenes')
for i, sc in enumerate(scenes):
    print(f'  {i:2d} {sc["type"]:7s} {sc["start"]:6.2f} +{sc["dur"]:5.2f}')
if render:
    out = os.path.join(ROOT, 'out', f'{name}.mp4')
    os.makedirs(os.path.dirname(out), exist_ok=True)
    subprocess.run(['npx', '--prefix', ROOT, 'hyperframes', 'render', proj, '-o', out, '-f', '30', '-q', spec.get('quality', 'delivery'), '--quiet'], check=True, cwd=proj)
    print('rendered', out)
