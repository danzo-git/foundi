const { test } = require('node:test');

const assert = require('node:assert/strict');

const { createRequestService } = require('../src/request-service');

const request = { categoryId: 'services', specialtyId: 'plomberie', zoneId: 'cocody', title: 'Réparer une fuite', description: 'Une fuite à réparer dans ma cuisine.', budget: 15000 };

const id = 'RequestIdentifier00001';

function setup() {

  const data = new Map([['referenceData/professionalOnboarding', { enabled: true,

    categories: [{ id: 'services', label: 'Services', specialties: [{ id: 'plomberie', label: 'Plomberie' }] }],

    zones: [{ id: 'ci', label: 'Côte d’Ivoire' }, { id: 'cocody', label: 'Cocody', parentId: 'ci' }] }]]);

  let pending = Promise.resolve(), now = 123456, failedWrite = null;
  const reads = [];

  const store = { transaction(operation) {

    const job = pending.then(async () => {

      const copy = structuredClone(data); let writing = false;

      const result = await operation({ get: async p => { assert.equal(writing, false); reads.push(p); return copy.get(p); },

        set: (p, v) => { if (p === failedWrite) throw Error('Simulated transaction failure'); writing = true; copy.set(p, v); } });

      data.clear(); for (const [p, v] of copy) data.set(p, v); return result;

    }); pending = job.catch(() => {}); return job;

  } };

  const account = { disabled: false, emailVerified: true };

  return { ...createRequestService({ store, auth: { getUser: async () => account }, clock: () => now }), data, account, reads,
    setTime: value => { now = value; }, failWrite: path => { failedWrite = path; } };

}

const fails = code => error => error.code === code;

test('active verified accounts can publish; public projection excludes UID, contacts and injected fields', async () => {

  const c = setup();

  const result = await c.publish('client', id, { ...request, ownerId: 'victim', email: 'private@example.test', status: 'approved', createdAt: 0 });

  assert.equal(result.status, 'published'); assert.equal(result.createdAt, 123456);

  assert.equal(result.zoneLabel, 'Côte d’Ivoire › Cocody');

  const saved = c.data.get('requests/' + id);

  assert.deepEqual(Object.keys(saved).sort(), ['categoryId','specialtyId','zoneId','title','description','budget','categoryLabel','specialtyLabel','zoneLabel','status','createdAt'].sort());

  assert.deepEqual(saved, c.data.get('userRequests/client/items/' + id));

  assert.equal(c.data.has('userRequests/victim/items/' + id), false);
  assert.deepEqual(c.data.get('requestPublicationLimits/client'), { schemaVersion: 92, createdAtMs: [123456] });

  await c.publish('professional', id + '2', request);

});

test('publication is atomic and idempotent under double clicks, lost responses and changed references', async () => {

  const c = setup();

  const results = await Promise.all([c.publish('u', id, request), c.publish('u', id, request)]);

  assert.deepEqual(results[0], results[1]);
  assert.deepEqual(c.data.get('requestPublicationLimits/u').createdAtMs, [123456]);

  c.data.get('referenceData/professionalOnboarding').enabled = false;

  assert.deepEqual(await c.publish('u', id, { ...request, title: 'Autre contenu' }), results[0]);
  c.reads.length = 0;
  c.setTime(123456 + 8 * 86400000);
  assert.deepEqual(await c.publish('u', id, null), results[0]);
  assert.deepEqual(c.reads, [`userRequests/u/items/${id}`]);
  assert.deepEqual(c.data.get('requestPublicationLimits/u').createdAtMs, [123456]);

  assert.equal([...c.data.keys()].filter(p => p.startsWith('requests/')).length, 1);

  await assert.rejects(c.publish('other', id, request), fails('already-exists'));

});

test('anonymous and disabled accounts cannot publish', async () => {

  const c = setup(); await assert.rejects(c.publish(null, id, request), fails('unauthenticated'));

  c.account.disabled = true; await assert.rejects(c.publish('u', id, request), fails('permission-denied'));

  assert.equal(c.data.size, 1);

});

test('email verification is required from Auth; client flags cannot forge it or consume quota', async () => {
  for (const emailVerified of [false, undefined, null, 'true']) {
    const c = setup(); c.account.emailVerified = emailVerified;
    await assert.rejects(c.publish('u', id, { ...request, emailVerified: true, registrationConfirmed: true }),
      e => e.code === 'failed-precondition' && e.message === 'Vérifie ton adresse e-mail avant de publier une demande.');
    assert.equal(c.data.size, 1); assert.deepEqual(c.reads, []);
  }
});

