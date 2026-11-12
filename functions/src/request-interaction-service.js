const { OtpError, requireUid } = require('./auth-validation');
const { key, internalId } = require('./notification-policy');
const { activeZones } = require('./catalog-service');
const { showcaseProjection } = require('./professional-showcase-service');
const { directRequestActivity } = require('./direct-request-context');

const dayMs = 86400000;
const pageSize = 24;
const dailyLimits = { likes: 120, directory: 60, recommendations: 10, incoming: 30 };
const requestIdValid = (id) => typeof id === 'string' && /^[a-zA-Z0-9_-]{20,80}$/.test(id);
const recommendationIdValid = (id) => typeof id === 'string' && /^[a-f0-9]{64}$/.test(id);
const fail = (code, message) => { throw new OtpError(code, message); };
const active = (account) => account?.emailVerified === true && !account.disabled;
const normalize = (text) => text.normalize('NFD').replace(/\p{M}/gu, '').toLowerCase().trim();
const publicName = (name) => typeof name === 'string' && name.length <= 150 &&
  !/@|(?<!\d)(?:\d[\s().+-]*){7}\d/u.test(name) ? name.trim() : '';

function directoryEntry(id, profile, catalog) {
  const name = publicName(profile.businessName);
  if (profile.status !== 'approved' || !name) return null;
  const categories = (catalog?.categories ?? []).filter((item) =>
    item.active !== false && profile.categoryIds?.includes(item.id));
  const specialties = categories.flatMap((category) => (category.specialties ?? []).filter((item) =>
    item.active !== false && profile.specialtyIds?.includes(item.id)));
  const zones = activeZones(catalog?.zones ?? []).filter((item) => profile.zoneIds?.includes(item.id));
  return {
    id, name, categories: categories.map((item) => item.label),
    specialties: specialties.map((item) => item.label), zones: zones.map((item) => item.label),
  };
}

