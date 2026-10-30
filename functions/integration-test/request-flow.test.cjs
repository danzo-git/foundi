const { test } = require('node:test');
const assert = require('node:assert/strict');
const { initializeApp, deleteApp } = require('firebase/app');
const { getAuth, connectAuthEmulator, signInWithEmailAndPassword } = require('firebase/auth');
const { getFirestore, connectFirestoreEmulator, doc, collection, getDocs, getDoc, query, where, orderBy, limit, setDoc } = require('firebase/firestore');
const { getFunctions, connectFunctionsEmulator, httpsCallable } = require('firebase/functions');
const { initializeApp: initializeAdmin, deleteApp: deleteAdmin } = require('firebase-admin/app');
const { getAuth: adminAuth } = require('firebase-admin/auth');
const { getFirestore: adminFirestore } = require('firebase-admin/firestore');
const enabled = Boolean(process.env.FIREBASE_AUTH_EMULATOR_HOST && process.env.FIRESTORE_EMULATOR_HOST);
const pair = host => { const [name, port] = host.split(':'); return [name, Number(port)]; };
test('V5/V6 real callables isolate authors, manage lifecycle and gate public opportunities', { skip: !enabled, timeout: 120000 }, async () => {
  const projectId = 'demo-foundi';
  process.env.FUNCTIONS_EMULATOR_HOST ||= '127.0.0.1:5139';
  const admin = initializeAdmin({ projectId }, 'requests-integration');
  const dbAdmin = adminFirestore(admin), authAdmin = adminAuth(admin), apps = [], users = [];
  const stamp = Date.now();
  async function client(name, signedIn) {
    const app = initializeApp({ projectId, apiKey: 'emulator-only', appId: 'v5-test-' + name }, name + stamp); apps.push(app);
    const auth = getAuth(app); connectAuthEmulator(auth, 'http://' + process.env.FIREBASE_AUTH_EMULATOR_HOST, { disableWarnings: true });
    let uid;
    if (signedIn) {
      const email = `${name}.${stamp}@example.test`, password = 'Local-Test-Password42!';
      const account = await authAdmin.createUser({ email, password, emailVerified: true }); uid = account.uid; users.push(uid);
      await signInWithEmailAndPassword(auth, email, password);
    }
    const db = getFirestore(app); connectFirestoreEmulator(db, ...pair(process.env.FIRESTORE_EMULATOR_HOST));
    const functions = getFunctions(app, 'europe-west1'); connectFunctionsEmulator(functions, ...pair(process.env.FUNCTIONS_EMULATOR_HOST));
    return { uid, db, manage: data => httpsCallable(functions, 'manageRequest')(data).then(r => r.data), opportunities: data => httpsCallable(functions, 'listOpportunities')(data).then(r => r.data), publish: data => httpsCallable(functions, 'publishRequest')(data).then(r => r.data) };
  }
  try {
    await dbAdmin.doc('referenceData/professionalOnboarding').set({ enabled: true, version: 'v5-test', categories: [{ id: 'c', label: 'Services de test', specialties: [{ id: 's', label: 'Spécialité de test' }] }], zones: [{ id: 'z', label: 'Zone de test' }] });
    const owner = await client('request-owner', true), other = await client('request-other', true), guest = await client('request-guest', false);
    // There is deliberately no professional profile or user role for this author.
    const requestId = doc(collection(owner.db, 'requests')).id;
    const request = { categoryId: 'c', specialtyId: 's', zoneId: 'z', title: 'Besoin public de test', description: 'Description publique pour le test local.', budget: null };
    await assert.rejects(guest.publish({ requestId, request }), e => e.code === 'functions/unauthenticated');
    const responses = await Promise.all([owner.publish({ requestId, request }), owner.publish({ requestId, request })]);
    assert.deepEqual(responses[0], responses[1]); assert.equal(responses[0].status, 'published');
    const publicData = (await getDoc(doc(guest.db, 'requests/' + requestId))).data();
    assert.deepEqual(Object.keys(publicData).sort(), ['categoryId','specialtyId','zoneId','title','description','budget','categoryLabel','specialtyLabel','zoneLabel','status','createdAt'].sort());
    const feed = await getDocs(query(collection(guest.db, 'requests'), where('status', '==', 'published'), orderBy('createdAt', 'desc'), limit(30)));
    assert.equal(feed.docs.filter(d => d.id === requestId).length, 1);
    const mine = await getDocs(query(collection(owner.db, `userRequests/${owner.uid}/items`), orderBy('createdAt', 'desc'), limit(50)));
    assert.equal(mine.docs.filter(d => d.id === requestId).length, 1);
    const others = await getDocs(query(collection(other.db, `userRequests/${other.uid}/items`), orderBy('createdAt', 'desc'), limit(50)));
    assert.equal(others.empty, true);
    await assert.rejects(getDoc(doc(other.db, `userRequests/${owner.uid}/items/${requestId}`)), e => e.code === 'permission-denied');
    await assert.rejects(setDoc(doc(owner.db, 'requests/forged'), { ...request, status: 'published' }), e => e.code === 'permission-denied');
    await dbAdmin.doc('referenceData/professionalOnboarding').update({ enabled: false });
    await assert.rejects(owner.publish({ requestId: doc(collection(owner.db, 'requests')).id, request }), e => e.code === 'functions/failed-precondition');
    assert.deepEqual(await owner.publish({ requestId, request }), responses[0]);
    await dbAdmin.doc('referenceData/professionalOnboarding').update({ enabled: true });
    await assert.rejects(other.opportunities({}), e => e.code === 'functions/permission-denied');
    await dbAdmin.doc(`professionalProfiles/${other.uid}`).set({ status: 'approved', categoryIds: ['c'], specialtyIds: ['s'], zoneIds: ['z'], email: 'private@example.test' });
    const opportunities = await other.opportunities({});
    assert.equal(opportunities.items.filter(r => r.id === requestId).length, 1);
    for (const item of opportunities.items) { assert.equal('email' in item, false); assert.equal('ownerId' in item, false); }
    await assert.rejects(other.manage({ requestId, action: 'close' }), e => e.code === 'functions/permission-denied');
    const edited = await owner.manage({ requestId, action: 'edit', request: { ...request, title: 'Titre modifié' }, expectedRevision: responses[0].createdAt });
    assert.equal(edited.id, requestId); assert.equal(edited.title, 'Titre modifié');
    assert.equal((await getDoc(doc(guest.db, 'requests/' + requestId))).data().title, 'Titre modifié');
    await owner.manage({ requestId, action: 'close' });
    assert.equal((await getDoc(doc(owner.db, `userRequests/${owner.uid}/items/${requestId}`))).data().status, 'closed');
    await assert.rejects(getDoc(doc(guest.db, 'requests/' + requestId)), e => e.code === 'permission-denied');
    assert.equal((await other.opportunities({})).items.some(r => r.id === requestId), false);
    await owner.manage({ requestId, action: 'delete' });
    assert.equal((await dbAdmin.doc(`userRequests/${owner.uid}/items/${requestId}`).get()).data().status, 'deleted');
    await dbAdmin.doc(`professionalProfiles/${other.uid}`).update({status: 'suspended'});
    await assert.rejects(other.opportunities({}), e => e.code === 'functions/permission-denied');

  } finally {
    await Promise.all(users.map(uid => authAdmin.deleteUser(uid)));
    await Promise.all(apps.map(deleteApp)); await deleteAdmin(admin);
  }
});
