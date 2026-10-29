const { randomUUID } = require('node:crypto');
const { OtpError, requireUid } = require('./auth-validation');
const CATALOG_PATH = 'referenceData/professionalOnboarding';
const idPattern = /^[a-zA-Z0-9_-]{1,80}$/;
const zoneTypes = ['country', 'district', 'region', 'department', 'subprefecture', 'city', 'commune', 'quartier', 'intervention'];
const fail = (code, message) => { throw new OtpError(code, message); };
const text = (v, max = 150, required = false) => {
  if (typeof v !== 'string' || v.trim().length > max || (required && !v.trim())) fail('invalid-argument', 'Nom ou description invalide.');
  return v.trim();
};
function activeZones(zones = []) {
  const byId = new Map(zones.map(z => [z.id, z]));
  return zones.filter(zone => {
    const seen = new Set(); let current = zone;
    while (current) {
      if (current.active === false || seen.has(current.id)) return false;
      seen.add(current.id);
      if (current.parentId && !byId.has(current.parentId)) return false;
      current = current.parentId ? byId.get(current.parentId) : null;
    }
    return true;
  });
}
function validateCatalog(catalog, publishing = false) {
  const lists = [catalog.categories, catalog.zones, catalog.documentTypes];
  for (const list of lists) {
    if (!Array.isArray(list) || list.length > 1000 || list.some(x => !x || !idPattern.test(x.id) || typeof x.label !== 'string' || !x.label.trim() || x.label.length > 150) || new Set(list.map(x => x.id)).size !== list.length) fail('invalid-argument', 'Référentiel invalide ou identifiants dupliqués.');
  }
  const specialtyIds = new Set();
  for (const c of catalog.categories) {
    if (!Array.isArray(c.specialties) || c.specialties.length > 100) fail('invalid-argument', 'Spécialités invalides.');
    for (const s of c.specialties) {
      if (!idPattern.test(s.id) || typeof s.label !== 'string' || !s.label.trim() || s.label.length > 150 || specialtyIds.has(s.id)) fail('invalid-argument', 'Identifiant de spécialité invalide ou dupliqué.');
      specialtyIds.add(s.id);
    }
    for (const type of ['independent', 'company']) {
      if (!Array.isArray(c.requirements?.[type]) || c.requirements[type].length > 29 || c.requirements[type].some(id => !catalog.documentTypes.some(d => d.id === id))) fail('invalid-argument', 'Configurez les justificatifs des indépendants et entreprises.');
    }
  }
  const byId = new Map(catalog.zones.map(z => [z.id, z]));
  for (const zone of catalog.zones) {
    if (zone.type && !zoneTypes.includes(zone.type)) fail('invalid-argument', 'Type de zone invalide.');
    if (zone.countryCode && zone.countryCode !== 'CI') fail('invalid-argument', 'Seules les zones de Côte d’Ivoire sont prises en charge.');
    const visited = new Set([zone.id]); let parent = zone.parentId;
    while (parent) {
      if (!byId.has(parent) || visited.has(parent)) fail('invalid-argument', 'Parent absent ou cycle dans les zones.');
      visited.add(parent); parent = byId.get(parent).parentId;
    }
    if (zone.parentId && zone.type && byId.get(zone.parentId).type && zoneTypes.indexOf(zone.type) <= zoneTypes.indexOf(byId.get(zone.parentId).type)) fail('invalid-argument', 'Le type de la zone doit se situer sous celui du parent.');
  }
  if (publishing) {
    if (!catalog.categories.some(c => c.active !== false) || !activeZones(catalog.zones).length || !catalog.documentTypes.some(d => d.id === 'identity' && d.active !== false)) fail('failed-precondition', 'Ajoutez au moins une catégorie, une zone active et le justificatif identity avant activation.');
    for (const c of catalog.categories.filter(c => c.active !== false)) for (const type of ['independent', 'company']) {
      if (c.requirements[type].some(id => !catalog.documentTypes.some(d => d.id === id && d.active !== false))) fail('failed-precondition', 'Un justificatif requis est désactivé. Modifiez les exigences ou mettez le référentiel en pause.');
    }
  }
  // Keep below Firestore's 1 MiB document ceiling, with space for metadata.
  if (Buffer.byteLength(JSON.stringify(catalog)) > 800000) fail('resource-exhausted', 'Le référentiel atteint sa capacité. Une migration versionnée sera nécessaire.');
  return catalog;
}
function createCatalogService({ store, auth, clock = () => Date.now(), generateId = randomUUID }) {
  async function update(uid, claims, input) {
    requireUid(uid);
    if (claims?.admin !== true) fail('permission-denied', 'Accès administratif requis.');
    const admin = await auth.getUser(uid);
    if (admin.disabled || admin.customClaims?.admin !== true) fail('permission-denied', 'Accès administratif révoqué.');
    if (!input || typeof input.expectedVersion !== 'string') fail('invalid-argument', 'La version du référentiel est requise.');
    return store.transaction(async tx => {
      const existing = await tx.get(CATALOG_PATH);
      const catalog = structuredClone(existing || { enabled: false, version: '', categories: [], zones: [], documentTypes: [] });
      if ((catalog.version || '') !== input.expectedVersion) fail('aborted', 'Le référentiel a changé. Actualisez-le avant de réessayer.');
      let before = null, after = null;
      if (input.operation === 'publish') {
        if (typeof input.enabled !== 'boolean') fail('invalid-argument', 'Statut invalide.');
        before = { enabled: catalog.enabled }; catalog.enabled = input.enabled; after = { enabled: input.enabled };
      } else {
        const collections = { category: catalog.categories, zone: catalog.zones, documentType: catalog.documentTypes };
        let list = collections[input.operation];
        if (input.operation === 'specialty') {
          const parent = catalog.categories.find(c => c.id === input.categoryId);
          if (!parent) fail('not-found', 'Catégorie introuvable.');
          list = parent.specialties;
        }
        if (!list) fail('invalid-argument', 'Opération inconnue.');
        const data = input.value;
        if (!data || typeof data.active !== 'boolean') fail('invalid-argument', 'Élément invalide.');
        const id = input.id || (input.operation === 'documentType' && data.id) || generateId();
        if (!idPattern.test(id)) fail('invalid-argument', 'Identifiant invalide.');
        const index = list.findIndex(x => x.id === id);
        if (input.id && index < 0) fail('not-found', 'Élément introuvable.');
        if (!input.id && index >= 0) fail('already-exists', 'Cet identifiant existe déjà.');
        before = index < 0 ? null : list[index];
        after = { ...before, id, label: text(data.label, 150, true), description: text(data.description || '', 2000), active: data.active };
        if (input.operation === 'category') {
          after.specialties = before?.specialties || [];
          after.icon = ['home','car','build','storefront','event','favorite','school','work'].includes(data.icon) ? data.icon : 'work';
          after.requirements = {};
          for (const type of ['independent','company']) {
            const requirements = data.requirements?.[type];
            if (!Array.isArray(requirements) || requirements.some(v => typeof v !== 'string')) fail('invalid-argument', 'Justificatifs invalides.');
            after.requirements[type] = [...new Set(requirements)];
          }
        }
        if (input.operation === 'zone') {
          after.type = data.type; after.parentId = data.parentId || null; after.countryCode = 'CI';
          if (!zoneTypes.includes(after.type)) fail('invalid-argument', 'Type de zone invalide.');
        }
        if (index < 0) list.push(after); else list[index] = after;
      }
      validateCatalog(catalog, catalog.enabled === true);
      const now = clock(); catalog.version = `${now}_${generateId()}`; catalog.updatedAt = now; catalog.updatedBy = uid;
      tx.set(CATALOG_PATH, catalog);
      tx.set(`professionalAudit/${generateId()}`, { type: 'catalog', operation: input.operation, categoryId: input.categoryId || null, adminUid: uid, before, after, version: catalog.version, createdAt: now });
      return { version: catalog.version, id: after?.id || null };
    });
  }
  return { update };
}
module.exports = { createCatalogService, validateCatalog, activeZones, CATALOG_PATH };
