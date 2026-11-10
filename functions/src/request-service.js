const { OtpError, requireUid } = require('./auth-validation');

const { activeZones } = require('./catalog-service');
const { photoIds: validatePhotoIds } = require('./request-photo-service');

const fail = (code, message) => { throw new OtpError(code, message); };

const idPattern = /^[a-zA-Z0-9_-]{1,80}$/;

const DAY_MS = 24 * 60 * 60 * 1000;
const REQUEST_PUBLICATION_LIMITS = Object.freeze({
  minimumIntervalMs: 60 * 1000,
  dailyWindowMs: DAY_MS,
  dailyMaximum: 5,
  weeklyWindowMs: 7 * DAY_MS,
  weeklyMaximum: 20,
});

function checkPublicationLimit(saved, now) {
  const limits = REQUEST_PUBLICATION_LIMITS;
  const timestamps = saved == null ? [] : saved.createdAtMs;
  // This is server-owned data. Fail closed if its shape is ever corrupted.
  if (!Array.isArray(timestamps) || timestamps.some(t => !Number.isSafeInteger(t) || t < 0)) {
    fail('failed-precondition', 'La protection des publications est temporairement indisponible. Réessaie plus tard.');
  }
  const recent = timestamps.filter(t => t > now - limits.weeklyWindowMs).sort((a, b) => a - b);
  if (recent.length && now - recent[recent.length - 1] < limits.minimumIntervalMs) {
    fail('resource-exhausted', `Attends ${Math.ceil(limits.minimumIntervalMs / 1000)} secondes entre deux nouvelles demandes.`);
  }
  if (recent.filter(t => t > now - limits.dailyWindowMs).length >= limits.dailyMaximum) {
    fail('resource-exhausted', `Tu as atteint la limite de ${limits.dailyMaximum} nouvelles demandes sur ${limits.dailyWindowMs / (60 * 60 * 1000)} heures. Réessaie plus tard.`);
  }
  if (recent.length >= limits.weeklyMaximum) {
    fail('resource-exhausted', `Tu as atteint la limite de ${limits.weeklyMaximum} nouvelles demandes sur ${limits.weeklyWindowMs / DAY_MS} jours. Réessaie plus tard.`);
  }
  return [...recent, now];
}

function text(value, min, max) {

  if (typeof value !== 'string' || value.trim().length < min || value.trim().length > max) {

    fail('invalid-argument', 'Vérifie le titre et la description de ta demande.');

  }

  return value.trim();

}

function requestInput(input) {

  if (!input || !['categoryId', 'zoneId'].every(key => typeof input[key] === 'string' && idPattern.test(input[key])) ||

      (input.specialtyId !== '' && (typeof input.specialtyId !== 'string' || !idPattern.test(input.specialtyId)))) {

    fail('invalid-argument', 'Choisis une catégorie, une spécialité et une zone valides.');

  }

  if (input.budget !== null && (!Number.isSafeInteger(input.budget) || input.budget < 0 || input.budget > 999999999999)) {

    fail('invalid-argument', 'Le budget doit être un montant entier positif ou nul en FCFA.');

  }

  return { categoryId: input.categoryId, specialtyId: input.specialtyId, zoneId: input.zoneId,

    title: text(input.title, 3, 120), description: text(input.description, 10, 3000), budget: input.budget };

}

