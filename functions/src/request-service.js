const { OtpError, requireUid } = require('./auth-validation');

const { activeZones } = require('./catalog-service');

const fail = (code, message) => { throw new OtpError(code, message); };

const idPattern = /^[a-zA-Z0-9_-]{1,80}$/;

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

function createRequestService({ store, auth, clock = () => Date.now() }) {

  async function publish(uid, requestId, input) {

    requireUid(uid);

    if (typeof requestId !== 'string' || !/^[a-zA-Z0-9_-]{20,80}$/.test(requestId)) fail('invalid-argument', 'Identifiant de publication invalide.');

    const account = await auth.getUser(uid);

    if (account.disabled) fail('permission-denied', 'Ce compte n’est pas disponible.');

    const value = requestInput(input);

    return store.transaction(async tx => {

      const ownPath = `userRequests/${uid}/items/${requestId}`;

      const existing = await tx.get(ownPath);

      // A retry after a lost response returns the actual saved content.

      if (existing) return { id: requestId, ...existing };

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

      const published = { ...value, categoryLabel: category.label, specialtyLabel: specialty?.label || '',

        zoneLabel: labels.join(' › '), status: 'published', createdAt: clock() };

      tx.set(publicPath, published);

      tx.set(ownPath, published);

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

      if (existing.status === 'deleted' || (action !== 'delete' && existing.status !== 'published')) fail('failed-precondition', 'Cette demande n’est plus modifiable.');

      if (value && expectedRevision !== (existing.updatedAt ?? existing.createdAt)) fail('aborted', 'Cette demande a changé. Rouvre-la avant de modifier.');
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

      tx.set(path, saved);

      const publicFields = ['title','description','categoryId','categoryLabel','specialtyId','specialtyLabel','zoneId','zoneLabel','budget','status','createdAt','updatedAt'];
      tx.set(`requests/${requestId}`, Object.fromEntries(publicFields.map(key => [key, saved[key]])));

      return { id: requestId, ...saved };

    });

  }

  return { publish, manage };

}

module.exports = { createRequestService };

