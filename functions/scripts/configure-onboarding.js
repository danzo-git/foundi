const fs = require('node:fs');
const { initializeApp, applicationDefault } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { requiredDocuments } = require('../src/professional-service');
const args = process.argv.slice(2);
const value = flag => { const i = args.indexOf(flag); return i < 0 ? null : args[i + 1]; };
const read = flag => { const path = value(flag); return path ? JSON.parse(fs.readFileSync(path, 'utf8')) : null; };
async function main() {
  const projectId = value('--project');
  const catalog = read('--catalog'), legal = read('--legal');
  if (!projectId || (!catalog && !legal)) throw new Error('Use --project ID and --catalog FILE and/or --legal FILE. Add --apply to publish.');
  if (catalog?.enabled === true) {
    const validChoices = list => Array.isArray(list) && list.every(c => typeof c.id === 'string' && /^[a-zA-Z0-9_-]{1,80}$/.test(c.id) && typeof c.label === 'string' && c.label.trim() && c.label.length <= 150) && new Set(list.map(c => c.id)).size === list.length;
    if (!validChoices(catalog.categories) || !validChoices(catalog.zones) || !validChoices(catalog.documentTypes) ||
        catalog.categories.some(c => !validChoices(c.specialties))) throw new Error('Invalid catalog choices or duplicate identifiers.');
    for (const c of catalog.categories.filter(c => c.active !== false)) for (const type of ['independent', 'company']) {
      requiredDocuments({ type, businessName: 'Configuration validation', description: 'Configuration validation only', categoryIds: [c.id], specialtyIds: c.specialties.filter(s => s.active !== false).slice(0, 1).map(s => s.id), zoneIds: [catalog.zones.find(z => z.active !== false)?.id] }, catalog);
    }
  }
  if (legal?.published === true && (typeof legal.version !== 'string' || !legal.version || legal.version.length > 100 ||
      !['terms', 'privacy'].every(key => typeof legal[key] === 'string' && legal[key].trim() && legal[key].length <= 300000))) {
    throw new Error('Published legal documents need a version and both complete texts.');
  }
  if (!args.includes('--apply')) { console.log('Configuration valid. Dry run: no remote changes.'); return; }
  initializeApp({ projectId, credential: applicationDefault() });
  const db = getFirestore(), batch = db.batch();
  if (catalog) batch.set(db.doc('referenceData/professionalOnboarding'), catalog);
  if (legal) batch.set(db.doc('legalDocuments/current'), legal);
  await batch.commit(); console.log('Foundi reference configuration published to ' + projectId + '.');
}
main().catch(error => { console.error(error.message); process.exitCode = 1; });
