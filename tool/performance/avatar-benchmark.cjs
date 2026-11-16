// Controlled service benchmark: in-memory documents, 3ms per store read.
// This is NOT a network, production Functions or billing measurement.
const fs = require('node:fs');
const path = require('node:path');
const {performance} = require('node:perf_hooks');
const label = process.argv[2] || 'after';
if (!['before', 'after'].includes(label)) throw Error('Use before or after');
const baselineRef = 'b8546e888d1f2ff7c057a03db0895d78ce461d50';
function serviceModule() {
  const filename = path.resolve(__dirname, '../../functions/src/conversation-avatar-service.js');
  if (label === 'after') return require(filename);
  // Execute the exact local reference module, preserving its relative imports.
  // execFileSync supplies arguments directly: no shell interpolation.
  const source = require('node:child_process').execFileSync('git',
    ['show', `${baselineRef}:functions/src/conversation-avatar-service.js`],
    {cwd:path.resolve(__dirname,'../..'), encoding:'utf8'});
  const reference = {exports:{}};
  new Function('require', 'module', 'exports', source)(
    require('node:module').createRequire(filename), reference, reference.exports);
  return reference.exports;
}
const {createConversationAvatarService} = serviceModule();
const delay = () => new Promise(resolve => setTimeout(resolve, 3));
async function main() {
  const samples = [], reads = [], imports = [];
  const ids = Array.from({length: 12}, (_, i) => `conversation_fixture_${String(i).padStart(3, '0')}`);
  for (let sample = 0; sample < 21; sample++) {
    let count = 0, identities = 0;
    const store = {get: async p => {
      count++; await delay();
      if (p.startsWith('conversations/')) return {clientUid:'fixture_client', professionalUid:'fixture_pro'};
      if (p === 'personalAvatars/fixture_pro') return {published:true, publicId:'a'.repeat(32), revision:'b'.repeat(32)};
      if (p.startsWith('publicPersonalAvatars/')) return {version:'b'.repeat(32)};
      return undefined;
    }};
    const service = createConversationAvatarService({store,
      auth:{getUser:async () => ({emailVerified:true, disabled:false})},
      ensureIdentity:async () => {identities++; await delay();}});
    const start = performance.now();
    const result = await service.resolve('fixture_client', {conversationIds:ids});
    if (Object.keys(result.avatars).length !== 12) throw Error('Missing fixture avatars');
    samples.push(performance.now()-start); reads.push(count); imports.push(identities);
  }
  const sorted = samples.slice(1).sort((a,b)=>a-b);
  const result = {kind:'node_service_synthetic_io', label,
    samplesMs:samples, medianMs:(sorted[9]+sorted[10])/2, p95Ms:sorted[18],
    storeReads:reads, identityImports:imports, conversations:12, fixtureReadDelayMs:3,
    actualFirestoreReads:null, actualNetworkBytes:null};
  const destination = path.resolve(__dirname, '../../docs/sprint-2-6');
  fs.mkdirSync(destination, {recursive:true});
  fs.writeFileSync(path.join(destination, `avatar-service-${result.label}.json`), JSON.stringify(result,null,2)+'\n');
  console.log(JSON.stringify(result));
}
if (process.argv.includes('--verify')) {
  if (typeof createConversationAvatarService !== 'function') throw Error('Invalid fixture module');
  console.log(`Verified ${label} service fixture`);
} else {
  main().catch(error => {console.error(error); process.exitCode=1;});
}
