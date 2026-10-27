const { OtpError, requireUid, normalizeEmail, requirePendingPasswordUser } = require("./auth-validation");

async function changeRegistrationEmail({ auth, uid, email, authTime, clock = Date.now }) {
  requireUid(uid);
  if (!Number.isFinite(authTime) || clock() / 1000 - authTime > 300 || authTime > clock() / 1000 + 30) {
    throw new OtpError("unauthenticated", "Reauthenticate before changing email.");
  }
  const user = await auth.getUser(uid);
  requirePendingPasswordUser(user);
  if (user.providerData.some(p => p.providerId === "google.com")) {
    throw new OtpError("failed-precondition", "Use account settings for a Google email.");
  }
  const normalized = normalizeEmail(email);
  if (normalized !== normalizeEmail(user.email)) {
    try {
      await auth.updateUser(uid, { email: normalized, emailVerified: false });
    } catch (error) {
      if (error.code === "auth/email-already-exists") {
        throw new OtpError("already-exists", "Email is already used by another account.");
      }
      throw error;
    }
  }
  return { updated: true };
}
module.exports = { changeRegistrationEmail };
