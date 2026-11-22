import assert from 'node:assert/strict';
import { chromium } from 'playwright';
import AxeBuilder from '@axe-core/playwright';
import { mkdir } from 'node:fs/promises';
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
  const goRoom = async room => {
    await p.evaluate(room => { history.pushState(null, '', location.pathname + '?room=' + room); dispatchEvent(new PopStateEvent('popstate')); }, room);
    await live();
  };
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

  // Reading mode must retain every draft field and restore writing from each entry point.
  const normalWidth = await p.locator('.stream-section').evaluate(n => n.getBoundingClientRect().width);
  await p.locator('#content-input').fill('A private in-memory draft');
  await p.locator('#kind-input').selectOption('poll');
  await p.locator('#poll-options').fill('Keep it\nImprove it');
  await p.locator('[data-ttl="60000"]').click();
  await p.locator('#focus-btn').click();
  assert(await p.locator('.composer').isHidden());
  assert(await p.locator('.stream-section').evaluate(n => n.getBoundingClientRect().width) > normalWidth + 100, 'Reading widens the conversation while keeping a readable line length');
  await p.keyboard.press('n');
  assert(await p.locator('#content-input').evaluate(n => n === document.activeElement), 'N restores and focuses writing');
  assert.equal(await p.locator('#content-input').inputValue(), 'A private in-memory draft');
  assert.equal(await p.locator('#poll-options').inputValue(), 'Keep it\nImprove it');
  assert.equal(await p.locator('#kind-input').inputValue(), 'poll');
  assert.equal(await p.locator('[data-ttl="60000"]').getAttribute('aria-pressed'), 'true');
  await p.locator('#focus-btn').click();
  await card('Second lifecycle fixture').getByRole('button', { name: 'Reply', exact: true }).click();
  assert(await p.locator('.composer').isVisible(), 'Reply restores writing');
  assert.equal(await p.locator('#reply-preview').textContent(), 'Second lifecycle fixture');
  assert.equal(await p.locator('#content-input').inputValue(), 'A private in-memory draft');
  await p.locator('#cancel-reply').click();
  await p.locator('#focus-btn').click();
  await p.locator('#reading-compose-btn').click();
  assert(await p.locator('#content-input').evaluate(n => n === document.activeElement));
  await p.setViewportSize({ width: 390, height: 500 });
  await p.locator('#focus-btn').click();
  await p.locator('.stream-foot').scrollIntoViewIfNeeded();
  await p.locator('#mobile-compose-btn').click();
  assert(await p.locator('.composer').isVisible(), 'Mobile shortcut restores writing');
  assert.equal(await p.locator('#poll-options').inputValue(), 'Keep it\nImprove it');
  await p.locator('#clear-draft-btn').click();
  await p.locator('#kind-input').selectOption('thought');
  await p.setViewportSize({ width: 1440, height: 1000 });
  await post('A message that stays visible');

  // Hiding is reversible while other messages remain, and never crosses rooms.
  await card('Second lifecycle fixture').getByRole('button', { name: 'Hide', exact: true }).click();
  assert(await p.locator('#hidden-notice').isVisible());
  assert.equal(await p.locator('#feed .message-card').count(), 1);
  assert.equal(await p.locator('#hidden-count').textContent(), 'Hidden in this room: 1');
  await p.locator('#undo-hide').click(); await card('Second lifecycle fixture').waitFor();
  assert(await p.locator('#hidden-notice').isHidden());
  await card('Second lifecycle fixture').getByRole('button', { name: 'Hide', exact: true }).click();
  await card('A message that stays visible').getByRole('button', { name: 'Hide', exact: true }).click();
  await p.locator('#undo-hide').click(); await card('A message that stays visible').waitFor();
  assert.equal(await card('Second lifecycle fixture').count(), 0, 'Undo restores only the most recent hide');
  const otherRoom = 'read-other-' + Date.now();
  await goRoom(otherRoom);
  assert(await p.locator('#hidden-notice').isHidden());
  assert.equal(await p.locator('#empty-action').textContent(), 'Write a message', 'Other-room hides do not change an empty room');
  await p.locator('#focus-btn').click(); await p.locator('#empty-action').click();
  assert(await p.locator('.composer').isVisible(), 'Empty-state writing restores the composer');
  await post('Another room fixture');
  await card('Another room fixture').getByRole('button', { name: 'Hide', exact: true }).click();
  await goRoom(event.room.id);
  assert.equal(await card('Second lifecycle fixture').count(), 0, 'Room navigation preserves that room\'s hidden choice');
  await p.locator('#restore-hidden').click(); await card('Second lifecycle fixture').waitFor();
  await goRoom(otherRoom);
  assert.equal(await p.locator('#feed .message-card').count(), 0, 'Restoring room A never restores room B');
  assert.equal(await p.locator('#empty-action').textContent(), 'Show hidden messages');
  await p.locator('#empty-action').click(); await card('Another room fixture').waitFor();
  await goRoom(event.room.id);
  await card('Second lifecycle fixture').getByRole('button', { name: 'Hide', exact: true }).click();

  await mkdir('test-results', { recursive: true });
  await p.locator('#focus-btn').click();
  for (const [width, height, language, theme] of [[1440,1000,'en','dark'],[320,844,'ro','dark'],[390,844,'ro','light'],[768,844,'en','light'],[568,320,'ro','light']]) {
    await p.setViewportSize({ width, height });
    await p.locator('#language-input').selectOption(language);
    if (await p.locator('html').getAttribute('data-theme') !== theme) await p.locator(width <= 640 ? '#mobile-theme-btn' : '#theme-btn').click();
    await p.waitForTimeout(250);
    assert.equal(await p.evaluate(() => document.documentElement.scrollWidth > innerWidth), false, 'Reading/hidden controls fit at ' + width);
    const result = await new AxeBuilder({ page: p }).withTags(['wcag2a','wcag2aa','wcag21aa']).analyze();
    assert.deepEqual(result.violations.map(v => ({ id: v.id, nodes: v.nodes.map(n => n.target) })), [], 'Accessible reading view ' + width);
    if (language === 'ro') {
      assert.equal(await p.locator('#hidden-count').textContent(), 'Ascunse în această cameră: 1');
      assert.equal(await p.locator('#reading-controls > span').textContent(), 'Mod de citire');
    }
    if (width === 1440 || width === 390) await p.screenshot({ path: 'test-results/reading-' + width + '.png', fullPage: true });
  }
  await p.locator('#language-input').selectOption('en');
  await p.setViewportSize({ width: 1440, height: 1000 });
  await p.locator('#reading-compose-btn').click();
  await p.locator('#restore-hidden').click();
  assert.deepEqual(await p.evaluate(() => Object.keys(localStorage).filter(k => !['spectre:theme','spectre:view','spectre:motion','spectre:language'].includes(k))), []);
  assert.equal(await p.evaluate(() => sessionStorage.length), 0, 'No content, hide state or capabilities enter browser storage');
  console.log('Reading, draft entry points, room-scoped hide/undo and responsive accessibility passed.');

  await p.locator('[data-view="constellation"]').click();
  await until(painted, 'Remaining message is drawn');
  await goRoom('read-empty-' + Date.now());
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

  await p.locator('[data-view="feed"]').click();
  const hiddenExpiry = await context.request.post(base + '/api/messages', { data: { room: expiryRoom, content: 'A short hidden fixture', ttl: 4000, kind: 'thought' } });
  assert.equal(hiddenExpiry.status(), 201);
  await card('A short hidden fixture').getByRole('button', { name: 'Hide', exact: true }).click();
  await p.locator('#hidden-notice').waitFor();
  await until(async () => await p.locator('#hidden-notice').isHidden(), 'Expired hidden entries lose their restore controls');
  await p.evaluate(() => document.querySelector('#restore-hidden').click());
  assert.equal(await p.locator('#feed .message-card').count(), 0, 'Restore cannot revive an expired message');

  // Reload retained no owner keys; use the fixture's explicit private capabilities.
  await p.goto(base + '/?room=' + event.room.id + '#invite=' + event.access_key); await live();
  await p.locator('[data-view="constellation"]').click(); await until(painted, 'Live event paints before closure');
  const closed = await context.request.delete(base + '/api/room?room=' + event.room.id, { headers: { 'X-Room-Key': event.access_key, 'X-Moderator-Key': event.owner_key } });
  assert.equal(closed.status(), 200);
  await until(async () => await p.locator('#connection-text').textContent() === 'Room unavailable', 'Event closure reaches the reader');
  assert.equal(await painted(), false, 'Event closure clears pixels');
  assert.equal(await p.locator('#signal-index').textContent(), '');
  assert.deepEqual(errors, []);
  console.log('Browser reading/lifecycle regressions passed.');
} finally { releaseResponses.forEach(release => release()); await browser.close(); }
