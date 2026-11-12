const { test } = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const path = require('node:path');
const sharp = require('sharp');
const { createRequestPhotoService } = require('../src/request-photo-service');
const { createRequestService } = require('../src/request-service');

const id = 'RequestWithPhotos0001';
const keys = ['a', 'b', 'c', 'd'].map((letter) => letter.repeat(32));
const raw = readFileSync(path.join(__dirname, 'fixtures/photo.png'));
const data = {
  categoryId: 'home', specialtyId: '', zoneId: 'cocody',
  title: 'Réparer un meuble', description: 'Je cherche de l’aide pour réparer ce meuble.', budget: null,
};
const is = (code) => (error) => error.code === code;

function fixture() {
  const documents = new Map([
    ['referenceData/professionalOnboarding', {
      enabled: true, categories: [{ id: 'home', label: 'Maison' }],
      zones: [{ id: 'cocody', label: 'Cocody' }],
    }],
    ['professionalProfiles/pro', { status: 'approved' }],
    ['professionalProfiles/pending', { status: 'pending' }],
  ]);
  const objects = new Map();
  let queue = Promise.resolve();
  let now = 1000000;
  let count = 0;
  let failSave = false;
  let failRemove = false;
  const clock = () => now;
  const auth = { getUser: async (uid) => ({ disabled: uid === 'disabled', emailVerified: uid !== 'unverified' }) };
  const store = {
    transaction(operation) {
      const job = queue.then(async () => {
        const next = structuredClone(documents);
        let writing = false;
        const result = await operation({
          get: async (p) => { assert.equal(writing, false, 'read after transaction write'); return next.get(p); },
          set: (p, value) => { writing = true; next.set(p, value); },
          delete: (p) => { writing = true; next.delete(p); },
        });
        documents.clear();
        for (const [p, value] of next) documents.set(p, value);
        return result;
      });
      queue = job.catch(() => {});
      return job;
    },
    expiredRequestPhotos: async (time) => [...documents]
      .filter(([p, v]) => p.startsWith('requestPhotoFiles/') && v.deleteAt != null && v.deleteAt <= time)
      .map(([p]) => p),
  };
  const files = {
    async save(p, bytes, hash) {
      if (!objects.has(p)) objects.set(p, { bytes, hash });
      assert.equal(objects.get(p).hash, hash);
      if (failSave) throw Error('lost response after Storage save');
      return '1';
    },
    async read(p) { return objects.get(p).bytes; },
    async remove(p) {
      if (failRemove) throw Error('Storage offline');
      objects.delete(p);
    },
  };
  const photos = createRequestPhotoService({ store, auth, files, clock, newId: () => 'object-' + ++count });
  return {
    ...photos, ...createRequestService({ store, auth, photos, clock }), documents, objects,
    advance: (ms) => now += ms,
    failSave: (value) => failSave = value,
    failRemove: (value) => failRemove = value,
  };
}

