// Store screenshots for every device slot, in English and in Telugu+English
// mix (Telugu app screens, captions the way Hyderabad sites actually talk),
// plus the Play feature graphic in both.
//
// usage: node launch_store_assets.js <raw shots dir> <out dir>
//   raw shots: <dir>/<device>/<en|te>/*.png from
//   tool/store_screenshots/screenshots_test.dart, one run per device with
//   SHOTS_DEVICE=phone|iphone|tablet7|tablet10|ipad.
// assets/ beside this file: the Inter and Noto Telugu woff2 files and
// mitra/*.png (python3 mitra_sheets.py), as for the videos (README.md).
const { chromium } = require(process.env.PW || 'playwright');
const fs = require('fs'), path = require('path');
const [RAW, OUT] = process.argv.slice(2).map((p) => path.resolve(p));
const A = path.join(__dirname, 'assets');

// Order is the listing order.
const shots = [
  ['14_assistant', { en: 'Just say it.|FieldOS does it.', te: 'చెప్పండి చాలు,|FieldOS does it' }, 'talk'],
  ['01_home', { en: 'Every site.|One phone.', te: 'ప్రతి site,|ఒకే phone లో' }],
  ['15_brief', { en: 'Know which site|needs you today', te: 'Today ఏ site కి|మీరు అవసరం?' }],
  ['11_wage_sheet', { en: 'Saturday wages,|added up for you', te: 'Saturday కూలీ,|auto గా లెక్క' }],
  ['08_money', { en: 'Know where every|rupee went', te: 'ప్రతి రూపాయి|track అవుతుంది' }],
  ['16_owe', { en: 'Who you owe,|and since when', te: 'ఎవరికి ఎంత pending,|ఎప్పటినుంచి' }],
  ['02_dashboard', { en: 'Catch overspending|before month end', te: 'Month end ముందే|over-spend పట్టుకోండి' }],
  ['17_tour_0', { en: 'Mitra shows you|around in 2 minutes', te: 'Mitra 2 minutes లో|అంతా చూపిస్తాడు' }, 'wave'],
];

// Canvas, device frame and caption sizes per store slot.
const devices = {
  phone: { W: 1080, H: 1920, frame: 760, pad: 26, r: 96, top: 470, cap: 92, capTe: 80, kind: 'android' },
  tablet7: { W: 1200, H: 1920, frame: 960, pad: 30, r: 64, top: 470, cap: 96, capTe: 84, kind: 'tablet' },
  tablet10: { W: 1600, H: 2560, frame: 1300, pad: 38, r: 80, top: 620, cap: 128, capTe: 112, kind: 'tablet' },
  iphone: { W: 1290, H: 2796, frame: 948, pad: 30, r: 150, top: 640, cap: 112, capTe: 96, kind: 'iphone' },
  ipad: { W: 2048, H: 2732, frame: 1640, pad: 46, r: 96, top: 640, cap: 140, capTe: 124, kind: 'tablet' },
};

const font = (fam, file, w) => `@font-face{font-family:${fam};font-weight:${w};src:url(file://${A}/${file})}`;
const css = [
  font('Inter', 'inter-latin-500-normal.woff2', 500), font('Inter', 'inter-latin-600-normal.woff2', 600),
  font('Inter', 'inter-latin-800-normal.woff2', 800), font('Inter', 'inter-latin-900-normal.woff2', 900),
  font('Tel', 'noto-sans-telugu-telugu-700-normal.woff2', 800), font('Tel', 'noto-sans-telugu-telugu-400-normal.woff2', 500),
].join('\n');
const bg = `background:radial-gradient(120% 70% at 50% 0%,#2B4A73 0%,#112A4A 45%,#0B1D35 100%);color:#fff;position:relative`;
const helmet = (s) => `<svg width="${s}" height="${s}" viewBox="0 0 512 512"><path d="M124 266 A132 132 0 0 1 388 266 Z" fill="#F5A524"/><rect x="124" y="262" width="264" height="22" fill="#D6860E"/><rect x="241" y="158" width="30" height="110" rx="15" fill="#D6860E"/><rect x="72" y="286" width="368" height="36" rx="18" fill="#F5A524"/><rect x="131" y="366" width="250" height="13" rx="6.5" fill="#fff"/></svg>`;
const iosStatus = (h) => `<svg height="${h}" viewBox="0 0 190 34" fill="#fff"><rect x="0" y="22" width="8" height="10" rx="2"/><rect x="12" y="16" width="8" height="16" rx="2"/><rect x="24" y="10" width="8" height="22" rx="2"/><rect x="36" y="4" width="8" height="28" rx="2"/><path d="M78 30l-6-7a9 9 0 0 1 12 0z"/><path d="M66 17a18 18 0 0 1 24 0l-4 4.5a12 12 0 0 0-16 0z"/><path d="M60 10a27 27 0 0 1 36 0l-4 4.5a21 21 0 0 0-28 0z"/><rect x="112" y="5" width="66" height="26" rx="8" fill="none" stroke="#fff" stroke-opacity=".5" stroke-width="3"/><rect x="117" y="10" width="50" height="16" rx="4"/></svg>`;