test('invalid budgets, IDs and required texts are rejected before any write', async () => {

  const c = setup();

  for (const budget of [-1, 1.5, '1200', undefined, Infinity, 1000000000000]) {

    await assert.rejects(c.publish('u', id, { ...request, budget }), fails('invalid-argument'));

  }

  for (const change of [{ title: '' }, { description: ' ' }, { categoryId: '../users' }, { specialtyId: null }, { zoneId: '' }]) {

    await assert.rejects(c.publish('u', id, { ...request, ...change }), fails('invalid-argument'));

  }

  await assert.rejects(c.publish('u', '../bad', request), fails('invalid-argument'));

  assert.equal(c.data.size, 1);

});

test('inactive, missing and mismatched references including ancestors fail without orphaned documents', async () => {

  for (const kind of ['disabled', 'category', 'specialty', 'zone', 'ancestor', 'missingParent', 'cycle']) {

    const c = setup(), catalog = c.data.get('referenceData/professionalOnboarding');

    if (kind === 'disabled') catalog.enabled = false;

    if (kind === 'category') catalog.categories[0].active = false;

    if (kind === 'specialty') catalog.categories[0].specialties[0].active = false;

    if (kind === 'zone') catalog.zones[1].active = false;

    if (kind === 'ancestor') catalog.zones[0].active = false;

    if (kind === 'missingParent') catalog.zones[1].parentId = 'missing';

    if (kind === 'cycle') catalog.zones[0].parentId = 'cocody';

    await assert.rejects(c.publish('u', id, request), fails('failed-precondition'));

    assert.equal(c.data.size, 1);

  }

});

test('categories without specialties and optional budgets are supported', async () => {

  const c = setup(); c.data.get('referenceData/professionalOnboarding').categories[0].specialties = [];

  const result = await c.publish('u', id, { ...request, specialtyId: '', budget: null });

  assert.equal(result.specialtyLabel, ''); assert.equal(result.budget, null);

});



 test('owner lifecycle is atomic, protected and idempotent', async () => {

  const c = setup(); await c.publish('u', id, request);
  const quota = structuredClone(c.data.get('requestPublicationLimits/u'));
  c.account.emailVerified = false;

  await assert.rejects(c.manage('other', id, 'close'), fails('permission-denied'));

  await assert.rejects(c.manage('u', id, 'edit', {...request, createdAt: 0}), fails('invalid-argument'));

  c.data.get('userRequests/u/items/' + id).internalNote = 'private';
  const edited = await c.manage('u', id, 'edit', {...request, title: 'Un nouveau titre'}, 123456);

  await assert.rejects(c.manage('u', id, 'edit', request, 123456), fails('aborted'));
  assert.equal('internalNote' in c.data.get('requests/' + id), false);
  assert.equal(edited.id, id); assert.equal(edited.createdAt, 123456);

  assert.equal(c.data.get('requests/' + id).title, 'Un nouveau titre');

  const closed = await c.manage('u', id, 'close');

  assert.deepEqual(await c.manage('u', id, 'close'), closed);

  assert.equal(c.data.get('requests/' + id).status, 'closed');

  await assert.rejects(c.manage('u', id, 'edit', request), fails('failed-precondition'));

  await c.manage('u', id, 'delete'); await c.manage('u', id, 'delete');

  assert.equal(c.data.get('requests/' + id).status, 'deleted');
  assert.deepEqual(c.data.get('requestPublicationLimits/u'), quota);

 });

test('60-second cooldown is per UID, rejects at 59999 ms and accepts exactly at 60000 ms', async () => {
  const c = setup(), start = 123456;
  await c.publish('u', id, request);
  c.setTime(start + 59999);
  const before = structuredClone(c.data);
  await assert.rejects(c.publish('u', id + '2', request), fails('resource-exhausted'));
  assert.deepEqual(c.data, before);
  await c.publish('other', id + '3', request);
  c.setTime(start + 60000);
  await c.publish('u', id + '2', request);
  assert.deepEqual(c.data.get('requestPublicationLimits/u').createdAtMs, [start, start + 60000]);
});

