// Play Store screenshots (1080x1920) and the feature graphic (1024x500).
// Caption on top, the real app screen in a phone, in the listing's language.
const { chromium } = require('playwright');
const fs = require('fs'), path = require('path');
// usage: node store_screenshots.js <out dir>
// assets/ beside this file: fonts, shots/<en|hi|te>/*.png and mitra/*.png (see README.md)
const A = path.join(__dirname, 'assets');
const shots = [
  ['14_assistant', {en: 'Just say it.|FieldOS does it.', hi: 'बस बोलिए,|FieldOS कर देगा', te: 'చెప్పండి చాలు,|FieldOS చేసేస్తుంది'}, 'talk'],
  ['01_home', {en: 'Every site.|One phone.', hi: 'हर साइट,|एक फ़ोन में', te: 'ప్రతి సైట్,|ఒకే ఫోన్‌లో'}],
  ['15_brief', {en: 'Know which site|needs you today', hi: 'आज किस साइट को|आपकी ज़रूरत है', te: 'ఈ రోజు ఏ సైట్‌కు|మీరు అవసరం'}],
  ['11_wage_sheet', {en: 'Saturday wages,|added up for you', hi: 'शनिवार की मज़दूरी,|अपने आप जुड़ी', te: 'శనివారం కూలీ,|లెక్క సిద్ధం'}],
  ['08_money', {en: 'Know where every|rupee went', hi: 'हर रुपये का|हिसाब', te: 'ప్రతి రూపాయి|లెక్క'}],
  ['16_owe', {en: 'Who you owe,|and since when', hi: 'किसका कितना बाकी,|कब से', te: 'ఎవరికి ఎంత బాకీ,|ఎప్పటినుంచి'}],
  ['02_dashboard', {en: 'Catch overspending|before month end', hi: 'महीने के अंत से पहले|ज़्यादा खर्च पकड़ें', te: 'నెలాఖరు ముందే|అధిక ఖర్చు పట్టుకోండి'}],
  ['17_tour_0', {en: 'Mitra shows you|around in 2 minutes', hi: 'मित्र 2 मिनट में|सब सिखा देगा', te: 'మిత్ర 2 నిమిషాల్లో|అంతా చూపిస్తాడు'}],
];
const font = (fam, file, w) => `@font-face{font-family:${fam};font-weight:${w};src:url(file://${A}/${file})}`;
const css = [
  font('Inter', 'inter-latin-500-normal.woff2', 500), font('Inter', 'inter-latin-800-normal.woff2', 800),
  font('Inter', 'inter-latin-900-normal.woff2', 900),
  font('Deva', 'noto-sans-devanagari-devanagari-700-normal.woff2', 800), font('Tel', 'noto-sans-telugu-telugu-700-normal.woff2', 800),
].join('\n');
const bg = `background:radial-gradient(120% 70% at 50% 0%,#2B4A73 0%,#112A4A 45%,#0B1D35 100%);color:#fff;position:relative`;
const grid = `.grid{position:absolute;inset:0;background-image:linear-gradient(rgba(255,255,255,.045) 2px,transparent 2px),linear-gradient(90deg,rgba(255,255,255,.045) 2px,transparent 2px);background-size:120px 120px}`;
const helmet = (s) => `<svg width="${s}" height="${s}" viewBox="0 0 512 512"><path d="M124 266 A132 132 0 0 1 388 266 Z" fill="#F5A524"/><rect x="124" y="262" width="264" height="22" fill="#D6860E"/><rect x="241" y="158" width="30" height="110" rx="15" fill="#D6860E"/><rect x="72" y="286" width="368" height="36" rx="18" fill="#F5A524"/><rect x="131" y="366" width="250" height="13" rx="6.5" fill="#fff"/></svg>`;

async function render(page, file, html) {
  const f = file.replace(/\.png$/, '._tmp.html');
  fs.writeFileSync(f, html);
  await page.goto('file://' + f, { waitUntil: 'load' });
  await page.evaluate(() => document.fonts.ready);
  await page.screenshot({ path: file });
  fs.unlinkSync(f);
}

