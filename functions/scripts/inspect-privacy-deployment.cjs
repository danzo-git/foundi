const fs = require('node:fs');
const {GoogleAuth} = require('google-auth-library');
const args = process.argv.slice(2);
const option = name => args.includes(name) ? args[args.indexOf(name) + 1] : null;
const project = option('--project');
if (project !== 'foundi-7c837') throw new Error('Explicit --project foundi-7c837 required.');
async function main() {
  const client = await new GoogleAuth({scopes: ['https://www.googleapis.com/auth/cloud-platform']}).getClient();
  const get = async (url, optional = false) => {
    try { return (await client.request({url})).data; }
    catch (e) { if (optional && e.response?.status === 404) return null; throw new Error(url + ': ' + e.message); }
  };
  const pages = async (url, key) => {
    const rows = []; let token;
    do {
      const page = await get(url + (token ? (url.includes('?') ? '&' : '?') + 'pageToken=' + encodeURIComponent(token) : ''));
      rows.push(...(page[key] || [])); token = page.nextPageToken;
    } while (token);
    return rows;
  };
  const base = `https://firestore.googleapis.com/v1/projects/${project}/databases/(default)`;
  const [functions, indexes, fields, firestoreRelease, storageRelease, policy, authConfig, bucket] = await Promise.all([
    pages(`https://cloudfunctions.googleapis.com/v2/projects/${project}/locations/europe-west1/functions`, 'functions'),
    pages(base + '/collectionGroups/-/indexes', 'indexes'),
    pages(base + '/collectionGroups/-/fields?filter=' + encodeURIComponent('indexConfig.usesAncestorConfig:false OR ttlConfig:*'), 'fields'),
    get(`https://firebaserules.googleapis.com/v1/projects/${project}/releases/cloud.firestore`),
    get(`https://firebaserules.googleapis.com/v1/projects/${project}/releases/firebase.storage/${project}.firebasestorage.app`, true),
    get(base + '/documents/privacyConfiguration/current', true),
    get(`https://identitytoolkit.googleapis.com/admin/v2/projects/${project}/config`),
    get(`https://storage.googleapis.com/storage/v1/b/${project}.firebasestorage.app`),
  ]);
  const rules = {};
  for (const [key, release] of Object.entries({firestore: firestoreRelease, storage: storageRelease})) {
    if (release) rules[key] = {release, source: await get('https://firebaserules.googleapis.com/v1/' + release.rulesetName)};
  }
  const snapshot = {project, checkedAt: new Date().toISOString(), functions: functions.map(f => ({
    name: f.name.split('/').at(-1), state: f.state, revision: f.serviceConfig?.revision,
    updateTime: f.updateTime, serviceAccount: f.serviceConfig?.serviceAccountEmail,
    uri: f.serviceConfig?.uri, deletionEnabled: f.serviceConfig?.environmentVariables?.ACCOUNT_DELETION_ENABLED,
  })), indexes, fields, rules, policy,
    auth: {authorizedDomains: authConfig.authorizedDomains, emailPrivacyConfig: authConfig.emailPrivacyConfig},
    storage: {name: bucket.name, location: bucket.location, softDeletePolicy: bucket.softDeletePolicy, retentionPolicy: bucket.retentionPolicy},
  };
  if (option('--output')) fs.writeFileSync(option('--output'), JSON.stringify(snapshot, null, 2));
  console.log(JSON.stringify({project, functions: snapshot.functions.length,
    privacyFunctions: snapshot.functions.filter(f => /AccountDeletion/.test(f.name)),
    indexes: indexes.length, ttl: fields.filter(f => f.ttlConfig).map(f => ({name: f.name, state: f.ttlConfig.state})),
    policyPresent: !!policy, auth: snapshot.auth, storage: snapshot.storage,
    output: option('--output')}, null, 2));
}
main().catch(e => { console.error(e.message); process.exitCode = 1; });
