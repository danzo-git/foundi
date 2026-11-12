const { OtpError } = require('./auth-validation');
const { internalId } = require('./notification-policy');
const { directoryEntry } = require('./request-interaction-service');
const { proposalId } = require('./proposal-service');
const { showcaseProjection } = require('./professional-showcase-service');
const { directRequestActivity } = require('./direct-request-context');

const pageSize = 20;
const requestIdPattern = /^[a-zA-Z0-9_-]{20,80}$/;

function requirePublished(snapshot) {
  const request = snapshot.data();
  if (request?.status !== 'published') {
    throw new OtpError('not-found', 'Cette demande n’est plus publique.');
  }
  return request;
}

function createRequestRespondentsService({ db, auth }) {
  async function list(uid, requestId, offset = 0) {
    if (typeof requestId !== 'string' || !requestIdPattern.test(requestId) ||
        !Number.isSafeInteger(offset) || offset < 0) {
      throw new OtpError('invalid-argument', 'Demande ou pagination invalide.');
    }
    const requestRef = db.doc(`requests/${requestId}`);
    const request = requirePublished(await requestRef.get());
    const proposals = db.collection('proposals').where('requestId', '==', requestId);
    const [count, own] = await Promise.all([
      proposals.count().get(),
      internalId(uid) ? db.doc(`userRequests/${uid}/items/${requestId}`).get() : null,
    ]);
    const total = count.data().count;
    const canViewProposals = own?.data()?.status === 'published' &&
      own.data().createdAt === request.createdAt;

    const items = [];
    let nextOffset = null;
    if (offset < total) {
      const page = await proposals.orderBy('professionalUid')
        .offset(offset).limit(pageSize).select('professionalUid').get();
      const ids = [...new Set(page.docs.map((doc) => doc.data().professionalUid).filter(internalId))];
      if (ids.length) {
        const profiles = ids.map((id) => db.doc(`professionalProfiles/${id}`));
        const [catalog, records, accounts] = await Promise.all([
          db.doc('referenceData/professionalOnboarding').get(),
          db.getAll(...profiles, { fieldMask: ['status', 'businessName', 'categoryIds', 'specialtyIds'] }),
          auth.getUsers(ids.map((id) => ({ uid: id }))),
        ]);
        const active = new Set(accounts.users.filter((user) => user.emailVerified && !user.disabled).map((user) => user.uid));
        for (const record of records) {
          if (!record.exists || !active.has(record.id)) continue;
          const entry = directoryEntry(record.id, record.data(), catalog.data());
          if (entry) items.push({ professionalId: record.id, name: entry.name,
            activity: entry.specialties.length ? entry.specialties : entry.categories });
        }
      }
      if (page.size && offset + page.size < total) nextOffset = offset + page.size;
    }
    requirePublished(await requestRef.get());
    return { total, items, nextOffset, canViewProposals };
  }

  async function readProfile(requestId, professionalId) {
    if (typeof requestId !== 'string' || !requestIdPattern.test(requestId) || !internalId(professionalId)) {
      throw new OtpError('invalid-argument', 'Profil professionnel invalide.');
    }
    const unavailable = () => { throw new OtpError('not-found', 'Ce profil professionnel n’est plus disponible.'); };
    return db.runTransaction(async (tx) => {
      const [parent, proposal] = await Promise.all([
        tx.get(db.doc(`requests/${requestId}`)),
        tx.get(db.doc(`proposals/${proposalId(requestId, professionalId)}`)),
      ]);
      requirePublished(parent);
      const response = proposal.data();
      if (response?.requestId !== requestId || response.professionalUid !== professionalId) unavailable();
      const [professional, catalog, showcase] = await Promise.all([
        tx.get(db.doc(`professionalProfiles/${professionalId}`)),
        tx.get(db.doc('referenceData/professionalOnboarding')),
        tx.get(db.doc(`professionalProfiles/${professionalId}/showcase/profile`)),
      ]);
      const entry = professional.exists && directoryEntry(professionalId, professional.data(), catalog.data());
      if (!entry) unavailable();
      let account;
      try {
        account = await auth.getUser(professionalId);
      } catch (error) {
        if (error.code === 'auth/user-not-found') unavailable();
        throw error;
      }
      if (!account.emailVerified || account.disabled) unavailable();
      return { ...(showcaseProjection(showcase.data()) ?? {
        revision: 0, name: entry.name, trade: [...entry.categories, ...entry.specialties].join(' · '),
        area: entry.zones.join(' · '), bio: '', portrait: null, cover: null, gallery: [],
      }), professionalId, requestActivity: directRequestActivity(professional.data(), catalog.data()) };
    });
  }

  return { list, readProfile };
}

module.exports = { createRequestRespondentsService };