function page(d, lang, l1, l2, img, mood) {
  const scr = d.frame - 2 * d.pad;
  const sb = Math.round(scr * (d.kind === 'iphone' ? 0.116 : 0.06));
  const fs1 = lang === 'en' ? d.cap : d.capTe;
  const fam = lang === 'te' ? 'Inter,Tel' : 'Inter';
  const status = d.kind === 'iphone'
    ? `<div class="island"></div><div class="st"><span>9:41</span>${iosStatus(Math.round(sb * 0.3))}</div>`
    : `<div class="st"><span>9:41</span><span>▴ ◼</span></div>`;
  const mitra = mood ? `<img class="mitra" src="file://${A}/mitra/mitra_${mood}.png">` : '';
  return `<html><head><style>${css}
*{margin:0;box-sizing:border-box} body{width:${d.W}px;height:${d.H}px;overflow:hidden;font-family:${fam};${bg}}
.grid{position:absolute;inset:0;background-image:linear-gradient(rgba(255,255,255,.045) 2px,transparent 2px),linear-gradient(90deg,rgba(255,255,255,.045) 2px,transparent 2px);background-size:${Math.round(d.W / 9)}px ${Math.round(d.W / 9)}px}
.glow{position:absolute;left:50%;top:${d.top - d.W * 0.2}px;width:${d.W * 1.1}px;height:${d.W * 1.1}px;transform:translateX(-50%);border-radius:50%;background:radial-gradient(circle,rgba(245,165,36,.16),transparent 62%)}
h1{position:relative;text-align:center;font-weight:800;font-size:${fs1}px;line-height:1.16;letter-spacing:${lang === 'en' ? '-.03em' : '-.01em'};padding:${Math.round(d.top * 0.25)}px ${Math.round(d.W * 0.05)}px 0}
h1 span{color:#F5A524;display:block}
.dev{position:absolute;left:50%;top:${d.top}px;transform:translateX(-50%);width:${d.frame}px;padding:${d.pad}px;background:#0A0F18;border-radius:${d.r}px;box-shadow:0 60px 160px rgba(0,0,0,.55),0 0 0 ${Math.max(4, d.pad / 6)}px rgba(255,255,255,.1) inset}
.scr{border-radius:${d.r - d.pad}px;overflow:hidden;background:#F4F6F9;position:relative}
.st{height:${sb}px;background:#112A4A;display:flex;justify-content:space-between;align-items:center;padding:${d.kind === 'iphone' ? sb * 0.16 : 0}px ${Math.round(scr * 0.075)}px 0;font:600 ${Math.round(sb * (d.kind === 'iphone' ? 0.36 : 0.42))}px Inter;color:#fff}
.island{position:absolute;left:50%;top:${sb * 0.2}px;transform:translateX(-50%);width:${scr * 0.28}px;height:${sb * 0.65}px;border-radius:${sb}px;background:#000}
.scr img{display:block;width:${scr}px}
.mitra{position:absolute;width:${Math.round(d.W * 0.3)}px;left:${-Math.round(d.W * 0.01)}px;bottom:${Math.round(d.H * 0.07)}px;filter:drop-shadow(0 24px 36px rgba(0,0,0,.45));z-index:3}
</style></head><body><div class="grid"></div><div class="glow"></div><h1>${l1}<span>${l2}</span></h1>
<div class="dev"><div class="scr">${status}<img src="file://${img}"></div></div>${mitra}</body></html>`;
}

