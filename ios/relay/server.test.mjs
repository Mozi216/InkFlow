import test from 'node:test';
import assert from 'node:assert/strict';
import { createRelay, payloadFor } from './server.mjs';

const setupKey = 'test-setup-key-with-more-than-32-characters';
const token = 'a1'.repeat(32);
const state = { source: 'broadcast', position: 12, anchorDate: 800000000,
  line: { text: 'hello world' }, playing: true, appearance: { theme: 'white' } };

async function fixture(t, send = async () => {}) {
  let clock = Date.now();
  const server = createRelay({ setupKey, bundleID: 'com.example.inkflow', send,
    now: () => clock, wait: async ms => { clock += ms; } });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(() => { server.closeAllConnections(); server.close(); });
  const call = (path, body, key = setupKey) => fetch(`http://127.0.0.1:${server.address().port}${path}`, {
    method: 'POST', headers: { authorization: `Bearer ${key}` }, body: JSON.stringify(body) });
  const register = () => call('/sessions', { token, bundleID: 'com.example.inkflow', state }).then(r => r.json());
  return { call, register, advance: ms => { clock += ms; } };
}

test('registration is authenticated and never returns an APNs token', async t => {
  const f = await fixture(t);
  assert.equal((await f.call('/sessions', { token }, 'wrong')).status, 401);
  assert.equal((await f.call('/sessions', { token, bundleID: 'foreign.app' })).status, 400);
  const session = await f.register();
  assert.equal(session.token, undefined);
  assert.ok(session.uploadKey.length >= 32);
});

test('session credentials cannot publish to another session', async t => {
  let sent = 0;
  const f = await fixture(t, async () => { sent++; });
  const a = await f.register(), b = await f.register();
  assert.equal((await f.call(`/sessions/${b.id}/updates`, { sequence: 1, state }, a.uploadKey)).status, 401);
  assert.equal(sent, 2); // Only the two authenticated registration checks reached APNs.
});

test('old updates cannot overwrite a newer lyric; APNs dates remain separate from Swift dates', async t => {
  const messages = [];
  const f = await fixture(t, async (_, body) => { messages.push(body); });
  const s = await f.register();
  const post = sequence => f.call(`/sessions/${s.id}/updates`, { sequence, state }, s.uploadKey);
  assert.equal((await post(2)).status, 200);
  assert.equal((await post(1)).status, 409);
  assert.equal((await post(3)).status, 200);
  assert.equal(messages.length, 3);
  assert.equal(messages[0].aps['content-state'].anchorDate, state.anchorDate);
  assert.ok(messages[1].aps.timestamp > messages[0].aps.timestamp);
});

test('push token rotation replaces the old destination', async t => {
  const tokens = [];
  const f = await fixture(t, async token => { tokens.push(token); });
  const s = await f.register();
  const updated = 'b2'.repeat(32);
  assert.equal((await f.call(`/sessions/${s.id}/token`, { token: updated }, s.uploadKey)).status, 200);
  await f.call(`/sessions/${s.id}/updates`, { sequence: 1, state }, s.uploadKey);
  assert.deepEqual(tokens, [token, updated]);
});

test('ending or expiring a session prevents any further updates', async t => {
  const messages = [];
  const f = await fixture(t, async (_, body) => { messages.push(body); });
  const s = await f.register();
  await f.call(`/sessions/${s.id}/updates`, { sequence: 1, state }, s.uploadKey);
  assert.equal((await f.call(`/sessions/${s.id}/end`, {}, s.uploadKey)).status, 200);
  assert.equal(messages.at(-1).aps.event, 'end');
  assert.equal((await f.call(`/sessions/${s.id}/updates`, { sequence: 2, state }, s.uploadKey)).status, 410);
  const expired = await f.register(); f.advance(7 * 60 * 60 * 1000);
  assert.equal((await f.call(`/sessions/${expired.id}/updates`, { sequence: 1, state }, expired.uploadKey)).status, 410);
});

test('APNs rejection does not report a successful connection', async t => {
  let calls = 0;
  const f = await fixture(t, async () => { if (++calls > 1) throw Object.assign(new Error('BadDeviceToken'), { status: 400 }); });
  const s = await f.register();
  assert.equal((await f.call(`/sessions/${s.id}/updates`, { sequence: 1, state }, s.uploadKey)).status, 410);
});

test('registration fails before the audio picker is offered if APNs rejects the token', async t => {
  const f = await fixture(t, async () => { throw new Error('MissingTopic'); });
  const response = await f.call('/sessions', { token, bundleID: 'com.example.inkflow', state });
  assert.equal(response.status, 502);
  assert.equal((await response.json()).uploadKey, undefined);
});

test('registration sends the confirmation marker without claiming audio capture has started', async t => {
  let delivered;
  const f = await fixture(t, async (_, payload) => { delivered = payload.aps['content-state']; });
  const session = await f.register();
  assert.equal(delivered.relaySession, session.id);
  assert.equal(delivered.connectionActive, false);
  assert.equal(delivered.anchorDate, state.anchorDate);
});

test('large artwork is dropped; oversized lyrics are rejected without truncating words', () => {
  const payload = payloadFor({ ...state, artwork: 'x'.repeat(5000) }, 'update');
  assert.equal(payload.aps['content-state'].artwork, undefined);
  assert.throws(() => payloadFor({ ...state, line: { text: '字'.repeat(5000) } }, 'update'));
});

test('malformed content never reaches APNs', async t => {
  let sent = false;
  const f = await fixture(t, async () => { sent = true; });
  const s = await f.register();
  sent = false;
  const response = await f.call(`/sessions/${s.id}/updates`, { sequence: 1, state: { ...state, anchorDate: 'wrong' } }, s.uploadKey);
  assert.equal(response.status, 400); assert.equal(sent, false);
});
