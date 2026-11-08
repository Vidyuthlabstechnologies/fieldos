// Play Store screenshots: 1080x1920, caption on top, real app screen in a phone.
const { chromium } = require('playwright');
const fs = require('fs'), path = require('path');
// usage: node store_screenshots.js <out dir>   (assets/ beside this file, see README.md)
const A = path.join(__dirname, 'assets');
const shots = [
  ['01_home', {en: 'Every site.|One phone.', hi: 'हर साइट,|एक फ़ोन में', te: 'ప్రతి సైట్,|ఒకే ఫోన్‌లో'}],
  ['08_money', {en: 'Know where every|rupee went', hi: 'हर रुपये का|हिसाब', te: 'ప్రతి రూపాయి|లెక్క'}],
  ['07_labour', {en: 'Attendance in|10 seconds', hi: '10 सेकंड में|हाजिरी', te: '10 సెకన్లలో|హాజరు'}],
  ['11_wage_sheet', {en: 'Wage sheet, ready|for Saturday', hi: 'शनिवार की|मज़दूरी तैयार', te: 'శనివారం కూలీ|సిద్ధం'}],
  ['06_stock', {en: 'See stock before|you order', hi: 'ऑर्डर से पहले|स्टॉक देखें', te: 'ఆర్డర్ ముందు|స్టాక్ చూడండి'}],
  ['02_dashboard', {en: 'Know which site is|over budget', hi: 'कौन-सी साइट बजट से|ऊपर, तुरंत जानें', te: 'ఏ సైట్ బడ్జెట్|దాటిందో తెలుసుకోండి'}],
  ['04_dpr', {en: 'DPR to WhatsApp|in one tap', hi: 'एक टैप में|DPR WhatsApp पर', te: 'ఒక్క టాప్‌తో|DPR వాట్సాప్‌కి'}],
  ['12_approvals', {en: 'Approve from|anywhere', hi: 'कहीं से भी|मंज़ूरी दें', te: 'ఎక్కడినుంచైనా|ఆమోదించండి'}],
];
const font = (fam, file, w) => `@font-face{font-family:${fam};font-weight:${w};src:url(file://${A}/${file})}`;
const css = [
  font('Inter', 'inter-latin-500-normal.woff2', 500), font('Inter', 'inter-latin-800-normal.woff2', 800),
  font('Deva', 'noto-sans-devanagari-devanagari-700-normal.woff2', 800), font('Tel', 'noto-sans-telugu-telugu-700-normal.woff2', 800),
].join('\n');
(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1080, height: 1920 }, deviceScaleFactor: 1 });
  for (const lang of ['en', 'hi', 'te']) {
    const dir = path.join(process.argv[2], lang); fs.mkdirSync(dir, { recursive: true });
    for (const [i, [shot, caps]] of shots.entries()) {
      const [l1, l2] = caps[lang].split('|');
      const fam = lang === 'hi' ? 'Inter,Deva' : lang === 'te' ? 'Inter,Tel' : 'Inter';
      const size = lang === 'en' ? 92 : 84;
      const f = path.join(dir, '_tmp.html'); fs.writeFileSync(f, `<html><head><style>${css}
*{margin:0;box-sizing:border-box} body{width:1080px;height:1920px;overflow:hidden;font-family:${fam};
background:radial-gradient(120% 70% at 50% 0%,#2B4A73 0%,#112A4A 45%,#0B1D35 100%);color:#fff;position:relative}
.grid{position:absolute;inset:0;background-image:linear-gradient(rgba(255,255,255,.045) 2px,transparent 2px),linear-gradient(90deg,rgba(255,255,255,.045) 2px,transparent 2px);background-size:120px 120px}
h1{position:relative;text-align:center;font-weight:800;font-size:${size}px;line-height:1.12;letter-spacing:${lang === 'en' ? '-.03em' : '0'};padding:120px 50px 0}
h1 span{color:#F5A524;display:block}
.phone{position:absolute;left:50%;top:470px;transform:translateX(-50%);width:760px;padding:26px;background:#0A0F18;border-radius:96px;box-shadow:0 50px 140px rgba(0,0,0,.55),0 0 0 4px rgba(255,255,255,.1) inset}
.scr{border-radius:72px;overflow:hidden;background:#F4F6F9}
.st{height:56px;background:#112A4A;display:flex;justify-content:space-between;align-items:center;padding:0 54px;font:600 24px Inter;color:#fff}
img{display:block;width:708px}
</style></head><body><div class="grid"></div><h1>${l1}<span>${l2}</span></h1>
<div class="phone"><div class="scr"><div class="st"><span>9:41</span><span>▴ ◼</span></div><img src="file://${A}/shots/${shot}.png"></div></div></body></html>`); await page.goto('file://' + f, { waitUntil: 'load' });
      await page.evaluate(() => document.fonts.ready);
      await page.screenshot({ path: path.join(dir, `${String(i + 1).padStart(2, '0')}_${shot.slice(3)}.png`) });
      fs.unlinkSync(f);
    }
  }
  await browser.close();
})();
