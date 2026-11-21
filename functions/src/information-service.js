const {randomUUID} = require('node:crypto');
const {OtpError, requireUid} = require('./auth-validation');
const INDEX = 'foundiInformation/current';
const COLLECTION = 'foundiAnnouncements';
const fail = (code, message) => { throw new OtpError(code, message); };
const idValid = id => typeof id === 'string' && /^[a-zA-Z0-9_-]{1,80}$/.test(id);
const active = (item, now) => item?.status === 'published' && item.endsAt > now;
function inputObject(input) {
  if (!input || typeof input !== 'object' || Array.isArray(input)) fail('invalid-argument', 'Requête invalide.');
}
function text(value, max) {
  if (typeof value !== 'string' || !value.trim() || value.trim().length > max || /[\x00-\x08\x0b\x0c\x0e-\x1f]/.test(value)) {
    fail('invalid-argument', 'Le titre, le résumé ou le contenu est invalide.');
  }
  return value.trim();
}
function summary(item) {
  return Object.fromEntries(['id', 'version', 'title', 'summary', 'publishedAt', 'endsAt'].map(key => [key, item[key]]));
}
function createInformationService({store, auth, clock = Date.now, generateId = randomUUID}) {
  async function admin(uid, claims) {
    requireUid(uid);
    if (claims?.admin !== true) fail('permission-denied', 'Accès administratif requis.');
    const account = await auth.getUser(uid);
    if (account.disabled || account.customClaims?.admin !== true) fail('permission-denied', 'Accès administratif révoqué.');
  }
  async function list(input = {}) {
    inputObject(input);
    const now = clock();
    const index = await store.get(INDEX);
    const items = (index?.items || []).filter(item => item.endsAt > now)
      .sort((a, b) => b.publishedAt - a.publishedAt || a.id.localeCompare(b.id));
    return {items: input.featuredOnly === true ? items.slice(0, 1) : items, serverNow: now};
  }
  async function read(input = {}) {
    inputObject(input);
    if (!idValid(input.id)) fail('invalid-argument', 'Annonce invalide.');
    const item = await store.get(`${COLLECTION}/${input.id}`);
    if (!active(item, clock())) fail('not-found', 'Cette annonce n’est plus disponible.');
    return {...summary(item), body: item.body, serverNow: clock()};
  }
  async function listAdmin(uid, claims, input = {}) {
    await admin(uid, claims);
    inputObject(input);
    const cursor = input.cursor;
    if (cursor != null && (!idValid(cursor.id) || !Number.isSafeInteger(cursor.updatedAt))) fail('invalid-argument', 'Page invalide.');
    const rows = await store.list(cursor, 31);
    const page = rows.slice(0, 30);
    const last = page.at(-1);
    return {items: page.map(item => ({...item, status: active(item, clock()) ? 'published' : item.status === 'published' ? 'expired' : item.status})),
      cursor: rows.length > 30 ? {id: last.id, updatedAt: last.updatedAt} : null};
  }
  async function save(uid, claims, input = {}) {
    await admin(uid, claims);
    inputObject(input);
    if (input.id != null && !idValid(input.id)) fail('invalid-argument', 'Annonce invalide.');
    if (typeof input.expectedVersion !== 'string' || !['draft', 'published', 'archived'].includes(input.status)) fail('invalid-argument', 'Statut ou version invalide.');
    const fields = {title: text(input.title, 100), summary: text(input.summary, 240), body: text(input.body, 12000)};
    const now = clock();
    if (!Number.isSafeInteger(input.endsAt) || input.endsAt <= 0 || input.endsAt > now + 366 * 86400000 || (input.status === 'published' && input.endsAt <= now)) {
      fail('invalid-argument', 'Choisis une date de fin future, dans les 12 prochains mois, pour publier.');
    }
    const id = input.id || generateId(), version = generateId(), auditId = generateId();
    return store.transaction(async tx => {
      const old = await tx.get(`${COLLECTION}/${id}`);
      const registry = await tx.get(INDEX);
      if ((old?.version || '') !== input.expectedVersion) fail('aborted', 'Cette annonce a changé. Actualise avant de réessayer.');
      if (input.id && !old) fail('not-found', 'Annonce introuvable.');
      const item = {...fields, id, version, status: input.status, endsAt: input.endsAt,
        createdAt: old?.createdAt ?? now, updatedAt: now,
        publishedAt: input.status === 'published' && old?.status !== 'published' ? now : old?.publishedAt ?? null};
      const items = (registry?.items || []).filter(entry => entry.id !== id && entry.endsAt > now);
      if (active(item, now)) items.push(summary(item));
      if (items.length > 20) fail('resource-exhausted', '20 annonces sont déjà en cours. Archive une annonce avant de publier.');
      tx.set(`${COLLECTION}/${id}`, item);
      tx.set(INDEX, {items});
      tx.set(`foundiInformationAudit/${auditId}`, {announcementId: id, actorUid: uid, at: now, previousVersion: old?.version ?? null, version, status: item.status});
      return {id, version};
    });
  }
  return {list, read, listAdmin, save};
}
function createInformationStore(db) {
  return {
    transaction: operation => require('./privacy-guard').guardedTransaction(db, operation),
    get: async path => (await db.doc(path).get()).data(),
    list: async (cursor, size) => {
      let query = db.collection(COLLECTION).orderBy('updatedAt', 'desc')
        .orderBy(require('firebase-admin/firestore').FieldPath.documentId(), 'desc');
      if (cursor) query = query.startAfter(cursor.updatedAt, cursor.id);
      return (await query.limit(size).get()).docs.map(doc => ({...doc.data(), id: doc.id}));
    },
  };
}
module.exports = {createInformationService, createInformationStore};
