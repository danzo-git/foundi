const { test } = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const path = require('node:path');
const { initializeApp, deleteApp } = require('firebase/app');
const { connectAuthEmulator, getAuth, signInWithEmailAndPassword } = require('firebase/auth');
const { connectFirestoreEmulator, getFirestore, doc, getDoc, setDoc } = require('firebase/firestore');
const { connectFunctionsEmulator, getFunctions, httpsCallable } = require('firebase/functions');
const { connectStorageEmulator, getStorage, ref, getBytes, getDownloadURL, uploadBytes } = require('firebase/storage');
const { initializeApp: adminApp, deleteApp: deleteAdmin } = require('firebase-admin/app');
const { getAuth: adminAuth } = require('firebase-admin/auth');
const { getFirestore: adminFirestore } = require('firebase-admin/firestore');
const { getStorage: adminStorage } = require('firebase-admin/storage');
const { createRequestPhotoService } = require('../src/request-photo-service');

const projectId = 'demo-foundi';
const ports = process.env;
const storageAddress = ports.FIREBASE_STORAGE_EMULATOR_HOST || ports.STORAGE_EMULATOR_HOST?.replace(/^https?:\/\//, '');
const enabled = !!(ports.FIREBASE_AUTH_EMULATOR_HOST && ports.FIRESTORE_EMULATOR_HOST &&
  ports.FUNCTIONS_EMULATOR_HOST && storageAddress);
const host = (address) => {
  const url = new URL(`http://${address}`);
  return [url.hostname, Number(url.port)];
};
const bytes = readFileSync(path.join(__dirname, '../test/fixtures/photo.png'));
const mime = 'image/png';

test('Firebase emulators enforce private storage and explicit public photo publication', { skip: !enabled, timeout: 160000 }, async () => {
  const stamp = Date.now();
  const requestId = `RequestPhotoEmulator${stamp}`;
  const publicId = requestId + 'Public';
  const ids = ['1', '2', '3', '4'].map((n) => n.repeat(32));
  const admin = adminApp({ projectId, storageBucket: projectId + '.appspot.com' }, `request-photo-${stamp}`);
  const auth = adminAuth(admin);
  const db = adminFirestore(admin);
  const bucket = adminStorage(admin).bucket();
  const apps = [];
  const users = [];
  const cleanupDocs = [`requests/${requestId}`, `requestOwnership/${requestId}`, `requestPhotoDrafts/${requestId}`,
    ...ids.map((id) => `requestPhotoFiles/${requestId}_${id}`)];
  const catalog = db.doc('referenceData/professionalOnboarding');
  const previousCatalog = await catalog.get();

  async function client(name, verified = true) {
    const app = initializeApp({ projectId, storageBucket: projectId + '.appspot.com', apiKey: 'emulator-only', appId: name }, name + stamp);
    apps.push(app);
    const a = getAuth(app);
    connectAuthEmulator(a, 'http://' + ports.FIREBASE_AUTH_EMULATOR_HOST, { disableWarnings: true });
    const email = `${name}.${stamp}@example.test`;
    const password = 'Test-Password-123!';
    const { uid } = await auth.createUser({ email, password, emailVerified: verified });
    users.push(uid);
    cleanupDocs.push(`requestPhotoLimits/${uid}`);
    await signInWithEmailAndPassword(a, email, password);
    const firestore = getFirestore(app);
    connectFirestoreEmulator(firestore, ...host(ports.FIRESTORE_EMULATOR_HOST));
    const functions = getFunctions(app, 'europe-west1');
    connectFunctionsEmulator(functions, ...host(ports.FUNCTIONS_EMULATOR_HOST));
    const storage = getStorage(app);
    connectStorageEmulator(storage, ...host(storageAddress));
    return { uid, firestore, storage, token: await a.currentUser.getIdToken(),
      call: (n, payload) => httpsCallable(functions, n)(payload).then((r) => r.data) };
  }

  function request(name, user, photoId, type = mime, payload = bytes, id = requestId) {
    const url = new URL(`http://${ports.FUNCTIONS_EMULATOR_HOST}/${projectId}/europe-west1/${name}`);
    url.searchParams.set('requestId', id);
    url.searchParams.set('photoId', photoId);
    url.searchParams.set('token', 'arbitrary-fake-token');
    const headers = user ? { Authorization: 'Bearer ' + user.token } : {};
    return name === 'uploadRequestPhoto'
      ? fetch(url, { method: 'POST', headers: { ...headers, 'Content-Type': type }, body: payload })
      : fetch(url, { headers });
  }

  try {
    const owner = await client('photo-owner');
    const pro = await client('photo-pro');
    const other = await client('photo-other');
    const unverified = await client('photo-unverified', false);
    cleanupDocs.push(`professionalProfiles/${pro.uid}`, `professionalProfiles/${other.uid}`,
      `userRequests/${owner.uid}/items/${requestId}`, `requestPublicationLimits/${owner.uid}`);
    await db.doc(`professionalProfiles/${pro.uid}`).set({ status: 'approved' });
    await db.doc(`professionalProfiles/${other.uid}`).set({ status: 'pending' });
    await catalog.set({ enabled: true, categories: [{ id: 'test', label: 'Maison' }], zones: [{ id: 'zone', label: 'Cocody' }] });
    const draft = { categoryId: 'test', specialtyId: '', zoneId: 'zone',
      title: 'Réparer un meuble', description: 'Réparer un meuble dans la chambre.', budget: null };
    const upload = (user, id, type, payload, rid) => request('uploadRequestPhoto', user, id, type, payload, rid);
    const read = (user, id) => request('readRequestPhoto', user, id);
    const readPublic = (id, rid) => request('readPublicRequestPhoto', null, id, undefined, undefined, rid);
    assert.equal((await upload(null, ids[0])).status, 401);
    assert.equal((await upload(unverified, ids[0])).status, 403);
    assert.equal((await upload(owner, ids[0], mime, bytes, '../' + requestId)).status, 400);
    assert.equal((await upload(owner, ids[0], 'image/jpeg')).status, 400);
    assert.equal((await upload(owner, ids[0])).status, 200);
    assert.equal((await upload(other, ids[1])).status, 403);
    assert.equal((await read(pro, ids[0])).status, 404);
    assert.equal((await db.doc(`requestPublicationLimits/${owner.uid}`).get()).exists, false);

    const fileDoc = `requestPhotoFiles/${requestId}_${ids[0]}`;
    const info = (await db.doc(fileDoc).get()).data();
    const object = `requestPhotos/${owner.uid}/${requestId}/${ids[0]}/${info.objectId}.webp`;
    const [meta] = await bucket.file(object).getMetadata();
    assert.equal(meta.metadata?.firebaseStorageDownloadTokens, undefined);
    for (const user of [owner, pro, other]) {
      await assert.rejects(getBytes(ref(user.storage, object)), (e) => e.code === 'storage/unauthorized');
      await assert.rejects(getDownloadURL(ref(user.storage, object)), (e) => e.code === 'storage/unauthorized');
      await assert.rejects(getDoc(doc(user.firestore, fileDoc)), (e) => e.code === 'permission-denied');
    }
    await assert.rejects(uploadBytes(ref(owner.storage, object), bytes, { contentType: mime }),
      (e) => e.code === 'storage/unauthorized');
    await assert.rejects(setDoc(doc(other.firestore, fileDoc), { state: 'ready', uid: owner.uid }),
      (e) => e.code === 'permission-denied');

    const saved = await owner.call('publishRequest', { requestId, request: { ...draft, photoIds: [ids[0]] } });
    const replay = await owner.call('publishRequest', { requestId, request: { ...draft, photoIds: [ids[1]] } });
    assert.deepEqual(saved, replay);
    assert.equal(saved.status, 'published');
    assert.deepEqual(saved.photoIds, [ids[0]]);
    assert.equal((await readPublic(ids[0], requestId)).status, 404);
    assert.equal((await db.doc(`requestPublicationLimits/${owner.uid}`).get()).data().createdAtMs.length, 1);
    assert.equal((await read(null, ids[0])).status, 401);
    assert.equal((await read(other, ids[0])).status, 403);
    const response = await read(pro, ids[0]);
    assert.equal(response.status, 200);
    assert.equal(response.headers.get('content-type'), 'image/webp');
    assert.equal(response.headers.get('cache-control'), 'private, no-store');
    assert.equal(Buffer.from(await response.arrayBuffer()).toString('ascii', 8, 12), 'WEBP');
    const edited = await owner.call('manageRequest', { requestId, action: 'edit', request: draft, expectedRevision: saved.createdAt });
    assert.deepEqual(edited.photoIds, [ids[0]]);
    assert.equal((await upload(owner, ids[1])).status, 200);
    assert.equal((await read(pro, ids[1])).status, 404);
    const replace = { requestId, action: 'edit', expectedRevision: edited.updatedAt,
      request: { ...draft, photoIds: [ids[1]], photosPublic: false } };
    const replaced = await owner.call('manageRequest', replace);
    assert.deepEqual(await owner.call('manageRequest', replace), replaced);
    assert.equal(replaced.createdAt, saved.createdAt);
    assert.deepEqual(replaced.photoIds, [ids[1]]);
    assert.equal((await read(owner, ids[0])).status, 404);
    assert.equal((await read(pro, ids[1])).status, 200);
    assert.equal((await readPublic(ids[1], requestId)).status, 404);
    assert.equal((await db.doc(`userRequests/${owner.uid}/items/${requestId}`).get()).data().status, 'published');
    assert.equal((await db.doc(`requestPublicationLimits/${owner.uid}`).get()).data().createdAtMs.length, 1);
    await owner.call('manageRequest', { requestId, action: 'delete' });
    assert.equal((await read(owner, ids[0])).status, 404);
    assert.equal((await db.doc(fileDoc).get()).data().state, 'discarded');
    const cleanup = createRequestPhotoService({
      auth,
      store: {
        transaction: (operation) => db.runTransaction((tx) => operation({
          get: async (p) => (await tx.get(db.doc(p))).data(),
          set: (p, value) => tx.set(db.doc(p), value),
          delete: (p) => tx.delete(db.doc(p)),
        })),
        expiredRequestPhotos: async (now, size) => (await db.collection('requestPhotoFiles')
          .where('deleteAt', '<=', now).orderBy('deleteAt').limit(size).get()).docs.map((d) => d.ref.path),
      },
      files: { remove: (p) => bucket.file(p).delete({ ignoreNotFound: true }) },
    });
    assert.deepEqual(await cleanup.cleanup(), { removed: 2, failed: 0 });
    assert.equal((await bucket.file(object).exists())[0], false);
    assert.equal((await db.doc(fileDoc).get()).exists, false);

    cleanupDocs.push(`requests/${publicId}`, `requestOwnership/${publicId}`,
      `requestPhotoDrafts/${publicId}`, `requestPhotoFiles/${publicId}_${ids[0]}`,
      `userRequests/${other.uid}/items/${publicId}`, `requestPublicationLimits/${other.uid}`);
    assert.equal((await upload(other, ids[0], mime, bytes, publicId)).status, 200);
    assert.equal((await readPublic(ids[0], publicId)).status, 404);
    const publicRequest = await other.call('publishRequest', {
      requestId: publicId, request: { ...draft, photoIds: [ids[0]], photosPublic: true },
    });
    assert.equal(publicRequest.photosPublic, true);
    const publicResponse = await readPublic(ids[0], publicId);
    assert.equal(publicResponse.status, 200);
    assert.equal(publicResponse.headers.get('cache-control'), 'private, no-store');
    assert.equal(Buffer.from(await publicResponse.arrayBuffer()).toString('ascii', 8, 12), 'WEBP');
    assert.equal((await readPublic(ids[1], publicId)).status, 404);
    const publicFile = (await db.doc(`requestPhotoFiles/${publicId}_${ids[0]}`).get()).data();
    const publicObject = `requestPhotos/${other.uid}/${publicId}/${ids[0]}/${publicFile.objectId}.webp`;
    await assert.rejects(getDownloadURL(ref(owner.storage, publicObject)), { code: 'storage/unauthorized' });
    await other.call('manageRequest', { requestId: publicId, action: 'close' });
    assert.equal((await readPublic(ids[0], publicId)).status, 404);
  } finally {
    for (const uid of users) {
      for (const id of [requestId, publicId]) await bucket.deleteFiles({ prefix: `requestPhotos/${uid}/${id}/` });
    }
    await Promise.all(cleanupDocs.map((p) => db.doc(p).delete()));
    if (previousCatalog.exists) await catalog.set(previousCatalog.data());
    else await catalog.delete();
    await Promise.all(users.map((uid) => auth.deleteUser(uid)));
    await Promise.all(apps.map(deleteApp));
    await deleteAdmin(admin);
  }
});
