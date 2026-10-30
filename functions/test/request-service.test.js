const { test } = require('node:test');

const assert = require('node:assert/strict');

const { createRequestService } = require('../src/request-service');

const request = { categoryId: 'services', specialtyId: 'plomberie', zoneId: 'cocody', title: 'Réparer une fuite', description: 'Une fuite à réparer dans ma cuisine.', budget: 15000 };

const id = 'RequestIdentifier00001';

function setup() {

  const data = new Map([['referenceData/professionalOnboarding', { enabled: true,

    categories: [{ id: 'services', label: 'Services', specialties: [{ id: 'plomberie', label: 'Plomberie' }] }],

    zones: [{ id: 'ci', label: 'Côte d’Ivoire' }, { id: 'cocody', label: 'Cocody', parentId: 'ci' }] }]]);

  let pending = Promise.resolve();

  const store = { transaction(operation) {

    const job = pending.then(async () => {

      const copy = structuredClone(data); let writing = false;

      const result = await operation({ get: async p => { assert.equal(writing, false); return copy.get(p); },

        set: (p, v) => { writing = true; copy.set(p, v); } });

      data.clear(); for (const [p, v] of copy) data.set(p, v); return result;

    }); pending = job.catch(() => {}); return job;

  } };

  const account = { disabled: false, emailVerified: false };

  return { ...createRequestService({ store, auth: { getUser: async () => account }, clock: () => 123456 }), data, account };

}

const fails = code => error => error.code === code;

test('any authenticated account can publish; public projection excludes UID, contacts and injected fields', async () => {

  const c = setup();

  const result = await c.publish('client', id, { ...request, ownerId: 'victim', email: 'private@example.test', status: 'approved', createdAt: 0 });

  assert.equal(result.status, 'published'); assert.equal(result.createdAt, 123456);

  assert.equal(result.zoneLabel, 'Côte d’Ivoire › Cocody');

  const saved = c.data.get('requests/' + id);

  assert.deepEqual(Object.keys(saved).sort(), ['categoryId','specialtyId','zoneId','title','description','budget','categoryLabel','specialtyLabel','zoneLabel','status','createdAt'].sort());

  assert.deepEqual(saved, c.data.get('userRequests/client/items/' + id));

  assert.equal(c.data.has('userRequests/victim/items/' + id), false);

  await c.publish('professional', id + '2', request);

});

test('publication is atomic and idempotent under double clicks, lost responses and changed references', async () => {

  const c = setup();

  const results = await Promise.all([c.publish('u', id, request), c.publish('u', id, request)]);

  assert.deepEqual(results[0], results[1]);

  c.data.get('referenceData/professionalOnboarding').enabled = false;

  assert.deepEqual(await c.publish('u', id, { ...request, title: 'Autre contenu' }), results[0]);

  assert.equal([...c.data.keys()].filter(p => p.startsWith('requests/')).length, 1);

  await assert.rejects(c.publish('other', id, request), fails('already-exists'));

});

test('anonymous and disabled accounts cannot publish', async () => {

  const c = setup(); await assert.rejects(c.publish(null, id, request), fails('unauthenticated'));

  c.account.disabled = true; await assert.rejects(c.publish('u', id, request), fails('permission-denied'));

  assert.equal(c.data.size, 1);

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

 });

