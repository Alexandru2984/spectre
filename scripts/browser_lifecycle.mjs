import assert from 'node:assert/strict';
import { chromium } from 'playwright';

const base = process.env.BASE_URL || 'http://127.0.0.1:4400';
assert(['localhost', '127.0.0.1'].includes(new URL(base).hostname), 'Use an isolated server.');
const browser = await chromium.launch();
const context = await browser.newContext();
const client = '9'.repeat(48);
await context.setExtraHTTPHeaders({ 'X-Real-IP': 'lifecycle-' + Date.now(), 'X-Spectre-Client': client });
const page = await context.newPage();
const errors = [];
page.on('pageerror', error => errors.push(error.message));
async function until(check, label, timeout = 8000) {
  const deadline = Date.now() + timeout;
  while (Date.now() < deadline) {
    if (await check()) return;
    await page.waitForTimeout(100);
  }
  assert.fail(label);
}
async function post(path, data) {
  const response = await context.request.post(base + path, { data });
  assert(response.ok(), 'Fixture request: ' + response.status());
  return response.json();
}
try {
  // Initial transport failures must recover without a manual click.
  let first = true;
  await page.route('**/api/snapshot?*', async route => {
    if (first) { first = false; await route.abort('failed'); }
    else await route.continue();
  });
  await page.goto(base + '/?room=lifecycle-' + Date.now());
  await page.locator('#connection-text').filter({ hasText: 'Live now' }).waitFor({ timeout: 20000 });
  await page.unroute('**/api/snapshot?*');
  const room = new URL(page.url()).searchParams.get('room');
  await page.locator('#content-input').fill('Parent removed with dependants');
  await page.locator('[data-ttl="300000"]').click();
  const created = page.waitForResponse(response => response.url().endsWith('/api/messages') && response.request().method() === 'POST');
  await page.locator('#send-btn').click();
  const parent = await (await created).json();
  await post('/api/messages', { room, content: 'Child must disappear immediately', ttl: 300000, parent_id: parent.id });
  await page.locator('#feed .message-card').nth(1).waitFor();
  await page.locator('#pause-btn').click();
  await page.getByRole('button', { name: 'Burn your message', exact: true }).click();
  await page.locator('#confirm-burn').click();
  await until(async () => await page.locator('#feed .message-card').count() === 0, 'Burn cascades while paused');

  const event = await post('/api/rooms', { name: 'Privacy lifecycle', minutes: 15 });
  const eventRoom = event.room.id;
  const message = await post('/api/messages', { room: eventRoom, content: 'Short-lived report preview', ttl: 6000 });
  await post('/api/messages/' + message.id + '/report?room=' + eventRoom, { reason: 'spam' });
  await page.goto(base + '/?room=' + eventRoom);
  await page.locator('#connection-text').filter({ hasText: 'Live now' }).waitFor();
  await page.locator('#moderate-btn').click();
  await page.locator('#moderator-key').fill(event.owner_key);
  await page.locator('#load-reports').click();
  await page.locator('#moderator-reports .moderation-report').waitFor();
  await page.locator('#moderator-reports .moderation-report').waitFor({ state: 'detached', timeout: 8000 });
  assert.equal(await page.locator('#moderator-reports').textContent(), '', 'Expired report text is removed');
  await page.keyboard.press('Escape');

  const late = await post('/api/messages', { room: eventRoom, content: 'Previous room report', ttl: 300000 });
  await post('/api/messages/' + late.id + '/report?room=' + eventRoom, { reason: 'spam' });
  let release, reached;
  const gate = new Promise(resolve => { release = resolve; });
  const intercepted = new Promise(resolve => { reached = resolve; });
  await page.route('**/api/reports?*', async route => {
    const response = await route.fetch(); reached(); await gate; await route.fulfill({ response });
  });
  await page.locator('#moderate-btn').click();
  await intercepted;
  await page.evaluate(() => document.querySelector('[data-room="ideas"]').click());
  release();
  await page.locator('#room-label').filter({ hasText: 'Bright ideas' }).waitFor();
  await page.waitForTimeout(300);
  assert.equal(await page.locator('#moderator-reports').textContent(), '', 'Obsolete report cannot repopulate a new room');
  assert.equal(await page.locator('#moderator-key').inputValue(), '');
  await page.unroute('**/api/reports?*');

  // Decryption can finish after fetch has completed and its signal is aborted.
  // An obsolete snapshot must never reopen a room closed by a live notification.
  const closing = await post('/api/rooms', { name: 'Delayed snapshot', minutes: 15 });
  await post('/api/messages', { room: closing.room.id, content: 'Must not reappear after closure', ttl: 300000 });
  await page.goto(base + '/?room=' + closing.room.id);
  await page.locator('#connection-text').filter({ hasText: 'Live now' }).waitFor();
  await page.evaluate(() => {
    const decrypt = window.SpectreCrypto.decrypt;
    const gate = new Promise(resolve => { window.releaseOfflineSnapshot = resolve; });
    window.SpectreCrypto.decrypt = async (...args) => {
      window.offlineSnapshotDecoding = true; await gate;
      const value = await decrypt(...args); window.offlineSnapshotDecoded = true; return value;
    };
    document.querySelector('#retry-btn').click();
  });
  await until(async () => await page.evaluate(() => window.offlineSnapshotDecoding), 'Snapshot decoding is suspended before disconnect');
  await context.setOffline(true);
  await page.locator('#offline-banner:not([hidden])').waitFor();
  await page.evaluate(() => window.releaseOfflineSnapshot());
  await until(async () => await page.evaluate(() => window.offlineSnapshotDecoded), 'Snapshot finishes decoding while offline');
  await page.waitForTimeout(100);
  assert.equal(await page.locator('#connection-text').textContent(), 'Offline', 'A buffered response cannot claim a live connection');
  assert(await page.locator('#offline-banner').isVisible());
  await context.setOffline(false);
  await page.locator('#connection-text').filter({ hasText: 'Live now' }).waitFor();
  await page.reload();
  await page.locator('#connection-text').filter({ hasText: 'Live now' }).waitFor();
  await page.evaluate(() => {
    const decrypt = window.SpectreCrypto.decrypt;
    const gate = new Promise(resolve => { window.releaseSnapshot = resolve; });
    window.SpectreCrypto.decrypt = async (...args) => {
      window.snapshotDecoding = true; await gate; return decrypt(...args);
    };
    document.querySelector('#retry-btn').click();
  });
  await until(async () => await page.evaluate(() => window.snapshotDecoding), 'Snapshot is held during decoding');
  const closed = await context.request.delete(base + '/api/room?room=' + closing.room.id, { headers: { 'X-Moderator-Key': closing.owner_key } });
  assert(closed.ok());
  await page.locator('#room-locked:not([hidden])').waitFor();
  await page.evaluate(() => window.releaseSnapshot());
  await page.waitForTimeout(300);
  assert(await page.locator('#send-btn').isDisabled());
  assert.equal(await page.locator('#feed .message-card').count(), 0, 'Late decoded snapshot cannot restore closed-room content');
  assert.deepEqual(errors, []);
  console.log('Lifecycle regressions passed: initial reconnect, paused burn cascade, report expiry, obsolete dialogs, delayed offline responses and decoded snapshots after closure.');
} finally { await browser.close(); }
