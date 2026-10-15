const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const context = {};
const source = fs.readFileSync(path.join(__dirname, '../Vendor/NetEaseFingerprint/fingerprint-runtime.js'), 'utf8');
vm.runInNewContext(source, context);
const pcm = Buffer.alloc(96_000 * 4);
let seed = 0x1234abcd;
for (let i = 0; i < 96_000; i++) {
  seed = (Math.imul(seed, 1_664_525) + 1_013_904_223) >>> 0;
  pcm.writeFloatLE((seed | 0) / 2_147_483_648 * 0.25, i * 4);
}
for (let i = 0; i < 20; i++) {
  const fingerprint = context.inkflowFingerprint(pcm.toString('base64'));
  assert.equal(crypto.createHash('sha256').update(fingerprint).digest('hex'),
    '92175b608e6bc8b4c653516256f927df2fe1fe9fec0f09eed923393279e7a7d6');
}
assert.equal(context.inkflowFingerprint(Buffer.alloc(pcm.length).toString('base64')), '');
assert.equal(crypto.createHash('sha256').update(context.inkflowFingerprint(pcm.toString('base64'))).digest('hex'),
  '92175b608e6bc8b4c653516256f927df2fe1fe9fec0f09eed923393279e7a7d6');
console.log('Fingerprint parity, repeated windows and silence: passed. No network or microphone used.');