test('five creations per rolling 24 hours; exact expiry releases one slot, retries bypass a full quota', async () => {
  const c = setup(), start = 123456;
  let saved;
  for (let i = 0; i < 5; i++) {
    c.setTime(start + i * 60000);
    const result = await c.publish('u', id + i, request);
    if (!i) saved = result;
  }
  c.setTime(start + 86400000 - 1);
  const before = structuredClone(c.data);
  await assert.rejects(c.publish('u', id + 'next', request), e => e.code === 'resource-exhausted' && e.message.includes('5 nouvelles demandes sur 24 heures'));
  assert.deepEqual(c.data, before);
  assert.deepEqual(await c.publish('u', id + '0', request), saved);
  assert.deepEqual(c.data, before);
  c.setTime(start + 86400000);
  await c.publish('u', id + 'next', request);
  assert.equal(c.data.get('requestPublicationLimits/u').createdAtMs.length, 6);
  assert.equal(c.data.get('requestPublicationLimits/u').createdAtMs.filter(t => t > start).length, 5);
});

test('twenty creations per rolling seven days; exact expiry and automatic bounded pruning', async () => {
  const c = setup(), start = 123456, day = 86400000;
  for (let d = 0; d < 4; d++) for (let slot = 0; slot < 5; slot++) {
    c.setTime(start + d * day + slot * 60000);
    await c.publish('u', `${id}_${d}_${slot}`, request);
  }
  assert.equal(c.data.get('requestPublicationLimits/u').createdAtMs.length, 20);
  c.setTime(start + 7 * day - 1);
  const before = structuredClone(c.data);
  await assert.rejects(c.publish('u', id + '_blocked', request), e => e.code === 'resource-exhausted' && e.message.includes('20 nouvelles demandes sur 7 jours'));
  assert.deepEqual(c.data, before);
  c.setTime(start + 7 * day);
  await c.publish('u', id + '_expiry', request);
  const times = c.data.get('requestPublicationLimits/u').createdAtMs;
  assert.equal(times.length, 20); assert.ok(!times.includes(start));
  c.setTime(start + 15 * day);
  await c.publish('u', id + '_pruned', request);
  assert.deepEqual(c.data.get('requestPublicationLimits/u').createdAtMs, [start + 15 * day]);
});

test('simultaneous different IDs cannot bypass the shared quota document', async () => {
  const c = setup();
  const jobs = await Promise.allSettled([c.publish('u', id, request), c.publish('u', id + '2', request)]);
  assert.equal(jobs.filter(r => r.status === 'fulfilled').length, 1);
  assert.equal(jobs.find(r => r.status === 'rejected').reason.code, 'resource-exhausted');
  assert.equal(c.data.get('requestPublicationLimits/u').createdAtMs.length, 1);
  assert.equal([...c.data.keys()].filter(p => p.startsWith('requests/')).length, 1);
});

test('failed writes roll back publication, ownership and quota; retry creates exactly once', async () => {
  const c = setup();
  c.failWrite('requestPublicationLimits/u');
  const before = structuredClone(c.data);
  await assert.rejects(c.publish('u', id, request), /Simulated transaction failure/);
  assert.deepEqual(c.data, before);
  c.failWrite(null);
  await c.publish('u', id, request);
  assert.deepEqual(c.data.get('requestPublicationLimits/u').createdAtMs, [123456]);
});

test('closing or deleting gives no quota refund and retries do not recreate deleted requests', async () => {
  const c = setup(); await c.publish('u', id, request);
  await c.manage('u', id, 'close'); await c.manage('u', id, 'delete');
  const before = structuredClone(c.data);
  const repeated = await c.publish('u', id, request);
  assert.equal(repeated.status, 'deleted'); assert.deepEqual(c.data, before);
  await assert.rejects(c.publish('u', id + 'new', request), fails('resource-exhausted'));
  assert.deepEqual(c.data, before);
});

test('invalid new attempts preserve existing quota, and malformed server quota fails closed', async () => {
  const c = setup(); await c.publish('u', id, request); c.setTime(123456 + 60000);
  const before = structuredClone(c.data);
  await assert.rejects(c.publish('u', id + 'bad', { ...request, description: '' }), fails('invalid-argument'));
  assert.deepEqual(c.data, before);
  c.data.get('referenceData/professionalOnboarding').enabled = false;
  const disabled = structuredClone(c.data);
  await assert.rejects(c.publish('u', id + 'bad', request), fails('failed-precondition'));
  assert.deepEqual(c.data, disabled);
  for (const value of [null, 'bad', [NaN], [-1]]) {
    const malformed = setup(); malformed.data.set('requestPublicationLimits/u', {createdAtMs:value});
    const snapshot = structuredClone(malformed.data);
    await assert.rejects(malformed.publish('u', id, request), fails('failed-precondition'));
    assert.deepEqual(malformed.data, snapshot);
  }
});

