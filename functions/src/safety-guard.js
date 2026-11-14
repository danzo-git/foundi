const { OtpError } = require('./auth-validation');
const {assertOpen}=require('./privacy-guard');
const fail = message => { throw new OtpError('permission-denied', message); };
async function assertActive(tx, uid) {
  await assertOpen(tx,uid);
  if ((await tx.get(`accountSafety/${uid}`))?.suspended === true) fail('Ce compte est suspendu. Contacte l’assistance.');
}
async function contactAllowed(tx, a, b) {
  const records = await Promise.all([
    tx.get(`accountSafety/${a}`), tx.get(`accountSafety/${b}`),
    tx.get(`userBlocks/${a}/items/${b}`), tx.get(`userBlocks/${b}/items/${a}`),
    tx.get(`accountLifecycle/${a}`),tx.get(`accountLifecycle/${b}`),
  ]);
  return !records[0]?.suspended && !records[1]?.suspended && !records[2] && !records[3] && !records[4] && !records[5];
}
async function assertContact(tx, a, b) {
  if (!await contactAllowed(tx, a, b)) fail('Ce contact est indisponible. Un blocage ou une restriction empêche cette interaction.');
}
async function publicProfileAllowed(tx, uid) {
  const [account, content, life] = await Promise.all([tx.get(`accountSafety/${uid}`), tx.get(`safetyContent/professional_${uid}`),tx.get(`accountLifecycle/${uid}`)]);
  return !account?.suspended && !content?.hidden && !life;
}
module.exports = { assertActive, contactAllowed, assertContact, publicProfileAllowed };
