// YouTube thumbnails (1280x720) and Reel covers (1080x1920): big words,
// Mitra and a real app screen. usage: node thumbnails.js <out dir>
const { chromium } = require('playwright');
const fs = require('fs'), path = require('path');
const A = path.join(__dirname, 'assets');
const font = (fam, file, w) => `@font-face{font-family:${fam};font-weight:${w};src:url(file://${A}/${file})}`;
const css = [font('Inter', 'inter-latin-800-normal.woff2', 800), font('Inter', 'inter-latin-900-normal.woff2', 900),
  font('Inter', 'inter-latin-600-normal.woff2', 600),
  font('Deva', 'noto-sans-devanagari-devanagari-700-normal.woff2', 900), font('Tel', 'noto-sans-telugu-telugu-700-normal.woff2', 900)].join('\n');
const bg = 'background:radial-gradient(110% 110% at 20% 10%,#2B4A73 0%,#112A4A 50%,#0B1D35 100%);color:#fff';

const wide = [
  ['fieldos-youtube-one-day-four-sites', ['4 SITES.', '1 PHONE.'], 'One contractor\'s full day', 'en/15_brief', 'celebrate'],
  ['fieldos-youtube-talk-to-your-site-app', ['TALK.', 'IT SAVES.'], 'Site paperwork, zero typing', 'en/14_assistant', 'talk'],
  ['fieldos-video-guide', ['HOW TO', 'USE FieldOS'], '3-minute guide', 'en/01_home', 'point'],
  ['fieldos-play-promo', ['JUST', 'SAY IT.'], 'Site paperwork, by voice', 'en/14_assistant', 'wave'],
];
const tall = [
  ['fieldos-reel-1-just-say-it', ['Stop typing.', 'Just say it.'], 'en/14_assistant', 'talk', 'Inter'],
  ['fieldos-reel-2-saturday-wages', ['Saturday wages,', 'no fight.'], 'en/11_wage_sheet', 'money', 'Inter'],
  ['fieldos-reel-3-evening-brief', ['7:30 pm. Which site', 'needs you?'], 'en/15_brief', 'chai', 'Inter'],
  ['fieldos-reel-4-who-you-owe', ['₹12 lakh owed.', 'Since when?'], 'en/16_owe', 'surprised', 'Inter'],
  ['fieldos-reel-5-telugu', ['మీ సైట్ యాప్', 'ఇప్పుడు తెలుగులో!'], 'te/14_assistant', 'wave', 'Inter,Tel'],
  ['fieldos-reel-6-hindi', ['आपकी साइट का ऐप', 'अब हिंदी में!'], 'hi/14_assistant', 'wave', 'Inter,Deva'],
];

async function shot(page, file, html) {
  const f = file + '._tmp.html';
  fs.writeFileSync(f, html);
  await page.goto('file://' + f, { waitUntil: 'load' });
  await page.evaluate(() => document.fonts.ready);
  await page.screenshot({ path: file, type: 'jpeg', quality: 90 });
  fs.unlinkSync(f);
}

(async () => {
  const out = path.resolve(process.argv[2]); fs.mkdirSync(out, { recursive: true });
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1280, height: 720 } });
  for (const [name, [l1, l2], sub, scr, mood] of wide) {
    await shot(p, path.join(out, name + '.jpg'), `<html><head><style>${css}*{margin:0;box-sizing:border-box}
body{width:1280px;height:720px;overflow:hidden;font-family:Inter;${bg};position:relative}
h1{position:absolute;left:64px;top:70px;font-weight:900;font-size:132px;line-height:.98;letter-spacing:-.04em;-webkit-text-stroke:6px #0B1D35;paint-order:stroke fill}
h1 span{color:#F5A524;display:block}
p{position:absolute;left:68px;bottom:70px;font-weight:800;font-size:44px;background:#F5A524;color:#0B1D35;padding:10px 24px;border-radius:14px}
.ph{position:absolute;right:250px;top:46px;width:300px;padding:12px;background:#0A0F18;border-radius:44px;transform:rotate(5deg);box-shadow:0 30px 70px rgba(0,0,0,.6)}
.ph img{display:block;width:276px;border-radius:34px}
.m{position:absolute;right:-10px;bottom:-10px;width:340px;filter:drop-shadow(0 20px 30px rgba(0,0,0,.5))}
</style></head><body><h1>${l1}<span>${l2}</span></h1><p>${sub}</p>
<div class="ph"><img src="file://${A}/shots/${scr}.png"></div><img class="m" src="file://${A}/mitra/mitra_${mood}.png"></body></html>`);
  }
  await p.setViewportSize({ width: 1080, height: 1920 });
  for (const [name, [l1, l2], scr, mood, fam] of tall) {
    await shot(p, path.join(out, name + '.jpg'), `<html><head><style>${css}*{margin:0;box-sizing:border-box}
body{width:1080px;height:1920px;overflow:hidden;font-family:${fam};${bg};position:relative}
h1{position:absolute;left:0;right:0;top:170px;text-align:center;font-weight:900;font-size:${fam === 'Inter' ? 118 : 104}px;line-height:1.1;letter-spacing:${fam === 'Inter' ? '-.035em' : '0'};padding:0 50px}
h1 span{color:#F5A524;display:block}
.ph{position:absolute;left:50%;top:620px;transform:translateX(-50%) rotate(-3deg);width:620px;padding:22px;background:#0A0F18;border-radius:80px;box-shadow:0 40px 100px rgba(0,0,0,.6)}
.ph img{display:block;width:576px;border-radius:60px}
.m{position:absolute;right:20px;bottom:180px;width:400px;filter:drop-shadow(0 20px 30px rgba(0,0,0,.5))}
</style></head><body><h1>${l1}<span>${l2}</span></h1>
<div class="ph"><img src="file://${A}/shots/${scr}.png"></div><img class="m" src="file://${A}/mitra/mitra_${mood}.png"></body></html>`);
  }
  await b.close();
})();
