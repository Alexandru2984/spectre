'use strict';
window.SpectreCrypto = (() => {
  const encoder = new TextEncoder(), decoder = new TextDecoder('utf-8', { fatal: true });
  const to64 = bytes => btoa(String.fromCharCode(...bytes)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  function from64(text) {
    if (!/^[A-Za-z0-9_-]+$/.test(text)) throw new Error('Invalid encryption key.');
    return Uint8Array.from(atob(text.replace(/-/g, '+').replace(/_/g, '/')), c => c.charCodeAt(0));
  }
  async function generate() {
    if (!crypto.subtle) throw new Error('Encryption requires HTTPS and a browser with Web Crypto support.');
    return to64(crypto.getRandomValues(new Uint8Array(32)));
  }
  async function key(raw) {
    const bytes = from64(raw || '');
    if (bytes.length !== 32) throw new Error('Invalid encryption key.');
    return crypto.subtle.importKey('raw', bytes, { name: 'AES-GCM' }, false, ['encrypt', 'decrypt']);
  }
  function aad(message) {
    return encoder.encode(JSON.stringify(['spectre-v1', message.room, message.kind || 'thought', message.parent_id || '', (message.options || []).length]));
  }
  async function encrypt(message, rawKey) {
    const iv = crypto.getRandomValues(new Uint8Array(12));
    const payload = encoder.encode(JSON.stringify({ content: message.content, options: message.options || [] }));
    const ciphertext = await crypto.subtle.encrypt({ name: 'AES-GCM', iv, additionalData: aad(message), tagLength: 128 }, await key(rawKey), payload);
    return { ...message, encrypted: true, content: JSON.stringify({ v: 1, iv: to64(iv), ciphertext: to64(new Uint8Array(ciphertext)) }), options: (message.options || []).map((_, i) => 'Encrypted option ' + (i + 1)) };
  }
  async function decrypt(message, rawKey) {
    if (!message.encrypted) return message;
    try {
      const envelope = JSON.parse(message.content);
      if (envelope.v !== 1) throw new Error();
      const iv = from64(envelope.iv);
      if (iv.length !== 12) throw new Error();
      const plaintext = await crypto.subtle.decrypt({ name: 'AES-GCM', iv, additionalData: aad(message), tagLength: 128 }, await key(rawKey), from64(envelope.ciphertext));
      const value = JSON.parse(decoder.decode(plaintext));
      if (typeof value.content !== 'string' || !Array.isArray(value.options) || value.options.length !== message.options.length || value.options.some(x => typeof x !== 'string' || x.length > 400) || value.content.length > 2000) throw new Error();
      return { ...message, content: value.content, options: value.options };
    } catch {
      return { ...message, content: 'Unable to decrypt this message. Check the invitation key.', options: [], decrypt_error: true };
    }
  }
  return { generate, encrypt, decrypt };
})();
