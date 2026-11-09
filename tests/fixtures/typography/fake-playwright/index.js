// A fake playwright for tests/test-typography-check.sh: it logs how tools/typography-computed.mjs used it to
// $FAKE_PW_LOG and never starts a browser. FAKE_PW_MODE=nochrome makes launch() fail like a missing Chrome.
const fs = require('fs');
const log = (s) => fs.appendFileSync(process.env.FAKE_PW_LOG, s + '\n');
exports.chromium = {
  async launch(o) {
    if (process.env.FAKE_PW_MODE === 'nochrome') throw new Error("browserType.launch: Executable doesn't exist at /fake/chrome\nsecond line");
    log('launch ' + JSON.stringify(o));
    return {
      async newContext(c) {
        log('context ' + JSON.stringify(c));
        let handler;
        return {
          async route(_pattern, fn) { handler = fn; },
          async newPage() {
            return {
              async goto(url) {
                const probes = [url, new URL('fonts/a.woff2', url).href, 'file:///etc/hosts', 'https://example.invalid/x', 'data:text/css,a'];
                for (const u of probes) {
                  await handler({ request: () => ({ url: () => u }), continue: () => log('continue ' + u), abort: () => log('abort ' + u) });
                }
              },
              async evaluate() {
                return { version: 1, page: { scroll_w: 1, inner_w: 1 }, elements: [{ selector: 'p', tag: 'p', text: 'x', family: 'Inter, sans-serif', size_px: 16, weight: 400, color: 'rgb(23, 44, 79)', bg: 'rgb(255, 255, 255)' }] };
              },
            };
          },
        };
      },
      async close() { log('close'); },
    };
  },
};
