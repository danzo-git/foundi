const { test, before, after } = require('node:test');

const fs = require('node:fs');

const path = require('node:path');

const { initializeTestEnvironment, assertFails, assertSucceeds } = require('@firebase/rules-unit-testing');

const { doc, setDoc, getDoc, getDocs, collection, query, where, orderBy, limit, updateDoc, deleteDoc } = require('firebase/firestore');

const enabled = Boolean(process.env.FIRESTORE_EMULATOR_HOST);

let env;

const published = { title: 'Besoin de test', description: 'Description publique de test.', categoryId: 'c', categoryLabel: 'Catégorie', specialtyId: '', specialtyLabel: '', zoneId: 'z', zoneLabel: 'Zone', status: 'published', budget: null, createdAt: 1234 };

before(async () => {

  if (!enabled) return;

  env = await initializeTestEnvironment({ projectId: 'demo-foundi-requests', firestore: { rules: fs.readFileSync(path.join(__dirname, '../../firestore.rules'), 'utf8') } });

  await env.withSecurityRulesDisabled(async c => {

    const db = c.firestore();

    await setDoc(doc(db, 'requests/public'), published);

    await setDoc(doc(db, 'requests/closed'), { ...published, status: 'closed' });

    await setDoc(doc(db, 'requests/deleted'), { ...published, status: 'deleted' });

    await setDoc(doc(db, 'requests/hidden'), { ...published, status: 'draft' });

    await setDoc(doc(db, 'userRequests/owner/items/public'), published);

    await setDoc(doc(db, 'users/owner'), { email: 'private@example.test', phone: '+2250100000000' });

    await setDoc(doc(db, 'professionalProfiles/owner/documents/identity'), { name: 'private.pdf' });

  });

});

after(async () => { if (env) await env.cleanup(); });

const check = (name, fn) => test(name, { skip: !enabled }, fn);

check('anonymous public feed requires published filter and a bounded query', async () => {

  const db = env.unauthenticatedContext().firestore();

  await assertSucceeds(getDoc(doc(db, 'requests/public')));

  await assertFails(getDoc(doc(db, 'requests/hidden')));

  await assertFails(getDoc(doc(db, 'requests/closed')));

  await assertFails(getDoc(doc(db, 'requests/deleted')));

  const feed = await assertSucceeds(getDocs(query(collection(db, 'requests'), where('status', '==', 'published'), orderBy('createdAt', 'desc'), limit(30))));

  require('node:assert/strict').deepEqual(feed.docs.map(d => d.id), ['public']);

  for (const d of feed.docs) require('node:assert/strict').deepEqual(Object.keys(d.data()).sort(), Object.keys(published).sort());

  await assertFails(getDocs(query(collection(db, 'requests'), limit(30))));

  await assertFails(getDocs(query(collection(db, 'requests'), where('status', '==', 'published'))));

  await assertFails(getDocs(query(collection(db, 'requests'), where('status', '==', 'published'), limit(51))));

});

check('private author lists are inaccessible to guests and other accounts', async () => {

  for (const c of [env.unauthenticatedContext(), env.authenticatedContext('other')]) {

    const db = c.firestore();

    await assertFails(getDoc(doc(db, 'userRequests/owner/items/public')));

    await assertFails(getDocs(query(collection(db, 'userRequests/owner/items'), limit(50))));

    for (const p of ['users/owner', 'professionalProfiles/owner/documents/identity']) await assertFails(getDoc(doc(db, p)));

  }

  const db = env.authenticatedContext('owner').firestore();

  await assertSucceeds(getDocs(query(collection(db, 'userRequests/owner/items'), orderBy('createdAt', 'desc'), limit(50))));

});

check('all direct client writes are forbidden, including forged ownership and FOUN-40 actions', async () => {

  for (const c of [env.unauthenticatedContext(), env.authenticatedContext('owner'), env.authenticatedContext('other'), env.authenticatedContext('admin', {admin: true})]) {

    for (const p of ['requests/public', 'userRequests/owner/items/public']) {

      const db = c.firestore();

      await assertFails(setDoc(doc(db, p), published));

      await assertFails(updateDoc(doc(db, p), { status: 'closed' }));

      await assertFails(deleteDoc(doc(db, p)));

    }

  }

});


check('shared Explorer filters remain anonymous, bounded, public and intersect dimensions', async () => {
  const entries = [
    ['filter-auto-cocody', { ...published, categoryId: 'auto', specialtyId: 'repair', zoneId: 'cocody' }],
    ['filter-auto-bingerville', { ...published, categoryId: 'auto', specialtyId: 'repair', zoneId: 'bingerville' }],
    ['filter-home-cocody', { ...published, categoryId: 'home', specialtyId: 'rent', zoneId: 'cocody' }],
    ['filter-closed', { ...published, categoryId: 'auto', specialtyId: 'repair', zoneId: 'cocody', status: 'closed' }],
    ['filter-deleted', { ...published, categoryId: 'auto', specialtyId: 'repair', zoneId: 'cocody', status: 'deleted' }],
  ];
  await env.withSecurityRulesDisabled(async c => { for (const [id, data] of entries) await setDoc(doc(c.firestore(), 'requests/' + id), data); });
  for (const context of [env.unauthenticatedContext(), env.authenticatedContext('client'), env.authenticatedContext('professional')]) {
    const db = context.firestore();
    for (const filters of [{categoryId:'auto'}, {zoneId:'cocody'}, {categoryId:'auto',zoneId:'cocody'}, {categoryId:'auto',specialtyId:'repair'}, {categoryId:'auto',specialtyId:'repair',zoneId:'cocody'}, {categoryId:'absent'}]) {
      const constraints = [where('status','==','published'), ...Object.entries(filters).map(([k,v]) => where(k,'==',v)), orderBy('createdAt','desc'), orderBy('__name__','desc'), limit(30)];
      const snapshot = await assertSucceeds(getDocs(query(collection(db,'requests'), ...constraints)));
      const expected = entries.filter(([,d])=>d.status==='published' && Object.entries(filters).every(([k,v])=>d[k]===v)).map(([id])=>id).sort().reverse();
      require('node:assert/strict').deepEqual(snapshot.docs.map(d=>d.id),expected);
    }
  }
  await env.withSecurityRulesDisabled(async c => { for (const [id] of entries) await deleteDoc(doc(c.firestore(),'requests/'+id)); });
});
