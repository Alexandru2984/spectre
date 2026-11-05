'use strict';
(() => {
  const $ = (selector, root = document) => root.querySelector(selector);
  const $$ = (selector, root = document) => [...root.querySelectorAll(selector)];
  const iconsPath = '/static/icons.svg#';
  const roomPattern = /^[a-z0-9][a-z0-9-]{0,31}(?![\s\S])/;
  const knownRooms = { lobby: 'The lobby', ideas: 'Bright ideas', questions: 'Open questions', 'after-hours': 'After hours' };
  const kinds = { thought: ['A thought', 'spark'], idea: ['An idea', 'bulb'], question: ['A question', 'question'] };
  const reactionNames = { spark: 'Inspired', heart: 'Love', curious: 'Curious' };
  const state = {
    room: 'lobby', messages: [], burnKeys: new Map(), myReactions: new Map(),
    ttl: 30000, filter: 'all', view: 'feed', paused: false, failures: 0,
    clockOffset: 0, timer: null, toastTimer: null, syncing: false, generation: 0,
    controller: null, signature: '', selectedId: null, burnId: null,
    pending: new Set(), hits: [], animation: null, canvasWidth: 0, canvasHeight: 0,
    motion: !window.matchMedia('(prefers-reduced-motion: reduce)').matches,
  };
  const canvas = $('#constellation');
  const ctx = canvas.getContext('2d');
  let clientToken;
  try {
    clientToken = [...crypto.getRandomValues(new Uint8Array(24))].map(n => n.toString(16).padStart(2, '0')).join('');
  } catch {
    feedback('This browser cannot create secure reaction tokens. You can still read and post.', true);
  }
  function preference(name, value) {
    try {
      if (value === undefined) return localStorage.getItem('spectre:' + name);
      localStorage.setItem('spectre:' + name, value);
    } catch { /* Appearance preferences are optional. */ }
  }
  function element(tag, className, text) {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text !== undefined) node.textContent = text;
    return node;
  }
  function icon(name) {
    const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    svg.classList.add('icon');
    svg.setAttribute('aria-hidden', 'true');
    const use = document.createElementNS(svg.namespaceURI, 'use');
    use.setAttribute('href', iconsPath + name);
    svg.append(use);
    return svg;
  }
  function setButtonIcon(button, name) {
    const svg = $('svg', button);
    if (svg) svg.replaceWith(icon(name));
  }
  function toast(message) {
    const node = $('#toast');
    $('span', node).textContent = message;
    node.hidden = false;
    clearTimeout(state.toastTimer);
    state.toastTimer = setTimeout(() => { node.hidden = true; }, 3500);
  }
  function feedback(message, error = false) {
    const node = $('#compose-feedback');
    node.textContent = message;
    node.classList.toggle('error', error);
  }
  function now() { return Date.now() + state.clockOffset; }
  function timeLeft(message) { return Math.max(0, message.expires_at - now()); }
  function formatTime(milliseconds) {
    const seconds = Math.ceil(milliseconds / 1000);
    return seconds >= 60 ? Math.floor(seconds / 60) + 'm ' + (seconds % 60 ? seconds % 60 + 's' : '') : seconds + 's';
  }
  function connection(status, text) {
    $('#connection').dataset.state = status;
    $('#connection-text').textContent = text;
  }
  function showDialog(id) {
    const dialog = $(id);
    if (!dialog.open) dialog.showModal();
  }
  function setTheme(theme) {
    document.documentElement.dataset.theme = theme;
    $('#theme-btn').setAttribute('aria-label', 'Switch to ' + (theme === 'dark' ? 'light' : 'dark') + ' theme');
    setButtonIcon($('#theme-btn'), theme === 'dark' ? 'sun' : 'moon');
    const mobile = $('#mobile-theme-btn');
    if (mobile) { mobile.setAttribute('aria-label', $('#theme-btn').getAttribute('aria-label')); setButtonIcon(mobile, theme === 'dark' ? 'sun' : 'moon'); }
    $('meta[name="theme-color"]').setAttribute('content', theme === 'dark' ? '#101412' : '#f7f8f2');
    drawCanvas();
  }
  setTheme(preference('theme') === 'light' ? 'light' : 'dark');
  $('#theme-btn').addEventListener('click', () => {
    const theme = document.documentElement.dataset.theme === 'dark' ? 'light' : 'dark';
    setTheme(theme); preference('theme', theme);
  });
  // Keep theme control available on small screens without a second tab stop.
  const mobileTheme = $('#theme-btn').cloneNode(true);
  mobileTheme.id = 'mobile-theme-btn';
  mobileTheme.classList.add('mobile-help');
  $('.topbar-actions').insertBefore(mobileTheme, $('#mobile-help-btn'));
  mobileTheme.addEventListener('click', () => {
    $('#theme-btn').click();
    mobileTheme.setAttribute('aria-label', $('#theme-btn').getAttribute('aria-label'));
    setButtonIcon(mobileTheme, document.documentElement.dataset.theme === 'dark' ? 'sun' : 'moon');
  });

  $$('#help-btn, #mobile-help-btn, #privacy-btn').forEach(button => button.addEventListener('click', () => showDialog('#help-dialog')));
  $('#shortcuts-btn').addEventListener('click', () => showDialog('#shortcuts-dialog'));
  $$('[data-close]').forEach(button => button.addEventListener('click', () => button.closest('dialog').close()));
  $$('dialog').forEach(dialog => dialog.addEventListener('click', event => {
    if (event.target !== dialog) return;
    const rect = dialog.getBoundingClientRect();
    if (event.clientX < rect.left || event.clientX > rect.right || event.clientY < rect.top || event.clientY > rect.bottom) dialog.close();
  }));
  $('#message-dialog').addEventListener('close', () => { state.selectedId = null; $('#message-detail').replaceChildren(); });
  $('#new-room-btn').addEventListener('click', () => { $('#room-input').value = ''; showDialog('#room-dialog'); });
  $('#room-form').addEventListener('submit', event => {
    event.preventDefault();
    const input = $('#room-input');
    const room = input.value.trim();
    if (!roomPattern.test(room)) { input.reportValidity(); return; }
    $('#room-dialog').close();
    changeRoom(room, true);
    toast('Your space is open. Share its link to bring people in.');
  });
  $('#room-input').addEventListener('input', event => {
    event.target.value = event.target.value.toLowerCase().replace(/\s+/g, '-');
  });
  $('.room-nav').addEventListener('click', event => {
    const link = event.target.closest('[data-room]');
    if (!link || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
    event.preventDefault(); changeRoom(link.dataset.room, true);
  });
  window.addEventListener('popstate', () => changeRoom(new URLSearchParams(location.search).get('room') || 'lobby'));
  async function copyText(text, success) {
    try { await navigator.clipboard.writeText(text); toast(success); }
    catch { toast('Clipboard unavailable. Select and copy the text or address manually.'); }
  }
  $('#share-room-btn').addEventListener('click', () => {
    const url = new URL('/', location.origin); url.searchParams.set('room', state.room);
    copyText(url.href, 'Room link copied. Everyone with the link can read this public room.');
  });
  function changeRoom(room, push = false) {
    if (!roomPattern.test(room)) { toast('That room name is invalid. Welcome to the lobby.'); room = 'lobby'; }
    state.generation++;
    state.controller?.abort();
    clearTimeout(state.timer);
    state.syncing = false;
    state.room = room;
    state.messages = [];
    state.selectedId = null;
    state.failures = 0;
    state.signature = '';
    state.filter = 'all';
    $('#search-input').value = '';
    $('#content-input').value = '';
    updateCharacterCount();
    feedback('');
    $$('dialog[open]').forEach(dialog => dialog.close());
    state.burnId = null;
    const custom = $('#custom-room-link');
    custom.hidden = Object.hasOwn(knownRooms, room);
    custom.dataset.room = room;
    custom.href = '/?room=' + encodeURIComponent(room);
    $('span', custom).textContent = room;
    $$('.room-link[data-room]').forEach(link => {
      const active = link.dataset.room === room;
      link.classList.toggle('active', active);
      if (active) link.setAttribute('aria-current', 'page'); else link.removeAttribute('aria-current');
    });
    const name = knownRooms[room] || '#' + room;
    $('#room-crumb').textContent = name.toLowerCase();
    $('#room-label').textContent = name;
    document.title = room === 'lobby' && !new URLSearchParams(location.search).has('room') ? 'Spectre — live, ephemeral messages for the moment' : name + ' · Spectre';
    $('#kind-input').value = room === 'ideas' ? 'idea' : room === 'questions' ? 'question' : 'thought';
    $$('[data-filter]').forEach(button => button.setAttribute('aria-pressed', button.dataset.filter === 'all'));
    if (push) { const url = new URL(location.href); url.search = ''; url.searchParams.set('room', room); url.hash = ''; history.pushState(null, '', url); }
    $('#offline-banner').hidden = true;
    connection('', state.paused ? 'Paused' : 'Connecting');
    render();
    if (!state.paused) syncRoom();
  }

  function apiPath(suffix = '') { return '/api/messages' + suffix + '?room=' + encodeURIComponent(state.room); }
  class ApiError extends Error {
    constructor(message, status, retryAfter) { super(message); this.status = status; this.retryAfter = retryAfter; }
  }
  async function api(path, options = {}) {
    const response = await fetch(path, { cache: 'no-store', credentials: 'omit', ...options });
    const data = await response.json().catch(() => ({}));
    if (!response.ok) {
      const delay = Math.min(120, Math.max(1, Number(response.headers.get('retry-after')) || 5));
      const detail = data.error || (response.status === 429 ? 'Too many requests. Give it a moment.' : 'The server could not complete that request.');
      throw new ApiError(detail, response.status, delay);
    }
    return { data, response };
  }
  function schedule(delay = 4000) {
    clearTimeout(state.timer);
    if (!state.paused && !document.hidden) state.timer = setTimeout(syncRoom, delay);
  }
  function validMessage(message) {
    return message && typeof message.id === 'string' && typeof message.content === 'string'
      && Object.hasOwn(kinds, message.kind) && message.room === state.room
      && Number.isFinite(message.expires_at) && Number.isFinite(message.created_at)
      && Number.isFinite(message.ttl_ms) && message.reactions && typeof message.reactions === 'object';
  }
  async function syncRoom() {
    if (state.syncing || state.paused || document.hidden) return;
    clearTimeout(state.timer);
    state.syncing = true;
    const generation = state.generation;
    const controller = new AbortController();
    state.controller = controller;
    const timeout = setTimeout(() => controller.abort(), 10000);
    let delay = 4000;
    try {
      const started = Date.now();
      const { data, response } = await api(apiPath(), { signal: controller.signal });
      if (generation !== state.generation) return;
      if (!Array.isArray(data)) throw new Error('Invalid server response.');
      const serverTime = Number(response.headers.get('x-server-time'));
      if (serverTime > 0) state.clockOffset = serverTime - (started + Date.now()) / 2;
      state.messages = data.filter(validMessage).filter(message => timeLeft(message) > 0);
      state.failures = 0;
      connection('live', 'Live now');
      $('#offline-banner').hidden = true;
      $('#sync-label').textContent = 'Live updates · every 4 seconds';
      cleanCapabilities();
      render();
    } catch (error) {
      if (generation !== state.generation || state.paused) return;
      state.failures++;
      delay = error.status === 429 ? error.retryAfter * 1000 : Math.min(60000, 4000 * 2 ** Math.min(state.failures, 4));
      connection('error', navigator.onLine ? 'Reconnecting' : 'Offline');
      $('#offline-banner').hidden = false;
      $('#sync-label').textContent = error.status === 429 ? 'Taking a breather · retrying shortly' : 'Reconnecting · your draft stays here';
    } finally {
      clearTimeout(timeout);
      if (generation === state.generation) { state.syncing = false; schedule(delay); }
    }
  }
  function cleanCapabilities() {
    const timestamp = now();
    for (const [id, capability] of state.burnKeys) if (capability.expires <= timestamp) state.burnKeys.delete(id);
    for (const [id, reaction] of state.myReactions) if (reaction.expires <= timestamp) state.myReactions.delete(id);
  }
  $('#retry-btn').addEventListener('click', syncRoom);
  window.addEventListener('online', syncRoom);
  window.addEventListener('offline', () => { connection('error', 'Offline'); $('#offline-banner').hidden = false; });
  document.addEventListener('visibilitychange', () => {
    clearTimeout(state.timer);
    if (document.hidden) stopAnimation(); else { syncRoom(); startAnimation(); }
  });
  $('#pause-btn').addEventListener('click', () => {
    state.paused = !state.paused;
    $('#pause-btn').setAttribute('aria-pressed', state.paused);
    $('#pause-btn').setAttribute('aria-label', state.paused ? 'Resume live updates' : 'Pause live updates');
    setButtonIcon($('#pause-btn'), state.paused ? 'play' : 'pause');
    if (state.paused) {
      clearTimeout(state.timer); state.controller?.abort();
      connection('paused', 'Paused'); $('#sync-label').textContent = 'Updates paused · countdowns keep running';
    } else syncRoom();
  });

  function updateCharacterCount() {
    const count = $('#content-input').value.length;
    $('#character-count').textContent = count + ' / 500';
    $('#character-count').classList.toggle('near-limit', count > 450);
  }
  $('#content-input').addEventListener('input', updateCharacterCount);
  $$('[data-ttl]').forEach(button => button.addEventListener('click', () => {
    state.ttl = Number(button.dataset.ttl);
    $$('[data-ttl]').forEach(item => item.setAttribute('aria-pressed', item === button));
  }));
  $('#message-form').addEventListener('submit', async event => {
    event.preventDefault();
    if ($('#send-btn').disabled) return;
    const input = $('#content-input');
    const content = input.value.trim();
    if (!content) { feedback('Give your thought a few words first.', true); input.focus(); return; }
    if (new TextEncoder().encode(content).length > 2000) { feedback('That thought is a little too large. Keep it under 2000 UTF-8 bytes.', true); return; }
    const room = state.room;
    const generation = state.generation;
    $('#send-btn').disabled = true;
    feedback('Leaving your thought…');
    try {
      const { data } = await api('/api/messages', {
        method: 'POST', headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ content, ttl: state.ttl, room, kind: $('#kind-input').value }),
        signal: AbortSignal.timeout(10000),
      });
      if (data.message && data.burn_key) state.burnKeys.set(data.id, { key: data.burn_key, expires: data.message.expires_at });
      if (generation !== state.generation) { toast('Your thought was sent to #' + room + '.'); return; }
      if (input.value.trim() === content) input.value = '';
      updateCharacterCount();
      feedback('It’s here. For a little while.');
      if (validMessage(data.message)) { state.messages = [...state.messages.filter(message => message.id !== data.id), data.message]; render(); }
      toast('Thought shared. Let the moment happen.');
      if (!state.paused) syncRoom();
    } catch (error) {
      if (generation === state.generation) feedback(error.status ? error.message + (error.status === 429 ? ' Try again in ' + error.retryAfter + 's.' : '') : 'We couldn’t confirm the send. Your draft is kept; check the room before retrying.', true);
    } finally { $('#send-btn').disabled = false; }
  });
  const prompts = {
    small: ['thought', 'A small thing that made today better: '],
    idea: ['idea', 'What if we tried '],
    question: ['question', 'One question I’ve been sitting with: '],
  };
  $$('[data-prompt]').forEach(button => button.addEventListener('click', () => {
    const [kind, prompt] = prompts[button.dataset.prompt];
    if ($('#content-input').value.trim()) { $('#content-input').focus(); return; }
    $('#kind-input').value = kind; $('#content-input').value = prompt;
    updateCharacterCount(); $('#content-input').focus();
  }));
  $('#empty-action').addEventListener('click', () => {
    if (state.filter !== 'all' || $('#search-input').value) {
      state.filter = 'all'; $('#search-input').value = '';
      $$('[data-filter]').forEach(button => button.setAttribute('aria-pressed', button.dataset.filter === 'all'));
      render();
    } else $('#content-input').focus();
  });
  $$('[data-filter]').forEach(button => button.addEventListener('click', () => {
    state.filter = button.dataset.filter;
    $$('[data-filter]').forEach(item => item.setAttribute('aria-pressed', item === button)); render();
  }));
  $('#search-input').addEventListener('input', () => render());
  $('#sort-input').addEventListener('change', () => render());
  function setView(view) {
    state.view = view === 'constellation' ? 'constellation' : 'feed';
    $$('[data-view]').forEach(button => button.setAttribute('aria-pressed', button.dataset.view === state.view));
    state.signature = ''; render();
    if (state.view === 'constellation') { resizeCanvas(); startAnimation(); } else stopAnimation();
  }
  $$('[data-view]').forEach(button => button.addEventListener('click', () => { setView(button.dataset.view); preference('view', state.view); }));
  function reactionCount(message) { return Object.keys(reactionNames).reduce((sum, key) => sum + (Number(message.reactions[key]) || 0), 0); }
  function visibleMessages() {
    const query = $('#search-input').value.trim().toLocaleLowerCase();
    const sort = $('#sort-input').value;
    return state.messages.filter(message => timeLeft(message) > 0)
      .filter(message => state.filter === 'all' || (state.filter === 'mine' ? state.burnKeys.has(message.id) : message.kind === state.filter))
      .filter(message => !query || message.content.toLocaleLowerCase().includes(query))
      .sort((a, b) => (sort === 'expiring' ? a.expires_at - b.expires_at : sort === 'reactions' ? reactionCount(b) - reactionCount(a) : b.created_at - a.created_at) || a.id.localeCompare(b.id));
  }
  function buildCard(message, detail = false) {
    const card = element('article', 'message-card');
    card.dataset.messageId = message.id;
    const header = element('div', 'card-top');
    const [label, kindIcon] = kinds[message.kind];
    const tag = element('span', 'kind-tag ' + message.kind);
    tag.append(icon(kindIcon), document.createTextNode(label)); header.append(tag);
    if (state.burnKeys.has(message.id)) header.append(element('span', 'owner-badge', 'You'));
    const age = element('time', 'card-age', 'just now');
    age.dateTime = new Date(message.created_at).toISOString(); age.title = new Date(message.created_at).toLocaleTimeString(); header.append(age);
    const content = element('p', 'message-content', message.content);
    const lifetime = element('div', 'card-lifetime');
    const progress = element('progress'); progress.max = message.ttl_ms; progress.value = timeLeft(message);
    progress.setAttribute('aria-label', 'Message lifetime remaining');
    const countdown = element('span', 'countdown', formatTime(timeLeft(message)) + ' left');
    lifetime.append(progress, countdown);
    const footer = element('div', 'card-footer');
    const reactions = element('div', 'reactions'); reactions.setAttribute('role', 'group'); reactions.setAttribute('aria-label', 'Reactions');
    for (const [key, name] of Object.entries(reactionNames)) {
      const count = Number(message.reactions[key]) || 0;
      const button = element('button', 'reaction'); button.type = 'button';
      button.append(icon(key), element('span', '', String(count)));
      button.setAttribute('aria-label', name + ': ' + count + '. Toggle reaction');
      button.setAttribute('aria-pressed', state.myReactions.get(message.id)?.emoji === key);
      button.dataset.focusKey = (detail ? 'detail-' : '') + message.id + '-' + key;
      button.disabled = !clientToken || state.pending.has(message.id);
      button.addEventListener('click', () => react(message, key)); reactions.append(button);
    }
    const actions = element('div', 'card-actions');
    const copy = element('button', 'icon-button'); copy.type = 'button'; copy.append(icon('copy')); copy.setAttribute('aria-label', 'Copy thought');
    copy.dataset.focusKey = (detail ? 'detail-' : '') + message.id + '-copy';
    copy.addEventListener('click', () => copyText(message.content, 'Thought copied. Keep it with care.')); actions.append(copy);
    if (state.burnKeys.has(message.id)) {
      const burn = element('button', 'icon-button burn-action'); burn.type = 'button'; burn.append(icon('flame')); burn.setAttribute('aria-label', 'Burn your message');
      burn.dataset.focusKey = (detail ? 'detail-' : '') + message.id + '-burn';
      burn.addEventListener('click', () => { state.burnId = message.id; showDialog('#burn-dialog'); }); actions.append(burn);
    }
    footer.append(reactions, actions); card.append(header, content, lifetime, footer);
    return card;
  }
  function render() {
    const messages = visibleMessages();
    const active = state.messages.filter(message => timeLeft(message) > 0).length;
    $('#active-count').textContent = active;
    $('#feed-count').textContent = messages.length;
    const noMatch = active > 0 || state.filter !== 'all' || Boolean($('#search-input').value);
    $('#empty-state').hidden = messages.length > 0;
    $('#empty-title').textContent = noMatch ? 'No thoughts in this corner. Yet.' : 'A little quiet. A lot of possibility.';
    $('#empty-description').textContent = noMatch ? 'Try another filter, clear your search, or start a new thought.' : 'Be the first to leave a thought. Sometimes that’s all it takes.';
    $('#empty-action').firstChild.textContent = noMatch ? 'Clear the filters ' : 'Start a little something';
    $('.starter-prompts').hidden = noMatch;
    $('#feed').hidden = state.view !== 'feed' || !messages.length;
    $('#constellation-panel').hidden = state.view !== 'constellation' || !messages.length;
    const signature = JSON.stringify([state.view, messages, [...state.pending], [...state.myReactions], [...state.burnKeys.keys()]]);
    if (signature !== state.signature) {
      state.signature = signature;
      const focused = document.activeElement?.dataset?.focusKey;
      if (state.view === 'feed') $('#feed').replaceChildren(...messages.map(message => buildCard(message)));
      else {
        $('#feed').replaceChildren();
        $('#signal-index').replaceChildren(...messages.slice(0, 40).map(message => {
          const button = element('button', '', message.content.slice(0, 24) + (message.content.length > 24 ? '…' : ''));
          button.type = 'button'; button.addEventListener('click', () => openMessage(message.id)); return button;
        }));
      }
      if (focused) $('[data-focus-key="' + CSS.escape(focused) + '"]')?.focus({ preventScroll: true });
      updateDetail();
    }
    tickCards();
    if (state.view === 'constellation') { resizeCanvas(); startAnimation(); drawCanvas(); }
  }
  async function react(message, emoji) {
    if (state.pending.has(message.id) || !clientToken) return;
    const generation = state.generation;
    const selected = state.myReactions.get(message.id)?.emoji;
    state.pending.add(message.id); render();
    try {
      const { data } = await api(apiPath('/' + encodeURIComponent(message.id) + '/reactions'), {
        method: 'POST', headers: { 'content-type': 'application/json', 'x-spectre-client': clientToken },
        body: JSON.stringify({ emoji }), signal: AbortSignal.timeout(10000),
      });
      if (selected === emoji) state.myReactions.delete(message.id); else state.myReactions.set(message.id, { emoji, expires: message.expires_at });
      if (generation !== state.generation) return;
      state.messages = state.messages.map(item => item.id === message.id && validMessage(data) ? data : item);
    } catch (error) { if (generation === state.generation) toast(error.status ? error.message : 'Reaction could not be confirmed. Refresh before retrying.'); }
    finally { state.pending.delete(message.id); render(); }
  }
  $('#confirm-burn').addEventListener('click', async () => {
    const id = state.burnId;
    const capability = state.burnKeys.get(id);
    if (!capability) { $('#burn-dialog').close(); toast('That message has already gone.'); return; }
    const generation = state.generation;
    $('#confirm-burn').disabled = true;
    try {
      await api(apiPath('/' + encodeURIComponent(id)), { method: 'DELETE', headers: { 'x-burn-key': capability.key }, signal: AbortSignal.timeout(10000) });
      state.burnKeys.delete(id);
      if (generation === state.generation) { state.messages = state.messages.filter(message => message.id !== id); render(); }
      $('#burn-dialog').close(); toast('Gone. A little space for the next thought.');
    } catch (error) { toast(error.status ? error.message : 'Couldn’t confirm the burn. Please try again.'); }
    finally { $('#confirm-burn').disabled = false; }
  });
  function tickCards() {
    $$('.message-card').forEach(card => {
      const message = state.messages.find(item => item.id === card.dataset.messageId);
      if (!message) return;
      const left = timeLeft(message);
      $('.countdown', card).textContent = formatTime(left) + ' left';
      $('progress', card).value = left;
      card.classList.toggle('expiring', left < 10000);
      const seconds = Math.max(0, Math.floor((now() - message.created_at) / 1000));
      $('.card-age', card).textContent = seconds < 10 ? 'just now' : seconds < 60 ? seconds + 's ago' : Math.floor(seconds / 60) + 'm ago';
    });
  }
  function openMessage(id) { state.selectedId = id; updateDetail(); if (state.messages.some(message => message.id === id)) showDialog('#message-dialog'); }
  function updateDetail() {
    if (!state.selectedId) return;
    const message = state.messages.find(item => item.id === state.selectedId && timeLeft(item) > 0);
    if (!message) {
      if ($('#message-dialog').open) { $('#message-dialog').close(); toast('That thought has drifted away.'); }
      state.selectedId = null; $('#message-detail').replaceChildren();
    } else {
      const focused = document.activeElement?.dataset?.focusKey;
      $('#message-detail').replaceChildren(buildCard(message, true));
      if (focused?.startsWith('detail-')) $('[data-focus-key="' + CSS.escape(focused) + '"]')?.focus({ preventScroll: true });
    }
  }
  setInterval(() => {
    const count = state.messages.length;
    state.messages = state.messages.filter(message => timeLeft(message) > 0);
    cleanCapabilities();
    if (count !== state.messages.length) render(); else tickCards();
  }, 500);

  // Canvas is decorative; the signal buttons provide the same entry points
  // for keyboard and assistive technology. No content becomes HTML.
  if (!ctx) {
    $('[data-view="constellation"]').disabled = true;
    $('[data-view="constellation"]').title = 'Canvas is unavailable in this browser.';
  }
  function resizeCanvas() {
    if (!ctx || $('#constellation-panel').hidden) return;
    const rect = canvas.getBoundingClientRect();
    if (!rect.width || !rect.height) return;
    const ratio = Math.min(window.devicePixelRatio || 1, 2);
    if (canvas.width !== Math.round(rect.width * ratio) || canvas.height !== Math.round(rect.height * ratio)) {
      canvas.width = Math.round(rect.width * ratio); canvas.height = Math.round(rect.height * ratio);
      ctx.setTransform(ratio, 0, 0, ratio, 0, 0);
    }
    state.canvasWidth = rect.width; state.canvasHeight = rect.height;
  }
  function drawCanvas(timestamp = performance.now()) {
    if (!ctx || state.view !== 'constellation' || $('#constellation-panel').hidden) return;
    const w = state.canvasWidth, h = state.canvasHeight;
    ctx.clearRect(0, 0, w, h);
    const theme = getComputedStyle(document.documentElement);
    const accent = theme.getPropertyValue('--accent').trim();
    const muted = theme.getPropertyValue('--muted').trim();
    const panel = theme.getPropertyValue('--panel').trim();
    const line = theme.getPropertyValue('--line').trim();
    const messages = visibleMessages().slice(0, 40);
    const t = state.motion ? timestamp / 18000 : 0;
    const hits = messages.map((message, i) => {
      const seed = parseInt(message.id.slice(0, 8), 16) || i + 1;
      const angle = (i / Math.max(messages.length, 1)) * Math.PI * 2 + t * (i % 2 ? -.35 : .35);
      const ring = .25 + (seed % 40) / 100;
      const x = w / 2 + Math.cos(angle) * Math.max(20, w / 2 - 55) * ring * 1.4;
      const y = h / 2 + Math.sin(angle) * Math.max(20, h / 2 - 50) * ring * 1.3;
      return { message, x, y, r: 23 + (seed % 13) };
    });
    ctx.strokeStyle = line; ctx.lineWidth = 1;
    for (let i = 0; i < hits.length; i++) {
      const a = hits[i], b = hits[(i + 1) % hits.length];
      if (hits.length > 1) { ctx.beginPath(); ctx.moveTo(a.x, a.y); ctx.lineTo(b.x, b.y); ctx.stroke(); }
    }
    for (const node of hits) {
      const { x, y, r, message } = node;
      const fraction = Math.max(.1, timeLeft(message) / message.ttl_ms);
      ctx.globalAlpha = .45 + fraction * .55;
      ctx.fillStyle = panel; ctx.strokeStyle = line;
      ctx.beginPath(); ctx.arc(x, y, r, 0, Math.PI * 2); ctx.fill(); ctx.stroke();
      ctx.strokeStyle = accent; ctx.lineWidth = 2;
      ctx.beginPath(); ctx.arc(x, y, r, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * fraction); ctx.stroke();
      ctx.fillStyle = accent; ctx.font = '15px Georgia'; ctx.textAlign = 'center'; ctx.fillText(message.kind === 'question' ? '?' : message.kind === 'idea' ? '✦' : '·', x, y + 1);
      ctx.fillStyle = muted; ctx.font = '8px monospace'; ctx.fillText(formatTime(timeLeft(message)).trim(), x, y + 13);
      if (hits.length <= 12) { ctx.font = '10px sans-serif'; ctx.fillText(message.content.slice(0, 17) + (message.content.length > 17 ? '…' : ''), x, y + r + 18); }
    }
    ctx.globalAlpha = 1; state.hits = hits;
  }
  function stopAnimation() { if (state.animation) cancelAnimationFrame(state.animation); state.animation = null; }
  function startAnimation() {
    if (!ctx || !state.motion || state.view !== 'constellation' || state.animation || document.hidden || $('#constellation-panel').hidden) return;
    let last = 0;
    function frame(timestamp) {
      state.animation = requestAnimationFrame(frame);
      if (timestamp - last < 33) return;
      last = timestamp; drawCanvas(timestamp);
    }
    state.animation = requestAnimationFrame(frame);
  }
  if (typeof ResizeObserver === 'function') new ResizeObserver(() => { resizeCanvas(); drawCanvas(); }).observe(canvas);
  window.addEventListener('resize', () => { resizeCanvas(); drawCanvas(); });
  canvas.addEventListener('click', event => {
    const rect = canvas.getBoundingClientRect();
    const x = event.clientX - rect.left, y = event.clientY - rect.top;
    const hit = [...state.hits].reverse().find(node => Math.hypot(node.x - x, node.y - y) <= node.r + 8);
    if (hit) openMessage(hit.message.id);
  });
  function motionLabel() { $('#motion-btn').textContent = state.motion ? 'Pause motion' : 'Resume motion'; $('#motion-btn').setAttribute('aria-pressed', !state.motion); }
  if (preference('motion') === 'off') state.motion = false;
  motionLabel();
  $('#motion-btn').addEventListener('click', () => {
    state.motion = !state.motion; preference('motion', state.motion ? 'on' : 'off'); motionLabel();
    if (state.motion) startAnimation(); else { stopAnimation(); drawCanvas(); }
  });
  window.matchMedia('(prefers-reduced-motion: reduce)').addEventListener('change', event => {
    if (event.matches) { state.motion = false; stopAnimation(); motionLabel(); drawCanvas(); }
  });
  document.addEventListener('keydown', event => {
    if (event.isComposing || event.altKey) return;
    const typing = event.target.closest('input, textarea, select, [contenteditable]');
    if ((event.ctrlKey || event.metaKey) && event.key === 'Enter' && event.target === $('#content-input')) { event.preventDefault(); $('#message-form').requestSubmit(); return; }
    if (typing || $('dialog[open]') || event.ctrlKey || event.metaKey) return;
    if (event.key === '/') { event.preventDefault(); $('#search-input').focus(); }
    if (event.key.toLowerCase() === 'n') { event.preventDefault(); $('#content-input').focus(); }
    if (event.key === '?') { event.preventDefault(); showDialog('#help-dialog'); }
  });
  // Server-side rendering contains no room messages. Only cosmetic preferences
  // survive reload; capabilities, drafts, reactions and content stay in memory.
  const initialRoom = new URLSearchParams(location.search).get('room') || 'lobby';
  changeRoom(initialRoom);
  if (ctx && preference('view') === 'constellation') setView('constellation');
})();
