const { OtpError, requireUid } = require('./auth-validation');
const { responderUid, certifiedProfile } = require('./responder');
// One batch per visible list, no listener or callable per respondent.
function createProposalCertificationService({ db, auth }) {
  async function resolve(uid, input) {
    requireUid(uid);
    const ids = input?.proposalIds;
    if (!input || Object.keys(input).some(k => k !== 'proposalIds') || !Array.isArray(ids) || ids.length > 30 || ids.some(id => typeof id !== 'string' || !/^[a-f0-9]{64}$/.test(id))) {
      throw new OtpError('invalid-argument', 'Propositions invalides.');
    }
    const account = await auth.getUser(uid);
    if (account.disabled || !account.emailVerified) throw new OtpError('permission-denied', 'Compte indisponible.');
    if (!ids.length) return { certifications: {} };
    return db.runTransaction(async tx => {
      const proposals = await tx.getAll(...[...new Set(ids)].map(id => db.doc(`proposals/${id}`)));
      const people = [...new Set([uid, ...proposals.map(p => responderUid(p.data())).filter(Boolean)])];
      const paths = people.flatMap(id => [`professionalProfiles/${id}`, `accountSafety/${id}`, `accountLifecycle/${id}`, `safetyContent/professional_${id}`]);
      const [records, accounts] = await Promise.all([
        tx.getAll(...paths.map(path => db.doc(path))), auth.getUsers(people.map(uid => ({ uid }))),
      ]);
      const values = new Map(records.map(row => [row.ref.path, row.data()]));
      if (values.get(`accountSafety/${uid}`)?.suspended || values.get(`accountLifecycle/${uid}`)) throw new OtpError('permission-denied', 'Compte indisponible.');
      const active = new Set(accounts.users.filter(a => !a.disabled && a.emailVerified).map(a => a.uid));
      const certifications = {};
      for (const row of proposals) {
        const p = row.data(), id = responderUid(p);
        // A forged third-party ID never discloses private membership or certification.
        if (!p || ![p.clientUid, id].includes(uid)) continue;
        certifications[row.id] = active.has(id) && certifiedProfile(values.get(`professionalProfiles/${id}`)) &&
          !values.get(`accountSafety/${id}`)?.suspended && !values.get(`accountLifecycle/${id}`) && !values.get(`safetyContent/professional_${id}`)?.hidden;
      }
      return { certifications };
    });
  }
  return { resolve };
}
module.exports = { createProposalCertificationService };