function createRequestService({ store, auth, photos, clock = () => Date.now() }) {

  async function publish(uid, requestId, input) {

    requireUid(uid);

    if (typeof requestId !== 'string' || !/^[a-zA-Z0-9_-]{20,80}$/.test(requestId)) fail('invalid-argument', 'Identifiant de publication invalide.');

    const account = await auth.getUser(uid);

    if (account.disabled) fail('permission-denied', 'Ce compte n’est pas disponible.');
    if (account.emailVerified !== true) fail('failed-precondition', 'Vérifie ton adresse e-mail avant de publier une demande.');

    return store.transaction(async tx => {

      const ownPath = `userRequests/${uid}/items/${requestId}`;

      const existing = await tx.get(ownPath);

      // A retry after a lost response returns the actual saved content.

      if (existing) return { id: requestId, ...existing };

      const value = requestInput(input);
      const photoIds = input.photoIds === undefined ? [] : validatePhotoIds(input.photoIds);

      const publicPath = `requests/${requestId}`;

      const occupied = await tx.get(publicPath);

      const catalog = await tx.get('referenceData/professionalOnboarding');

      if (occupied) fail('already-exists', 'Cet identifiant de publication est déjà utilisé.');

      if (catalog?.enabled !== true) fail('failed-precondition', 'Les catégories et zones sont temporairement indisponibles.');

      const category = catalog.categories?.find(c => c.id === value.categoryId && c.active !== false);

      const specialties = category?.specialties?.filter(s => s.active !== false) || [];

      const specialty = specialties.find(s => s.id === value.specialtyId);

      const zone = activeZones(catalog.zones).find(z => z.id === value.zoneId);

      if (!category || !zone || (specialties.length ? !specialty : value.specialtyId !== '')) {

        fail('failed-precondition', 'Une sélection n’est plus disponible. Actualise les catégories et zones.');

      }

      const labels = [zone.label];

      let parent = zone.parentId;

      while (parent) {

        const ancestor = catalog.zones.find(z => z.id === parent);

        labels.unshift(ancestor.label); parent = ancestor.parentId;

      }

      // Explicit public projection: no UID, account identity, contact or internal metadata.

      const quotaPath = `requestPublicationLimits/${uid}`;
      const quota = await tx.get(quotaPath);
      const now = clock();
      const createdAtMs = checkPublicationLimit(quota, now);
      if (photoIds.length) {
        if (!photos) fail('failed-precondition', 'Les photos sont indisponibles.');
        await photos.link(tx, uid, requestId, photoIds, now);
      }

      const published = { ...value, categoryLabel: category.label, specialtyLabel: specialty?.label || '',

        zoneLabel: labels.join(' › '), status: 'published', createdAt: now,
        ...(photoIds.length ? { photoIds } : {}) };

      tx.set(publicPath, published);

      tx.set(ownPath, published);
      tx.set(`requestOwnership/${requestId}`, { ownerUid: uid });
      tx.set(quotaPath, { schemaVersion: 92, createdAtMs });

      return { id: requestId, ...published };

    });

  }

  async function manage(uid, requestId, action, input, expectedRevision) {

    requireUid(uid);

    if (typeof requestId !== 'string' || !/^[a-zA-Z0-9_-]{20,80}$/.test(requestId) || !['edit', 'close', 'delete'].includes(action)) fail('invalid-argument', 'Action invalide.');

    if ((await auth.getUser(uid)).disabled) fail('permission-denied', 'Compte indisponible.');

    const value = action === 'edit' ? requestInput(input) : null;

    if (value && Object.keys(input).some(k => !Object.keys(value).includes(k))) fail('invalid-argument', 'Champ protégé.');

    return store.transaction(async tx => {

      const path = `userRequests/${uid}/items/${requestId}`;

      const existing = await tx.get(path);

      if (!existing) fail('permission-denied', 'Cette demande ne t’appartient pas.');

      const target = action === 'close' ? 'closed' : 'deleted';

      if (action !== 'edit' && existing.status === target) return { id: requestId, ...existing };

      if (existing.status === 'deleted' || (action === 'edit' && existing.status !== 'published') || (action === 'close' && !['published','in_discussion'].includes(existing.status))) fail('failed-precondition', 'Cette demande n’est plus modifiable.');

      if (value && expectedRevision !== (existing.updatedAt ?? existing.createdAt)) fail('aborted', 'Cette demande a changé. Rouvre-la avant de modifier.');
      const conversations = action !== 'edit' && tx.conversationsForRequest
        ? await tx.conversationsForRequest(requestId) : [];
      let changed = {};

      if (value) {

        const catalog = await tx.get('referenceData/professionalOnboarding');

        const category = catalog?.categories?.find(c => c.id === value.categoryId && c.active !== false);

        const specialties = category?.specialties?.filter(s => s.active !== false) || [];

        const specialty = specialties.find(s => s.id === value.specialtyId);

        const zone = activeZones(catalog?.zones).find(z => z.id === value.zoneId);

        if (!catalog?.enabled || !category || !zone || (specialties.length ? !specialty : value.specialtyId !== '')) fail('failed-precondition', 'Choisis des références actives.');

        const labels = [zone.label]; let parent = zone.parentId;

        while (parent) { const ancestor = catalog.zones.find(z => z.id === parent); labels.unshift(ancestor.label); parent = ancestor.parentId; }

        changed = { ...value, categoryLabel: category.label, specialtyLabel: specialty?.label || '', zoneLabel: labels.join(' › ') };

      }

      const saved = { ...existing, ...changed, status: value ? 'published' : target, updatedAt: Math.max(clock(), (existing.updatedAt ?? existing.createdAt) + 1) };
      if (action === 'delete' && existing.photoIds?.length && photos) {
        await photos.scheduleDelete(tx, uid, requestId, existing.photoIds);
      }

      tx.set(path, saved);
      for (const {id, ...conversation} of conversations) {
        if (conversation.clientUid !== uid) fail('failed-precondition', 'Discussion incohérente.');
        tx.set(`conversations/${id}`, {...conversation,
          ...(action === 'delete' ? {status:'read_only',archivedReason:'request_deleted'} : {}),
          requestSnapshot:{...conversation.requestSnapshot,status:target}});
      }

      const publicFields = ['title','description','categoryId','categoryLabel','specialtyId','specialtyLabel','zoneId','zoneLabel','budget','status','createdAt','updatedAt'];
      if (saved.photoIds?.length && action !== 'delete') publicFields.push('photoIds');
      tx.set(`requests/${requestId}`, Object.fromEntries(publicFields.map(key => [key, saved[key]])));

      return { id: requestId, ...saved };

    });

  }

  return { publish, manage };

}

module.exports = { createRequestService, REQUEST_PUBLICATION_LIMITS };
