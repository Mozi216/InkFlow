import http2 from 'node:http2';
import { createPrivateKey, sign } from 'node:crypto';
import { readFileSync } from 'node:fs';

export class ApnsError extends Error {
  constructor(status, reason) { super(reason); this.status = status; }
}

export function createApns(config) {
  const privateKey = createPrivateKey(readFileSync(config.keyFile));
  if (privateKey.asymmetricKeyType !== 'ec' || privateKey.asymmetricKeyDetails?.namedCurve !== 'prime256v1') {
    throw new Error('APNs requires an ES256 signing key');
  }
  const origin = config.environment === 'production'
    ? 'https://api.push.apple.com' : 'https://api.sandbox.push.apple.com';
  let client;
  let jwt;
  let signedAt = 0;

  function authorization() {
    const now = Math.floor(Date.now() / 1000);
    if (jwt && now - signedAt < 1800) return jwt;
    const encode = value => Buffer.from(JSON.stringify(value)).toString('base64url');
    const input = `${encode({ alg: 'ES256', kid: config.keyID })}.${encode({ iss: config.teamID, iat: now })}`;
    const signature = sign('sha256', Buffer.from(input), { key: privateKey, dsaEncoding: 'ieee-p1363' });
    jwt = `${input}.${signature.toString('base64url')}`;
    signedAt = now;
    return jwt;
  }

  async function send(token, payload) {
    if (!client || client.closed || client.destroyed) {
      client = http2.connect(origin);
      client.on('error', () => {}); // Request errors are handled below without logging credentials.
    }
    return new Promise((resolve, reject) => {
      const request = client.request({ ':method': 'POST', ':path': `/3/device/${token}`,
        authorization: `bearer ${authorization()}`,
        'apns-topic': `${config.bundleID}.push-type.liveactivity`, 'apns-push-type': 'liveactivity',
        'apns-priority': '5', 'apns-expiration': '0', 'content-type': 'application/json' });
      let status = 0;
      let body = '';
      request.setEncoding('utf8');
      request.setTimeout(7000, () => { request.destroy(new Error('APNs timed out')); });
      request.on('response', headers => { status = Number(headers[':status']); });
      request.on('data', chunk => { if (body.length < 8192) body += chunk; });
      request.on('error', reject);
      request.on('end', () => {
        if (status === 200) return resolve();
        let reason = 'APNs rejected the update';
        try { reason = JSON.parse(body).reason ?? reason; } catch {}
        if (reason === 'ExpiredProviderToken') jwt = undefined;
        reject(new ApnsError(status, reason));
      });
      request.end(JSON.stringify(payload));
    });
  }
  return { send, close: () => client?.destroy() };
}
