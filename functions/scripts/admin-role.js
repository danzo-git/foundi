const { initializeApp, applicationDefault } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
// Operator-only script. Never called by the public application.
(async () => {
  const [project, uid, action] = process.argv.slice(2);
  if (project !== 'foundi-7c837' || !uid || !['grant','revoke'].includes(action) || process.env.CONFIRM_ADMIN_CHANGE !== `${project}:${uid}:${action}`) throw new Error('Usage: CONFIRM_ADMIN_CHANGE=project:uid:grant|revoke node scripts/admin-role.js foundi-7c837 UID grant|revoke');
  initializeApp({ credential: applicationDefault(), projectId: project });
  const auth = getAuth(); const user = await auth.getUser(uid);
  if (action === 'grant' && (user.disabled || !user.emailVerified)) throw new Error('Verified active account required');
  const claims = { ...user.customClaims }; if (action === 'grant') claims.admin = true; else delete claims.admin;
  await auth.setCustomUserClaims(uid, claims);
  await auth.revokeRefreshTokens(uid);
  console.log(`Admin role ${action}: ${uid}. Sign in again.`);
})().catch(e => { console.error(e.message); process.exitCode = 1; });
