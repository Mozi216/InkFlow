import http from 'node:http';
import { createHash, randomBytes, randomUUID, timingSafeEqual } from 'node:crypto';
import { pathToFileURL } from 'node:url';
import { setTimeout as sleep } from 'node:timers/promises';
import { createApns } from './apns.mjs';

class RequestError extends Error {
  constructor(status) { super(`Request failed (${status})`); this.status = status; }
}

function authorized(request, key) {
  const hash = value => createHash('sha256').update(value).digest();
  return typeof key === 'string' && timingSafeEqual(hash(request.headers.authorization ?? ''), hash(`Bearer ${key}`));
}

async function readJSON(request) {
  const chunks = [];
  let size = 0;
  for await (const chunk of request) {
    size += chunk.length;
    if (size > 8192) throw new RequestError(413);
    chunks.push(chunk);
  }
  try { return JSON.parse(Buffer.concat(chunks).toString('utf8')); }
  catch { throw new RequestError(400); }
}

function validToken(token) { return typeof token === 'string' && /^(?:[a-fA-F0-9]{2}){16,256}$/.test(token); }

export function payloadFor(state, event, now = Date.now()) {
  if (!state || state.source !== 'broadcast' || !Number.isFinite(state.position)
      || !Number.isFinite(state.anchorDate) || typeof state.line?.text !== 'string'
      || typeof state.playing !== 'boolean' || !state.appearance) throw new RequestError(400);
  // ContentState uses Swift's DEFAULT Date encoding (seconds since 2001). Never rewrite its dates.
  // APNs envelope dates are separately expressed as Unix seconds.
  const timestamp = Math.floor(now / 1000);
  const aps = { timestamp, event, 'content-state': structuredClone(state), 'stale-date': timestamp + 45 };
  if (event === 'end') aps['dismissal-date'] = timestamp;
  const payload = { aps };
  if (Buffer.byteLength(JSON.stringify(payload)) > 4000) delete aps['content-state'].artwork;
  if (Buffer.byteLength(JSON.stringify(payload)) > 4000) throw new RequestError(413);
  return payload;
}

// A private, single-owner relay. Deploy behind HTTPS; don't distribute its setup key in an IPA.
// Sessions are memory-only and expire after six hours. Restarting the service requires reconnecting.
export function createRelay({ setupKey, bundleID, send, now = Date.now, wait = sleep }) {
  if (typeof setupKey !== 'string' || setupKey.length < 32 || !bundleID || typeof send !== 'function') {
    throw new Error('A setup key, bundle ID, and APNs sender are required');
  }
  const sessions = new Map();
  const server = http.createServer(async (request, response) => {
    const reply = (status, value = {}) => {
      response.writeHead(status, { 'content-type': 'application/json', 'cache-control': 'no-store' });
      response.end(JSON.stringify(value));
    };
    try {
      for (const [id, session] of sessions) if (session.expires <= now()) sessions.delete(id);
      if (request.method !== 'POST') throw new RequestError(405);
      if (request.url === '/sessions') {
        if (!authorized(request, setupKey)) throw new RequestError(401);
        if (sessions.size >= 100) throw new RequestError(429);
        const input = await readJSON(request);
        if (!validToken(input.token) || input.bundleID !== bundleID) throw new RequestError(400);
        const id = randomUUID();
        const initial = payloadFor({ ...input.state, relaySession: id, connectionActive: false }, 'update', now());
        try { await send(input.token, initial); }
        catch { throw new RequestError(502); }
        const uploadKey = randomBytes(32).toString('base64url');
        const expires = now() + 6 * 60 * 60 * 1000;
        sessions.set(id, { token: input.token, uploadKey, expires, sequence: 0, queued: 0,
          lastTimestamp: initial.aps.timestamp, state: input.state, ended: false, queue: Promise.resolve() });
        return reply(201, { id, uploadKey, expires: expires / 1000 });
      }
      const route = /^\/sessions\/([a-f0-9-]{36})\/(updates|token|end)$/.exec(request.url ?? '');
      if (!route) throw new RequestError(404);
      const [, id, action] = route;
      const session = sessions.get(id);
      if (!session) throw new RequestError(410);
      if (!authorized(request, session.uploadKey)) throw new RequestError(401);
      if (session.queued >= 3) throw new RequestError(429);
      const input = await readJSON(request);
      session.queued++;
      const job = session.queue.then(async () => {
        if (session.ended) throw new RequestError(410);
        if (action === 'token') {
          if (!validToken(input.token)) throw new RequestError(400);
          session.token = input.token;
          return;
        }
        if (action === 'updates' && (!Number.isSafeInteger(input.sequence) || input.sequence <= session.sequence)) {
          throw new RequestError(409);
        }
        if (action === 'end') {
          session.ended = true;
          sessions.delete(id);
        }
        const state = input.state ?? (action === 'end' ? session.state : null);
        if (!state && action === 'end') return;
        payloadFor(state, action === 'end' ? 'end' : 'update', now()); // Validate before waiting or changing sequence.
        if (action === 'updates') session.sequence = input.sequence;
        // Same-second timestamps can be discarded by ActivityKit. Keep messages ordered without future dating them.
        const delay = (session.lastTimestamp + 1) * 1000 - now();
        if (delay > 0) await wait(delay);
        const payload = payloadFor(state, action === 'end' ? 'end' : 'update', now());
        try { await send(session.token, payload); }
        catch (error) {
          if (error.status === 410 || ['BadDeviceToken', 'DeviceTokenNotForTopic'].includes(error.message)) {
            sessions.delete(id);
            throw new RequestError(410);
          }
          throw new RequestError(502);
        }
        session.lastTimestamp = payload.aps.timestamp;
        session.state = state;
      });
      session.queue = job.catch(() => {});
      try { await job; } finally { session.queued--; }
      reply(200);
    } catch (error) { reply(error instanceof RequestError ? error.status : 500); }
  });
  server.requestTimeout = 10_000;
  server.headersTimeout = 10_000;
  return server;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const env = process.env;
  for (const name of ['INKFLOW_SETUP_KEY', 'APNS_BUNDLE_ID', 'APNS_TEAM_ID', 'APNS_KEY_ID', 'APNS_KEY_FILE', 'APNS_ENVIRONMENT']) {
    if (!env[name]) throw new Error(`Missing ${name}`);
  }
  if (!['sandbox', 'production'].includes(env.APNS_ENVIRONMENT)) throw new Error('Invalid APNS_ENVIRONMENT');
  const apns = createApns({ bundleID: env.APNS_BUNDLE_ID, teamID: env.APNS_TEAM_ID,
    keyID: env.APNS_KEY_ID, keyFile: env.APNS_KEY_FILE, environment: env.APNS_ENVIRONMENT });
  const server = createRelay({ setupKey: env.INKFLOW_SETUP_KEY, bundleID: env.APNS_BUNDLE_ID, send: apns.send });
  const port = Number(env.PORT || 8787);
  server.listen(port, '127.0.0.1', () => console.log(`InkFlow relay listening on loopback port ${port}`));
  for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, () => {
    server.close(); apns.close(); server.closeAllConnections();
  });
}