test('three real photos link atomically with V9.2 publication and have no public storage metadata', async () => {
  const c = fixture();
  const input = { ...data, photoIds: keys.slice(0, 3) };
  await assert.rejects(c.publish('owner', id, input), is('failed-precondition'));
  for (const [index, type] of ['image/jpeg', 'image/png', 'image/webp'].entries()) {
    const bytes = await sharp(raw).withMetadata({ orientation: 6 }).toFormat(type.slice(6)).toBuffer();
    await c.upload('owner', id, keys[index], bytes, type);
  }
  await assert.rejects(c.upload('owner', id, keys[3], raw, 'image/png'), is('resource-exhausted'));
  await assert.rejects(c.upload('other', id, keys[3], raw, 'image/png'), is('permission-denied'));
  await assert.rejects(c.read('owner', id, keys[0]), is('not-found'));
  await assert.rejects(c.publish('other', id, input), is('failed-precondition'));
  await assert.rejects(c.publish('owner', id, { ...input, photoIds: [keys[0], keys[0]] }), is('invalid-argument'));
  await assert.rejects(c.publish('owner', id, { ...input, photoIds: keys }), is('invalid-argument'));
  assert.equal(c.documents.has('requestPublicationLimits/owner'), false);
  const [first, second] = await Promise.all([c.publish('owner', id, input), c.publish('owner', id, input)]);
  assert.deepEqual(first, second);
  assert.deepEqual(first.photoIds, input.photoIds);
  assert.equal(first.status, 'published');
  assert.deepEqual(c.documents.get('requestPublicationLimits/owner').createdAtMs, [first.createdAt]);
  assert.equal(c.objects.size, 3);
  assert.deepEqual(await c.publish('owner', id, { ...data, photoIds: [] }), first);
  assert.deepEqual(await c.upload('owner', id, keys[0], raw, 'image/png'), { published: true });
  assert.equal(c.objects.size, 3);
  assert.doesNotMatch(JSON.stringify(c.documents.get('requests/' + id)), /uid|generation|requestPhotos|token/i);
  const bytes = await c.read('pro', id, keys[0]);
  const meta = await sharp(bytes).metadata();
  assert.equal(meta.format, 'webp');
  assert.equal(meta.exif, undefined);
  assert.deepEqual(await c.read('owner', id, keys[0]), bytes);
  await assert.rejects(c.read(null, id, keys[0]), is('unauthenticated'));
  for (const uid of ['other', 'pending', 'unverified', 'disabled']) {
    await assert.rejects(c.read(uid, id, keys[0]), is('permission-denied'));
  }
  await assert.rejects(c.read('pro', id + 'Other', keys[0]), is('not-found'));
  const edited = await c.manage('owner', id, 'edit', { ...data, title: 'Titre corrigé' }, first.createdAt);
  assert.deepEqual(edited.photoIds, input.photoIds);
  assert.deepEqual(c.documents.get('requests/' + id).photoIds, input.photoIds);
  await assert.rejects(c.manage('owner', id, 'edit', { ...data, photoIds: [keys[3]] }, edited.updatedAt), is('failed-precondition'));
  await c.manage('owner', id, 'close');
  await assert.rejects(c.read('pro', id, keys[0]), is('not-found'));
  assert.equal(c.objects.size, 3);
  await c.manage('owner', id, 'delete');
  await assert.rejects(c.read('owner', id, keys[0]), is('not-found'));
  assert.equal(c.documents.get('requests/' + id).photoIds, undefined);
  assert.deepEqual(await c.cleanup(), { removed: 3, failed: 0 });
  assert.equal(c.objects.size, 0);
  assert.deepEqual(c.documents.get('requestPublicationLimits/owner').createdAtMs, [first.createdAt]);
});

test('editing replaces photos atomically, retries the same revision and preserves proposals and quotas', async () => {
  const c = fixture();
  for (const key of keys.slice(0, 3)) await c.upload('owner', id, key, raw, 'image/png');
  const original = await c.publish('owner', id, { ...data, photoIds: keys.slice(0, 3), photosPublic: true });
  const quota = structuredClone(c.documents.get('requestPublicationLimits/owner'));
  const ownPath = `userRequests/owner/items/${id}`;
  c.documents.set(ownPath, { ...c.documents.get(ownPath), proposalCount: 2, selectedProposalId: 'private-proposal' });
  const proposal = { requestId: id, amount: 75000, description: 'Contenu privé' };
  c.documents.set('proposals/private-proposal', proposal);

  await assert.rejects(c.upload('other', id, keys[3], raw, 'image/png'), is('permission-denied'));
  c.failSave(true);
  await assert.rejects(c.upload('owner', id, keys[3], raw, 'image/png'));
  assert.deepEqual(c.documents.get('requests/' + id).photoIds, original.photoIds);
  c.failSave(false);
  await c.upload('owner', id, keys[3], raw, 'image/png');
  await assert.rejects(c.readPublic(id, keys[3]), is('not-found'));
  const edit = { ...data, photoIds: [keys[1], keys[3]], photosPublic: true };
  const beforeInvalid = structuredClone(c.documents);
  await assert.rejects(c.manage('owner', id, 'edit', { ...edit, photoIds: keys }, original.createdAt), is('invalid-argument'));
  assert.deepEqual(c.documents, beforeInvalid);
  const [saved, retried] = await Promise.all([
    c.manage('owner', id, 'edit', edit, original.createdAt),
    c.manage('owner', id, 'edit', edit, original.createdAt),
  ]);
  assert.deepEqual(retried, saved);
  assert.equal(saved.id, original.id);
  assert.equal(saved.createdAt, original.createdAt);
  assert.equal(saved.status, 'published');
  assert.equal(saved.proposalCount, 2);
  assert.equal(saved.selectedProposalId, 'private-proposal');
  assert.deepEqual(c.documents.get('proposals/private-proposal'), proposal);
  assert.deepEqual(c.documents.get('requestPublicationLimits/owner'), quota);
  assert.deepEqual(c.documents.get('requests/' + id).photoIds, edit.photoIds);
  assert.equal(c.documents.get('requests/' + id).lastEdit, undefined);
  await assert.rejects(c.manage('owner', id, 'edit', { ...edit, title: 'Autre modification' }, original.createdAt), is('aborted'));
  for (const key of [keys[0], keys[2]]) await assert.rejects(c.readPublic(id, key), is('not-found'));
  for (const key of edit.photoIds) assert.ok((await c.readPublic(id, key)).length);
  assert.deepEqual(await c.cleanup(), { removed: 2, failed: 0 });
  assert.equal(c.objects.size, 2);

  const empty = await c.manage('owner', id, 'edit', { ...data, photoIds: [], photosPublic: false }, saved.updatedAt);
  assert.equal(empty.photoIds, undefined);
  assert.equal(empty.photosPublic, undefined);
  assert.equal(c.documents.get('requests/' + id).photoIds, undefined);
  assert.deepEqual(await c.cleanup(), { removed: 2, failed: 0 });
  assert.equal(c.objects.size, 0);
});

