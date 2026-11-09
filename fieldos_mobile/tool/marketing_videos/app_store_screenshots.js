// App Store iPhone screenshots, 1290x2796 (the 6.9-inch slot), in the same
// look as the Play set (store_screenshots.js), with an iPhone status bar.
//
// usage: node app_store_screenshots.js <raw shots dir> <out dir> <@fontsource dir> <mascot dir>
//   raw shots: <dir>/<en|hi|te>/*.png from tool/store_screenshots/screenshots_test.dart
//   rendered at iPhone size: set _logical = Size(430, 932) and _pixelRatio = 3.0
//   there first (1290x2796). Fonts: npm i @fontsource/inter
//   @fontsource/noto-sans-devanagari @fontsource/noto-sans-telugu, then pass
//   node_modules/@fontsource. Mascot: fieldos_mobile/assets/mascot.
const { chromium } = require(process.env.PW || 'playwright');
const fs = require('fs'), path = require('path');
const [RAW, OUT, F, MITRA] = process.argv.slice(2);
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
const font = (fam, file, w) => `@font-face{font-family:${fam};font-weight:${w};src:url(file://${F}/${file})}`;
const css = [
  font('Inter', 'inter/files/inter-latin-500-normal.woff2', 500), font('Inter', 'inter/files/inter-latin-600-normal.woff2', 600),
  font('Inter', 'inter/files/inter-latin-800-normal.woff2', 800),
  font('Deva', 'noto-sans-devanagari/files/noto-sans-devanagari-devanagari-700-normal.woff2', 800),
  font('Tel', 'noto-sans-telugu/files/noto-sans-telugu-telugu-700-normal.woff2', 800),
].join('\n');
const bg = `background:radial-gradient(120% 70% at 50% 0%,#2B4A73 0%,#112A4A 45%,#0B1D35 100%);color:#fff;position:relative`;
const grid = `.grid{position:absolute;inset:0;background-image:linear-gradient(rgba(255,255,255,.045) 2px,transparent 2px),linear-gradient(90deg,rgba(255,255,255,.045) 2px,transparent 2px);background-size:144px 144px}`;
// iOS-style status icons: signal bars, wifi, battery.
const status = `<svg width="190" height="34" viewBox="0 0 190 34" fill="#fff"><rect x="0" y="22" width="8" height="10" rx="2"/><rect x="12" y="16" width="8" height="16" rx="2"/><rect x="24" y="10" width="8" height="22" rx="2"/><rect x="36" y="4" width="8" height="28" rx="2"/>
<path d="M78 30l-6-7a9 9 0 0 1 12 0z"/><path d="M66 17a18 18 0 0 1 24 0l-4 4.5a12 12 0 0 0-16 0z"/><path d="M60 10a27 27 0 0 1 36 0l-4 4.5a21 21 0 0 0-28 0z"/>
<rect x="112" y="5" width="66" height="26" rx="8" fill="none" stroke="#fff" stroke-opacity=".5" stroke-width="3"/><rect x="117" y="10" width="50" height="16" rx="4"/><rect x="181" y="13" width="5" height="10" rx="2" fill-opacity=".5"/></svg>`;
(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1290, height: 2796 }, deviceScaleFactor: 1 });
  for (const lang of ['en', 'hi', 'te']) {
    const dir = path.join(OUT, lang); fs.mkdirSync(dir, { recursive: true });
    for (const [i, [shot, caps, mood]] of shots.entries()) {
      const [l1, l2] = caps[lang].split('|');
      const fam = lang === 'hi' ? 'Inter,Deva' : lang === 'te' ? 'Inter,Tel' : 'Inter';
      const size = lang === 'en' ? 112 : lang === 'te' ? 92 : 102;
      const mitra = mood ? `<img class="mitra" src="file://${MITRA}/mitra_${mood}.png">` : '';
      const f = path.join(dir, '_tmp.html');
      fs.writeFileSync(f, `<html><head><style>${css}
*{margin:0;box-sizing:border-box} body{width:1290px;height:2796px;overflow:hidden;font-family:${fam};${bg}}
${grid}
h1{position:relative;text-align:center;font-weight:800;font-size:${size}px;line-height:1.14;letter-spacing:${lang === 'en' ? '-.03em' : '0'};padding:170px 60px 0}
h1 span{color:#F5A524;display:block}
.phone{position:absolute;left:50%;top:640px;transform:translateX(-50%);width:948px;padding:30px;background:#0A0F18;border-radius:150px;box-shadow:0 60px 160px rgba(0,0,0,.55),0 0 0 5px rgba(255,255,255,.1) inset}
.scr{border-radius:120px;overflow:hidden;background:#F4F6F9;position:relative}
.st{height:110px;background:#112A4A;display:flex;justify-content:space-between;align-items:center;padding:18px 74px 0 92px;font:600 40px Inter;color:#fff}
.island{position:absolute;left:50%;top:22px;transform:translateX(-50%);width:250px;height:72px;border-radius:40px;background:#000}
.scr img{display:block;width:888px}
.mitra{position:absolute;width:360px;left:-10px;bottom:210px;filter:drop-shadow(0 24px 36px rgba(0,0,0,.45));z-index:3}
</style></head><body><div class="grid"></div><h1>${l1}<span>${l2}</span></h1>
<div class="phone"><div class="scr"><div class="island"></div><div class="st"><span>9:41</span>${status}</div><img src="file://${RAW}/${lang}/${shot}.png"></div></div>${mitra}</body></html>`);
      await page.goto('file://' + f, { waitUntil: 'load' });
      await page.evaluate(() => document.fonts.ready);
      await page.screenshot({ path: path.join(dir, `${String(i + 1).padStart(2, '0')}_${shot.slice(3)}.png`) });
      fs.unlinkSync(f);
    }
  }
  await browser.close();
})();
