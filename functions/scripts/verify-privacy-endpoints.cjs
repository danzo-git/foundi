const assert = require('node:assert/strict');
const fs = require('node:fs');
const {randomBytes} = require('node:crypto');
const {GoogleAuth} = require('google-auth-library');
async function main() {
  if (!process.argv.includes('--project') || process.argv[process.argv.indexOf('--project') + 1] !== 'foundi-7c837') throw new Error('Explicit --project foundi-7c837 required.');
  const enabled = process.argv.includes('--enabled');
  const base = 'https://europe-west1-foundi-7c837.cloudfunctions.net/';
  const receipt = {requestId: randomBytes(32).toString('hex'), receiptToken: randomBytes(32).toString('hex')};
  const results = [];
  for (const [name, body, expectedStatus, expectedCode] of [
    ['requestAccountDeletion', {data: {...receipt, confirm: true}}, 401, 'UNAUTHENTICATED'],
    ['readAccountDeletionStatus', receipt, 404, 'not-found'],
    ['retryAccountDeletion', receipt, enabled ? 404 : 409, enabled ? 'not-found' : 'failed-precondition'],
    ['listAccountDeletions', {data: {}}, 401, 'UNAUTHENTICATED'],
  ]) {
    const response = await fetch(base + name, {method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify(body), signal: AbortSignal.timeout(120000)});
    const payload = await response.json();
    assert.equal(response.status, expectedStatus, name);
    assert.equal(payload.error?.status || payload.error?.code, expectedCode, name);
    results.push({name, status: response.status, code: expectedCode});
  }
  const client = await new GoogleAuth({scopes: ['https://www.googleapis.com/auth/cloud-platform']}).getClient();
  const job = (await client.request({url: 'https://cloudscheduler.googleapis.com/v1/projects/foundi-7c837/locations/europe-west1/jobs/firebase-schedule-runAccountDeletion-europe-west1'})).data;
  assert.equal(job.state, 'ENABLED');
  assert.ok(['* * * * *', 'every 1 minutes'].includes(job.schedule), 'Worker must run every minute.');
  const snapshot = {project: 'foundi-7c837', checkedAt: new Date().toISOString(), endpoints: results,
    scheduler: {name: job.name, state: job.state, schedule: job.schedule, lastAttemptTime: job.lastAttemptTime, status: job.status},
    accountDeletionRequested: false};
  const outputIndex = process.argv.indexOf('--output');
  if (outputIndex !== -1) fs.writeFileSync(process.argv[outputIndex + 1], JSON.stringify(snapshot, null, 2));
  console.log(JSON.stringify(snapshot, null, 2));
}
main().catch(e => { console.error(e.message); process.exitCode = 1; });
