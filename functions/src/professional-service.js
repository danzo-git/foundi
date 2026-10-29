const { randomUUID } = require('node:crypto');
const { OtpError, requireUid } = require('./auth-validation');

const { activeZones } = require('./catalog-service');

const MAX_DOCUMENT_BYTES = 5 * 1024 * 1024;
const idPattern = /^[a-zA-Z0-9_-]{1,80}$/;
const fail = (code, message) => { throw new OtpError(code, message); };
const text = (value, max) => typeof value === 'string' && value.trim().length <= max
  ? value.trim() : fail('invalid-argument', 'Vérifie les champs du dossier.');
function ids(value) {
  if (!Array.isArray(value) || value.length > 30 || !value.every(v => typeof v === 'string' && idPattern.test(v))) {
    fail('invalid-argument', 'Sélection invalide.');
  }
  return [...new Set(value)];
}
function activity(input) {
  if (!input || !['independent', 'company'].includes(input.type)) fail('invalid-argument', 'Choisis ton type d’activité.');
  return {
    type: input.type, businessName: text(input.businessName, 150),
    categoryIds: ids(input.categoryIds), specialtyIds: ids(input.specialtyIds),
    zoneIds: ids(input.zoneIds), description: text(input.description, 2000),
  };
}
function configuredCatalog(catalog) {
  if (catalog?.enabled !== true || typeof catalog.version !== 'string' || !catalog.version ||
      !Array.isArray(catalog.categories) || !catalog.categories.length ||
      !Array.isArray(catalog.zones) || !catalog.zones.length || !Array.isArray(catalog.documentTypes)) {
    fail('failed-precondition', 'Les références et justificatifs requis doivent être configurés par Foundi. Ton brouillon reste enregistré.');
  }
  return catalog;
}
function validateActivity(value, catalog) {
  configuredCatalog(catalog);
  if (value.businessName.length < 2 || value.description.length < 20 || !value.categoryIds.length || !value.zoneIds.length) {
    fail('failed-precondition', 'Complète ton activité, tes catégories, tes zones et ta description (20 caractères minimum).');
  }
  const categories = value.categoryIds.map(id => catalog.categories.find(c => c.id === id && c.active !== false));
  const zoneIds = activeZones(catalog.zones).map(z => z.id);
  if (categories.some(c => !c) || value.zoneIds.some(id => !zoneIds.includes(id)) ||
      value.specialtyIds.some(id => !categories.some(c => c.specialties?.some(s => s.id === id && s.active !== false)))) {
    fail('failed-precondition', 'Les sélections ont changé. Actualise les références.');
  }
  if (categories.some(c => c.specialties?.some(s => s.active !== false)) && !value.specialtyIds.length) fail('failed-precondition', 'Sélectionne au moins une spécialité.');
  return categories;
}
function requiredDocuments(value, catalog) {
  const categories = validateActivity(value, catalog);
  const required = new Set(['identity']);
  for (const category of categories) {
    const requirements = category.requirements?.[value.type];
    if (!Array.isArray(requirements)) fail('failed-precondition', 'Les justificatifs de cette activité ne sont pas encore définis.');
    requirements.forEach(id => required.add(id));
  }
  for (const id of required) {
    if (!idPattern.test(id) || !catalog.documentTypes.some(d => d.id === id && d.active !== false)) {
      fail('failed-precondition', 'La configuration des justificatifs est incomplète.');
    }
  }
  if (required.size > 30) fail('failed-precondition', 'La configuration des justificatifs est invalide.');
  return [...required];
}
function documentBytes(base64) {
  if (typeof base64 !== 'string' || base64.length > Math.ceil(MAX_DOCUMENT_BYTES / 3) * 4 || base64.length % 4 !== 0) {
    fail('invalid-argument', 'Choisis un PDF, JPEG ou PNG de 5 Mo maximum.');
  }
  const bytes = Buffer.from(base64, 'base64');
  // Avoid a repeated-group regular expression over multi-megabyte input.
  if (bytes.toString('base64') !== base64) fail('invalid-argument', 'Encodage du document invalide.');
  const type = bytes.subarray(0, 5).toString() === '%PDF-' ? 'application/pdf'
    : bytes.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10])) ? 'image/png'
      : bytes[0] === 255 && bytes[1] === 216 && bytes[2] === 255 ? 'image/jpeg' : null;
  if (!type || bytes.length < 12 || bytes.length > MAX_DOCUMENT_BYTES) {
    fail('invalid-argument', 'Ce fichier doit être un PDF, JPEG ou PNG valide de 5 Mo maximum.');
  }
  return { bytes, type };
}

