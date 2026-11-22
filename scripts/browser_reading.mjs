import assert from 'node:assert/strict';
import { chromium } from 'playwright';
import { openRoomTool } from './browser_helpers.mjs';

const base = process.env.BASE_URL || 'http://127.0.0.1:4400';
assert(['localhost', '127.0.0.1'].includes(new URL(base).hostname), 'Use an isolated server.');
const browser = await chromium.launch();
const errors = [];
const releaseResponses = [];
try {
  const context = await browser.newContext({ viewport: { width: 1440, height: 1000 }, extraHTTPHeaders: { 'X-Real-IP': 'reading-' + Date.now() } });
  const p = await context.newPage();
  p.on('pageerror', e => errors.push(e.message));
  p.on('console', m => { if (m.type() === 'error' && /content security|refused|uncaught/i.test(m.text())) errors.push(m.text()); });
  const live = async () => p.locator('#connection-text').filter({ hasText: 'Live now' }).waitFor();
  const card = text => p.locator('#feed .message-card').filter({ has: p.locator('.message-content').filter({ hasText: text }) });
  async function post(text) {
    await p.locator('#content-input').fill(text);
    await p.locator('[data-ttl="300000"]').click();
    await p.locator('#send-btn').click();
    await card(text).waitFor();
  }
  async function until(check, label) {
    const end = Date.now() + 8000;
    while (Date.now() < end) { if (await check()) return; await p.waitForTimeout(100); }
    assert.fail(label);
  }
  async function painted() {
    return p.locator('#constellation').evaluate(c => c.getContext('2d').getImageData(0, 0, c.width, c.height).data.some(v => v !== 0));
  }
  // Hold an actual server response after the mutation commits, then reopen its dialog.
  async function holdResponse(match, action) {
    let release, arrived;
    const held = new Promise(resolve => { release = resolve; });
    releaseResponses.push(() => release());
    const ready = new Promise(resolve => { arrived = resolve; });
    await p.route(match, async route => {
      const response = await route.fetch();
      arrived(); await held; await route.fulfill({ response });
    });
    const waiting = ready.then(() => true);
    await action();
    assert(await Promise.race([waiting, p.waitForTimeout(8000).then(() => false)]), 'Mutation response arrived');
    return async () => { release(); await p.unrouteAll({ behavior: 'wait' }); await p.waitForTimeout(200); };
  }

  await p.goto(base + '/?room=reading-' + Date.now()); await live();
  await p.locator('#new-room-btn').click();
  await p.locator('#room-input').fill('Reading workshop');
  await p.locator('#room-private').check();
  const created = p.waitForResponse(r => new URL(r.url()).pathname === '/api/rooms' && r.request().method() === 'POST');
  await p.locator('#room-form button[type=submit]').click();
  const event = await (await created).json();
  await p.locator('#room-settings-btn:not([hidden])').waitFor({ state: 'attached' }); await live();
  await post('First lifecycle fixture'); await post('Second lifecycle fixture');

  await p.locator('[data-view="constellation"]').click();
  await until(painted, 'Constellation renders current content');
  await p.locator('[data-view="feed"]').click();
  assert.equal(await p.locator('#signal-index').textContent(), '', 'Inactive constellation clears message excerpts');
  assert.equal(await painted(), false, 'Inactive constellation clears pixels');
  console.log('Constellation cleanup passed.');

  await card('First lifecycle fixture').getByRole('button', { name: 'Open thread', exact: true }).click();
  await p.evaluate(() => { document.querySelector('#message-dialog').close(); [...document.querySelectorAll('#feed .message-card .message-tools button')].find(b => b.textContent === 'Open thread').click(); });
  await p.waitForTimeout(150);
  assert(await p.locator('#message-dialog').evaluate(d => d.open));
  assert.equal(await p.locator('#message-detail .message-content').count(), 1, 'A queued close cannot erase a reopened thread');
  await p.locator('#message-dialog [data-close]').click();
  assert.equal(await p.locator('#message-detail').textContent(), '', 'Explicit dismissal clears synchronously');

  await p.locator('#share-room-btn').click();
  await p.evaluate(() => { document.querySelector('#share-dialog').close(); document.querySelector('#share-room-btn').click(); });
  await p.waitForTimeout(150);
  assert((await p.locator('#share-url').inputValue()).includes('#invite='), 'A queued close cannot erase a new invitation');
  await p.locator('#share-dialog [data-close]').click();
  assert.equal(await p.locator('#share-url').inputValue(), '');

  await openRoomTool(p, '#room-settings-btn');
  await p.evaluate(() => { document.querySelector('#room-settings-dialog').close(); document.querySelector('#room-settings-btn').click(); });
  await p.waitForTimeout(150);
  assert.equal(await p.locator('#settings-name').inputValue(), 'Reading workshop', 'A queued close cannot erase reopened settings');
  await p.locator('#settings-name').fill('Saved workshop');
  const releaseSettings = await holdResponse(/\/api\/room\?/, () => p.locator('#room-settings-form button[type=submit]').click());
  await p.locator('#room-settings-dialog [data-close]').click();
  await openRoomTool(p, '#room-settings-btn');
  await p.locator('#settings-topic').fill('A new unsaved edit');
  await releaseSettings();
  assert(await p.locator('#room-settings-dialog').evaluate(d => d.open), 'Old settings success leaves the newer dialog open');
  assert.equal(await p.locator('#settings-topic').inputValue(), 'A new unsaved edit');
  await p.keyboard.press('Escape');
  console.log('Dialog reopening and settings race passed.');

  await card('First lifecycle fixture').getByRole('button', { name: 'Report', exact: true }).click();
  await p.evaluate(() => { document.querySelector('#report-dialog').close(); [...document.querySelectorAll('#feed .message-card')].find(c => c.textContent.includes('First lifecycle fixture')).querySelectorAll('.message-tools button').forEach(b => { if (b.textContent === 'Report') b.click(); }); });
  await p.waitForTimeout(150);
  const releaseReport = await holdResponse(/\/api\/messages\/[^/]+\/report\?/, () => p.locator('#submit-report').click());
  await p.locator('#report-dialog [data-close]').click();
  await card('Second lifecycle fixture').getByRole('button', { name: 'Report', exact: true }).click();
  await releaseReport();
  assert(await p.locator('#report-dialog').evaluate(d => d.open), 'Old report success leaves the newer report open');
  await p.locator('#submit-report').click();
  await p.locator('#report-dialog').waitFor({ state: 'hidden' });
  await openRoomTool(p, '#moderate-btn');
  await until(async () => await p.locator('.moderation-report').count() === 2, 'Both reports target their original messages');
  await p.evaluate(() => { document.querySelector('#moderator-dialog').close(); document.querySelector('#moderate-btn').click(); });
  await p.waitForTimeout(150);
  await until(async () => await p.locator('.moderation-report').count() === 2, 'A queued close cannot invalidate reopened moderation');
  await p.keyboard.press('Escape');
  console.log('Report race passed.');

  await card('First lifecycle fixture').getByRole('button', { name: 'Delete your message', exact: true }).click();
  const releaseDelete = await holdResponse(/\/api\/messages\/[^/?]+\?/, () => p.locator('#confirm-burn').click());
  if (await p.locator('#burn-dialog').evaluate(d => d.open)) await p.locator('#burn-dialog [data-close]').first().click();
  await card('Second lifecycle fixture').getByRole('button', { name: 'Delete your message', exact: true }).click();
  await releaseDelete();
  assert(await p.locator('#burn-dialog').evaluate(d => d.open), 'Old delete success leaves the newer confirmation open');
  await p.keyboard.press('Escape');

  await p.locator('[data-view="constellation"]').click();
  await until(painted, 'Remaining message is drawn');
  await p.locator('[data-room="ideas"]').click(); await live();
  assert.equal(await painted(), false, 'Navigation to an empty room clears pixels');
  assert.equal(await p.locator('#signal-index').textContent(), '');
  const expiryRoom = 'read-expiry-' + Date.now();
  await p.goto(base + '/?room=' + expiryRoom); await live();
  const ephemeral = await context.request.post(base + '/api/messages', { data: { room: expiryRoom, content: 'A short canvas fixture', ttl: 3000, kind: 'thought' } });
  assert.equal(ephemeral.status(), 201);
  await p.locator('#signal-index button').waitFor(); await until(painted, 'Expiring message is drawn');
  await until(async () => await p.locator('#constellation-panel').isHidden(), 'Expiry hides constellation');
  assert.equal(await painted(), false, 'Expiry clears pixels');
  assert.equal(await p.locator('#signal-index').textContent(), '');

  const closed = await context.request.delete(base + '/api/room?room=' + event.room.id, { headers: { 'X-Room-Key': event.access_key, 'X-Moderator-Key': event.owner_key } });
  assert.equal(closed.status(), 200);
  assert.deepEqual(errors, []);
  console.log('Browser reading/lifecycle regressions passed.');
} finally { releaseResponses.forEach(release => release()); await browser.close(); }
