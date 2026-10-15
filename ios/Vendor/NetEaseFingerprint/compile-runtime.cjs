const fs = require('node:fs');
let core = fs.readFileSync('fingerprint-core.js', 'utf8')
  .replace("import * as a from 'a';", '')
  .split('var retasmFunc = asmFunc(')[0];
let glue = fs.readFileSync('afp.js', 'utf8');
glue = glue.slice(glue.indexOf('let AudioFingerprintRuntime'), glue.indexOf('// XXX: With PythonMonkey'));
glue = glue.replace('"object" != typeof WebAssembly && abort("no native wasm support detected");', '');
const loading = 'w || "function" != typeof WebAssembly.instantiate || isDataURI(Q) || isFileURI(Q) || getBinaryPromise(load_wasm)';
if (!glue.includes(loading)) throw new Error('Unexpected upstream loader');
glue = glue.replace(loading, 'updateGlobalBufferAndViews({exports: asmFunc(import_table)})');
const wrapper = `
var inkflowFingerprint = (() => {
const WASM_BINARY_PLACEHOLDER = 'bundled';
const console = {log(){}, warn(){}, error(){}};
${core}
${glue}
const runtime = AudioFingerprintRuntime();
function encode(bytes) {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  let result = '';
  for (let i=0; i<bytes.length; i+=3) {
    const a=bytes[i], b=bytes[i+1] || 0, c=bytes[i+2] || 0;
    result += chars[a>>2] + chars[((a&3)<<4)|(b>>4)]
      + (i+1<bytes.length ? chars[((b&15)<<2)|(c>>6)] : '=')
      + (i+2<bytes.length ? chars[c&63] : '=');
  }
  return result;
}
return function(base64) {
  const padding = base64.endsWith('==') ? 2 : base64.endsWith('=') ? 1 : 0;
  const pcm = new Uint8Array(base64.length*3/4-padding);
  base64DecodeToExistingUint8Array(pcm, 0, base64);
  const samples = new Float32Array(pcm.buffer);
  let energy = 0;
  for (let i=0; i<samples.length; i++) energy += samples[i]*samples[i];
  // The upstream extractor aborts on an all-zero window. Never enter it on silence.
  if (!Number.isFinite(energy) || energy/samples.length < 1e-10) return '';
  const vector = runtime.ExtractQueryFP(pcm.buffer);
  try {
    const bytes = new Uint8Array(vector.size());
    for (let i=0; i<bytes.length; i++) bytes[i] = vector.get(i);
    return encode(bytes);
  } finally { vector.delete(); }
};
})();
`;
fs.writeFileSync('fingerprint-runtime.js', wrapper);
console.log('bundled runtime', Buffer.byteLength(wrapper));
