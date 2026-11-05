'use strict';
(() => {
  const $ = (selector, root = document) => root.querySelector(selector);
  const $$ = (selector, root = document) => [...root.querySelectorAll(selector)];
  const iconsPath = '/static/icons.svg#';
  const roomPattern = /^[a-z0-9][a-z0-9-]{0,31}(?![\s\S])/;
  const knownRooms = { lobby: 'The lobby', ideas: 'Bright ideas', questions: 'Open questions', 'after-hours': 'After hours' };
  const kinds = { thought: ['A thought', 'spark'], idea: ['An idea', 'bulb'], question: ['A question', 'question'], poll: ['A poll', 'list'] };
  const reactionNames = { spark: 'Inspired', heart: 'Love', curious: 'Curious' };
  const state = {
    capabilities: new Map(), aliases: new Map(), hidden: new Map(), myPollVotes: new Map(), replyTo: '', alias: '', roomMeta: null, locked: true, sending: false, revision: -1, watchController: null, presenceTimer: null, watchRetry: null,
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
  $('#room-form').addEventListener('submit', createRoom);
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
  $('#share-room-btn').addEventListener('click', showShare);
  function changeRoom(room, push = false) {
    if (!roomPattern.test(room)) { toast('That room name is invalid. Welcome to the lobby.'); room = 'lobby'; }
    const oldRoom = state.room;
    if (clientToken && state.roomMeta) fetch('/api/presence?room=' + encodeURIComponent(oldRoom), { method: 'DELETE', headers: authHeaders(), credentials: 'omit', keepalive: true }).catch(() => {});
    readInvitation(room);
    state.watchController?.abort(); state.watchController = null;
    clearTimeout(state.presenceTimer); clearTimeout(state.watchRetry);
    state.roomMeta = null; state.locked = true; state.revision = -1; cancelReply();
    $('#send-btn').disabled = true;
    state.generation++;
    state.controller?.abort();
    clearTimeout(state.timer);
    state.syncing = false;
    state.room = room; state.alias = state.aliases.get(room) || '';
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
    $('span', custom).textContent = room; $('span', custom).dataset.untranslated = '';
    $$('.room-link[data-room]').forEach(link => {
      const active = link.dataset.room === room;
      link.classList.toggle('active', active);
      if (active) link.setAttribute('aria-current', 'page'); else link.removeAttribute('aria-current');
    });
    const name = knownRooms[room] || '#' + room;
    $('#room-crumb').textContent = name.toLowerCase();
    $('#room-label').textContent = name;
    document.title = room === 'lobby' && !new URLSearchParams(location.search).has('room') ? 'Spectre — live, ephemeral messages for the moment' : name + ' · Spectre';
    $('#poll-editor').hidden = true;
    $('#kind-input').value = room === 'ideas' ? 'idea' : room === 'questions' ? 'question' : 'thought';
    $$('[data-filter]').forEach(button => button.setAttribute('aria-pressed', button.dataset.filter === 'all'));
    if (push) { const url = new URL(location.href); url.search = ''; url.searchParams.set('room', room); url.hash = ''; history.pushState(null, '', url); }
    $('#offline-banner').hidden = true;
    connection('', state.paused ? 'Paused' : 'Connecting');
    render();
    if (!state.paused) syncRoom().then(heartbeat);
  }

  function apiPath(suffix = '') { return '/api/messages' + suffix + '?room=' + encodeURIComponent(state.room); }
  class ApiError extends Error {
    constructor(message, status, retryAfter) { super(message); this.status = status; this.retryAfter = retryAfter; }
  }
  async function api(path, options = {}) {
    const headers = { ...authHeaders(), ...(options.headers || {}) };
    if (options.method === 'POST' && path === '/api/messages') {
      let message = JSON.parse(options.body);
      const cap = capabilities(message.room);
      if (message.encrypted) message = await SpectreCrypto.encrypt(message, cap.key);
      options = { ...options, body: JSON.stringify(message) };
    }
    const response = await fetch(path, { cache: 'no-store', credentials: 'omit', ...options, headers });
    let data = await response.json().catch(() => ({}));
    if (!response.ok) {
      const delay = Math.min(120, Math.max(1, Number(response.headers.get('retry-after')) || 5));
      const detail = data.error || (response.status === 429 ? 'Too many requests. Give it a moment.' : 'The server could not complete that request.');
      throw new ApiError(detail, response.status, delay);
    }
    const decode = message => SpectreCrypto.decrypt(message, capabilities(message.room).key);
    if (Array.isArray(data)) data = await Promise.all(data.map(async item => item?.message ? { ...item, message: await decode(item.message) } : item?.expires_at && item?.content ? decode(item) : item));
    else if (data.messages && data.room) data = { ...data, messages: await Promise.all(data.messages.map(decode)) };
    else if (data.message) data = { ...data, message: await decode(data.message) };
    else if (data.id && data.content && data.expires_at) data = await decode(data);
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
      const { data, response } = await api(roomPath('snapshot'), { signal: controller.signal });
      if (generation !== state.generation) return;
      if (!Array.isArray(data.messages) || !data.room) throw new Error('Invalid server response.');
      const serverTime = Number(response.headers.get('x-server-time'));
      if (serverTime > 0) state.clockOffset = serverTime - (started + Date.now()) / 2;
      state.messages = data.messages.filter(validMessage).filter(message => timeLeft(message) > 0);
      updateRoomMeta(data.room, data.presence);
      state.failures = 0;
      connection('live', 'Live now');
      $('#offline-banner').hidden = true;
      $('#sync-label').textContent = 'Live updates · connected';
      cleanCapabilities();
      render();
    } catch (error) {
      if (generation !== state.generation || state.paused) return;
      if ([403,404,410].includes(error.status)) { lockRoom(error.message); return; }
      state.failures++;
      delay = error.status === 429 ? error.retryAfter * 1000 : Math.min(60000, 4000 * 2 ** Math.min(state.failures, 4));
      connection('error', navigator.onLine ? 'Reconnecting' : 'Offline');
      $('#offline-banner').hidden = false;
      $('#sync-label').textContent = error.status === 429 ? 'Taking a breather · retrying shortly' : 'Reconnecting · your draft stays here';
    } finally {
      clearTimeout(timeout);
      if (generation === state.generation) { state.syncing = false; if (!state.locked) { schedule(state.failures ? delay : 20000); watchRoom(); } }
    }
  }
  function cleanCapabilities() {
    const timestamp = now();
    for (const [id, capability] of state.burnKeys) if (capability.expires <= timestamp) state.burnKeys.delete(id);
    for (const [id, reaction] of state.myReactions) if (reaction.expires <= timestamp) state.myReactions.delete(id);
    for (const [id, vote] of state.myPollVotes) if (vote.expires <= timestamp) state.myPollVotes.delete(id);
    for (const [id, expires] of state.hidden) if (expires <= timestamp) state.hidden.delete(id);
    for (const [room, cap] of state.capabilities) if (cap.expires && cap.expires <= timestamp) { state.capabilities.delete(room); state.aliases.delete(room); }
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
      clearTimeout(state.timer); state.controller?.abort(); state.watchController?.abort(); clearTimeout(state.watchRetry);
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
    if ($('#send-btn').disabled || state.locked) return;
    const input = $('#content-input');
    const content = input.value.trim();
    if (!content) { feedback('Give your thought a few words first.', true); input.focus(); return; }
    if (new TextEncoder().encode(content).length > 2000) { feedback('That thought is a little too large. Keep it under 2000 UTF-8 bytes.', true); return; }
    const options = $('#kind-input').value === 'poll' ? $('#poll-options').value.split('\n').map(value => value.trim()).filter(Boolean) : [];
    if ($('#kind-input').value === 'poll' && (options.length < 2 || options.length > 6 || new Set(options).size !== options.length || options.some(value => [...value].length > 100))) { feedback('A poll needs 2–6 distinct options of up to 100 characters.', true); return; }
    const room = state.room;
    const generation = state.generation;
    state.sending = true; $('#send-btn').disabled = true;
    feedback('Leaving your thought…');
    try {
      const { data } = await api('/api/messages', {
        method: 'POST', headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ content, ttl: state.ttl, room, kind: $('#kind-input').value, parent_id: state.replyTo, options, author: state.alias, encrypted: Boolean(state.roomMeta?.encrypted) }),
        signal: AbortSignal.timeout(10000),
      });
      if (data.message && data.burn_key) state.burnKeys.set(data.id, { key: data.burn_key, expires: data.message.expires_at });
      if (generation !== state.generation) { toast('Your thought was sent to #' + room + '.'); return; }
      if (input.value.trim() === content) input.value = '';
      updateCharacterCount(); cancelReply(); $('#poll-options').value = '';
      feedback('It’s here. For a little while.');
      if (validMessage(data.message)) { state.messages = [...state.messages.filter(message => message.id !== data.id), data.message]; render(); }
      toast('Thought shared. Let the moment happen.');
      if (!state.paused) syncRoom();
    } catch (error) {
      if (generation === state.generation) feedback(error.status ? error.message + (error.status === 429 ? ' Try again in ' + error.retryAfter + 's.' : '') : 'We couldn’t confirm the send. Your draft is kept; check the room before retrying.', true);
    } finally { state.sending = false; $('#send-btn').disabled = state.locked || Boolean(state.roomMeta?.encrypted && !capabilities().key); }
  });
  const prompts = {
    small: ['thought', 'A small thing that made today better: '],
    idea: ['idea', 'What if we tried '],
    question: ['question', 'One question I’ve been sitting with: '],
  };
  $$('[data-prompt]').forEach(button => button.addEventListener('click', () => {
    const [kind, prompt] = prompts[button.dataset.prompt];
    if ($('#content-input').value.trim()) { $('#content-input').focus(); return; }
    $('#kind-input').value = kind; $('#poll-editor').hidden = true; $('#content-input').value = SpectreI18n.t(prompt.trim()) + ' ';
    updateCharacterCount(); $('#content-input').focus();
  }));
  $('#empty-action').addEventListener('click', () => {
    if (state.filter !== 'all' || $('#search-input').value) {
      state.filter = 'all'; $('#search-input').value = '';
      $$('[data-filter]').forEach(button => button.setAttribute('aria-pressed', button.dataset.filter === 'all'));
      render();
    } else if (state.hidden.size) { state.hidden.clear(); render(); } else $('#content-input').focus();
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
    return state.messages.filter(message => timeLeft(message) > 0 && !state.hidden.has(message.id) && !state.hidden.has(message.parent_id))
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
    addMessageFeatures(card, message);
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
    $('#empty-action').firstChild.textContent = state.hidden.size && state.filter === 'all' && !$('#search-input').value ? 'Show hidden messages ' : noMatch ? 'Clear the filters ' : 'Start a little something';
    $('.starter-prompts').hidden = noMatch;
    $('#feed').hidden = state.view !== 'feed' || !messages.length;
    $('#constellation-panel').hidden = state.view !== 'constellation' || !messages.length;
    const signature = JSON.stringify([state.view, messages, [...state.pending], [...state.myReactions], [...state.burnKeys.keys()], [...state.myPollVotes], Boolean(state.roomMeta?.can_moderate)]);
    if (signature !== state.signature) {
      state.signature = signature;
      const focused = document.activeElement?.dataset?.focusKey;
      if (state.view === 'feed') $('#feed').replaceChildren(...messages.map(message => buildCard(message)));
      else {
        $('#feed').replaceChildren();
        $('#signal-index').replaceChildren(...messages.slice(0, 40).map(message => {
          const button = element('button', '', message.content.slice(0, 24) + (message.content.length > 24 ? '…' : ''));
          button.type = 'button'; button.dataset.untranslated = ''; button.addEventListener('click', () => openMessage(message.id)); return button;
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
  function openMessage(id) { const item = state.messages.find(message => message.id === id); id = item?.parent_id || id; state.selectedId = id; updateDetail(); if (state.messages.some(message => message.id === id)) showDialog('#message-dialog'); }
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
    cleanCapabilities(); tickEvent();
    if (state.replyTo && !state.messages.some(message => message.id === state.replyTo)) cancelReply();
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
  function roomPath(endpoint) { return '/api/' + endpoint + '?room=' + encodeURIComponent(state.room); }
  function capabilities(room = state.room) { return state.capabilities.get(room) || {}; }
  function inviteUrl() {
    const url = new URL('/', location.origin); url.searchParams.set('room', state.room);
    const cap = capabilities();
    if (cap.access || cap.key) { const hash = new URLSearchParams(); if (cap.access) hash.set('invite', cap.access); if (cap.key) hash.set('key', cap.key); url.hash = hash.toString(); }
    return url.href;
  }
  function readInvitation(room) {
    if (new URLSearchParams(location.search).get('room') !== room || !location.hash) return;
    const hash = new URLSearchParams(location.hash.slice(1));
    const access = hash.get('invite'), key = hash.get('key');
    if (access || key) {
      const cap = { ...capabilities(room) };
      if (access && /^[0-9a-f]{48}$/.test(access)) cap.access = access;
      if (key && /^[A-Za-z0-9_-]{43}$/.test(key)) cap.key = key;
      state.capabilities.set(room, cap);
      history.replaceState(null, '', location.pathname + location.search);
    }
  }
  function showShare() {
    if (state.locked) { toast('Open a valid invitation before sharing this room.'); return; }
    const url = inviteUrl(); $('#share-url').value = url;
    $('#share-disclosure').textContent = state.roomMeta?.private ? 'This invitation includes private room access. Anyone holding it can join.' : 'Everyone with this link can read this public room.';
    const qr = window.qrcode(0, 'M'); qr.addData(url); qr.make();
    const canvas = $('#share-qr'), context = canvas.getContext('2d');
    const count = qr.getModuleCount(), scale = Math.floor(280 / (count + 8));
    canvas.width = canvas.height = (count + 8) * scale;
    context.fillStyle = '#ffffff'; context.fillRect(0, 0, canvas.width, canvas.height); context.fillStyle = '#101412';
    for (let y = 0; y < count; y++) for (let x = 0; x < count; x++) if (qr.isDark(y, x)) context.fillRect((x + 4) * scale, (y + 4) * scale, scale, scale);
    copyText(url, state.roomMeta?.private ? 'Private invitation copied. Share it carefully.' : 'Room link copied.');
    showDialog('#share-dialog');
  }
  $('#share-dialog').addEventListener('close', () => { $('#share-url').value = ''; const canvas = $('#share-qr'); canvas.getContext('2d').clearRect(0,0,canvas.width,canvas.height); });
  $('#copy-invite').addEventListener('click', () => copyText(inviteUrl(), 'Invitation copied.'));
  $('#room-private').addEventListener('change', () => { if ($('#room-private').checked) $('#room-discoverable').checked = false; else $('#room-encrypted').checked = false; });
  $('#room-encrypted').addEventListener('change', () => { if ($('#room-encrypted').checked) { $('#room-private').checked = true; $('#room-discoverable').checked = false; } });
  $('#room-discoverable').addEventListener('change', () => { if ($('#room-discoverable').checked) { $('#room-private').checked = false; $('#room-encrypted').checked = false; } });
  async function createRoom(event) {
    event.preventDefault(); const button = $('#room-form button[type="submit"]'); if (button.disabled) return;
    button.disabled = true; $('#room-create-error').textContent = '';
    try {
      const encrypted = $('#room-encrypted').checked;
      const key = encrypted ? await SpectreCrypto.generate() : '';
      const { data } = await api('/api/rooms', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ name: $('#room-input').value.trim(), topic: $('#room-topic-input').value.trim(), minutes: Number($('#room-duration').value), private: $('#room-private').checked, encrypted, discoverable: $('#room-discoverable').checked }), signal: AbortSignal.timeout(10000) });
      state.capabilities.set(data.room.id, { access: data.access_key, owner: data.owner_key, key });
      $('#room-dialog').close(); changeRoom(data.room.id, true);
      toast('Your event is open. Save the invitation and owner key before reloading.');
    } catch (error) { $('#room-create-error').textContent = error.message; }
    finally { button.disabled = false; }
  }
  function cancelReply() { state.replyTo = ''; $('#reply-context').hidden = true; }
  $('#cancel-reply').addEventListener('click', cancelReply);
  $('#kind-input').addEventListener('change', () => { $('#poll-editor').hidden = $('#kind-input').value !== 'poll'; });
  function replyTo(message) {
    const parent = message.parent_id ? state.messages.find(item => item.id === message.parent_id) : message;
    if (!parent || timeLeft(parent) <= 0) { toast('That conversation has ended.'); return; }
    state.replyTo = parent.id; $('#reply-preview').textContent = parent.content.slice(0, 120); $('#reply-context').hidden = false;
    $('#message-dialog').close(); $('#content-input').focus(); $('#content-input').scrollIntoView({ block: 'center', behavior: 'auto' });
  }
  function addMessageFeatures(card, message) {
    const content = $('.message-content', card); content.dataset.untranslated = '';
    if (message.decrypt_error) content.classList.add('decrypt-error');
    if (message.author) { const author = element('span', 'card-author', message.author); author.dataset.untranslated = ''; $('.card-top', card).insertBefore(author, $('.card-age', card)); }
    if (message.parent_id) {
      card.classList.add('reply-card'); const caption = element('p', 'reply-caption', '↳ ' + (state.messages.find(item => item.id === message.parent_id)?.content.slice(0, 90) || 'Reply'));
      caption.dataset.untranslated = ''; content.before(caption);
    }
    if (message.kind === 'poll' && !message.decrypt_error) {
      const poll = element('div', 'poll-choices'); poll.setAttribute('role', 'group'); poll.setAttribute('aria-label', 'Poll choices');
      for (const [index, option] of message.options.entries()) {
        const button = element('button', 'poll-choice'); button.type = 'button'; button.setAttribute('aria-pressed', state.myPollVotes.get(message.id)?.index === index);
        const label = element('span', '', option); label.dataset.untranslated = '';
        const votes = Number(message.poll_counts?.[index]) || 0;
        const total = Number(message.poll_total) || 0;
        button.append(label, element('span', '', votes + ' · ' + (total ? Math.round(votes * 100 / total) : 0) + '%'));
        button.disabled = state.pending.has(message.id); button.dataset.focusKey = message.id + '-poll-' + index;
        button.addEventListener('click', () => vote(message, index)); poll.append(button);
      }
      poll.append(element('span', 'poll-meta', 'Votes: ' + message.poll_total)); content.after(poll);
    }
    const tools = element('div', 'message-tools');
    function action(label, callback) { const button = element('button', 'text-button', label); button.type = 'button'; button.addEventListener('click', callback); tools.append(button); }
    action('Reply', () => replyTo(message));
    const children = state.messages.filter(item => item.parent_id === message.id && timeLeft(item) > 0);
    if (!message.parent_id && children.length) action('Thread (' + children.length + ')', () => openMessage(message.id));
    action('Hide', () => { state.hidden.set(message.id, message.expires_at); if ($('#message-dialog').open) $('#message-dialog').close(); render(); });
    action('Report', () => { state.reportId = message.id; showDialog('#report-dialog'); });
    if (state.roomMeta?.can_moderate && !state.burnKeys.has(message.id)) action('Remove', () => removeAsModerator(message.id));
    $('.card-footer', card).before(tools);
  }
  async function vote(message, index) {
    if (state.pending.has(message.id)) return;
    const generation = state.generation; state.pending.add(message.id); render();
    try {
      const { data } = await api(apiPath('/' + message.id + '/vote'), { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ option: index }), signal: AbortSignal.timeout(10000) });
      state.myPollVotes.set(message.id, { index, expires: message.expires_at });
      if (generation === state.generation) state.messages = state.messages.map(item => item.id === message.id ? data : item);
    } catch (error) { toast(error.message); }
    finally { state.pending.delete(message.id); render(); }
  }
  $('#submit-report').addEventListener('click', async () => {
    const button = $('#submit-report'); if (button.disabled) return; button.disabled = true;
    try { await api(apiPath('/' + state.reportId + '/report'), { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ reason: $('#report-reason').value }), signal: AbortSignal.timeout(10000) }); $('#report-dialog').close(); toast('Report submitted. It expires with the message.'); }
    catch (error) { toast(error.message); } finally { button.disabled = false; }
  });
  $('#moderate-btn').addEventListener('click', () => { $('#moderator-key').value = ''; $('#moderator-feedback').textContent = ''; $('#moderator-reports').replaceChildren(); showDialog('#moderator-dialog'); if (state.roomMeta?.can_moderate) loadReports(); });
  $('#load-reports').addEventListener('click', () => {
    const key = $('#moderator-key').value.trim();
    if (key) { if (!/^[0-9a-f]{48}$/.test(key)) { $('#moderator-feedback').textContent = 'Invalid moderator key.'; return; } state.capabilities.set(state.room, { ...capabilities(), owner: key }); $('#moderator-key').value = ''; }
    loadReports();
  });
  $('#copy-owner-key').addEventListener('click', () => { const key = capabilities().owner; if (key) copyText(key, 'Owner key copied. Keep it private; it can moderate or close your room.'); else toast('No owner key is available in this tab.'); });
  async function loadReports() {
    try {
      const { data } = await api(roomPath('reports'), { signal: AbortSignal.timeout(10000) });
      $('#moderator-feedback').textContent = data.length ? 'Active reports: ' + data.length : 'No active reports.';
      $('#moderator-reports').replaceChildren(...data.map(report => {
        const div = element('div', 'moderation-report'); const text = element('p', '', report.message.content); text.dataset.untranslated = '';
        const remove = element('button', 'button danger', 'Remove message'); remove.type = 'button'; remove.addEventListener('click', async () => { await removeAsModerator(report.id); loadReports(); });
        div.append(element('span', 'tiny-label', report.count + ' reports'), text, remove); return div;
      }));
      await syncRoom();
    } catch (error) { $('#moderator-feedback').textContent = error.message; }
  }
  async function removeAsModerator(id) {
    try { await api(apiPath('/' + id), { method: 'DELETE', signal: AbortSignal.timeout(10000) }); state.messages = state.messages.filter(item => item.id !== id && item.parent_id !== id); render(); toast('Message removed.'); }
    catch (error) { toast(error.message); }
  }
  $('#close-room-btn').addEventListener('click', () => showDialog('#close-room-dialog'));
  $('#confirm-close-room').addEventListener('click', async () => {
    try { await api(roomPath('room'), { method: 'DELETE', signal: AbortSignal.timeout(10000) }); $('#close-room-dialog').close(); lockRoom('This event has ended. Its messages and sessions have been removed.'); }
    catch (error) { toast(error.message); }
  });
  function lockRoom(message) {
    state.locked = true; state.messages = []; state.roomMeta = null; cancelReply(); state.watchController?.abort();
    clearTimeout(state.timer); clearTimeout(state.presenceTimer); clearTimeout(state.watchRetry);
    $('#room-locked').textContent = message; $('#room-locked').hidden = false; $('#send-btn').disabled = true;
    $('#close-room-btn').hidden = true; connection('error', 'Room unavailable'); document.body.classList.add('event-ended'); render();
  }
  function updateRoomMeta(meta, people) {
    state.roomMeta = meta; state.locked = false; state.revision = meta.revision;
    const cap = capabilities();
    if (meta.expires_at) state.capabilities.set(state.room, { ...cap, expires: meta.expires_at });
    const missingKey = meta.encrypted && !cap.key;
    $('#room-locked').hidden = !missingKey;
    if (missingKey) $('#room-locked').textContent = 'Encryption key missing. Open the complete invitation to send or read encrypted text.';
    $('#send-btn').disabled = state.sending || missingKey;
    document.body.classList.remove('event-ended');
    $('#room-label').textContent = knownRooms[meta.id] || meta.name;
    for (const node of [$('#room-label'), $('#room-crumb')]) { if (knownRooms[meta.id]) delete node.dataset.untranslated; else node.dataset.untranslated = ''; }
    $('#room-crumb').textContent = knownRooms[meta.id] || meta.name;
    $('#room-security').textContent = meta.encrypted ? 'Private · E2EE text' : meta.private ? 'Private · access controlled' : 'Public room';
    $('.public-tag').textContent = meta.private ? 'PRIVATE ROOM' : 'PUBLIC ROOM';
    $('#compose-privacy').replaceChildren(icon(meta.private ? 'ghost' : 'globe'), document.createTextNode(meta.encrypted ? 'Message text is encrypted in your browser. Invitation holders can read it.' : meta.private ? 'Invitation holders can read this room. Text is processed by the server.' : 'Public by design. Share thoughts, never secrets.'));
    $('#close-room-btn').hidden = !meta.is_owner;
    $('#presence-count').textContent = people.count + ' active sessions';
    $('#participants-list').replaceChildren(...people.aliases.map(alias => { const node = element('li', '', alias); node.dataset.untranslated = ''; return node; }));
    if (!people.aliases.length) $('#participants-list').append(element('li', '', 'No aliases shared.'));
    tickEvent();
  }
  function tickEvent() {
    if (state.roomMeta?.expires_at) {
      const left = Math.max(0, state.roomMeta.expires_at - now()); $('#event-countdown').textContent = 'Event ends in ' + formatTime(left);
      if (!left) lockRoom('This event has ended. Its messages and sessions have been removed.');
    } else $('#event-countdown').textContent = '';
  }
  async function heartbeat() {
    clearTimeout(state.presenceTimer); if (state.locked || document.hidden || !clientToken) return;
    const generation = state.generation;
    try { await api(roomPath('presence'), { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ alias: state.alias }), signal: AbortSignal.timeout(8000) }); }
    catch (error) { if ([403,404,410].includes(error.status) && generation === state.generation) { lockRoom(error.message); return; } }
    if (generation === state.generation) state.presenceTimer = setTimeout(heartbeat, 20000);
  }
  $('#people-btn').addEventListener('click', () => { $('#alias-input').value = state.alias; showDialog('#people-dialog'); });
  $('#save-alias').addEventListener('click', async () => { state.alias = $('#alias-input').value.trim(); state.aliases.set(state.room,state.alias); await heartbeat(); await syncRoom(); $('#people-dialog').close(); toast('Temporary alias updated.'); });
  $('#discover-btn').addEventListener('click', async () => {
    showDialog('#discover-dialog'); $('#discovery-list').replaceChildren(element('p', '', 'Loading rooms…'));
    try {
      const { data } = await api('/api/rooms', { signal: AbortSignal.timeout(10000) });
      $('#discovery-list').replaceChildren(...data.map(room => {
        const button = element('button', 'discovery-card'); button.type = 'button';
        const name = element('strong', '', knownRooms[room.id] || room.name); if (!knownRooms[room.id]) name.dataset.untranslated = '';
        const topic = element('p', '', room.topic || 'A space for fleeting thoughts.'); if (room.topic) topic.dataset.untranslated = '';
        button.append(name, topic, element('small', '', room.active + ' messages · ' + room.sessions + ' active sessions'));
        button.addEventListener('click', () => { $('#discover-dialog').close(); changeRoom(room.id, true); }); return button;
      }));
    } catch (error) { $('#discovery-list').replaceChildren(element('p', '', error.message)); }
  });
  async function watchRoom() {
    if (state.watchController || state.paused || state.locked || document.hidden || !state.roomMeta) return;
    const generation = state.generation; const controller = new AbortController(); state.watchController = controller;
    const timer = setTimeout(() => controller.abort(), 24000);
    let retry = 0;
    try {
      const { data } = await api(roomPath('events') + '&since=' + encodeURIComponent(state.revision), { signal: controller.signal });
      if (generation !== state.generation || state.paused || state.locked) return;
      if (data.revision !== state.revision) await syncRoom();
    } catch (error) {
      if (generation !== state.generation || state.paused || document.hidden || state.locked) return;
      if ([403,404,410].includes(error.status)) { lockRoom(error.message); return; }
      retry = error.status === 429 ? error.retryAfter * 1000 : Math.min(30000, 1500 * 2 ** Math.min(state.failures++,4));
    } finally {
      clearTimeout(timer);
      if (generation === state.generation && state.watchController === controller) {
        state.watchController = null;
        if (!state.paused && !state.locked && !document.hidden) state.watchRetry = setTimeout(watchRoom, retry);
      }
    }
  }
  const challenges = [
    ['What small kindness could you offer someone today?', 'Ce mic gest de bunătate ai putea face pentru cineva azi?'],
    ['Invent something that would make a rainy day better.', 'Inventează ceva care ar face o zi ploioasă mai frumoasă.'],
    ['Ask a question you wish people asked more often.', 'Pune o întrebare pe care ai vrea să o auzi mai des.'],
    ['Share one thing you changed your mind about.', 'Spune un lucru despre care ți-ai schimbat părerea.'],
    ['Describe a place using only three words.', 'Descrie un loc folosind doar trei cuvinte.'],
    ['What would you build if nobody could judge it?', 'Ce ai construi dacă nimeni nu te-ar judeca?'],
    ['Leave a tiny piece of good advice for a stranger.', 'Lasă un mic sfat bun pentru un necunoscut.'],
  ];
  function dailyChallenge() { const day = Math.floor(Date.now() / 86400000); return challenges[day % challenges.length][SpectreI18n.language === 'ro' ? 1 : 0]; }
  function updateDaily() { $('#daily-topic').dataset.untranslated = ''; $('#daily-topic').textContent = dailyChallenge(); }
  $('#daily-use').addEventListener('click', () => { if (!$('#content-input').value.trim()) { $('#content-input').value = dailyChallenge() + '\n'; updateCharacterCount(); } $('#content-input').focus(); });
  document.addEventListener('spectre:language', () => { updateDaily(); render(); });
  updateDaily();
  document.addEventListener('visibilitychange', () => { if (document.hidden) { state.watchController?.abort(); clearTimeout(state.presenceTimer); } else { heartbeat(); watchRoom(); } });
  window.addEventListener('pagehide', () => { state.watchController?.abort(); if (clientToken && !state.locked) fetch(roomPath('presence'), { method: 'DELETE', headers: authHeaders(), keepalive: true, credentials: 'omit' }).catch(() => {}); });
  function authHeaders() {
    const cap = capabilities(), headers = {};
    if (clientToken) headers['x-spectre-client'] = clientToken;
    if (cap.access) headers['x-room-key'] = cap.access;
    if (cap.owner) headers['x-moderator-key'] = cap.owner;
    return headers;
  }

  const initialRoom = new URLSearchParams(location.search).get('room') || 'lobby';
  changeRoom(initialRoom);
  if (ctx && preference('view') === 'constellation') setView('constellation');
})();
