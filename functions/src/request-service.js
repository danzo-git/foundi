const { OtpError, requireUid } = require('./auth-validation');
const { createHash } = require('node:crypto');

const { activeZones } = require('./catalog-service');
const { photoIds: validatePhotoIds } = require('./request-photo-service');
const { directRequestActivity, accountRequesterName } = require('./direct-request-context');
const { assertActive, assertContact, publicProfileAllowed } = require('./safety-guard');

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

  const result=value.trim();
  if (/(.)\1{79}/u.test(result) || /(?:\b(\p{L}{2,})\b[\s,;.!]*)\1(?:[\s,;.!]+\1){28}/iu.test(result)) {
    fail('invalid-argument','Ce texte contient une répétition excessive. Décris ton besoin avec des phrases utiles.');
  }
  return result;

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

  async function publish(uid, requestId, input, professionalId = null) {

    requireUid(uid);

    if (typeof requestId !== 'string' || !/^[a-zA-Z0-9_-]{20,80}$/.test(requestId)) fail('invalid-argument', 'Identifiant de publication invalide.');

    const account = await auth.getUser(uid);

    if (account.disabled) fail('permission-denied', 'Ce compte n’est pas disponible.');
    if (account.emailVerified !== true) fail('failed-precondition', 'Vérifie ton adresse e-mail avant de publier une demande.');

    return store.transaction(async tx => {

      await assertActive(tx,uid);
      if (professionalId) {
        await assertContact(tx,uid,professionalId);
        if (!await publicProfileAllowed(tx,professionalId)) fail('permission-denied','Ce professionnel est indisponible.');
      }

      const ownPath = `userRequests/${uid}/items/${requestId}`;

      const existing = await tx.get(ownPath);

      // A retry after a lost response returns the actual saved content.

      if (existing) {
        if ((existing.directProfessionalId || null) !== professionalId) fail('already-exists', 'Cet identifiant correspond à une autre demande.');
        return { id: requestId, ...existing };
      }

      const value = requestInput(input);
      const photoIds = input.photoIds === undefined ? [] : validatePhotoIds(input.photoIds);
      if (input.photosPublic !== undefined && (input.photosPublic !== true || !photoIds.length)) {
        fail('invalid-argument', 'La publication des photos doit être confirmée avec les photos choisies.');
      }

      const publicPath = `requests/${requestId}`;

      const occupied = await tx.get(publicPath);
      const privateOccupied = await tx.get(`directRequests/${requestId}`);
      let recipient;
      if (professionalId) {
        if (professionalId === uid) fail('permission-denied', 'Tu ne peux pas t’envoyer une demande directe.');
        recipient = await tx.get(`professionalProfiles/${professionalId}`);
        let account;
        try { account = await auth.getUser(professionalId); }
        catch (error) { if (error.code !== 'auth/user-not-found') throw error; }
        if (recipient?.status !== 'approved' || !recipient.businessName?.trim() || !account?.emailVerified || account.disabled) {
          fail('failed-precondition', 'Ce professionnel n’est plus disponible.');
        }
        if (input.photosPublic === true) fail('invalid-argument', 'Les photos d’une demande directe restent privées.');
      }

      const catalog = await tx.get('referenceData/professionalOnboarding');

      if (occupied || privateOccupied) fail('already-exists', 'Cet identifiant de publication est déjà utilisé.');

      if (catalog?.enabled !== true) fail('failed-precondition', 'Les catégories et zones sont temporairement indisponibles.');

      const requesterName = accountRequesterName(await tx.get(`users/${uid}`), account);
      if (professionalId) {
        const activity = directRequestActivity(recipient, catalog);
        if (!activity || value.categoryId !== activity.categoryId || value.specialtyId !== activity.specialtyId) {
          fail('failed-precondition', 'L’activité du professionnel a changé. Rouvre son profil avant d’envoyer ta demande.');
        }
        if (!requesterName) fail('failed-precondition', 'Renseigne ton nom dans les informations personnelles de ton compte.');
      }

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

      // The account-derived name is public; UID, contacts and internal metadata stay private.

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
        ...(!professionalId && requesterName ? {authorPublicName: requesterName} : {}),
        ...(photoIds.length ? { photoIds } : {}),
        ...(input.photosPublic === true ? { photosPublic: true } : {}) };
      if (!published.authorPublicName) delete published.authorPublicName;

      if (professionalId) {
        Object.assign(published, {visibility: 'direct', requesterName, directProfessionalId: professionalId, directProfessionalName: recipient.businessName.trim()});
        tx.set(`directRequests/${requestId}`, {...published, clientUid: uid});
      } else {
        tx.set(publicPath, published);
      }

      tx.set(ownPath, published);
      tx.set(`requestOwnership/${requestId}`, { ownerUid: uid });
      tx.set(quotaPath, { schemaVersion: 92, createdAtMs });

      return { id: requestId, ...published };

    });

  }

  async function manage(uid, requestId, action, input, expectedRevision) {

    requireUid(uid);

    if (typeof requestId !== 'string' || !/^[a-zA-Z0-9_-]{20,80}$/.test(requestId) || !['edit', 'close', 'delete'].includes(action)) fail('invalid-argument', 'Action invalide.');

    const account = await auth.getUser(uid);
    if (account.disabled) fail('permission-denied', 'Compte indisponible.');

    const value = action === 'edit' ? requestInput(input) : null;
    if (value && input.photoIds !== undefined) {
      value.photoIds = validatePhotoIds(input.photoIds);
      if (input.photosPublic !== undefined && typeof input.photosPublic !== 'boolean') {
        fail('invalid-argument', 'Vérifie la visibilité des photos.');
      }
      if (input.photosPublic !== undefined) value.photosPublic = input.photosPublic;
    }

    // Older clients may still send a per-request name. Ignore it completely.
    if (value && Object.keys(input).some(k => k !== 'authorPublicName' && !Object.keys(value).includes(k))) fail('invalid-argument', 'Champ protégé.');
    const editFingerprint = value && createHash('sha256').update(JSON.stringify(value)).digest('hex');

    return store.transaction(async tx => {

      const path = `userRequests/${uid}/items/${requestId}`;

      const existing = await tx.get(path);

      await assertActive(tx,uid);
      const moderation = await tx.get(`safetyContent/request_${requestId}`);

      if (!existing) fail('permission-denied', 'Cette demande ne t’appartient pas.');

      const target = action === 'close' ? 'closed' : 'deleted';

      if (action !== 'edit' && existing.status === target) return { id: requestId, ...existing };

      if (existing.status === 'deleted' || (action === 'edit' && existing.status !== 'published') || (action === 'close' && !['published','in_discussion'].includes(existing.status))) fail('failed-precondition', 'Cette demande n’est plus modifiable.');

      if (value && expectedRevision !== (existing.updatedAt ?? existing.createdAt)) {
        if (existing.lastEdit?.baseRevision === expectedRevision && existing.lastEdit.fingerprint === editFingerprint) {
          return { id: requestId, ...existing };
        }
        fail('aborted', 'Cette demande a changé. Rouvre-la avant de modifier.');
      }
      const conversations = action !== 'edit' && tx.conversationsForRequest
        ? await tx.conversationsForRequest(requestId) : [];
      let changed = {};
      const accountName = accountRequesterName(await tx.get(`users/${uid}`), account);
      let requesterName;
      if (existing.visibility === 'direct') {
        if (value && (value.categoryId !== existing.categoryId || value.specialtyId !== existing.specialtyId)) {
          fail('invalid-argument', 'L’activité d’une demande directe ne peut pas être modifiée.');
        }
        requesterName = accountName ?? existing.requesterName;
      }

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

      const saved = { ...existing, ...changed, status: value ? 'published' : target, updatedAt: Math.max(clock(), (existing.updatedAt ?? existing.createdAt) + 1),
        ...(value ? { lastEdit: { baseRevision: expectedRevision, fingerprint: editFingerprint } } : {}) };
      if (existing.visibility === 'direct') {
        delete saved.authorPublicName;
        if (requesterName) saved.requesterName = requesterName;
      } else {
        // Never retain an old per-request alias when editing or managing a request.
        if (accountName) saved.authorPublicName = accountName;
        else delete saved.authorPublicName;
      }
      if (!saved.authorPublicName) delete saved.authorPublicName;
      if (value?.photoIds !== undefined) {
        if (!photos) fail('failed-precondition', 'Les photos sont indisponibles.');
        await photos.replace(tx, uid, requestId, existing.photoIds ?? [], value.photoIds, clock());
        if (!saved.photoIds.length) {
          delete saved.photoIds;
          delete saved.photosPublic;
        }
      }
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
      if (saved.authorPublicName && action !== 'delete') publicFields.push('authorPublicName');
      if (saved.photoIds?.length && action !== 'delete') {
        publicFields.push('photoIds');
        if (saved.photosPublic === true) publicFields.push('photosPublic');
      }
      if (existing.visibility === 'direct') {
        if (saved.photosPublic === true) fail('invalid-argument', 'Les photos d’une demande directe restent privées.');
        tx.set(`directRequests/${requestId}`, {...saved, clientUid: uid});
      } else {
        if (!moderation?.hidden) tx.set(`requests/${requestId}`, Object.fromEntries(publicFields.filter(key=>saved[key]!==undefined).map(key => [key, saved[key]])));
      }

      return { id: requestId, ...saved };

    });

  }

  async function publishDirect(uid, requestId, professionalId, input) {
    requireUid(uid);
    if (typeof professionalId !== 'string' || !/^[a-zA-Z0-9_-]{1,128}$/.test(professionalId)) fail('invalid-argument', 'Professionnel invalide.');
    return publish(uid, requestId, input, professionalId);
  }

  // Resolve legacy requests without migrating production documents or exposing
  // user records. Every ID is checked against its private canonical document.
  async function readDirectAuthors(uid, ids) {
    requireUid(uid);
    const account = await auth.getUser(uid);
    if (account.disabled || !account.emailVerified) fail('permission-denied', 'Compte indisponible.');
    if (!Array.isArray(ids) || !ids.length || ids.length > 50 ||
        ids.some(id => typeof id !== 'string' || !/^[a-zA-Z0-9_-]{20,80}$/.test(id))) {
      fail('invalid-argument', 'Demandes privées invalides.');
    }
    return store.transaction(async tx => {
      const recipient = await tx.get(`professionalProfiles/${uid}`);
      const authors = {};
      for (const id of new Set(ids)) {
        const request = await tx.get(`directRequests/${id}`);
        if (!request || request.visibility !== 'direct' || request.status === 'deleted' ||
            !(request.clientUid === uid || (request.directProfessionalId === uid && recipient?.status === 'approved'))) {
          fail('permission-denied', 'Cette demande privée est indisponible.');
        }
        const profile = await tx.get(`users/${request.clientUid}`);
        let author;
        if (!accountRequesterName(profile)) {
          try { author = await auth.getUser(request.clientUid); }
          catch (error) { if (error.code !== 'auth/user-not-found') throw error; }
        }
        authors[id] = accountRequesterName(profile, author) ?? 'Membre Foundi';
      }
      return { authors };
    });
  }
  return { publish, publishDirect, manage, readDirectAuthors };

}

module.exports = { createRequestService, REQUEST_PUBLICATION_LIMITS };
