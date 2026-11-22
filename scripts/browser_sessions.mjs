import { openRoomTool } from './browser_helpers.mjs';
import assert from 'node:assert/strict';
import { mkdir } from 'node:fs/promises';
import { chromium } from 'playwright';
import AxeBuilder from '@axe-core/playwright';

const base = process.env.BASE_URL || 'http://127.0.0.1:4400';
assert(['localhost', '127.0.0.1'].includes(new URL(base).hostname), 'Use an isolated server.');
const browser = await chromium.launch();
const errors = [];
async function axe(page, label) {
  const result = await new AxeBuilder({ page }).withTags(['wcag2a', 'wcag2aa', 'wcag21aa']).analyze();
  assert.deepEqual(result.violations.map(v => ({ id: v.id, nodes: v.nodes.map(n => n.target) })), [], label);
}
async function until(page, check, label, timeout = 8000) {
  const deadline = Date.now() + timeout;
  while (Date.now() < deadline) { if (await check()) return; await page.waitForTimeout(100); }
  assert.fail(label);
}
try {
  await mkdir('test-results', { recursive: true });
  const owner = await browser.newContext({ viewport: { width: 1440, height: 1000 } });
  const participant = await browser.newContext({ viewport: { width: 390, height: 844 } });
  await owner.setExtraHTTPHeaders({ 'X-Real-IP': 'session-owner-' + Date.now() });
  await participant.setExtraHTTPHeaders({ 'X-Real-IP': 'session-reader-' + Date.now() });
  const p = await owner.newPage(), q = await participant.newPage();
  for (const page of [p, q]) {
    page.on('pageerror', e => errors.push(e.message));
    page.on('console', m => { if (m.type() === 'error' && /content security|refused|uncaught/i.test(m.text())) errors.push(m.text()); });
  }
  await p.goto(base + '/?room=session-' + Date.now());
  await p.locator('#connection-text').filter({ hasText: 'Live now' }).waitFor();
  await p.locator('#new-room-btn').click();
  await p.locator('#room-input').fill('A live workshop');
  await p.locator('#room-encrypted').check();
  const creation = p.waitForResponse(r => new URL(r.url()).pathname === '/api/rooms' && r.request().method() === 'POST');
  await p.locator('#room-form button[type=submit]').click();
  const event = await (await creation).json();
  await p.locator('#room-settings-btn:not([hidden])').waitFor({ state: 'attached' });
  await p.locator('#share-room-btn').click();
  const invite = await p.locator('#share-url').inputValue();
  const key = new URLSearchParams(new URL(invite).hash.slice(1)).get('key');
  await p.keyboard.press('Escape');
  await q.goto(invite);
  await q.locator('#connection-text').filter({ hasText: 'Live now' }).waitFor();
  const question = 'What should we make better? <script>untrusted()</script>';
  await q.locator('#content-input').fill(question);
  await q.locator('#kind-input').selectOption('question');
  await q.locator('[data-ttl="300000"]').click();
  await q.locator('#send-btn').click();
  const questionCard = page => page.locator('#feed .message-card').filter({ has: page.locator('.message-content').filter({ hasText: question }) });
  await questionCard(p).waitFor();
  assert.equal(await questionCard(q).getByRole('button', { name: 'Spotlight', exact: true }).count(), 0, 'Creator is not a room moderator');
  await questionCard(p).getByRole('button', { name: 'Spotlight', exact: true }).click();
  await q.locator('#spotlight-preview').filter({ hasText: question }).waitFor();
  await q.locator('[data-filter="unanswered"]').click();
  await questionCard(q).getByRole('button', { name: 'Mark resolved', exact: true }).click();
  await until(q, async () => await q.locator('#feed .message-card').count() === 0, 'Creator resolves their question');
  await questionCard(p).getByText('Resolved', { exact: true }).waitFor();
  await q.locator('[data-filter="all"]').click();
  await questionCard(q).getByRole('button', { name: 'Reopen question', exact: true }).click();
  await questionCard(p).getByRole('button', { name: 'Mark resolved', exact: true }).waitFor();

  await p.locator('#content-input').fill('Pick a direction');
  await p.locator('#kind-input').selectOption('poll');
  await p.locator('#poll-options').fill('Build\nExplore');
  await p.locator('[data-ttl="300000"]').click();
  const sending = p.waitForResponse(r => new URL(r.url()).pathname === '/api/messages' && r.request().method() === 'POST');
  await p.locator('#send-btn').click();
  const response = await sending;
  assert(!response.request().postData().includes('Pick a direction'), 'Poll text stays encrypted');
  const pollResult = await response.json();
  const pollCard = page => page.locator('#feed .message-card').filter({ has: page.locator('.message-content').filter({ hasText: 'Pick a direction' }) });
  await pollCard(q).waitFor();
  await pollCard(q).locator('button.poll-choice').first().click();
  await pollCard(p).getByText('Votes: 1', { exact: true }).waitFor();
  await pollCard(p).getByRole('button', { name: 'Close voting', exact: true }).click();
  await pollCard(q).getByText('Poll closed', { exact: true }).waitFor();
  assert(await pollCard(q).locator('button.poll-choice').first().isDisabled());
  const stale = await participant.request.post(base + '/api/messages/' + pollResult.id + '/vote?room=' + event.room.id, {
    data: { option: 1 }, headers: { 'X-Room-Key': event.access_key, 'X-Spectre-Client': '7'.repeat(48) },
  });
  assert.equal(stale.status(), 409, 'A stale client cannot vote in a closed poll');
  await pollCard(p).getByRole('button', { name: 'Reopen voting', exact: true }).click();
  await until(q, async () => await pollCard(q).locator('button.poll-choice').last().isEnabled(), 'Reopen propagates');
  await pollCard(q).locator('button.poll-choice').last().click();
  await until(q, async () => await pollCard(q).locator('.poll-bar').first().evaluate(node => node.value) === 0, 'Previous option drops to zero');
  await q.waitForTimeout(700);
  assert.equal(await pollCard(q).locator('.poll-bar').first().evaluate(node => node.value), 0, 'Lifetime ticks do not corrupt poll bars');

  await openRoomTool(p, '#present-btn');
  await p.locator('#presentation-dialog[open]').waitFor();
  assert.equal(await p.locator('#presentation-message .message-content').textContent(), question, 'Spotlight opens first');
  assert.equal(await p.locator('#presentation-message .message-tools, #presentation-message .card-footer').count(), 0);
  await p.locator('#presentation-next').focus();
  await p.keyboard.press('ArrowRight');
  await p.locator('#presentation-message .message-content').filter({ hasText: 'Pick a direction' }).waitFor();
  assert.equal(await p.locator('#presentation-message button.poll-choice').count(), 0, 'Presentation poll is read-only');
  assert.equal(await p.locator('#presentation-message div.poll-choice').count(), 2);
  await axe(p, 'Desktop presentation');
  await p.locator('#presentation-dialog').screenshot({ path: 'test-results/session-presentation-desktop.png' });
  await p.keyboard.press('Escape');

  await q.locator('#language-input').selectOption('ro');
  await openRoomTool(q, '#present-btn');
  for (const width of [320, 390, 768]) {
    await q.setViewportSize({ width, height: 844 });
    assert.equal(await q.evaluate(() => document.documentElement.scrollWidth > innerWidth), false, 'No page overflow at ' + width);
    assert.equal(await q.locator('#presentation-dialog').evaluate(node => node.scrollWidth > node.clientWidth), false, 'No dialog overflow at ' + width);
  }
  for (const [width, height] of [[568, 320], [844, 390]]) {
    await q.setViewportSize({ width, height });
    assert.equal(await q.locator('#presentation-dialog').evaluate(node => node.scrollWidth > node.clientWidth), false, 'No landscape overflow');
    assert(await q.locator('#presentation-message').evaluate(node => node.getBoundingClientRect().height >= 180), 'Landscape preserves a readable message area');
    await q.locator('#presentation-spotlight').scrollIntoViewIfNeeded();
    assert(await q.locator('#presentation-spotlight').isVisible(), 'Landscape navigation remains reachable');
  }
  await q.setViewportSize({ width: 390, height: 844 });
  await q.locator('#presentation-dialog').evaluate(node => { node.scrollTop = 0; });
  await q.locator('#presentation-filter').selectOption('poll');
  await q.locator('#presentation-position').filter({ hasText: '1 din 1' }).waitFor();
  await axe(q, 'Romanian dark mobile presentation');
  await q.keyboard.press('Escape');
  await q.locator('#mobile-theme-btn').click();
  await openRoomTool(q, '#present-btn');
  await axe(q, 'Romanian light mobile presentation');
  await q.locator('#presentation-dialog').screenshot({ path: 'test-results/session-presentation-mobile.png' });
  await questionCard(p).getByRole('button', { name: 'Remove', exact: true }).click();
  await q.locator('#presentation-message .message-content').filter({ hasText: 'Pick a direction' }).waitFor();
  assert.equal(await q.locator('#spotlight-preview').textContent(), '', 'Burn clears spotlight copy');
  assert(!(await q.locator('#presentation-message').textContent()).includes(question));
  await q.keyboard.press('Escape');
  await pollCard(q).getByRole('button', { name: 'Ascunde', exact: true }).click();
  await openRoomTool(q, '#present-btn');
  await q.locator('#presentation-empty:not([hidden])').waitFor();
  assert.equal(await q.locator('#presentation-message').textContent(), '', 'Local hide applies in presentation');
  await q.keyboard.press('Escape');
  await q.locator('#empty-action').click();

  const shortContent = 'The expired spotlight must disappear';
  const envelope = await p.evaluate(async ({ key, room, content }) => window.SpectreCrypto.encrypt({ room, content, ttl: 3000, kind: 'thought', parent_id: '', options: [], author: '' }, key), { key, room: event.room.id, content: shortContent });
  const shortResponse = await owner.request.post(base + '/api/messages', { data: envelope, headers: { 'X-Room-Key': event.access_key } });
  assert.equal(shortResponse.status(), 201);
  const short = await shortResponse.json();
  const pinned = await owner.request.post(base + '/api/spotlight?room=' + event.room.id, { data: { message_id: short.id }, headers: { 'X-Room-Key': event.access_key, 'X-Moderator-Key': event.owner_key } });
  assert(pinned.ok());
  await q.locator('#spotlight-preview').filter({ hasText: shortContent }).waitFor();
  await openRoomTool(q, '#present-btn');
  await q.locator('#presentation-message .message-content').filter({ hasText: shortContent }).waitFor();
  await q.locator('#spotlight-banner').waitFor({ state: 'hidden', timeout: 6000 });
  assert.equal(await q.locator('#spotlight-preview').textContent(), '');
  assert(!(await q.locator('#presentation-message').textContent()).includes(shortContent), 'Expiry clears presentation copy');
  await q.evaluate(() => document.querySelector('[data-room="ideas"]').click());
  assert.equal(await q.locator('#presentation-message').textContent(), '', 'Navigation clears presentation');
  assert.equal(await q.locator('#presentation-dialog').evaluate(node => node.open), false);
  await q.goBack();
  await q.locator('#connection-text').filter({ hasText: 'Live acum' }).waitFor();
  await openRoomTool(q, '#present-btn');
  await openRoomTool(p, '#close-room-btn');
  await p.locator('#confirm-close-room').click();
  await q.locator('#room-locked:not([hidden])').waitFor();
  assert.equal(await q.locator('#presentation-dialog').evaluate(node => node.open), false);
  assert.equal(await q.locator('#presentation-message').textContent(), '');
  assert.deepEqual(errors, []);
  console.log('Session browsers passed: encrypted spotlight, creator resolution, poll freeze/reopen, read-only keyboard presentation, RO/themes/mobile/axe, expiry/hide/burn/navigation/closure cleanup.');
} finally { await browser.close(); }
