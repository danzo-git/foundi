const { test } = require('node:test');
const assert = require('node:assert/strict');
const { initializeApp, deleteApp } = require('firebase/app');
const { connectAuthEmulator, getAuth, signInWithEmailAndPassword } = require('firebase/auth');
const { connectFirestoreEmulator, getFirestore, doc, getDoc, setDoc } = require('firebase/firestore');
const { connectFunctionsEmulator, getFunctions, httpsCallable } = require('firebase/functions');
const { initializeApp: adminApp, deleteApp: deleteAdmin } = require('firebase-admin/app');
const { getAuth: adminAuth } = require('firebase-admin/auth');
const { getFirestore: adminFirestore } = require('firebase-admin/firestore');
const { key } = require('../src/notification-policy');

const projectId = 'demo-foundi';
const { FIREBASE_AUTH_EMULATOR_HOST: authHost, FIRESTORE_EMULATOR_HOST: firestoreHost,
  FUNCTIONS_EMULATOR_HOST: functionsHost } = process.env;
const endpoint = (address) => {
  const url = new URL(`http://${address}`);
  return [url.hostname, Number(url.port)];
};

test('request interactions enforce Firebase rules, real ownership, notifications and proposal boundaries',
  { skip: !(authHost && firestoreHost && functionsHost), timeout: 140000 }, async () => {
    const stamp = Date.now();
    const requestId = `RequestInteraction${stamp}`;
    const admin = adminApp({ projectId }, `interactions-${stamp}`);
    const auth = adminAuth(admin), db = adminFirestore(admin);
    const apps = [], users = [], cleanup = [];
    const catalog = db.doc('referenceData/professionalOnboarding');
    const previousCatalog = await catalog.get();
    const publicRef = db.doc(`requests/${requestId}`);
    cleanup.push(publicRef.path, `requestOwnership/${requestId}`, `requestEngagement/${requestId}`);

    async function client(name, verified = true) {
      const app = initializeApp({ projectId, apiKey: 'emulator-only', appId: name }, `${name}${stamp}`);
      apps.push(app);
      const firestore = getFirestore(app);
      connectFirestoreEmulator(firestore, ...endpoint(firestoreHost));
      const functions = getFunctions(app, 'europe-west1');
      connectFunctionsEmulator(functions, ...endpoint(functionsHost));
      const result = { firestore, call: (fn, data) => httpsCallable(functions, fn)(data).then((value) => value.data) };
      if (name === 'guest') return result;
      const a = getAuth(app);
      connectAuthEmulator(a, 'http://' + authHost, { disableWarnings: true });
      const email = `${name}.${stamp}@example.test`;
      const password = 'Test-Password-123!';
      const { uid } = await auth.createUser({ email, password, emailVerified: verified });
      users.push(uid);
      await signInWithEmailAndPassword(a, email, password);
      return { ...result, uid };
    }

    try {
      const owner = await client('owner');
      const alice = await client('alice');
      const pro = await client('pro');
      const pending = await client('pending');
      const guest = await client('guest');
      const unverified = await client('unverified', false);
      const ownPath = `userRequests/${owner.uid}/items/${requestId}`;
      const proPath = `professionalProfiles/${pro.uid}`;
      const pendingPath = `professionalProfiles/${pending.uid}`;
      const engagement = `requestEngagement/${requestId}`;
      const marker = `${engagement}/likes/${alice.uid}`;
      const recId = key(requestId, alice.uid, pro.uid);
      const recPath = `requestRecommendations/${recId}`;
      const noteId = key(recPath, owner.uid);
      const notePath = `users/${owner.uid}/notifications/${noteId}`;
      cleanup.push(ownPath, proPath, pendingPath, marker, recPath, notePath, `notificationOutbox/${noteId}`,
        `users/${owner.uid}/notificationState/inbox`, `requestInteractionLimits/${key('incoming', requestId)}`,
        `requestInteractionLimits/${key('recommendations', alice.uid)}`,
        `requestInteractionLimits/${key('directory', alice.uid)}`, `requestInteractionLimits/${key('likes', alice.uid)}`);
      const profile = { status: 'approved', businessName: 'Atelier Ébène', categoryIds: ['service'],
        specialtyIds: ['repair'], zoneIds: ['cocody'], phone: 'private', documents: { proof: 'private' } };
      const request = { status: 'published', createdAt: stamp, title: 'Réparer un meuble',
        description: 'Une demande de test', categoryId: 'service', specialtyId: 'repair', zoneId: 'cocody' };
      await Promise.all([
        publicRef.set(request),
        db.doc(ownPath).set({ ...request, proposalCount: 0 }),
        db.doc(`requestOwnership/${requestId}`).set({ ownerUid: owner.uid }),
        db.doc(proPath).set(profile),
        db.doc(pendingPath).set({ ...profile, status: 'pending' }),
        catalog.set({ categories: [{ id: 'service', label: 'Services', specialties: [{ id: 'repair', label: 'Réparation' }] }],
          zones: [{ id: 'cocody', label: 'Cocody' }] }),
      ]);

      const like = (user, liked) => user.call('setRequestLike', { requestId, liked });
      await assert.rejects(like(guest, true), { code: 'functions/unauthenticated' });
      await assert.rejects(like(unverified, true), { code: 'functions/permission-denied' });
      await Promise.all([like(alice, true), like(alice, true)]);
      assert.deepEqual((await getDoc(doc(guest.firestore, engagement))).data(), { likeCount: 1 });
      assert.ok((await getDoc(doc(alice.firestore, marker))).exists());
      await assert.rejects(getDoc(doc(owner.firestore, marker)), { code: 'permission-denied' });
      await assert.rejects(setDoc(doc(alice.firestore, engagement), { likeCount: 500 }), { code: 'permission-denied' });
      await assert.rejects(setDoc(doc(alice.firestore, marker), { createdAt: 1 }), { code: 'permission-denied' });
      assert.equal((await like(alice, false)).likeCount, 0);
      await assert.rejects(getDoc(doc(alice.firestore, proPath)), { code: 'permission-denied' });

      const directory = await alice.call('searchRecommendationProfessionals', { requestId, query: 'ebene' });
      assert.deepEqual(directory.items, [{ id: pro.uid, name: 'Atelier Ébène', categories: ['Services'],
        specialties: ['Réparation'], zones: ['Cocody'] }]);
      const recommend = (user, professionalId) => user.call('recommendRequestProfessional', { requestId, professionalId });
      await assert.rejects(recommend(guest, pro.uid), { code: 'functions/unauthenticated' });
      await assert.rejects(recommend(pro, pro.uid), { code: 'functions/invalid-argument' });
      await assert.rejects(recommend(alice, pending.uid), { code: 'functions/failed-precondition' });
      assert.deepEqual(await recommend(alice, pro.uid), { alreadyRecommended: false });
      assert.deepEqual(await recommend(alice, pro.uid), { alreadyRecommended: true });
      await assert.rejects(getDoc(doc(owner.firestore, recPath)), { code: 'permission-denied' });
      await assert.rejects(setDoc(doc(alice.firestore, recPath), { ownerUid: alice.uid }), { code: 'permission-denied' });
      const read = (user) => user.call('readRequestRecommendation', { recommendationId: recId });
      await assert.rejects(read(alice), { code: 'functions/not-found' });
      assert.equal((await read(owner)).name, 'Atelier Ébène');
      let notification;
      for (let i = 0; i < 45; i++) {
        notification = (await db.doc(notePath).get()).data();
        if (notification) break;
        await new Promise((resolve) => setTimeout(resolve, 1000));
      }
      assert.equal(notification?.type, 'request.recommended');
      assert.equal((await db.doc(`users/${owner.uid}/notificationState/inbox`).get()).data().unreadCount, 1);
      assert.deepEqual(await owner.call('resolveNotification', { notificationId: noteId }),
        { resourceType: 'recommendation', resourceId: recId });
      await assert.rejects(alice.call('resolveNotification', { notificationId: noteId }), { code: 'functions/not-found' });
      assert.equal((await db.doc(ownPath).get()).data().proposalCount, 0);
      assert.equal((await db.doc(`requestPublicationLimits/${alice.uid}`).get()).exists, false);
      assert.deepEqual((await publicRef.get()).data(), request);
      assert.equal((await pro.call('proposalAccess', { requestId })).canSend, true);
      await assert.rejects(pending.call('proposalAccess', { requestId }), { code: 'functions/permission-denied' });
      await db.doc(proPath).update({ status: 'suspended' });
      await assert.rejects(read(owner), { code: 'functions/not-found' });
      await assert.rejects(owner.call('resolveNotification', { notificationId: noteId }), { code: 'functions/not-found' });
      await publicRef.update({ status: 'closed' });
      await assert.rejects(like(alice, true), { code: 'functions/failed-precondition' });
      await assert.rejects(getDoc(doc(guest.firestore, engagement)), { code: 'permission-denied' });
    } finally {
      await Promise.allSettled(apps.map(deleteApp));
      await Promise.allSettled(users.map((uid) => auth.deleteUser(uid)));
      await Promise.allSettled(cleanup.map((path) => db.doc(path).delete()));
      if (previousCatalog.exists) await catalog.set(previousCatalog.data());
      else await catalog.delete();
      await deleteAdmin(admin);
    }
  });
