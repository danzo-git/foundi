const { responderUid, responderName, certifiedProfile } = require('./responder');
const { OtpError } = require('./auth-validation');
const { internalId } = require('./notification-policy');
const { directoryEntry } = require('./request-interaction-service');
const { proposalId } = require('./proposal-service');
const { showcaseProjection } = require('./professional-showcase-service');
const { directRequestActivity } = require('./direct-request-context');
const { publicProfileAllowed } = require('./safety-guard');

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
      // Document-ID order includes old and neutral schemas in one stable page.
      const page = await proposals.orderBy('__name__')
        .offset(offset).limit(pageSize).select('responderUid', 'professionalUid', 'responderName', 'professionalName').get();
      const byUid = new Map(page.docs.map(doc => [responderUid(doc.data()), doc.data()]).filter(([id]) => internalId(id)));
      const ids = [...byUid.keys()];
      if (ids.length) {
        const paths = ids.flatMap(id => [`professionalProfiles/${id}`, `accountSafety/${id}`, `accountLifecycle/${id}`, `safetyContent/professional_${id}`, `personalAvatars/${id}`]);
        const [catalog, records, accounts] = await Promise.all([
          db.doc('referenceData/professionalOnboarding').get(),
          db.getAll(...paths.map(path => db.doc(path)), {fieldMask:['status','businessName','categoryIds','specialtyIds','suspended','hidden','published','publicId','revision']}),
          auth.getUsers(ids.map(uid => ({ uid }))),
        ]);
        const values = new Map(records.map(record => [record.ref.path, record.data()]));
        const active = new Set(accounts.users.filter(user => user.emailVerified && !user.disabled).map(user => user.uid));
        for (const id of ids) {
          if (!active.has(id) || values.get(`accountSafety/${id}`)?.suspended || values.get(`accountLifecycle/${id}`)) continue;
          const profile = values.get(`professionalProfiles/${id}`);
          const approved = certifiedProfile(profile) && !values.get(`safetyContent/professional_${id}`)?.hidden;
          const entry = approved && directoryEntry(id, profile, catalog.data());
          const avatar = values.get(`personalAvatars/${id}`);
          items.push({ responderId: id, name: responderName(byUid.get(id)), activity: entry ? (entry.specialties.length ? entry.specialties : entry.categories) : [],
            certified: approved, professionalId: entry ? id : null,
            avatarKey: avatar?.published && /^[a-f0-9]{32}$/.test(avatar.publicId) ? avatar.publicId : null,
            avatarVersion: avatar?.published && /^[a-f0-9]{32}$/.test(avatar.revision) ? avatar.revision : null });
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
      if (response?.requestId !== requestId || responderUid(response) !== professionalId) unavailable();
      const [professional, catalog, showcase, account] = await Promise.all([
        tx.get(db.doc(`professionalProfiles/${professionalId}`)),
        tx.get(db.doc('referenceData/professionalOnboarding')),
        tx.get(db.doc(`professionalProfiles/${professionalId}/showcase/profile`)),
        auth.getUser(professionalId).catch(error => {
          if (error.code === 'auth/user-not-found') unavailable();
          throw error;
        }),
      ]);
      const entry = professional.exists && directoryEntry(professionalId, professional.data(), catalog.data());
      if (!entry) unavailable();
      if (!account.emailVerified || account.disabled) unavailable();
      if (!await publicProfileAllowed({get:async p=>(await tx.get(db.doc(p))).data()},professionalId)) unavailable();
      return { ...(showcaseProjection(showcase.data()) ?? {
        revision: 0, name: entry.name, trade: [...entry.categories, ...entry.specialties].join(' · '),
        area: entry.zones.join(' · '), bio: '', portrait: null, cover: null, gallery: [],
      }), professionalId, requestActivity: directRequestActivity(professional.data(), catalog.data()) };
    });
  }

  return { list, readProfile };
}

module.exports = { createRequestRespondentsService };
