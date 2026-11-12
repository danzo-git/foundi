const { OtpError } = require('./auth-validation');

const requestIdPattern = /^[a-zA-Z0-9_-]{20,80}$/;
const sources = [
  { collection: 'requestRecommendations', field: 'recommendationCount', time: 'recommendationsCountedAt' },
  { collection: 'proposals', field: 'responseCount', time: 'responsesCountedAt' },
];

function atLeastAsRecent(next, previous) {
  return !previous || next.seconds > previous.seconds ||
    (next.seconds === previous.seconds && next.nanoseconds >= previous.nanoseconds);
}

function createRequestEngagementService({ db }) {
  async function refresh(requestId) {
    if (typeof requestId !== 'string' || !requestIdPattern.test(requestId)) {
      throw new OtpError('invalid-argument', 'Demande invalide.');
    }
    const request = db.doc(`requests/${requestId}`);
    if ((await request.get()).data()?.status !== 'published') return null;
    const counts = await Promise.all(sources.map(({ collection }) =>
      db.collection(collection).where('requestId', '==', requestId).count().get()));
    const engagement = db.doc(`requestEngagement/${requestId}`);
    return db.runTransaction(async (tx) => {
      const [parent, current] = await Promise.all([tx.get(request), tx.get(engagement)]);
      if (parent.data()?.status !== 'published') return null;
      const saved = { ...current.data() };
      for (const [index, source] of sources.entries()) {
        const snapshot = counts[index];
        // Aggregate read times prevent an older or redelivered trigger from
        // replacing a more recent count, including after a deletion.
        if (atLeastAsRecent(snapshot.readTime, saved[source.time])) {
          saved[source.field] = snapshot.data().count;
          saved[source.time] = snapshot.readTime;
        }
      }
      tx.set(engagement, saved);
      return {
        likeCount: saved.likeCount ?? 0,
        recommendationCount: saved.recommendationCount,
        responseCount: saved.responseCount,
      };
    });
  }

  async function read(requestId) {
    const counts = await refresh(requestId);
    if (!counts) throw new OtpError('not-found', 'Cette demande n’est plus publique.');
    return counts;
  }

  async function changed(change) {
    const requestId = change?.after.data()?.requestId ?? change?.before.data()?.requestId;
    if (typeof requestId !== 'string' || !requestIdPattern.test(requestId)) return;
    await refresh(requestId);
  }

  return { read, refresh, changed };
}

module.exports = { createRequestEngagementService };