test('discarded and expired edit uploads never remove linked photos or reopen a closed request', async () => {
  const c = fixture();
  await c.upload('owner', id, keys[0], raw, 'image/png');
  const original = await c.publish('owner', id, { ...data, photoIds: [keys[0]] });
  await c.upload('owner', id, keys[1], raw, 'image/png');
  await c.discard('owner', id, [keys[0], keys[1]]);
  assert.equal(c.documents.get(`requestPhotoFiles/${id}_${keys[0]}`).state, 'linked');
  assert.deepEqual(c.documents.get('requests/' + id).photoIds, [keys[0]]);
  await c.upload('owner', id, keys[2], raw, 'image/png');
  await c.manage('owner', id, 'close');
  await assert.rejects(c.upload('owner', id, keys[3], raw, 'image/png'), is('failed-precondition'));
  await assert.rejects(c.manage('owner', id, 'edit', { ...data, photoIds: [keys[2]] }, original.createdAt), is('failed-precondition'));
  c.advance(25 * 3600000);
  assert.deepEqual(await c.cleanup(), { removed: 2, failed: 0 });
  assert.equal(c.documents.get(`requestPhotoFiles/${id}_${keys[0]}`).state, 'linked');
  assert.equal(c.objects.size, 1);
});

test('public photo reads require explicit consent on first publication and stop on closure', async () => {
  const privateRequest = fixture();
  await privateRequest.upload('owner', id, keys[0], raw, 'image/png');
  const input = { ...data, photoIds: [keys[0]] };
  await assert.rejects(privateRequest.readPublic(id, keys[0]), is('not-found'));
  await assert.rejects(privateRequest.publish('owner', id, { ...input, photosPublic: 'true' }), is('invalid-argument'));
  const original = await privateRequest.publish('owner', id, input);
  const retry = await privateRequest.publish('owner', id, { ...input, photosPublic: true });
  assert.deepEqual(retry, original);
  await assert.rejects(
    privateRequest.manage('owner', id, 'edit', { ...data, photosPublic: true }, original.createdAt),
    is('invalid-argument'),
  );
  await assert.rejects(privateRequest.readPublic(id, keys[0]), is('not-found'));
  assert.ok((await privateRequest.read('owner', id, keys[0])).length);

  const publicRequest = fixture();
  await publicRequest.upload('owner', id, keys[0], raw, 'image/png');
  const saved = await publicRequest.publish('owner', id, { ...input, photosPublic: true });
  assert.equal(saved.photosPublic, true);
  assert.ok((await publicRequest.readPublic(id, keys[0])).length);
  await assert.rejects(publicRequest.readPublic(id, keys[1]), is('not-found'));
  await publicRequest.manage('owner', id, 'edit', data, saved.createdAt);
  assert.equal(publicRequest.documents.get('requests/' + id).photosPublic, true);
  await publicRequest.manage('owner', id, 'close');
  await assert.rejects(publicRequest.readPublic(id, keys[0]), is('not-found'));
  await publicRequest.manage('owner', id, 'delete');
  assert.equal(publicRequest.documents.get('requests/' + id).photosPublic, undefined);
});