function createRequestInteractionService({ store, auth, ownerForRequest, clock = Date.now }) {
  async function isActive(uid) {
    if (!internalId(uid)) return false;
    try { return active(await auth.getUser(uid)); }
    catch (error) { if (error.code === 'auth/user-not-found') return false; throw error; }
  }

  async function requireAccount(uid) {
    requireUid(uid);
    if (!await isActive(uid)) fail('permission-denied', 'Un compte actif avec une adresse e-mail vérifiée est nécessaire.');
  }

  function validateRequest(id) {
    if (!requestIdValid(id)) fail('invalid-argument', 'Demande invalide.');
  }

  function open(request) {
    if (request?.status !== 'published') fail('failed-precondition', 'Cette demande n’est plus ouverte.');
    return request;
  }

  async function allowance(tx, id, kind, now) {
    const path = `requestInteractionLimits/${key(kind, id)}`;
    const previous = await tx.get(path);
    const day = Math.floor(now / dayMs);
    const count = previous?.day === day ? previous.count : 0;
    if (count >= dailyLimits[kind]) fail('resource-exhausted', 'Limite d’interactions atteinte. Réessaie demain.');
    return { path, value: { day, count: count + 1 } };
  }

  async function setLike(uid, id, liked) {
    await requireAccount(uid);
    validateRequest(id);
    if (typeof liked !== 'boolean') fail('invalid-argument', 'Réaction invalide.');
    const aggregate = `requestEngagement/${id}`;
    const marker = `${aggregate}/likes/${uid}`;
    return store.transaction(async (tx) => {
      const [request, count, current] = await Promise.all([
        tx.get(`requests/${id}`), tx.get(aggregate), tx.get(marker),
      ]);
      open(request);
      const likeCount = count?.likeCount ?? 0;
      if (Boolean(current) === liked) return { liked, likeCount };
      const now = clock();
      const budget = await allowance(tx, uid, 'likes', now);
      const next = likeCount + (liked ? 1 : -1);
      if (!Number.isSafeInteger(next) || next < 0) fail('failed-precondition', 'Compteur indisponible.');
      tx.set(budget.path, budget.value);
      tx.set(aggregate, { ...count, likeCount: next });
      if (liked) tx.set(marker, { createdAt: now });
      else tx.delete(marker);
      return { liked, likeCount: next };
    });
  }

  async function search(uid, id, query = '', cursor = null) {
    await requireAccount(uid);
    validateRequest(id);
    if (typeof query !== 'string' || query.length > 80 || (cursor !== null && !internalId(cursor))) {
      fail('invalid-argument', 'Recherche invalide.');
    }
    const [request, catalog] = await Promise.all([
      store.get(`requests/${id}`), store.get('referenceData/professionalOnboarding'),
    ]);
    open(request);
    await store.transaction(async (tx) => {
      const budget = await allowance(tx, uid, 'directory', clock());
      tx.set(budget.path, budget.value);
    });
    const rows = await store.approvedPage(cursor, pageSize + 1);
    const page = rows.slice(0, pageSize);
    const term = normalize(query);
    const rank = (profile) => Number(!!profile.categoryIds?.includes(request.categoryId)) * 4 +
      Number(!!profile.specialtyIds?.includes(request.specialtyId)) * 2 +
      Number(!!profile.zoneIds?.includes(request.zoneId));
    const matches = page.filter((row) => row.id !== uid && internalId(row.id))
      .map(({ id: professionalId, profile }) => ({
        entry: directoryEntry(professionalId, profile, catalog), score: rank(profile),
      }))
      .filter(({ entry }) => entry && normalize(
        [entry.name, ...entry.categories, ...entry.specialties, ...entry.zones].join(' '),
      ).includes(term))
      .sort((a, b) => b.score - a.score || a.entry.name.localeCompare(b.entry.name, 'fr'));
    const accounts = matches.length
      ? await auth.getUsers(matches.map(({ entry }) => ({ uid: entry.id }))) : { users: [] };
    const enabled = new Set(accounts.users.filter(active).map((account) => account.uid));
    return {
      items: matches.filter(({ entry }) => enabled.has(entry.id)).map(({ entry }) => entry),
      cursor: rows.length > pageSize ? page.at(-1).id : null,
    };
  }

  async function recommend(uid, id, professionalUid) {
    await requireAccount(uid);
    validateRequest(id);
    if (!internalId(professionalUid) || professionalUid === uid) {
      fail('invalid-argument', 'Tu ne peux pas te recommander toi-même.');
    }
    const ownerUid = await ownerForRequest(id);
    const path = `requestRecommendations/${key(id, uid, professionalUid)}`;
    return store.transaction(async (tx) => {
      const [request, own, profile, prior] = await Promise.all([
        tx.get(`requests/${id}`), tx.get(`userRequests/${ownerUid}/items/${id}`),
        tx.get(`professionalProfiles/${professionalUid}`), tx.get(path),
      ]);
      open(request);
      if (own?.status !== 'published' || own.createdAt !== request.createdAt) {
        fail('failed-precondition', 'Le propriétaire de cette demande ne peut pas être confirmé.');
      }
      if (profile?.status !== 'approved' || !publicName(profile.businessName) || !await isActive(professionalUid)) {
        fail('failed-precondition', 'Ce professionnel n’est plus disponible.');
      }
      if (prior) return { alreadyRecommended: true };
      const now = clock();
      const budgets = await Promise.all([
        allowance(tx, uid, 'recommendations', now), allowance(tx, id, 'incoming', now),
      ]);
      for (const budget of budgets) tx.set(budget.path, budget.value);
      tx.set(path, { requestId: id, ownerUid, actorUid: uid, professionalUid, createdAt: now });
      return { alreadyRecommended: false };
    });
  }

  async function readRecommendation(uid, id) {
    await requireAccount(uid);
    if (!recommendationIdValid(id)) fail('invalid-argument', 'Recommandation invalide.');
    return store.transaction(async (tx) => {
      const rec = await tx.get(`requestRecommendations/${id}`);
      if (rec?.ownerUid !== uid) fail('not-found', 'Cette recommandation est indisponible.');
      const [own, profile, catalog, showcase] = await Promise.all([
        tx.get(`userRequests/${uid}/items/${rec.requestId}`),
        tx.get(`professionalProfiles/${rec.professionalUid}`),
        tx.get('referenceData/professionalOnboarding'),
        tx.get(`professionalProfiles/${rec.professionalUid}/showcase/profile`),
      ]);
      const entry = profile && directoryEntry(rec.professionalUid, profile, catalog);
      if (!own || own.status === 'deleted' || !entry || !await isActive(rec.professionalUid)) {
        fail('not-found', 'Ce professionnel n’est plus disponible.');
      }
      return { ...(showcaseProjection(showcase) ?? {
        revision: 0, name: entry.name, trade: [...entry.categories, ...entry.specialties].join(' · '),
        area: entry.zones.join(' · '), bio: '', gallery: [],
      }), professionalId: rec.professionalUid, requestActivity: directRequestActivity(profile, catalog) };
    });
  }
  return { setLike, search, recommend, readRecommendation };
}

module.exports = { createRequestInteractionService, directoryEntry };