function feature(lang) {
  const te = lang === 'te';
  return `<html><head><style>${css}
*{margin:0;box-sizing:border-box} body{width:1024px;height:500px;overflow:hidden;font-family:${te ? 'Inter,Tel' : 'Inter'};color:#fff;position:relative;
background:radial-gradient(90% 120% at 15% 20%,#2B4A73 0%,#112A4A 50%,#0B1D35 100%)}
.grid{position:absolute;inset:0;background-image:linear-gradient(rgba(255,255,255,.045) 2px,transparent 2px),linear-gradient(90deg,rgba(255,255,255,.045) 2px,transparent 2px);background-size:80px 80px}
.l{position:absolute;left:70px;top:${te ? 84 : 92}px;width:580px}
.w{display:flex;align-items:center;gap:14px;font:900 76px Inter;letter-spacing:-.03em}
.w span{color:#F5A524}
.t{font-weight:800;font-size:${te ? 40 : 44}px;line-height:1.16;letter-spacing:-.02em;margin-top:18px}
.s{font-weight:500;font-size:24px;color:#C9D6E8;margin-top:16px}
.ph{position:absolute;right:150px;top:50px;width:250px;padding:10px;background:#0A0F18;border-radius:36px;transform:rotate(4deg);box-shadow:0 30px 70px rgba(0,0,0,.5)}
.ph img{display:block;width:230px;border-radius:28px}
.m{position:absolute;right:20px;bottom:-6px;width:210px;filter:drop-shadow(0 16px 24px rgba(0,0,0,.45))}
.glow{position:absolute;right:-120px;top:-160px;width:640px;height:640px;border-radius:50%;background:radial-gradient(circle,rgba(245,165,36,.22),transparent 65%)}
</style></head><body><div class="grid"></div><div class="glow"></div>
<div class="l"><div class="w">${helmet(84)}<div>Field<span>OS</span></div></div>
<div class="t">${te ? 'ప్రతి site ని<br>మీ phone నుంచే నడపండి.' : 'Run every site<br>from your phone.'}</div>
<div class="s">${te ? 'తెలుగు, हिंदी, English లో చెప్పండి చాలు.' : 'Just say it, in English or 5 Indian languages.'}</div></div>
<div class="ph"><img src="file://${RAW}/phone/${lang}/14_assistant.png"></div>
<img class="m" src="file://${A}/mitra/mitra_wave.png"></body></html>`;
}

async function shoot(pg, file, html, W, H) {
  await pg.setViewportSize({ width: W, height: H });
  const f = file.replace(/\.png$/, '._tmp.html');
  fs.writeFileSync(f, html);
  await pg.goto('file://' + f, { waitUntil: 'load' });
  await pg.evaluate(() => document.fonts.ready);
  await pg.screenshot({ path: file });
  fs.unlinkSync(f);
}

(async () => {
  const browser = await chromium.launch();
  const pg = await browser.newPage({ deviceScaleFactor: 1 });
  for (const [dev, d] of Object.entries(devices)) {
    for (const lang of ['en', 'te']) {
      const dir = path.join(OUT, dev, lang === 'en' ? 'english' : 'telugu-english');
      fs.mkdirSync(dir, { recursive: true });
      for (const [i, [shot, caps, mood]] of shots.entries()) {
        const [l1, l2] = caps[lang].split('|');
        const img = path.join(RAW, dev, lang, `${shot}.png`);
        await shoot(pg, path.join(dir, `${String(i + 1).padStart(2, '0')}_${shot.slice(3)}.png`), page(d, lang, l1, l2, img, mood), d.W, d.H);
      }
    }
  }
  for (const lang of ['en', 'te']) {
    await shoot(pg, path.join(OUT, `feature-graphic-1024x500-${lang === 'en' ? 'english' : 'telugu-english'}.png`), feature(lang), 1024, 500);
  }
  await browser.close();
})();
