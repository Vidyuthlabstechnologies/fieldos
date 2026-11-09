// node peek.js <project dir> <out.png> t1 t2 ... : contact sheet of frames at those times
const { chromium } = require('playwright');
const path = require('path');
(async () => {
  const [dir, out, ...ts] = process.argv.slice(2);
  const b = await chromium.launch();
  const p = await b.newPage();
  const html = path.resolve(dir, 'index.html');
  await p.goto('file://' + html);
  const [w, h] = await p.evaluate(() => [document.body.clientWidth || 1080, document.body.clientHeight || 1920]);
  await p.setViewportSize({ width: w, height: h });
  await p.evaluate(() => document.fonts.ready);
  const shots = [];
  for (const t of ts) {
    await p.evaluate((t) => {
      const tl = window.__timelines.main; tl.seek(+t, false);
      document.querySelectorAll('.clip').forEach(c => {
        const s = +c.dataset.start, d = +c.dataset.duration;
        if (!c.closest('#root') || c.id === 'root') return;
        c.style.visibility = (t >= s && t < s + d) ? 'visible' : 'hidden';
      });
    }, t);
    await p.waitForTimeout(150);
    shots.push(await p.screenshot({ type: 'jpeg', quality: 70 }));
  }
  // stitch
  const imgs = shots.map(s => 'data:image/jpeg;base64,' + s.toString('base64'));
  const scale = 0.25, cols = Math.min(imgs.length, 6);
  await p.setViewportSize({ width: Math.round(w * scale) * cols, height: Math.round(h * scale) * Math.ceil(imgs.length / cols) });
  await p.setContent('<body style="margin:0;display:flex;flex-wrap:wrap">' + imgs.map(i => `<img src="${i}" style="width:${Math.round(w * scale)}px">`).join('') + '</body>');
  await p.waitForTimeout(300);
  await p.screenshot({ path: out });
  await b.close();
})();
