// V1 neutral identity, with a read-only fallback for historical professionals.
const { accountRequesterName } = require('./direct-request-context');
const responderUid = value => value?.responderUid || value?.professionalUid;
const responderName = value => value?.responderName || value?.professionalName || 'Utilisateur Foundi';
const certifiedProfile = profile => profile?.status === 'approved';
const publicResponderName = (user, profile) => certifiedProfile(profile) ? profile.businessName : accountRequesterName(user);
function responderFields(uid, name, profile) {
  return { responderUid: uid, responderName: name,
    ...(certifiedProfile(profile) ? { professionalUid: uid, professionalName: name } : {}) };
}
module.exports = { responderUid, responderName, certifiedProfile, responderFields, publicResponderName };