// All state transitions use the same profile document, serializing edits,
// uploads, submission and administrative decisions against one another.
function createProfessionalService({ store, auth, files, clock = () => Date.now(), generateId = randomUUID }) {
  async function verified(uid) {
    requireUid(uid);
    const user = await auth.getUser(uid);
    if (user.disabled || !user.emailVerified) fail('permission-denied', 'Vérifie ton adresse e-mail pour continuer.');
    return user;
  }
  const profilePath = uid => 'professionalProfiles/' + requireUid(uid);
  const documentPath = (uid, kind) => profilePath(uid) + '/documents/' + kind;
  const draft = profile => {
    if (!['draft', 'needs_changes'].includes(profile?.status)) fail('failed-precondition', 'Seul un dossier brouillon peut être modifié.');
  };
  async function ensureDraft(uid) {
    await verified(uid);
    return store.transaction(async tx => {
      const path = profilePath(uid);
      const profile = await tx.get(path);
      if (profile) return { status: profile.status };
      const now = clock();
      tx.set(path, { status: 'draft', onboardingStep: 2, type: 'independent', businessName: '',
        categoryIds: [], specialtyIds: [], zoneIds: [], description: '', revision: 0, createdAt: now, updatedAt: now });
      return { status: 'draft' };
    });
  }
  async function saveActivity(uid, input, complete = false) {
    await verified(uid);
    const value = activity(input);
    return store.transaction(async tx => {
      const path = profilePath(uid);
      const profile = await tx.get(path);
      const catalog = await tx.get('referenceData/professionalOnboarding');
      draft(profile);
      if (complete) requiredDocuments(value, catalog);
      // Even partial saves never accept arbitrary reference identifiers.
      if (value.categoryIds.length || value.specialtyIds.length || value.zoneIds.length) {
        configuredCatalog(catalog);
        const available = catalog.categories.filter(c => c.active !== false);
        if (value.categoryIds.some(id => !available.some(c => c.id === id)) ||
            value.specialtyIds.some(id => !available.filter(c => value.categoryIds.includes(c.id)).some(c => c.specialties?.some(s => s.id === id && s.active !== false))) ||
            value.zoneIds.some(id => !activeZones(catalog.zones).some(z => z.id === id))) {
          fail('invalid-argument', 'Actualise tes catégories et tes zones.');
        }
      }
      tx.set(path, { ...profile, ...value, onboardingStep: complete ? 3 : 2,
        revision: profile.revision + 1, updatedAt: clock() });
      return { saved: true };
    });
  }
  async function uploadDocument(uid, kind, name, base64) {
    await verified(uid);
    if (typeof kind !== 'string' || !idPattern.test(kind)) fail('invalid-argument', 'Type de justificatif invalide.');
    const fileName = text(name, 180);
    const { bytes, type } = documentBytes(base64);
    const uploadId = generateId();
    const objectPath = `professionalDocuments/${uid}/${kind}/${uploadId}`;
    const previous = await store.transaction(async tx => {
      const path = profilePath(uid);
      const profile = await tx.get(path);
      const catalog = await tx.get('referenceData/professionalOnboarding');
      const old = await tx.get(documentPath(uid, kind));
      draft(profile);
      if (!requiredDocuments(activity(profile), catalog).includes(kind)) fail('invalid-argument', 'Ce document n’est pas demandé pour ton activité.');
      tx.set(documentPath(uid, kind), { kind, name: fileName, uploadId, objectPath, state: 'uploading', updatedAt: clock() });
      tx.set(path, { ...profile, revision: profile.revision + 1, updatedAt: clock() });
      return old;
    });
    try {
      // Admin upload deliberately creates no public download token or signed URL.
      const generation = await files.save(objectPath, bytes, type);
      await store.transaction(async tx => {
        const path = profilePath(uid);
        const profile = await tx.get(path);
        const doc = await tx.get(documentPath(uid, kind));
        draft(profile);
        if (doc?.uploadId !== uploadId) fail('aborted', 'Un autre envoi a remplacé ce document.');
        tx.set(documentPath(uid, kind), { ...doc, state: 'ready', contentType: type,
          size: bytes.length, generation: String(generation), updatedAt: clock() });
        tx.set(path, { ...profile, revision: profile.revision + 1, updatedAt: clock() });
      });
    } catch (error) {
      await files.remove(objectPath).catch(() => {});
      await store.transaction(async tx => {
        const path = profilePath(uid);
        const profile = await tx.get(path);
        const doc = await tx.get(documentPath(uid, kind));
        if (['draft', 'needs_changes'].includes(profile?.status) && doc?.uploadId === uploadId) {
          tx.set(documentPath(uid, kind), previous || { kind, name: fileName, state: 'failed', updatedAt: clock() });
          tx.set(path, { ...profile, revision: profile.revision + 1, updatedAt: clock() });
        }
      }).catch(() => {});
      throw error;
    }
    if (previous?.objectPath && previous.objectPath !== objectPath) await files.remove(previous.objectPath).catch(() => {});
    return { uploaded: true };
  }
  async function submit(uid, certified) {
    await verified(uid);
    if (certified !== true) fail('invalid-argument', 'Certifie l’exactitude des informations.');
    return store.transaction(async tx => {
      const path = profilePath(uid);
      const profile = await tx.get(path);
      const catalog = await tx.get('referenceData/professionalOnboarding');
      const user = await tx.get('users/' + uid);
      const legal = await tx.get('legalDocuments/current');
      // Retrying a timed-out submission is idempotent.
      if (profile?.status === 'pending') return { status: 'pending' };
      draft(profile);
      const required = requiredDocuments(activity(profile), catalog);
      const docs = await Promise.all(required.map(kind => tx.get(documentPath(uid, kind))));
      if (legal?.published !== true || !legal.version || !legal.terms || !legal.privacy || user?.termsVersion !== legal.version) {
        fail('failed-precondition', 'Les CGU et la politique de confidentialité doivent être publiées puis acceptées dans ton compte.');
      }
      for (let i = 0; i < required.length; i++) {
        const doc = docs[i];
        if (doc?.state !== 'ready' || !doc.generation || doc.objectPath !== `professionalDocuments/${uid}/${required[i]}/${doc.uploadId}`) {
          fail('failed-precondition', 'Ajoute tous les justificatifs requis avant la soumission.');
        }
        // Check the actual private object, not only client-supplied metadata.
        if (!(await files.exists(doc.objectPath, doc.generation))) fail('failed-precondition', 'Un justificatif est indisponible. Ajoute-le à nouveau.');
      }
      tx.set(path, { ...profile, status: 'pending', onboardingStep: 3,
        certifiedAt: clock(), submittedAt: clock(), catalogVersion: catalog.version,
        requiredDocumentIds: required, revision: profile.revision + 1, updatedAt: clock() });
      return { status: 'pending' };
    });
  }
  async function decide(adminUid, claims, uid, status, reason = '', expectedRevision) {
    requireUid(adminUid);
    if (claims?.admin !== true) fail('permission-denied', 'Accès administratif requis.');
    const admin = await auth.getUser(adminUid);
    if (admin.disabled || admin.customClaims?.admin !== true) fail('permission-denied', 'Accès administratif révoqué.');
    if (!['approved', 'rejected', 'needs_changes', 'suspended'].includes(status)) fail('invalid-argument', 'Décision invalide.');
    reason = text(reason, 2000);
    if (status !== 'approved' && reason.length < 5) fail('invalid-argument', 'Un motif de 5 caractères minimum est requis.');
    return store.transaction(async tx => {
      const path = profilePath(uid);
      const profile = await tx.get(path);
      if (expectedRevision !== undefined && profile?.revision !== expectedRevision) fail('aborted', 'Le dossier a changé. Actualise-le.');
      if (!(profile?.status === 'pending' && ['approved', 'rejected', 'needs_changes'].includes(status)) &&
          !(profile?.status === 'approved' && status === 'suspended')) {
        fail('failed-precondition', 'Cette transition n’est pas autorisée.');
      }
      const now = clock();
      tx.set(path, { ...profile, status, reviewReason: reason, reviewedAt: now, reviewedBy: adminUid, updatedAt: now, revision: profile.revision + 1 });
      tx.set(`users/${uid}/notifications/professionalDecision`, { type: 'professionalDecision', status, reason, createdAt: now });
      tx.set(`professionalAudit/${generateId()}`, { uid, adminUid, from: profile.status, to: status, reason, revision: profile.revision, createdAt: now });
      return { status };
    });
  }
  async function requireApproved(uid) {
    await verified(uid);
    return store.transaction(async tx => {
      const profile = await tx.get(profilePath(uid));
      if (profile?.status !== 'approved') fail('permission-denied', 'Un profil professionnel approuvé est requis.');
      return { approved: true };
    });
  }
  return { ensureDraft, saveActivity, uploadDocument, submit, decide, requireApproved };
}
module.exports = { createProfessionalService, requiredDocuments, MAX_DOCUMENT_BYTES };
