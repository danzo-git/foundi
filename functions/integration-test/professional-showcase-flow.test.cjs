const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const path = require('node:path');
const { test } = require('node:test');
const { initializeApp, deleteApp } = require('firebase/app');
const { connectAuthEmulator, getAuth, signInWithEmailAndPassword } = require('firebase/auth');
const { connectFirestoreEmulator, getFirestore, doc, getDoc } = require('firebase/firestore');
const { connectFunctionsEmulator, getFunctions, httpsCallable } = require('firebase/functions');
const { initializeApp: adminApp, deleteApp: deleteAdmin } = require('firebase-admin/app');
const { getAuth: adminAuth } = require('firebase-admin/auth');
const { getFirestore: adminFirestore } = require('firebase-admin/firestore');

const projectId = 'demo-foundi';
const enabled = ['FIREBASE_AUTH_EMULATOR_HOST', 'FIRESTORE_EMULATOR_HOST', 'FUNCTIONS_EMULATOR_HOST']
  .every((key) => process.env[key]);
const host = (address) => {
  const url = new URL(`http://${address}`);
  return [url.hostname, Number(url.port)];
};
const denied = (error) => error.code === 'functions/permission-denied';

test('emulated showcase callables persist sanitized photos and restrict access to the proposal client',
  { skip: !enabled, timeout: 120000 }, async () => {
    const stamp = Date.now();
    const admin = adminApp({ projectId }, `showcase-admin-${stamp}`);
    const auth = adminAuth(admin);
    const db = adminFirestore(admin);
    const apps = [];
    const users = [];
    const documents = [];

    async function client(name) {
      const app = initializeApp({ projectId, apiKey: 'emulator-only', appId: name }, name + stamp);
      apps.push(app);
      const clientAuth = getAuth(app);
      connectAuthEmulator(clientAuth, `http://${process.env.FIREBASE_AUTH_EMULATOR_HOST}`, { disableWarnings: true });
      const email = `${name}.${stamp}@example.test`;
      const password = 'Test-Password-123!';
      const { uid } = await auth.createUser({ email, password, emailVerified: true });
      users.push(uid);
      await signInWithEmailAndPassword(clientAuth, email, password);
      const firestore = getFirestore(app);
      connectFirestoreEmulator(firestore, ...host(process.env.FIRESTORE_EMULATOR_HOST));
      const functions = getFunctions(app, 'europe-west1');
      connectFunctionsEmulator(functions, ...host(process.env.FUNCTIONS_EMULATOR_HOST));
      return { uid, firestore, call: (name, data) => httpsCallable(functions, name)(data).then((response) => response.data) };
    }

    try {
      const owner = await client('showcase-owner');
      const recipient = await client('showcase-client');
      const other = await client('showcase-outsider');
      const privatePath = `professionalProfiles/${owner.uid}`;
      const showcasePath = `${privatePath}/showcase/profile`;
      const proposalId = `showcase-${stamp}`;
      documents.push(privatePath, showcasePath, `proposals/${proposalId}`);
      await db.doc(privatePath).set({ status: 'approved', phone: 'private-contact' });
      await db.doc(`proposals/${proposalId}`).set({ clientUid: recipient.uid, professionalUid: owner.uid });

      assert.equal(await owner.call('readProfessionalShowcase', {}), null);
      const base64 = readFileSync(path.join(__dirname, '../test/fixtures/photo.png')).toString('base64');
      const saved = await owner.call('saveProfessionalShowcase', {
        revision: 0, name: 'Atelier test', trade: 'Menuiserie', area: 'Cocody', bio: 'Agencement sur mesure',
        portrait: { base64 }, cover: { base64 }, gallery: [{ base64 }],
      });
      assert.equal(saved.revision, 1);
      assert.equal(saved.gallery.length, 1);
      assert.equal(saved.cover.id, saved.gallery[0].id);
      assert.equal('phone' in saved, false);
      assert.deepEqual(await owner.call('readProfessionalShowcase', {}), saved);
      assert.deepEqual(await recipient.call('readProfessionalShowcase', { proposalId }), saved);
      await assert.rejects(other.call('readProfessionalShowcase', { proposalId }), denied);
      await assert.rejects(getDoc(doc(recipient.firestore, showcasePath)), (error) => error.code === 'permission-denied');
      await assert.rejects(getDoc(doc(recipient.firestore, privatePath)), (error) => error.code === 'permission-denied');
      await db.doc(privatePath).update({ status: 'suspended' });
      assert.equal(await recipient.call('readProfessionalShowcase', { proposalId }), null);
      await assert.rejects(owner.call('readProfessionalShowcase', {}), denied);
    } finally {
      await Promise.all(documents.map((document) => db.doc(document).delete()));
      await Promise.all(users.map((uid) => auth.deleteUser(uid)));
      await Promise.all(apps.map(deleteApp));
      await deleteAdmin(admin);
    }
  });
