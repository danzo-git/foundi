const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { initializeTestEnvironment, assertFails, assertSucceeds } = require('@firebase/rules-unit-testing');
const { doc, setDoc, getDoc, updateDoc, collection, getDocs, serverTimestamp } = require('firebase/firestore');
const { ref, uploadBytes, getBytes } = require('firebase/storage');
const enabled = Boolean(process.env.FIRESTORE_EMULATOR_HOST && process.env.FIREBASE_STORAGE_EMULATOR_HOST);
let env;
before(async () => {
  if (!enabled) return;
  env = await initializeTestEnvironment({ projectId: 'demo-foundi',
    firestore: { rules: fs.readFileSync(path.join(__dirname, '../../firestore.rules'), 'utf8') },
    storage: { rules: fs.readFileSync(path.join(__dirname, '../../storage.rules'), 'utf8') } });
  await env.withSecurityRulesDisabled(async context => {
    const db = context.firestore();
    await setDoc(doc(db, 'users/owner'), { fullName: 'Awa', phone: '', registrationConfirmed: true, createdAt: new Date(), updatedAt: new Date() });
    await setDoc(doc(db, 'professionalProfiles/owner'), { status: 'pending', onboardingStep: 3 });
    await setDoc(doc(db, 'professionalProfiles/owner/documents/identity'), { state: 'ready', name: 'identity.pdf' });
    await setDoc(doc(db, 'users/owner/notifications/professionalDecision'), { status: 'approved' });
    await setDoc(doc(db, 'referenceData/professionalOnboarding'), { enabled: false });
    await setDoc(doc(db, 'legalDocuments/current'), { published: true, version: 'v1', terms: 'test', privacy: 'test' });
    await uploadBytes(ref(context.storage(), 'professionalDocuments/owner/identity/file'), Buffer.from('%PDF-1.4\nfixture'), { contentType: 'application/pdf' });
  });
});
after(async () => { if (env) await env.cleanup(); });
const check = (name, callback) => test(name, { skip: !enabled }, callback);
check('owner can read only their account, dossier, documents and private decision', async () => {
  const owner = env.authenticatedContext('owner').firestore(), other = env.authenticatedContext('other').firestore();
  for (const p of ['users/owner', 'professionalProfiles/owner', 'professionalProfiles/owner/documents/identity', 'users/owner/notifications/professionalDecision']) {
    await assertSucceeds(getDoc(doc(owner, p))); await assertFails(getDoc(doc(other, p)));
    await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), p)));
  }
  await assertFails(getDocs(collection(owner, 'professionalProfiles')));
});
check('profile owner and a token with an admin claim still cannot directly change verification status', async () => {
  for (const context of [env.authenticatedContext('owner'), env.authenticatedContext('reviewer', { professionalReviewer: true })]) {
    await assertFails(updateDoc(doc(context.firestore(), 'professionalProfiles/owner'), { status: 'approved' }));
    await assertFails(setDoc(doc(context.firestore(), 'professionalProfiles/new'), { status: 'approved' }));
    await assertFails(setDoc(doc(context.firestore(), 'professionalProfiles/owner/documents/fake'), { state: 'ready' }));
  }
});
check('ordinary own account edits succeed; roles, identity, creation time and other profiles are protected', async () => {
  const db = env.authenticatedContext('owner').firestore();
  await assertSucceeds(updateDoc(doc(db, 'users/owner'), { fullName: 'Awa Kouassi', phone: '', updatedAt: serverTimestamp() }));
  await assertFails(updateDoc(doc(db, 'users/owner'), { professionalReviewer: true, updatedAt: serverTimestamp() }));
  await assertFails(updateDoc(doc(db, 'users/owner'), { status: 'approved', updatedAt: serverTimestamp() }));
  await assertFails(updateDoc(doc(db, 'users/owner'), { createdAt: serverTimestamp(), updatedAt: serverTimestamp() }));
  await assertFails(updateDoc(doc(db, 'users/owner'), { phone: '0700000000', updatedAt: serverTimestamp() }));
  await assertFails(setDoc(doc(db, 'users/other'), { fullName: 'Other' }));
});
check('display preference never changes approval and cannot publish proposals', async () => {
  const db = env.authenticatedContext('owner').firestore();
  await assertSucceeds(updateDoc(doc(db, 'users/owner'), { preferredMode: 'professional', updatedAt: serverTimestamp() }));
  assert.equal((await getDoc(doc(db, 'professionalProfiles/owner'))).data().status, 'pending');
  await assertFails(setDoc(doc(db, 'proposals/forged'), { professionalId: 'owner', requestId: 'request', text: 'offer' }));
});
check('new client profile needs neither profession nor phone but cannot forge consent or server fields', async () => {
  const db = env.authenticatedContext('new-client').firestore();
  const profile = { fullName: 'Client', phone: '', registrationConfirmed: true, registrationPath: 'client', createdAt: serverTimestamp(), updatedAt: serverTimestamp() };
  await assertFails(setDoc(doc(db, 'users/new-client'), { ...profile, termsVersion: 'invented', termsAcceptedAt: serverTimestamp() }));
  await assertFails(setDoc(doc(db, 'users/new-client'), { ...profile, role: 'admin' }));
  await assertSucceeds(setDoc(doc(db, 'users/new-client'), profile));
  await assertSucceeds(updateDoc(doc(db, 'users/new-client'), { termsVersion: 'v1', termsAcceptedAt: serverTimestamp(), updatedAt: serverTimestamp() }));
});
check('references and published legal texts are readable, never client writable', async () => {
  const db = env.unauthenticatedContext().firestore();
  for (const p of ['referenceData/professionalOnboarding', 'legalDocuments/current']) {
    await assertSucceeds(getDoc(doc(db, p))); await assertFails(setDoc(doc(env.authenticatedContext('owner').firestore(), p), { enabled: true }));
  }
});
check('Storage documents are confidential and uploads are backend-only', async () => {
  const object = 'professionalDocuments/owner/identity/file';
  const owner = env.authenticatedContext('owner').storage();
  await assertSucceeds(getBytes(ref(owner, object)));
  await assertFails(getBytes(ref(env.unauthenticatedContext().storage(), object)));
  await assertFails(getBytes(ref(env.authenticatedContext('other').storage(), object)));
  await assertFails(uploadBytes(ref(owner, object), Buffer.from('replaced')));
  await assertFails(uploadBytes(ref(owner, 'professionalDocuments/owner/identity/new'), Buffer.from('new')));
});

check('admin can inspect dossiers and audit but never write decisions directly',async()=>{
 const db=env.authenticatedContext('admin',{admin:true}).firestore();
 await assertSucceeds(getDocs(collection(db,'professionalProfiles')));
 await assertSucceeds(getDoc(doc(db,'professionalProfiles/owner/documents/identity')));
 await assertSucceeds(getDocs(collection(db,'professionalAudit')));
 await assertFails(updateDoc(doc(db,'professionalProfiles/owner'),{status:'approved'}));
 await assertFails(setDoc(doc(db,'professionalAudit/fake'),{to:'approved'}));
 await assertFails(getDocs(collection(env.authenticatedContext('other').firestore(),'professionalAudit')));
});

check('catalog is shared readable data and cannot be edited even by a client with admin claim',async()=>{
 for(const context of [env.unauthenticatedContext(),env.authenticatedContext('owner'),env.authenticatedContext('admin',{admin:true})]){
  await assertSucceeds(getDoc(doc(context.firestore(),'referenceData/professionalOnboarding')));
  await assertFails(setDoc(doc(context.firestore(),'referenceData/professionalOnboarding'),{enabled:true,categories:[]}));
 }
});
