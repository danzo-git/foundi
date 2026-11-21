const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {initializeApp, deleteApp} = require('firebase-admin/app');
const {getFirestore} = require('firebase-admin/firestore');
const {initializeTestEnvironment, assertFails} = require('@firebase/rules-unit-testing');
const {doc, getDoc, getDocs, setDoc, collection, limit, query} = require('firebase/firestore');
const {createInformationService, createInformationStore} = require('../src/information-service');
test('INFORMATION real transactions, stable admin pagination, expiration and private SDK rules', {skip: !process.env.FIRESTORE_EMULATOR_HOST, timeout: 120000}, async () => {
  const projectId = 'demo-foundi-information';
  const app = initializeApp({projectId}, `information-${Date.now()}`), db = getFirestore(app);
  const env = await initializeTestEnvironment({projectId, firestore: {rules: fs.readFileSync(path.join(__dirname, '../../firestore.rules'), 'utf8')}});
  let now = 100000;
  const service = createInformationService({store: createInformationStore(db), auth: {getUser: async () => ({customClaims: {admin: true}})}, clock: () => now});
  const save = extra => service.save('admin', {admin: true}, {title: 'Annonce', summary: 'Résumé', body: 'Contenu privé avant publication', endsAt: now + 1000, expectedVersion: '', status: 'draft', ...extra});
  try {
    for (let i = 0; i < 32; i++) await save();
    const first = await service.listAdmin('admin', {admin: true});
    const second = await service.listAdmin('admin', {admin: true}, {cursor: first.cursor});
    assert.equal(first.items.length, 30); assert.equal(second.items.length, 2);
    assert.equal(new Set([...first.items, ...second.items].map(i => i.id)).size, 32);
    assert.equal(second.cursor, null); assert.equal((await service.list()).items.length, 0);
    const item = first.items[0];
    await save({id: item.id, expectedVersion: item.version, status: 'published'});
    assert.equal((await service.list()).items[0].id, item.id);
    assert.equal((await service.read({id: item.id})).body, item.body);
    const current = (await db.doc(`foundiAnnouncements/${item.id}`).get()).data();
    const mutations = await Promise.allSettled([save({...current, expectedVersion: current.version, title: 'A'}), save({...current, expectedVersion: current.version, title: 'B'})]);
    assert.equal(mutations.filter(r => r.status === 'fulfilled').length, 1);
    assert.equal(mutations.find(r => r.status === 'rejected').reason.code, 'aborted');
    const published = await save({status: 'published'}); now += 1000;
    assert.equal((await service.list()).items.length, 0);
    await assert.rejects(service.read({id: published.id}), e => e.code === 'not-found');
    for (const ctx of [env.unauthenticatedContext(), env.authenticatedContext('member'), env.authenticatedContext('admin', {admin: true})]) {
      const client = ctx.firestore();
      for (const resource of [`foundiAnnouncements/${published.id}`, 'foundiInformation/current', 'foundiInformationAudit/private']) {
        await assertFails(getDoc(doc(client, resource)));
        await assertFails(setDoc(doc(client, resource), {status: 'published', endsAt: now + 9999}));
      }
      await assertFails(getDocs(query(collection(client, 'foundiAnnouncements'), limit(30))));
    }
  } finally { await env.cleanup(); await deleteApp(app); }
});
