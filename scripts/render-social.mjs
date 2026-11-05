// Export the editable, code-native brand card without a remote image service.
import { readFile } from 'node:fs/promises';
import { chromium } from 'playwright';
const browser = await chromium.launch({ headless: true });
try {
  const page = await browser.newPage({ viewport: { width: 1200, height: 630 }, deviceScaleFactor: 1 });
  const svg = await readFile(new URL('../priv/static/social.svg', import.meta.url), 'utf8');
  await page.setContent('<style>html,body{margin:0;width:1200px;height:630px;overflow:hidden}</style>' + svg);
  await page.screenshot({ path: new URL('../priv/static/social.png', import.meta.url).pathname });
} finally { await browser.close(); }
