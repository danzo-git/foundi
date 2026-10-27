const { createHmac, randomInt, randomUUID, timingSafeEqual } = require("node:crypto");
const { OtpError, requireUid, normalizeEmail, requirePendingPasswordUser, requireCompleteProfile } = require("./auth-validation");

const TTL_MS = 10 * 60 * 1000;
const RESEND_MS = 60 * 1000;
const WINDOW_MS = 15 * 60 * 1000;
const MAX_ATTEMPTS = 5;

function quota(previous, limit, now, gap = 0) {
  const current = previous && now - previous.windowStartedAt < WINDOW_MS
    ? previous : { count: 0, windowStartedAt: now, lastAt: null };
  if (current.count >= limit || (current.lastAt !== null && now - current.lastAt < gap)) {
    throw new OtpError("resource-exhausted", "Please wait before trying again.");
  }
  return {
    count: current.count + 1, windowStartedAt: current.windowStartedAt, lastAt: now,
    deleteAfter: new Date(now + 24 * 60 * 60 * 1000),
  };
}

// Version 2: an authenticated password registration verifies its own email.
// This service never creates an account, removes a password or mints a login token.
function createOtpService({
  store, sendMail, auth, secret, clock = Date.now,
  generateCode = () => randomInt(0, 1000000).toString().padStart(6, "0"),
  generateId = randomUUID,
}) {
  if (typeof secret !== "string" || secret.length < 32) {
    throw new Error("OTP_HMAC_KEY must contain at least 32 characters.");
  }
  const digest = (...values) => createHmac("sha256", secret).update(JSON.stringify(values)).digest("hex");
  const ipPath = (ip, kind) => "authEmailRateLimits/" + digest(kind, ip || "unknown");

  async function requestCode(uid, ip) {
    requireUid(uid);
    const user = await auth.getUser(uid);
    requirePendingPasswordUser(user);
    const email = normalizeEmail(user.email);
    const now = clock();
    const id = generateId();
    const code = generateCode();
    const emailKey = digest("email", email);
    const emailPath = "authEmailRateLimits/" + emailKey;
    const addressPath = ipPath(ip, "send");
    const challengePath = "authEmailChallenges/" + id;

    await store.transaction(async tx => {
      const profile = await tx.get("users/" + uid);
      const emailRate = await tx.get(emailPath);
      const addressRate = await tx.get(addressPath);
      requireCompleteProfile(profile);
      const nextEmail = quota(emailRate, 5, now, RESEND_MS);
      const nextAddress = quota(addressRate, 20, now);
      tx.set(emailPath, { ...nextEmail, activeChallengeId: id });
      tx.set(addressPath, nextAddress);
      tx.set(challengePath, {
        schemaVersion: 2, purpose: "verify-email", userId: uid,
        email, emailKey, hash: digest("code", uid, id, email, code),
        attempts: 0, status: "pending", expiresAt: now + TTL_MS,
        deleteAfter: new Date(now + 24 * 60 * 60 * 1000),
      });
    });
    try {
      await sendMail({ email, code });
    } catch {
      await store.transaction(async tx => {
        const challenge = await tx.get(challengePath);
        if (challenge?.status === "pending") {
          tx.set(challengePath, { ...challenge, status: "failed", hash: null });
        }
      });
      throw new OtpError("unavailable", "Unable to deliver email.");
    }
    await store.transaction(async tx => {
      const challenge = await tx.get(challengePath);
      tx.set(challengePath, { ...challenge, status: "sent" });
    });
    return {
      challengeId: id,
      expiresInSeconds: Math.max(0, Math.floor((now + TTL_MS - clock()) / 1000)),
      resendAfterSeconds: Math.max(0, Math.ceil((now + RESEND_MS - clock()) / 1000)),
    };
  }

  async function verifyCode(uid, challengeId, code, ip) {
    requireUid(uid);
    if (typeof challengeId !== "string" || !/^[a-f0-9-]{36}$/.test(challengeId) ||
        typeof code !== "string" || !/^\d{6}$/.test(code)) {
      throw new OtpError("invalid-argument", "Invalid code.");
    }
    const user = await auth.getUser(uid);
    requirePendingPasswordUser(user);
    const email = normalizeEmail(user.email);
    const now = clock();
    const challengePath = "authEmailChallenges/" + challengeId;
    const addressPath = ipPath(ip, "verify");
    const outcome = await store.transaction(async tx => {
      const challenge = await tx.get(challengePath);
      const addressRate = await tx.get(addressPath);
      const profile = await tx.get("users/" + uid);
      const emailRate = challenge ? await tx.get("authEmailRateLimits/" + challenge.emailKey) : null;
      requireCompleteProfile(profile);
      tx.set(addressPath, quota(addressRate, 60, now));
      if (!challenge || challenge.schemaVersion !== 2 || challenge.purpose !== "verify-email" ||
          challenge.userId !== uid || challenge.email !== email) return { error: "unauthenticated" };
      if (challenge.status === "locked") return { error: "resource-exhausted" };
      if (challenge.status !== "sent" || emailRate?.activeChallengeId !== challengeId) {
        return { error: "unauthenticated" };
      }
      if (now >= challenge.expiresAt) return { error: "deadline-exceeded" };
      if (challenge.attempts >= MAX_ATTEMPTS) return { error: "resource-exhausted" };
      const expected = Buffer.from(challenge.hash, "hex");
      const actual = Buffer.from(digest("code", uid, challengeId, email, code), "hex");
      if (expected.length !== actual.length || !timingSafeEqual(expected, actual)) {
        const attempts = challenge.attempts + 1;
        tx.set(challengePath, { ...challenge, attempts, status: attempts >= MAX_ATTEMPTS ? "locked" : "sent" });
        return { error: attempts >= MAX_ATTEMPTS ? "resource-exhausted" : "unauthenticated" };
      }
      // Persist failed attempts and consume successes in the transaction, before Admin Auth.
      tx.set(challengePath, { ...challenge, status: "consumed", hash: null });
      return { email };
    });
    if (outcome.error) throw new OtpError(outcome.error, "Unable to verify code.");
    const current = await auth.getUser(uid);
    if (normalizeEmail(current.email) !== outcome.email) {
      throw new OtpError("unauthenticated", "The email changed.");
    }
    requirePendingPasswordUser(current);
    await auth.updateUser(uid, { emailVerified: true });
    return { verified: true };
  }
  return { requestCode, verifyCode };
}
module.exports = { createOtpService, OtpError, normalizeEmail };
