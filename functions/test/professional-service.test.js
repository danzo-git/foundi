const { test } = require('node:test');
const assert = require('node:assert/strict');
const { createProfessionalService } = require('../src/professional-service');
const catalog = { enabled: true, version: 'test-v1',
  categories: [{ id: 'test_sector', label: 'Secteur de test', specialties: [{ id: 'test_specialty' }], requirements: { independent: ['qualification'], company: ['registration', 'qualification'] } }],
  zones: [{ id: 'test_zone' }], documentTypes: [{ id: 'identity' }, { id: 'qualification' }, { id: 'registration' }] };
const activity = { type: 'independent', businessName: 'Activité de test', categoryIds: ['test_sector'], specialtyIds: ['test_specialty'], zoneIds: ['test_zone'], description: 'Description de prestations utilisée uniquement pour les tests.' };
const pdf = Buffer.from('%PDF-1.4\nTest fixture only').toString('base64');
const fails = code => error => error.code === code;
function setup() {
  const documents = new Map([
    ['referenceData/professionalOnboarding', structuredClone(catalog)],
    ['legalDocuments/current', { published: true, version: 'v1', terms: 'Test CGU', privacy: 'Test privacy' }],
    ['users/u', { termsVersion: 'v1' }],
  ]);
  let queue = Promise.resolve(), counter = 0;
  const store = { transaction(operation) {
    const job = queue.then(async () => {
      const pending = structuredClone(documents);
      const result = await operation({ get: async p => structuredClone(pending.get(p)), set: (p, v) => pending.set(p, structuredClone(v)) });
      documents.clear(); for (const [p, v] of pending) documents.set(p, v);
      return result;
    }); queue = job.catch(() => {}); return job;
  } };
  const objects = new Map();
  const users = new Map([['u', { emailVerified: true }], ['other', { emailVerified: true }], ['admin', { emailVerified: true, customClaims: { admin: true } }]]);
  const files = {
    save: async (p, bytes, type) => { objects.set(p, { bytes, type, generation: '1' }); return '1'; },
    remove: async p => { objects.delete(p); },
    exists: async (p, g) => objects.get(p)?.generation === g,
  };
  const service = createProfessionalService({ store, files, auth: { getUser: async uid => users.get(uid) || {} }, clock: () => 123456, generateId: () => 'id_' + ++counter });
  return { ...service, documents, objects, files, users, profile: () => documents.get('professionalProfiles/u') };
}
async function completeDraft(c) {
  await c.ensureDraft('u'); await c.saveActivity('u', activity, true);
  await c.uploadDocument('u', 'identity', 'identity.pdf', pdf);
  await c.uploadDocument('u', 'qualification', 'qualification.pdf', pdf);
}
test('one UID owns a resumable draft and repeated start preserves the fields and documents', async () => {
  const c = setup(); await completeDraft(c);
  await c.ensureDraft('u'); assert.equal(c.profile().status, 'draft');
  assert.equal(c.profile().onboardingStep, 3); assert.equal(c.profile().businessName, activity.businessName);
  assert.equal(c.documents.get('professionalProfiles/u/documents/identity').state, 'ready');
  assert.equal(c.documents.has('professionalProfiles/other'), false);
});
test('no authentication or unverified account can create a professional dossier', async () => {
  const c = setup(); await assert.rejects(c.ensureDraft(null), fails('unauthenticated'));
  c.users.get('u').emailVerified = false; await assert.rejects(c.ensureDraft('u'), fails('permission-denied'));
  assert.equal(c.profile(), undefined);
});
test('ordinary activity input never sets approval, step or server processing fields', async () => {
  const c = setup(); await c.ensureDraft('u'); await c.saveActivity('u', { ...activity, status: 'approved', reviewedBy: 'u', onboardingStep: 99 }, true);
  assert.equal(c.profile().status, 'draft'); assert.equal(c.profile().onboardingStep, 3); assert.equal(c.profile().reviewedBy, undefined);
});
test('missing reference configuration permits partial text drafts but blocks completion and submission', async () => {
  const c = setup(); await c.ensureDraft('u'); c.documents.delete('referenceData/professionalOnboarding');
  await c.saveActivity('u', { ...activity, categoryIds: [], specialtyIds: [], zoneIds: [] });
  await assert.rejects(c.saveActivity('u', activity, true), fails('failed-precondition'));
  await assert.rejects(c.submit('u', true), fails('failed-precondition')); assert.equal(c.profile().status, 'draft');
});
test('unknown references and missing category-specific document policy fail closed', async () => {
  const c = setup(); await c.ensureDraft('u');
  await assert.rejects(c.saveActivity('u', { ...activity, categoryIds: ['invented'] }, true), fails('failed-precondition'));
  delete c.documents.get('referenceData/professionalOnboarding').categories[0].requirements.company;
  await assert.rejects(c.saveActivity('u', { ...activity, type: 'company' }, true), fails('failed-precondition'));
});
test('company documents depend on the actual category and business type', async () => {
  const c = setup(); await completeDraft(c); await c.saveActivity('u', { ...activity, type: 'company' }, true);
  await assert.rejects(c.submit('u', true), fails('failed-precondition'));
  await c.uploadDocument('u', 'registration', 'registration.pdf', pdf); await c.submit('u', true);
  assert.equal(c.profile().status, 'pending');
});
test('submission checks certification, all required documents and actual storage objects', async () => {
  const c = setup(); await c.ensureDraft('u'); await c.saveActivity('u', activity, true);
  await assert.rejects(c.submit('u', true), fails('failed-precondition')); await completeDraft(c);
  await assert.rejects(c.submit('u', false), fails('invalid-argument'));
  c.objects.clear(); await assert.rejects(c.submit('u', true), fails('failed-precondition'));
  assert.equal(c.profile().status, 'draft');
});
test('legal documents must be published and current terms actually accepted', async () => {
  const c = setup(); await completeDraft(c); c.documents.get('legalDocuments/current').published = false;
  await assert.rejects(c.submit('u', true), fails('failed-precondition'));
  c.documents.get('legalDocuments/current').published = true; c.documents.get('users/u').termsVersion = 'old';
  await assert.rejects(c.submit('u', true), fails('failed-precondition'));
});
test('uploads reject spoofed MIME signatures, path traversal, unrequired documents and excessive bytes', async () => {
  const c = setup(); await c.ensureDraft('u'); await c.saveActivity('u', activity, true);
  await assert.rejects(c.uploadDocument('u', '../other', 'a.pdf', pdf), fails('invalid-argument'));
  await assert.rejects(c.uploadDocument('u', 'identity', 'a.pdf', Buffer.from('<script>spoofed</script>').toString('base64')), fails('invalid-argument'));
  await assert.rejects(c.uploadDocument('u', 'registration', 'a.pdf', pdf), fails('invalid-argument'));
  await assert.rejects(c.uploadDocument('u', 'identity', 'a.pdf', 'A'.repeat(7 * 1024 * 1024)), fails('invalid-argument'));
});
test('failed replacement preserves the previously associated private document', async () => {
  const c = setup(); await completeDraft(c);
  const previous = structuredClone(c.documents.get('professionalProfiles/u/documents/identity'));
  c.files.save = async () => { throw new Error('Storage offline'); };
  await assert.rejects(c.uploadDocument('u', 'identity', 'new.pdf', pdf));
  assert.deepEqual(c.documents.get('professionalProfiles/u/documents/identity'), previous);
  assert.equal(c.objects.has(previous.objectPath), true);
});
test('a real maximum-size payload is accepted and invalid base64 is refused', async () => {
  const c = setup(); await c.ensureDraft('u'); await c.saveActivity('u', activity, true);
  const bytes = Buffer.alloc(5 * 1024 * 1024, 32); bytes.write('%PDF-1.4\n');
  await c.uploadDocument('u', 'identity', 'large.pdf', bytes.toString('base64'));
  assert.equal(c.documents.get('professionalProfiles/u/documents/identity').size, bytes.length);
  await assert.rejects(c.uploadDocument('u', 'identity', 'invalid.pdf', '%%%%'), fails('invalid-argument'));
});
test('pending is idempotent and never grants professional access or allows further edits', async () => {
  const c = setup(); await completeDraft(c); await c.submit('u', true); await c.submit('u', true);
  await assert.rejects(c.requireApproved('u'), fails('permission-denied'));
  await assert.rejects(c.saveActivity('u', activity, true), fails('failed-precondition'));
  await assert.rejects(c.uploadDocument('u', 'identity', 'a.pdf', pdf), fails('failed-precondition'));
});
test('only a currently authorized reviewer can approve and decisions are audited and notified', async () => {
  const c = setup(); await completeDraft(c); await c.submit('u', true);
  await assert.rejects(c.decide('u', { admin: true }, 'u', 'approved'), fails('permission-denied'));
  await assert.rejects(c.decide('admin', {}, 'u', 'approved'), fails('permission-denied'));
  await c.decide('admin', { admin: true }, 'u', 'approved');
  assert.deepEqual(await c.requireApproved('u'), { approved: true });
  assert.equal(c.documents.get('users/u/notifications/professionalDecision').status, 'approved');
  assert.equal([...c.documents.keys()].filter(k => k.startsWith('professionalAudit/')).length, 1);
});
test('revoked reviewer claims and draft approval are refused', async () => {
  const c = setup(); await c.ensureDraft('u');
  await assert.rejects(c.decide('admin', { admin: true }, 'u', 'approved'), fails('failed-precondition'));
  c.users.get('admin').customClaims = {};
  await assert.rejects(c.decide('admin', { admin: true }, 'u', 'approved'), fails('permission-denied'));
});
test('rejected and suspended accounts never have professional permissions', async () => {
  for (const status of ['rejected', 'suspended']) {
    const c = setup(); await completeDraft(c); await c.submit('u', true);
    if (status === 'suspended') await c.decide('admin', { admin: true }, 'u', 'approved');
    await c.decide('admin', { admin: true }, 'u', status, 'Motif de test');
    await assert.rejects(c.requireApproved('u'), fails('permission-denied'));
  }
});

