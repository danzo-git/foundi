const fs = require('node:fs');
const path = require('node:path');
const {GoogleAuth} = require('google-auth-library');
const {policy} = require('../src/privacy-service');
const root = path.resolve(__dirname, '../..');
const args = process.argv.slice(2);
const option = name => args.includes(name) ? args[args.indexOf(name) + 1] : null;
const read = file => JSON.parse(fs.readFileSync(file, 'utf8'));
const indexKey = i => JSON.stringify([i.collectionGroup || i.name.split('/collectionGroups/')[1].split('/')[0], i.queryScope,
  i.fields.filter(f => f.fieldPath !== '__name__').map(f => [f.fieldPath, f.order || null, f.arrayConfig || null])]);
const normal = s => s.replace(/\r\n/g, '\n').trim();
function verify(snapshot, before) {
  if (snapshot.project !== 'foundi-7c837' || before.project !== snapshot.project) throw new Error('Project mismatch.');
  if (Date.now() - Date.parse(snapshot.checkedAt) > 3600000) throw new Error('Deployment verification is older than one hour.');
  for (const kind of ['firestore', 'storage']) {
    const actual = snapshot.rules[kind]?.source?.source?.files;
    const wanted = fs.readFileSync(path.join(root, kind + '.rules'), 'utf8');
    if (!actual?.some(f => normal(f.content) === normal(wanted))) throw new Error(kind + ' rules do not match local protections.');
  }
  const indexes = read(path.join(root, 'firestore.indexes.json'));
  for (const i of indexes.indexes) if (!snapshot.indexes.some(r => indexKey(r) === indexKey(i) && r.state === 'READY')) throw new Error('Index not ready: ' + i.collectionGroup);
  for (const i of before.indexes) if (!snapshot.indexes.some(r => r.name === i.name)) throw new Error('Existing index disappeared: ' + i.name);
  for (const f of indexes.fieldOverrides) {
    const actual = snapshot.fields.find(r => r.name.endsWith('/collectionGroups/' + f.collectionGroup + '/fields/' + f.fieldPath));
    if (f.ttl && actual?.ttlConfig?.state !== 'ACTIVE') throw new Error('TTL not active: ' + f.collectionGroup);
    for (const index of f.indexes || []) {
      if (!actual?.indexConfig?.indexes?.some(r => r.queryScope === index.queryScope && r.state === 'READY' && r.fields.some(v => v.fieldPath === f.fieldPath && v.order === index.order && v.arrayConfig === index.arrayConfig))) throw new Error('Field index not ready: ' + f.collectionGroup + '.' + f.fieldPath);
    }
  }
  const expected = ['requestAccountDeletion', 'readAccountDeletionStatus', 'retryAccountDeletion', 'listAccountDeletions', 'readAccountDeletion', 'resumeAccountDeletion', 'runAccountDeletion'];
  for (const name of [...before.functions.map(f => f.name), ...expected]) {
    const current = snapshot.functions.find(f => f.name === name);
    if (current?.state !== 'ACTIVE') throw new Error('Function is not active: ' + name);
    const prior = before.functions.find(f => f.name === name);
    if (prior && current.revision === prior.revision) throw new Error('Function did not receive closing-account protections: ' + name);
  }
  for (const name of ['requestAccountDeletion', 'retryAccountDeletion', 'resumeAccountDeletion', 'runAccountDeletion']) {
    if (snapshot.functions.find(f => f.name === name)?.deletionEnabled !== 'true') throw new Error('Runtime switch is off: ' + name);
  }
}
async function main() {
  if (option('--project') !== 'foundi-7c837' || !option('--policy')) throw new Error('Use --project foundi-7c837 --policy FILE [--verified FILE --before FILE --apply].');
  const configuration = read(option('--policy'));
  policy(configuration);
  if (option('--verified')) verify(read(option('--verified')), read(option('--before')));
  if (!args.includes('--apply')) { console.log('Policy valid; dry run only. ' + (option('--verified') ? 'Deployment prerequisites verified.' : 'Deployment still requires verification.')); return; }
  if (!option('--verified') || !option('--before')) throw new Error('Verified deployment snapshots are required for activation.');
  const client = await new GoogleAuth({scopes: ['https://www.googleapis.com/auth/cloud-platform']}).getClient();
  const name = 'projects/foundi-7c837/databases/(default)/documents/privacyConfiguration/current';
  let prior;
  try { prior = (await client.request({url: 'https://firestore.googleapis.com/v1/' + name})).data; }
  catch (e) { if (e.response?.status !== 404) throw e; }
  if (prior && prior.fields?.version?.stringValue !== configuration.version) throw new Error('A different remote policy exists; refusing to overwrite it.');
  const fields = Object.fromEntries(Object.entries(configuration).map(([key, value]) => [key,
    typeof value === 'boolean' ? {booleanValue: value} : typeof value === 'number' ? {integerValue: String(value)} : {stringValue: value}]));
  await client.request({url: 'https://firestore.googleapis.com/v1/projects/foundi-7c837/databases/(default)/documents:commit', method: 'POST',
    data: {writes: [{update: {name, fields}, currentDocument: prior ? {updateTime: prior.updateTime} : {exists: false}}]}});
  const actual = (await client.request({url: 'https://firestore.googleapis.com/v1/' + name})).data;
  if (JSON.stringify(actual.fields) !== JSON.stringify(fields)) {
    for (const [key, value] of Object.entries(fields)) if (JSON.stringify(actual.fields[key]) !== JSON.stringify(value)) throw new Error('Remote verification failed for ' + key);
  }
  console.log('Account deletion activated on foundi-7c837 with policy ' + configuration.version + '. No account deletion was requested by this script.');
}
main().catch(e => { console.error(e.message); process.exitCode = 1; });
