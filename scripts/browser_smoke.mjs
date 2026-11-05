import assert from 'node:assert/strict';
import { mkdir } from 'node:fs/promises';
import { chromium } from 'playwright';
import AxeBuilder from '@axe-core/playwright';

const baseURL = process.env.BASE_URL || 'http://127.0.0.1:4400';
assert(['127.0.0.1', 'localhost'].includes(new URL(baseURL).hostname), 'Use an isolated localhost server.');
const browser = await chromium.launch({ headless: true });
const context = await browser.newContext({ viewport: { width: 1440, height: 1100 }, permissions: ['clipboard-read', 'clipboard-write'] });
const page = await context.newPage();
const errors = [];
const room = 'browser-' + Date.now();
const content = 'A tiny spark ✦ <img src=x onerror="window.pwned=true">';
page.on('pageerror', error => errors.push(error.message));
page.on('console', message => { if (message.type() === 'error' && /content security|refused|uncaught/i.test(message.text())) errors.push(message.text()); });
async function waitFor(check, label) {
  for (let i = 0; i < 60; i++) { if (await check()) return; await page.waitForTimeout(100); }
  assert.fail(label);
}
async function noOverflow(label) {
  assert.equal(await page.evaluate(() => document.documentElement.scrollWidth > innerWidth), false, label + ': horizontal overflow');
}
async function accessibility(label) {
  const results = await new AxeBuilder({ page }).withTags(['wcag2a', 'wcag2aa', 'wcag21aa']).analyze();
  const failures = results.violations.map(v => ({ id: v.id, impact: v.impact, nodes: v.nodes.map(n => n.target) }));
  assert.deepEqual(failures, [], label + ': accessibility violations');
}
try {
  await mkdir('test-results', { recursive: true });
  await page.goto(baseURL + '/?room=' + room);
  await page.locator('#connection-text').filter({ hasText: 'Live now' }).waitFor();
  await noOverflow('desktop');
  await accessibility('empty desktop');
  await page.screenshot({ path: 'test-results/desktop-empty.png', fullPage: true });
  await page.locator('#content-input').fill(content);
  await page.locator('#kind-input').selectOption('idea');
  await page.locator('[data-ttl="300000"]').click();
  await page.locator('#send-btn').click();
  await page.locator('#feed .message-content').filter({ hasText: content }).waitFor();
  assert.equal(await page.evaluate(() => window.pwned), undefined);
  assert.equal(await page.locator('.message-content img').count(), 0);
  await page.getByRole('button', { name: 'Inspired: 0. Toggle reaction', exact: true }).click();
  await page.getByRole('button', { name: 'Inspired: 1. Toggle reaction', exact: true }).waitFor();
  await page.locator('[data-filter="mine"]').click();
  assert.equal(await page.locator('#feed .message-card').count(), 1);
  await page.locator('#search-input').fill('no-match-found');
  await page.locator('#empty-title').filter({ hasText: 'No thoughts' }).waitFor();
  await page.locator('#empty-action').click();
  assert.equal(await page.locator('#feed .message-card').count(), 1);
  await page.locator('#sort-input').selectOption('expiring');
  await page.locator('[data-view="constellation"]').click();
  await page.locator('#signal-index button').first().click();
  await page.locator('#message-dialog[open]').waitFor();
  assert.equal(await page.locator('#message-detail .message-content').textContent(), content);
  await page.keyboard.press('Escape');
  await page.locator('#motion-btn').click();
  assert.equal(await page.locator('#motion-btn').getAttribute('aria-pressed'), 'true');
  await page.locator('[data-view="feed"]').click();
  await page.locator('#pause-btn').click();
  await page.locator('#connection-text').filter({ hasText: 'Paused' }).waitFor();
  await page.locator('#pause-btn').click();
  await page.locator('#connection-text').filter({ hasText: 'Live now' }).waitFor();
  await page.locator('#search-input').focus();
  await page.keyboard.press('Tab');
  await page.locator('h1').click();
  await page.keyboard.press('/');
  assert.equal(await page.locator('#search-input').evaluate(node => node === document.activeElement), true);
  await page.locator('h1').click();
  await page.keyboard.press('n');
  assert.equal(await page.locator('#content-input').evaluate(node => node === document.activeElement), true);
  await page.locator('h1').click();
  await page.keyboard.press('?');
  await page.locator('#help-dialog[open]').waitFor();
  await accessibility('information dialog');
  await page.keyboard.press('Escape');
  await page.locator('#share-room-btn').click();
  assert.match(await page.evaluate(() => navigator.clipboard.readText()), new RegExp('room=' + room));
  await page.locator('[data-room="ideas"]').click();
  await waitFor(async () => await page.locator('#room-label').textContent() === 'Bright ideas', 'navigate to ideas');
  await page.goBack();
  await page.locator('#feed .message-content').filter({ hasText: content }).waitFor();
  await accessibility('desktop messages');
  await page.screenshot({ path: 'test-results/desktop-messages.png', fullPage: true });
  for (const width of [360, 390, 768]) {
    await page.setViewportSize({ width, height: 844 });
    await noOverflow('width ' + width);
  }
  await page.setViewportSize({ width: 390, height: 844 });
  await accessibility('mobile messages');
  await page.screenshot({ path: 'test-results/mobile-dark.png', fullPage: true });
  await page.locator('#mobile-theme-btn').click();
  await accessibility('mobile light');
  await page.screenshot({ path: 'test-results/mobile-light.png', fullPage: true });
  // Exercise capability deletion through the UI, including the confirmation.
  await page.getByRole('button', { name: 'Burn your message', exact: true }).click();
  await page.locator('#confirm-burn').click();
  await waitFor(async () => await page.locator('#feed .message-card').count() === 0, 'burn removes card');
  await page.locator('#new-room-btn').click();
  await page.locator('#room-input').fill('new-' + room);
  await page.locator('#room-form button[type="submit"]').click();
  assert.equal(await page.locator('#room-label').textContent(), '#new-' + room);
  // Hide the native connection while time still advances, then recover.
  await context.setOffline(true);
  await page.locator('#offline-banner:not([hidden])').waitFor({ timeout: 12000 });
  await context.setOffline(false);
  await page.locator('#connection-text').filter({ hasText: 'Live now' }).waitFor({ timeout: 15000 });
  const stored = await page.evaluate(() => Object.fromEntries(Object.entries(localStorage)));
  assert(Object.keys(stored).every(key => ['spectre:theme', 'spectre:view', 'spectre:motion'].includes(key)));
  assert(!JSON.stringify(stored).includes(content));
  await page.emulateMedia({ reducedMotion: 'reduce' });
  assert.equal(await page.locator('#motion-btn').getAttribute('aria-pressed'), 'true');
  assert.deepEqual(errors, []);
  console.log('Browser flows passed: rooms, Unicode/XSS text, posting, reactions, filters, sorting, constellation, burn, sharing, shortcuts, themes, offline recovery, reduced motion, storage and responsive layout.');
  console.log('Axe WCAG A/AA checks passed: desktop empty/messages, information dialog, mobile dark/light.');
} finally { await browser.close(); }
