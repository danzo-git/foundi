const { OtpError, requireUid } = require('./auth-validation');
const fail = (code, message) => { throw new OtpError(code, message); };
const fields = ['title','description','categoryId','categoryLabel','specialtyId','specialtyLabel','zoneId','zoneLabel','budget','status','createdAt'];
function createOpportunityService({ store, auth }) {
  return { async list(uid, input = {}) {
    requireUid(uid);
    const account = await auth.getUser(uid);
    if (account.disabled || !account.emailVerified) fail('permission-denied', 'Un compte actif avec une adresse vérifiée est nécessaire.');
    const profile = await store.get(`professionalProfiles/${uid}`);
    if (profile?.status !== 'approved') fail('permission-denied', 'Un dossier professionnel approuvé est nécessaire.');
    const catalog = await store.get('referenceData/professionalOnboarding');
    function subset(key, allowed) {
      const selected = input[key] ?? allowed;
      if (!Array.isArray(selected) || selected.some(v => typeof v !== 'string' || !allowed.includes(v))) fail('invalid-argument', 'Filtres non autorisés.');
      return [...new Set(selected)];
    }
    const categories = subset('categoryIds', profile.categoryIds || []);
    const specialties = subset('specialtyIds', profile.specialtyIds || []);
    const zones = subset('zoneIds', profile.zoneIds || []);
    // Exact IDs only. Missing declared zones means no personalized matches.
    const units = [];
    for (const categoryId of categories) {
      const category = catalog?.categories?.find(c => c.id === categoryId);
      if (!category) continue;
      const eligible = (category.specialties || []).map(s => s.id).filter(id => specialties.includes(id));
      const choices = category.specialties?.length ? eligible : [''];
      for (const zoneId of zones) for (const specialtyId of choices) units.push({ categoryId, zoneId, specialtyId });
    }
    const cursor = input.cursor ?? { unit: 0, after: null };
    if (!Number.isInteger(cursor.unit) || cursor.unit < 0 || cursor.unit > units.length || (cursor.after != null && (!Number.isSafeInteger(cursor.after.createdAt) || typeof cursor.after.id !== 'string' || !/^[a-zA-Z0-9_-]{1,80}$/.test(cursor.after.id)))) fail('invalid-argument', 'Pagination invalide.');
    let unit = cursor.unit, after = cursor.after, queries = 0, scanned = 0;
    const items = [];
    while (unit < units.length && queries < 10 && scanned < 60 && items.length < 30) {
      const size = Math.min(30 - items.length, 60 - scanned);
      const rows = await store.query(units[unit], after, size); queries++; scanned += rows.length;
      const ownIds = await store.owned(uid, rows.map(r => r.id));
      for (const row of rows) {
        if (row.status !== 'published' || ownIds.has(row.id)) continue;
        items.push({ id: row.id, ...Object.fromEntries(fields.map(k => [k, row[k]])) });
      }
      if (rows.length < size) { unit++; after = null; }
      else { const last = rows.at(-1); after = { createdAt: last.createdAt, id: last.id }; }
    }
    // Recheck approval after reads to handle a concurrent suspension.
    if ((await store.get(`professionalProfiles/${uid}`))?.status !== 'approved') fail('permission-denied', 'Accès professionnel suspendu.');
    return { items, cursor: unit < units.length ? { unit, after } : null };
  }};
}
module.exports = { createOpportunityService };