(async () => {
  const out = path.resolve(process.argv[2]);
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1080, height: 1920 }, deviceScaleFactor: 1 });
  for (const lang of ['en', 'hi', 'te']) {
    const dir = path.join(out, 'screenshots', lang); fs.mkdirSync(dir, { recursive: true });
    for (const [i, [shot, caps, mood]] of shots.entries()) {
      const [l1, l2] = caps[lang].split('|');
      const fam = lang === 'hi' ? 'Inter,Deva' : lang === 'te' ? 'Inter,Tel' : 'Inter';
      const size = lang === 'en' ? 92 : lang === 'te' ? 76 : 84;
      const mitra = mood ? `<img class="mitra" src="file://${A}/mitra/mitra_${mood}.png">` : '';
      await render(page, path.join(dir, `${String(i + 1).padStart(2, '0')}_${shot.slice(3)}.png`), `<html><head><style>${css}
*{margin:0;box-sizing:border-box} body{width:1080px;height:1920px;overflow:hidden;font-family:${fam};${bg}}
${grid}
h1{position:relative;text-align:center;font-weight:800;font-size:${size}px;line-height:1.14;letter-spacing:${lang === 'en' ? '-.03em' : '0'};padding:120px 50px 0}
h1 span{color:#F5A524;display:block}
.phone{position:absolute;left:50%;top:470px;transform:translateX(-50%);width:760px;padding:26px;background:#0A0F18;border-radius:96px;box-shadow:0 50px 140px rgba(0,0,0,.55),0 0 0 4px rgba(255,255,255,.1) inset}
.scr{border-radius:72px;overflow:hidden;background:#F4F6F9}
.st{height:56px;background:#112A4A;display:flex;justify-content:space-between;align-items:center;padding:0 54px;font:600 24px Inter;color:#fff}
.scr img{display:block;width:708px}
.mitra{position:absolute;width:300px;left:-10px;bottom:120px;filter:drop-shadow(0 20px 30px rgba(0,0,0,.45));z-index:3}
</style></head><body><div class="grid"></div><h1>${l1}<span>${l2}</span></h1>
<div class="phone"><div class="scr"><div class="st"><span>9:41</span><span>▴ ◼</span></div><img src="file://${A}/shots/${lang}/${shot}.png"></div></div>${mitra}</body></html>`);
    }
  }
  // Feature graphic: 1024x500, no text near the edges (Play crops on some surfaces).
  await page.setViewportSize({ width: 1024, height: 500 });
  await render(page, path.join(out, 'feature-graphic.png'), `<html><head><style>${css}
*{margin:0;box-sizing:border-box} body{width:1024px;height:500px;overflow:hidden;font-family:Inter;${bg};
background:radial-gradient(90% 120% at 15% 20%,#2B4A73 0%,#112A4A 50%,#0B1D35 100%)}
${grid}
.l{position:absolute;left:70px;top:92px;width:560px}
.w{display:flex;align-items:center;gap:14px;font-weight:900;font-size:76px;letter-spacing:-.03em}
.w span{color:#F5A524}
.t{font-weight:800;font-size:44px;line-height:1.12;letter-spacing:-.02em;margin-top:18px}
.s{font-weight:500;font-size:24px;color:#C9D6E8;margin-top:16px}
.ph{position:absolute;right:150px;top:50px;width:250px;padding:10px;background:#0A0F18;border-radius:36px;transform:rotate(4deg);box-shadow:0 30px 70px rgba(0,0,0,.5)}
.ph img{display:block;width:230px;border-radius:28px}
.m{position:absolute;right:20px;bottom:-6px;width:210px;filter:drop-shadow(0 16px 24px rgba(0,0,0,.45))}
.glow{position:absolute;right:-120px;top:-160px;width:640px;height:640px;border-radius:50%;background:radial-gradient(circle,rgba(245,165,36,.22),transparent 65%)}
</style></head><body><div class="grid"></div><div class="glow"></div>
<div class="l"><div class="w">${helmet(84)}<div>Field<span>OS</span></div></div>
<div class="t">Run every site<br>from your phone.</div>
<div class="s">Just say it in Telugu, Hindi or English.</div></div>
<div class="ph"><img src="file://${A}/shots/en/14_assistant.png"></div>
<img class="m" src="file://${A}/mitra/mitra_wave.png"></body></html>`);
  await browser.close();
})();
