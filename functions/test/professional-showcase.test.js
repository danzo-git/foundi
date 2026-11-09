const assert = require('node:assert/strict');
const { test } = require('node:test');
const sharp = require('sharp');
const { createProfessionalShowcaseService } = require('../src/professional-showcase-service');

const showcasePath = 'professionalProfiles/pro/showcase/profile';
const initial = {
  revision: 0,
  name: 'Atelier Test',
  trade: 'Menuiserie',
  area: 'Cocody',
  bio: 'Rangements sur mesure.',
  portrait: null,
  cover: null,
  gallery: [],
};
const fails = (code) => (error) => error.code === code;

function fixture() {
  const documents = new Map([
    ['professionalProfiles/pro', { status: 'approved', phone: 'private-phone', description: 'private-dossier' }],
    ['professionalProfiles/other', { status: 'pending' }],
    ['users/pro', { fullName: 'private-name', phone: 'private-phone' }],
    ['proposals/offer', { clientUid: 'client', professionalUid: 'pro' }],
  ]);
  const auth = { getUser: async (uid) => ({ emailVerified: uid !== 'unverified', disabled: uid === 'disabled' }) };
  let queue = Promise.resolve();
  const store = {
    transaction(operation) {
      const result = queue.then(async () => {
        const next = new Map(documents);
        const value = await operation({
          get: async (path) => structuredClone(next.get(path)),
          set: (path, data) => next.set(path, structuredClone(data)),
        });
        for (const [path, data] of next) documents.set(path, data);
        return value;
      });
      queue = result.catch(() => {});
      return result;
    },
  };
  return { documents, ...createProfessionalShowcaseService({ store, auth }) };
}

async function samplePhoto() {
  const bytes = await sharp({
    create: { width: 200, height: 100, channels: 3, background: '#158f70' },
  }).withMetadata({ orientation: 6 }).jpeg().toBuffer();
  return { base64: bytes.toString('base64') };
}

test('only the approved owner and the receiving client can read the explicit projection', async () => {
  const f = fixture();
  assert.equal(await f.read('pro'), null);
  assert.equal(await f.read('client', 'offer'), null);
  await assert.rejects(f.save('other', initial), fails('permission-denied'));
  await assert.rejects(f.read('unverified', 'offer'), fails('permission-denied'));
  await assert.rejects(f.read('disabled', 'offer'), fails('permission-denied'));
  await assert.rejects(f.read(null, 'offer'), fails('unauthenticated'));
  await assert.rejects(f.read('stranger', 'offer'), fails('permission-denied'));
  await assert.rejects(f.read('client', '../offer'), fails('invalid-argument'));

  const saved = await f.save('pro', {
    ...initial, uid: 'other', email: 'private@example.test', phone: 'private-phone',
    fullName: 'private-name', status: 'approved',
  });
  assert.equal(saved.revision, 1);
  assert.deepEqual(await f.read('client', 'offer'), saved);
  assert.equal(JSON.stringify(saved).includes('private'), false);
  assert.equal(JSON.stringify(f.documents.get(showcasePath)).includes('private'), false);
  assert.equal(f.documents.has('professionalProfiles/other/showcase/profile'), false);
  f.documents.set('professionalProfiles/pro', { status: 'suspended' });
  assert.equal(await f.read('client', 'offer'), null);
  await assert.rejects(f.read('pro'), fails('permission-denied'));
  await assert.rejects(f.save('pro', { ...initial, revision: 1 }), fails('permission-denied'));
});

test('photos are sanitized, retained by reference, and replaced atomically with idempotent retries', async () => {
  const f = fixture();
  const photo = await samplePhoto();
  const first = { ...initial, portrait: photo, cover: photo, gallery: [photo] };
  const saved = await f.save('pro', first);
  const bytes = Buffer.from(saved.portrait.base64, 'base64');
  const metadata = await sharp(bytes).metadata();
  assert.equal(metadata.format, 'jpeg');
  assert.equal(metadata.width, 100);
  assert.equal(metadata.exif, undefined);
  assert.equal(metadata.orientation, undefined);
  assert.ok(bytes.length <= 80 * 1024);
  assert.deepEqual(await f.save('pro', first), saved);
  const next = { ...initial, revision: 1, portrait: { id: saved.portrait.id }, bio: 'Nouvelle présentation.' };
  const [a, b] = await Promise.allSettled([
    f.save('pro', next),
    f.save('pro', { ...next, bio: 'Autre modification.' }),
  ]);
  const success = [a, b].find((result) => result.status === 'fulfilled').value;
  const rejected = [a, b].find((result) => result.status === 'rejected').reason;
  assert.equal(rejected.code, 'aborted');
  assert.equal(success.revision, 2);
  assert.deepEqual(success.portrait, saved.portrait);
  assert.equal(success.cover, null);
  assert.deepEqual(success.gallery, []);
  assert.deepEqual(await f.read('client', 'offer'), success);
});

test('invalid contacts, over-cap galleries and malformed or foreign photos do not change the record', async () => {
  const f = fixture();
  const invalid = [
    { bio: 'Contacte atelier@example.test' },
    { name: 'Atelier +225 07 01 02 03 04' },
    { gallery: Array.from({ length: 7 }, () => ({})) },
    { cover: { base64: Buffer.from('not an image').toString('base64') } },
    { gallery: [{ id: 'a'.repeat(64) }] },
  ];
  for (const patch of invalid) {
    await assert.rejects(f.save('pro', { ...initial, ...patch }), fails('invalid-argument'));
    assert.equal(f.documents.has(showcasePath), false);
  }
});
