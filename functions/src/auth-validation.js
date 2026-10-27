class OtpError extends Error {
  constructor(code, message) { super(message); this.code = code; }
}
function requireUid(uid) {
  if (typeof uid !== "string" || !uid || uid.length > 128) {
    throw new OtpError("unauthenticated", "Sign in with your password first.");
  }
  return uid;
}
function normalizeEmail(value) {
  if (typeof value !== "string") throw new OtpError("invalid-argument", "Invalid email.");
  const email = value.trim().toLowerCase();
  const parts = email.split("@");
  if (email.length > 254 || parts.length !== 2 || parts[0].length > 64 ||
      !/^[a-z0-9.!#$%&'*+/=?^_\x60{|}~-]+$/.test(parts[0]) ||
      parts[0].startsWith(".") || parts[0].endsWith(".") || parts[0].includes("..") ||
      !parts[1].includes(".") || !parts[1].split(".").every(label =>
        /^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/.test(label))) {
    throw new OtpError("invalid-argument", "Invalid email.");
  }
  return email;
}
function requirePendingPasswordUser(user) {
  if (user.disabled) throw new OtpError("permission-denied", "Account unavailable.");
  if (user.emailVerified || !user.providerData?.some(p => p.providerId === "password")) {
    throw new OtpError("failed-precondition", "No pending password registration.");
  }
  normalizeEmail(user.email);
}
function requireCompleteProfile(profile) {
  if (typeof profile?.fullName !== "string" || profile.fullName.trim().length < 2 ||
      profile.fullName.length > 100 || typeof profile.phone !== "string" ||
      !/^\+[1-9][0-9]{7,14}$/.test(profile.phone) ||
      typeof profile.profession !== "string" || !profile.profession.trim() ||
      profile.profession.length > 100 || profile.registrationConfirmed !== true) {
    throw new OtpError("failed-precondition", "Complete your registration profile.");
  }
}
module.exports = { OtpError, requireUid, normalizeEmail, requirePendingPasswordUser, requireCompleteProfile };