test('upload validation uses bytes, rejects unverified accounts and never readies invalid photos', async () => {
  const c = fixture();
  await assert.rejects(c.upload('unverified', id, keys[0], raw, 'image/png'), is('permission-denied'));
  await assert.rejects(c.upload('owner', '../' + id, keys[0], raw, 'image/png'), is('invalid-argument'));
  await assert.rejects(c.upload('owner', id, '../private', raw, 'image/png'), is('invalid-argument'));
  await assert.rejects(c.upload('owner', id, keys[0], raw, 'image/heic'), is('invalid-argument'));
  await assert.rejects(c.upload('owner', id, keys[0], raw, 'image/jpeg'), is('invalid-argument'));
  await assert.rejects(c.upload('owner', id, keys[0], Buffer.alloc(5 * 1048576 + 1), 'image/png'), is('invalid-argument'));
  await assert.rejects(c.upload('owner', id, keys[0], raw.subarray(0, 16), 'image/png'), is('invalid-argument'));
  const large = await sharp({ create: { width: 5000, height: 4100, channels: 3, background: 'white' } }).png().toBuffer();
  await assert.rejects(c.upload('owner', id, keys[1], large, 'image/png'), is('invalid-argument'));
  await assert.rejects(c.publish('owner', id, { ...data, photoIds: [keys[0]] }), is('failed-precondition'));
  assert.equal(c.objects.size, 0);
  assert.equal(c.documents.has('requestPublicationLimits/owner'), false);
});

test('lost Storage response, removal, expiry and cleanup retries keep the same draft and quota', async () => {
  const c = fixture();
  c.failSave(true);
  await assert.rejects(c.upload('owner', id, keys[0], raw, 'image/png'), /lost response/);
  assert.equal(c.objects.size, 1);
  c.failSave(false);
  await c.upload('owner', id, keys[0], raw, 'image/png');
  await c.upload('owner', id, keys[0], raw, 'image/png');
  assert.equal(c.objects.size, 1);
  await assert.rejects(c.discard('other', id, [keys[0]]), is('permission-denied'));
  await c.discard('owner', id, [keys[0]]);
  await assert.rejects(c.publish('owner', id, { ...data, photoIds: [keys[0]] }), is('failed-precondition'));
  await c.upload('owner', id, keys[1], raw, 'image/png');
  const saved = await c.publish('owner', id, { ...data, photoIds: [keys[1]] });
  assert.equal((await c.cleanup()).removed, 0);
  c.advance(180001);
  c.failRemove(true);
  assert.deepEqual(await c.cleanup(), { removed: 0, failed: 1 });
  c.advance(3600001);
  c.failRemove(false);
  assert.deepEqual(await c.cleanup(), { removed: 1, failed: 0 });
  assert.equal(c.objects.size, 1);
  const abandoned = id + 'Abandoned';
  await c.upload('owner', abandoned, keys[0], raw, 'image/png');
  c.advance(86400001);
  assert.equal((await c.cleanup()).removed, 1);
  assert.equal(c.objects.size, 1);
  assert.deepEqual(await c.publish('owner', id, data), saved);
});

test('media bandwidth counters are separate and reset at the next UTC day', async () => {
  const c = fixture();
  c.documents.set('requestPhotoLimits/owner', { date: 0, uploads: 39, bytes: 0, reads: 0 });
  await c.upload('owner', id, keys[0], raw, 'image/png');
  await assert.rejects(c.upload('owner', id, keys[0], raw, 'image/png'), is('resource-exhausted'));
  assert.equal(c.documents.has('requestPublicationLimits/owner'), false);
  c.documents.set('requestPhotoLimits/owner', { date: 0, uploads: 0, bytes: 100 * 1048576, reads: 0 });
  await assert.rejects(c.upload('owner', id, keys[0], raw, 'image/png'), is('resource-exhausted'));
  await c.publish('owner', id, { ...data, photoIds: [keys[0]] });
  c.documents.set('requestPhotoLimits/pro', { date: 0, uploads: 0, bytes: 0, reads: 300 });
  await assert.rejects(c.read('pro', id, keys[0]), is('resource-exhausted'));
  c.advance(86400000);
  assert.ok((await c.read('pro', id, keys[0])).length > 0);
  assert.equal(c.documents.get('requestPhotoLimits/pro').reads, 1);
  assert.equal(c.objects.size, 1);
});
