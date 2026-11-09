// Dumps the computed text styles of an HTML file for sabha-typography-check --browser.
// Usage: node typography-computed.mjs <page.html> <out.json>   (run it only through `sabha-heavy run typography --`)
// Needs playwright resolvable from SABHA_TYPO_PLAYWRIGHT_DIR (default: the current directory) and a Chrome it can launch.
// SABHA_TYPO_VIEWPORT=1440x900 sets the window. Output: {version, page:{scroll_w,inner_w}, elements:[{selector, tag, text,
// family, size_px, weight, color, bg, line_height_px, scroll_w, client_w, scroll_h, client_h, overflow_x, overflow_y,
// text_overflow, face_loaded}]}. face_loaded is false when document.fonts.check() says the first declared face is not loaded.
import { createRequire } from 'node:module';
import { writeFileSync } from 'node:fs';
import { resolve } from 'node:path';

const [html, out] = process.argv.slice(2);
if (!html || !out) { console.error('usage: node typography-computed.mjs <page.html> <out.json>'); process.exit(2); }
const req = createRequire(resolve(process.env.SABHA_TYPO_PLAYWRIGHT_DIR || process.cwd()) + '/');
const { chromium } = req('playwright');
const [vw, vh] = (process.env.SABHA_TYPO_VIEWPORT || '1440x900').split('x').map(Number);

const browser = await chromium.launch({ channel: 'chrome' });
try {
  const page = await browser.newPage({ viewport: { width: vw || 1440, height: vh || 900 } });
  await page.goto('file://' + resolve(html), { waitUntil: 'networkidle' });
  const data = await page.evaluate(async () => {
    await document.fonts.ready;
    const generic = new Set(['serif', 'sans-serif', 'monospace', 'cursive', 'fantasy', 'system-ui', 'ui-serif', 'ui-sans-serif', 'ui-monospace']);
    const sel = (el) => {
      let s = el.tagName.toLowerCase();
      if (el.id) return s + '#' + el.id;
      if (el.classList.length) s += '.' + [...el.classList].slice(0, 2).join('.');
      const p = el.parentElement;
      return p && p !== document.body && p !== document.documentElement ? sel(p) + ' > ' + s : s;
    };
    const bgOf = (el) => {
      for (let e = el; e; e = e.parentElement) {
        const c = getComputedStyle(e);
        if (c.backgroundImage !== 'none') return null;
        if (!/rgba\(.*,\s*0\)$|transparent/.test(c.backgroundColor)) return c.backgroundColor;
      }
      return 'rgb(255, 255, 255)';
    };
    const elements = [];
    for (const el of document.body.querySelectorAll('*')) {
      if (elements.length >= 5000) break;
      if (['SCRIPT', 'STYLE', 'NOSCRIPT', 'TEMPLATE'].includes(el.tagName)) continue;
      const own = [...el.childNodes].filter((n) => n.nodeType === 3 && n.textContent.trim()).map((n) => n.textContent.trim()).join(' ');
      if (!own) continue;
      const cs = getComputedStyle(el), r = el.getBoundingClientRect();
      if (cs.display === 'none' || cs.visibility === 'hidden' || (!r.width && !r.height)) continue;
      const first = cs.fontFamily.split(',')[0].trim().replace(/^["']|["']$/g, '');
      const lh = parseFloat(cs.lineHeight);
      elements.push({
        selector: sel(el), tag: el.tagName.toLowerCase(), text: own.slice(0, 60), family: cs.fontFamily,
        size_px: parseFloat(cs.fontSize), weight: parseInt(cs.fontWeight, 10), color: cs.color, bg: bgOf(el),
        line_height_px: Number.isFinite(lh) ? lh : null, scroll_w: el.scrollWidth, client_w: el.clientWidth,
        scroll_h: el.scrollHeight, client_h: el.clientHeight, overflow_x: cs.overflowX, overflow_y: cs.overflowY,
        text_overflow: cs.textOverflow, face_loaded: generic.has(first.toLowerCase()) ? true : document.fonts.check(cs.fontSize + ' "' + first + '"'),
      });
    }
    return { version: 1, page: { scroll_w: document.documentElement.scrollWidth, inner_w: window.innerWidth }, elements };
  });
  writeFileSync(out, JSON.stringify(data));
} finally {
  await browser.close();
}
