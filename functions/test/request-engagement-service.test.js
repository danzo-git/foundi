const { test } = require('node:test');
const assert = require('node:assert/strict');
const { createRequestEngagementService } = require('../src/request-engagement-service');

const requestId = 'RequestEngagement00001';

function fixture() {
  const docs = new Map([[`requests/${requestId}`, { status: 'published' }],
    [`requestEngagement/${requestId}`, { likeCount: 3 }]]);
  let recommendations = 4;
  let responses = 2;
  let nanos = 0;
  let pause = null;
  const db = {
    doc: (path) => ({ path, get: async () => ({ data: () => docs.get(path) }) }),
    collection: (collection) => ({ where: () => ({ count: () => ({ get: async () => {
      const count = collection === 'proposals' ? responses : recommendations;
      const snapshot = { data: () => ({ count }),
        readTime: { seconds: 1, nanoseconds: ++nanos } };
      const pending = pause;
      if (pending) await pending;
      return snapshot;
    } }) }) }),
    runTransaction: async (operation) => operation({
      get: (ref) => ref.get(),
      set: (ref, value) => docs.set(ref.path, value),
    }),
  };
  return { service: createRequestEngagementService({ db }), docs,
    setCounts: (rec, res) => { recommendations = rec; responses = res; },
    pause: (promise) => { pause = promise; } };
}

test('public engagement initializes real historical counts and excludes private proposal fields', async () => {
  const c = fixture();
  assert.deepEqual(await c.service.read(requestId), { likeCount: 3, recommendationCount: 4, responseCount: 2 });
  c.setCounts(1, 0);
  assert.deepEqual(await c.service.read(requestId), { likeCount: 3, recommendationCount: 1, responseCount: 0 });
  c.docs.get(`requests/${requestId}`).status = 'closed';
  await assert.rejects(c.service.read(requestId), { code: 'not-found' });
  await assert.rejects(c.service.read('../private'), { code: 'invalid-argument' });
});

test('a slow older count cannot overwrite a newer snapshot after deletion', async () => {
  const c = fixture();
  let release;
  c.pause(new Promise((resolve) => { release = resolve; }));
  const older = c.service.read(requestId);
  await new Promise((resolve) => setImmediate(resolve));
  c.pause(null);
  c.setCounts(0, 0);
  const current = await c.service.read(requestId);
  release();
  assert.deepEqual(await older, current);
  assert.equal(current.recommendationCount, 0);
  assert.equal(current.responseCount, 0);
  assert.equal(c.docs.get(`requestEngagement/${requestId}`).likeCount, 3);
});