test('corrections require a reason, preserve documents, resubmit and reject stale reviews', async () => {
  const c=setup(); await completeDraft(c); await c.submit('u',true);
  await assert.rejects(c.decide('admin',{admin:true},'u','needs_changes'),fails('invalid-argument'));
  await assert.rejects(c.decide('admin',{admin:true},'u','approved','',-1),fails('aborted'));
  await c.decide('admin',{admin:true},'u','needs_changes','Document illisible',c.profile().revision);
  await assert.rejects(c.requireApproved('u'),fails('permission-denied'));
  await c.saveActivity('u',activity,true);
  await c.uploadDocument('u','identity','corrected.pdf',pdf);
  await c.submit('u',true); assert.equal(c.profile().status,'pending');
  await c.decide('admin',{admin:true},'u','approved','',c.profile().revision);
  assert.equal(c.profile().status,'approved');
  assert.equal([...c.documents.keys()].filter(k=>k.startsWith('professionalAudit/')).length,2);
});
test('legacy reviewer alone cannot administer Foundi', async()=>{
  const c=setup();await completeDraft(c);await c.submit('u',true);
  await assert.rejects(c.decide('admin',{professionalReviewer:true},'u','approved'),fails('permission-denied'));
});

test('disabled category, specialty or ancestor zone blocks submission without losing a draft',async()=>{
 for(const kind of ['category','specialty','zone']){
  const c=setup();await completeDraft(c);const catalog=c.documents.get('referenceData/professionalOnboarding');
  if(kind==='category')catalog.categories[0].active=false;
  if(kind==='specialty')catalog.categories[0].specialties[0].active=false;
  if(kind==='zone'){catalog.zones.push({id:'parent',active:false});catalog.zones[0].parentId='parent';}
  await assert.rejects(c.submit('u',true),fails('failed-precondition'));assert.equal(c.profile().status,'draft');
 }
});
