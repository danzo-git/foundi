const {test} = require('node:test');
const assert = require('node:assert/strict');
const {createInformationService} = require('../src/information-service');
function fixture() {
  const docs = new Map(), account = {customClaims: {admin: true}};
  let time = 100000, counter = 0, queue = Promise.resolve(), reads = 0;
  const service = createInformationService({auth: {getUser: async () => account}, clock: () => time, generateId: () => `id_${++counter}`,
    store: {get: async path => { reads++; return structuredClone(docs.get(path)); },
      list: async () => [...docs].filter(([path]) => path.startsWith('foundiAnnouncements/')).map(([, value]) => value),
      transaction(operation) {
        const job = queue.then(async () => {
          const next = structuredClone(docs);
          const result = await operation({get: async p => structuredClone(next.get(p)), set: (p, v) => next.set(p, structuredClone(v))});
          docs.clear(); for (const [p, v] of next) docs.set(p, v);
          return result;
        }); queue = job.catch(() => {}); return job;
      }}});
  const input = extra => ({title: 'Nouveauté', summary: 'Résumé court', body: 'Contenu complet', status: 'published', expectedVersion: '', endsAt: time + 1000, ...extra});
  const save = extra => service.save('admin', {admin: true}, input(extra));
  return {service, docs, account, save, input, advance: ms => {time += ms;}, reads: () => reads};
}
const code = expected => error => error.code === expected;
test('public summaries use one bounded read; drafts, archives and expired bodies are unavailable', async () => {
  const f = fixture();
  await f.save({status: 'draft'}); const published = await f.save();
  await f.save({status: 'archived'}); f.advance(1); const latest = await f.save();
  const before = f.reads(), listing = await f.service.list({featuredOnly: true});
  assert.equal(f.reads() - before, 1); assert.equal(listing.items.length, 1); assert.equal(listing.items[0].id, latest.id);
  assert.equal('body' in listing.items[0], false); assert.equal('actorUid' in listing.items[0], false);
  assert.equal((await f.service.read({id: published.id})).body, 'Contenu complet');
  f.advance(1000);
  assert.equal((await f.service.list()).items.length, 0);
  await assert.rejects(f.service.read({id: latest.id}), code('not-found'));
  const archives = await f.service.listAdmin('admin', {admin: true});
  assert.deepEqual(archives.items.map(i => i.status).sort(), ['archived', 'draft', 'expired', 'expired']);
});
test('fresh administrator claims are required for listing and every mutation', async () => {
  const f = fixture();
  await assert.rejects(f.service.save(null, {admin: true}, f.input()), code('unauthenticated'));
  await assert.rejects(f.service.save('u', {}, f.input()), code('permission-denied'));
  f.account.customClaims = {};
  await assert.rejects(f.save(), code('permission-denied'));
  await assert.rejects(f.service.listAdmin('u', {admin: true}), code('permission-denied'));
  f.account.customClaims = {admin: true}; f.account.disabled = true;
  await assert.rejects(f.save(), code('permission-denied')); assert.equal(f.docs.size, 0);
});
test('concurrent edits conflict and archiving atomically removes public access while retaining content and audit', async () => {
  const f = fixture(), created = await f.save();
  const result = await Promise.allSettled([f.save({...created, expectedVersion: created.version, title: 'A'}), f.save({...created, expectedVersion: created.version, title: 'B'})]);
  assert.equal(result.filter(r => r.status === 'fulfilled').length, 1);
  assert.equal(result.find(r => r.status === 'rejected').reason.code, 'aborted');
  const current = f.docs.get(`foundiAnnouncements/${created.id}`);
  await f.save({id: created.id, expectedVersion: current.version, status: 'archived'});
  assert.equal((await f.service.list()).items.length, 0);
  await assert.rejects(f.service.read({id: created.id}), code('not-found'));
  assert.equal(f.docs.get(`foundiAnnouncements/${created.id}`).body, 'Contenu complet');
  assert.equal([...f.docs.keys()].filter(p => p.startsWith('foundiInformationAudit/')).length, 3);
});
test('invalid dates, text, status and forged metadata cannot publish or bypass expiry', async () => {
  const f = fixture();
  for (const input of [{endsAt: 100000}, {endsAt: NaN}, {endsAt: 100000 + 367 * 86400000}, {title: 'x'.repeat(101)}, {summary: ''}, {body: 'x'.repeat(12001)}, {status: 'expired'}, {id: '../other'}]) {
    await assert.rejects(f.save(input), code('invalid-argument'));
  }
  await assert.rejects(f.service.read({id: '../private'}), code('invalid-argument'));
  await assert.rejects(f.service.list(null), code('invalid-argument'));
  const saved = await f.save({actorUid: 'forged', publishedAt: 1, createdAt: 1, featured: true, certified: true});
  const item = f.docs.get(`foundiAnnouncements/${saved.id}`);
  assert.equal(item.publishedAt, 100000); assert.equal(item.createdAt, 100000); assert.equal(item.certified, undefined);
});
test('active capacity is bounded and expired slots can be reused without deleting archives', async () => {
  const f = fixture();
  for (let i = 0; i < 20; i++) await f.save();
  await assert.rejects(f.save(), code('resource-exhausted'));
  assert.equal((await f.service.list()).items.length, 20);
  f.advance(1000); await f.save();
  assert.equal((await f.service.list()).items.length, 1);
  assert.equal([...f.docs.keys()].filter(p => p.startsWith('foundiAnnouncements/')).length, 21);
});
