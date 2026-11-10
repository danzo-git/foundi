const test = require('node:test');
const assert = require('node:assert/strict');
const { key } = require('../src/notification-policy');
const { createRequestInteractionService } = require('../src/request-interaction-service');

const requestId = 'RequestInteraction00001';
const open = { status: 'published', createdAt: 10, categoryId: 'services', specialtyId: 'repair', zoneId: 'cocody' };
const approved = { status: 'approved', businessName: 'Atelier Ébène', categoryIds: ['services'],
  specialtyIds: ['repair'], zoneIds: ['cocody'], phone: 'secret', documents: ['secret'] };
const catalog = { categories: [{ id: 'services', label: 'Services', specialties: [{ id: 'repair', label: 'Réparation' }] }],
  zones: [{ id: 'cocody', label: 'Cocody' }] };
const seeded = () => {
  const docs = new Map([
    [`requests/${requestId}`, open],
    [`userRequests/owner/items/${requestId}`, { ...open, proposalCount: 2 }],
    ['professionalProfiles/pro', approved],
    ['professionalProfiles/other-pro', { ...approved, businessName: 'Atelier Autre', categoryIds: [], zoneIds: [] }],
    ['professionalProfiles/disabled', approved],
    ['professionalProfiles/pending', { ...approved, status: 'pending' }],
    ['referenceData/professionalOnboarding', catalog],
  ]);
  const account = (uid) => ({ uid, emailVerified: uid !== 'unverified', disabled: uid === 'disabled' });
  let clock = 1000, queue = Promise.resolve();
  const store = {
    get: async (path) => docs.get(path),
    approvedPage: async (cursor, limit) => Array.from(docs).filter(([path, value]) =>
      path.startsWith('professionalProfiles/') && value.status === 'approved')
      .map(([path, profile]) => ({ id: path.split('/')[1], profile }))
      .sort((a, b) => a.id.localeCompare(b.id))
      .filter(({ id }) => cursor == null || id > cursor).slice(0, limit),
    transaction(operation) {
      const run = queue.then(async () => {
        const working = new Map(docs);
        const result = await operation({
          get: async (path) => working.get(path),
          set: (path, value) => working.set(path, value),
          delete: (path) => working.delete(path),
        });
        docs.clear();
        for (const entry of working) docs.set(...entry);
        return result;
      });
      queue = run.catch(() => {});
      return run;
    },
  };
  const auth = { getUser: async (uid) => account(uid), getUsers: async (ids) => ({ users: ids.map(({ uid }) => account(uid)) }) };
  return { docs, service: createRequestInteractionService({ store, auth, ownerForRequest: async () => 'owner',
    clock: () => clock }), nextDay: () => { clock += 86400000; } };
};

test('likes are explicit, transactional, idempotent and never touch the request or publication quota', async () => {
  const { service, docs } = seeded();
  const set = (uid, liked) => service.setLike(uid, requestId, liked);
  await assert.rejects(set(undefined, true), { code: 'unauthenticated' });
  await assert.rejects(set('disabled', true), { code: 'permission-denied' });
  await assert.rejects(set('unverified', true), { code: 'permission-denied' });
  await assert.rejects(set('alice', 'true'), { code: 'invalid-argument' });
  await Promise.all([set('alice', true), set('alice', true), set('bob', true)]);
  const path = `requestEngagement/${requestId}`;
  assert.deepEqual(docs.get(path), { likeCount: 2 });
  assert.deepEqual(await set('alice', false), { liked: false, likeCount: 1 });
  assert.deepEqual(await set('alice', false), { liked: false, likeCount: 1 });
  assert.equal(docs.has(`${path}/likes/alice`), false);
  assert.deepEqual(docs.get(`requests/${requestId}`), open);
  assert.equal(docs.has('requestPublicationLimits/alice'), false);
  docs.set(`requests/${requestId}`, { ...open, status: 'closed' });
  await assert.rejects(set('alice', true), { code: 'failed-precondition' });
});

test('directory filters approvals and active accounts, ranks compatibility and returns public fields only', async () => {
  const { service, docs } = seeded();
  docs.set('professionalProfiles/contact-name', { ...approved, businessName: 'mail@example.test' });
  const results = await service.search('alice', requestId);
  assert.deepEqual(results.items.map(({ id }) => id), ['pro', 'other-pro']);
  assert.deepEqual(results.items[0], { id: 'pro', name: 'Atelier Ébène',
    categories: ['Services'], specialties: ['Réparation'], zones: ['Cocody'] });
  assert.equal((await service.search('alice', requestId, 'ebene')).items.length, 1);
  assert.deepEqual((await service.search('pro', requestId)).items.map(({ id }) => id), ['other-pro']);
  await assert.rejects(service.search('alice', requestId, '', '../private'), { code: 'invalid-argument' });
  for (let i = 0; i < 26; i++) docs.set('professionalProfiles/worker' + i, approved);
  const first = await service.search('alice', requestId);
  assert.ok(first.cursor);
  const second = await service.search('alice', requestId, '', first.cursor);
  assert.equal(second.cursor, null);
  assert.equal(new Set([...first.items, ...second.items].map(({ id }) => id)).size, 28);
});

test('recommendation validates ownership and eligibility, is idempotent, and grants a revocable read to the owner', async () => {
  const { service, docs } = seeded();
  const recommend = (uid, pro) => service.recommend(uid, requestId, pro);
  await assert.rejects(recommend('pro', 'pro'), { code: 'invalid-argument' });
  await assert.rejects(recommend('alice', 'pending'), { code: 'failed-precondition' });
  await assert.rejects(recommend('alice', 'disabled'), { code: 'failed-precondition' });
  const outcomes = await Promise.all([recommend('alice', 'pro'), recommend('alice', 'pro')]);
  assert.deepEqual(outcomes, [{ alreadyRecommended: false }, { alreadyRecommended: true }]);
  const recId = key(requestId, 'alice', 'pro');
  assert.equal(docs.get(`requestRecommendations/${recId}`).ownerUid, 'owner');
  await assert.rejects(service.readRecommendation('alice', recId), { code: 'not-found' });
  assert.equal((await service.readRecommendation('owner', recId)).name, 'Atelier Ébène');
  assert.equal(docs.get(`userRequests/owner/items/${requestId}`).proposalCount, 2);
  assert.deepEqual(docs.get(`requests/${requestId}`), open);
  docs.set('professionalProfiles/pro', { ...approved, status: 'suspended' });
  await assert.rejects(service.readRecommendation('owner', recId), { code: 'not-found' });
  await assert.rejects(recommend('alice', 'pro'), { code: 'failed-precondition' });
});

test('recommendation and like budgets are separate, bounded, and reset daily', async () => {
  const { service, docs, nextDay } = seeded();
  for (let i = 0; i <= 10; i++) {
    docs.set(`professionalProfiles/worker${i}`, approved);
    if (i < 10) await service.recommend('alice', requestId, `worker${i}`);
  }
  await assert.rejects(service.recommend('alice', requestId, 'worker10'), { code: 'resource-exhausted' });
  assert.deepEqual(await service.recommend('alice', requestId, 'worker0'), { alreadyRecommended: true });
  assert.equal((await service.setLike('alice', requestId, true)).likeCount, 1);
  nextDay();
  assert.deepEqual(await service.recommend('alice', requestId, 'worker10'), { alreadyRecommended: false });
});
