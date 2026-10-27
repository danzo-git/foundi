const { test } = require("node:test");
const assert = require("node:assert/strict");
const { createOtpService } = require("../src/otp-service");
const { changeRegistrationEmail } = require("../src/account-service");

class MemoryStore {
  documents = new Map();
  queue = Promise.resolve();
  transaction(operation) {
    const job = this.queue.then(async () => {
      const pending = new Map(this.documents);
      const result = await operation({
        get: async path => structuredClone(pending.get(path)),
        set: (path, data) => pending.set(path, structuredClone(data)),
      });
      this.documents = pending;
      return result;
    });
    this.queue = job.catch(() => {});
    return job;
  }
}
const completeProfile = {
  fullName: "Awa Kouassi", phone: "+2250700000000", profession: "Étudiante",
  registrationConfirmed: true,
};
function setup(options = {}) {
  let time = 1000000;
  let serial = 0;
  const store = new MemoryStore();
  const mail = [];
  const updates = [];
  const users = new Map();
  const addUser = (uid, email) => {
    users.set(uid, { uid, email, emailVerified: false, disabled: false, providerData: [{ providerId: "password" }] });
    store.documents.set("users/" + uid, structuredClone(completeProfile));
  };
  addUser("owner", "awa@example.com");
  const auth = {
    getUser: async uid => {
      if (!users.has(uid)) throw Object.assign(new Error(), { code: "auth/user-not-found" });
      return structuredClone(users.get(uid));
    },
    updateUser: async (uid, fields) => {
      updates.push({ uid, fields: structuredClone(fields) });
      Object.assign(users.get(uid), fields);
      return structuredClone(users.get(uid));
    },
    createUser: () => { throw new Error("OTP must never create an account."); },
    createCustomToken: () => { throw new Error("OTP must never mint a login token."); },
    revokeRefreshTokens: () => { throw new Error("OTP must preserve the password session."); },
  };
  const service = createOtpService({
    store, auth, secret: "test-secret-with-at-least-32-characters",
    clock: () => time,
    generateId: () => "00000000-0000-4000-8000-" + String(++serial).padStart(12, "0"),
    generateCode: () => "012345",
    sendMail: options.sendMail || (async message => mail.push(message)),
  });
  return { ...service, store, mail, users, updates, auth, addUser, advance: ms => { time += ms; } };
}
const failsWith = code => error => error.code === code;

test("verifies the authenticated account email, preserving UID and password provider", async () => {
  const ctx = setup();
  const challenge = await ctx.requestCode("owner", "ip");
  assert.equal(challenge.expiresInSeconds, 600);
  assert.equal(challenge.resendAfterSeconds, 60);
  assert.deepEqual(ctx.mail, [{ email: "awa@example.com", code: "012345" }]);
  assert.ok(!JSON.stringify([...ctx.store.documents.values()]).includes("012345"));
  assert.deepEqual(await ctx.verifyCode("owner", challenge.challengeId, "012345", "ip"), { verified: true });
  assert.deepEqual(ctx.updates, [{ uid: "owner", fields: { emailVerified: true } }]);
  assert.deepEqual(ctx.users.get("owner").providerData, [{ providerId: "password" }]);
  assert.equal(ctx.users.size, 1);
});

test("rejects unauthenticated requests and verification", async () => {
  const ctx = setup();
  await assert.rejects(ctx.requestCode(undefined, "ip"), failsWith("unauthenticated"));
  await assert.rejects(ctx.verifyCode(null, "00000000-0000-4000-8000-000000000001", "012345", "ip"), failsWith("unauthenticated"));
  assert.equal(ctx.mail.length, 0);
});

test("another authenticated user cannot use or consume the owner's code", async () => {
  const ctx = setup();
  ctx.addUser("other", "other@example.com");
  const { challengeId } = await ctx.requestCode("owner", "ip");
  await assert.rejects(ctx.verifyCode("other", challengeId, "012345", "ip2"), failsWith("unauthenticated"));
  assert.equal(ctx.store.documents.get("authEmailChallenges/" + challengeId).attempts, 0);
  await ctx.verifyCode("owner", challengeId, "012345", "ip");
  assert.equal(ctx.users.get("other").emailVerified, false);
});

test("invalid identifiers and codes never update a user", async () => {
  const ctx = setup();
  await assert.rejects(ctx.verifyCode("owner", "../other", "012345", "ip"), failsWith("invalid-argument"));
  await assert.rejects(ctx.verifyCode("owner", "00000000-0000-4000-8000-000000000001", "12345", "ip"), failsWith("invalid-argument"));
  assert.equal(ctx.updates.length, 0);
});

test("persists incorrect attempts and blocks the fifth failure across IP addresses", async () => {
  const ctx = setup();
  const { challengeId } = await ctx.requestCode("owner", "ip");
  for (let i = 0; i < 4; i++) {
    await assert.rejects(ctx.verifyCode("owner", challengeId, "999999", "ip"), failsWith("unauthenticated"));
  }
  await assert.rejects(ctx.verifyCode("owner", challengeId, "999999", "ip"), failsWith("resource-exhausted"));
  await assert.rejects(ctx.verifyCode("owner", challengeId, "012345", "other-ip"), failsWith("resource-exhausted"));
  assert.equal(ctx.updates.length, 0);
});

test("expires at ten minutes without relying on Firestore TTL", async () => {
  const ctx = setup();
  const { challengeId } = await ctx.requestCode("owner", "ip");
  ctx.advance(600000);
  await assert.rejects(ctx.verifyCode("owner", challengeId, "012345", "ip"), failsWith("deadline-exceeded"));
});

test("concurrent verification consumes the code at most once", async () => {
  const ctx = setup();
  const { challengeId } = await ctx.requestCode("owner", "ip");
  const results = await Promise.allSettled([
    ctx.verifyCode("owner", challengeId, "012345", "ip"),
    ctx.verifyCode("owner", challengeId, "012345", "ip"),
  ]);
  assert.equal(results.filter(r => r.status === "fulfilled").length, 1);
  assert.equal(ctx.updates.length, 1);
});

test("resends invalidate previous codes and enforce per-email limits", async () => {
  const ctx = setup();
  const first = await ctx.requestCode("owner", "ip");
  await assert.rejects(ctx.requestCode("owner", "other-ip"), failsWith("resource-exhausted"));
  ctx.advance(60000);
  await ctx.requestCode("owner", "ip");
  await assert.rejects(ctx.verifyCode("owner", first.challengeId, "012345", "ip"), failsWith("unauthenticated"));
  for (let i = 0; i < 3; i++) { ctx.advance(60000); await ctx.requestCode("owner", "ip"); }
  ctx.advance(60000);
  await assert.rejects(ctx.requestCode("owner", "other-ip"), failsWith("resource-exhausted"));
  ctx.advance(900000);
  await ctx.requestCode("owner", "ip");
  assert.equal(ctx.mail.length, 6);
});

test("simultaneous sends cannot bypass the resend delay", async () => {
  const ctx = setup();
  const results = await Promise.allSettled([ctx.requestCode("owner", "ip1"), ctx.requestCode("owner", "ip2")]);
  assert.equal(results.filter(r => r.status === "fulfilled").length, 1);
  assert.equal(ctx.mail.length, 1);
});

test("per-IP quotas apply to many addresses and unknown challenges", async () => {
  const ctx = setup();
  for (let i = 0; i < 21; i++) ctx.addUser("u" + i, "p" + i + "@example.com");
  for (let i = 0; i < 20; i++) await ctx.requestCode("u" + i, "ip");
  await assert.rejects(ctx.requestCode("u20", "ip"), failsWith("resource-exhausted"));
  for (let i = 0; i < 60; i++) {
    await assert.rejects(ctx.verifyCode("owner", "00000000-0000-4000-8000-000000000099", "012345", "ip"), failsWith("unauthenticated"));
  }
  await assert.rejects(ctx.verifyCode("owner", "00000000-0000-4000-8000-000000000099", "012345", "ip"), failsWith("resource-exhausted"));
});

test("failed SMTP delivery leaves an unusable code and keeps rate limits", async () => {
  const ctx = setup({ sendMail: async () => { throw new Error("sensitive SMTP error"); } });
  await assert.rejects(ctx.requestCode("owner", "ip"), failsWith("unavailable"));
  await assert.rejects(ctx.verifyCode("owner", "00000000-0000-4000-8000-000000000001", "012345", "ip"), failsWith("unauthenticated"));
  await assert.rejects(ctx.requestCode("owner", "ip"), failsWith("resource-exhausted"));
  assert.equal(ctx.updates.length, 0);
});

test("legacy passwordless challenges cannot verify a password registration", async () => {
  const ctx = setup();
  const { challengeId } = await ctx.requestCode("owner", "ip");
  const old = ctx.store.documents.get("authEmailChallenges/" + challengeId);
  delete old.schemaVersion; delete old.userId; delete old.purpose;
  await assert.rejects(ctx.verifyCode("owner", challengeId, "012345", "ip"), failsWith("unauthenticated"));
  assert.equal(ctx.updates.length, 0);
});

test("disabled, verified, Google-only and legacy users cannot request registration codes", async () => {
  for (const fields of [
    { disabled: true }, { emailVerified: true },
    { providerData: [{ providerId: "google.com" }] }, { providerData: [] },
  ]) {
    const ctx = setup();
    Object.assign(ctx.users.get("owner"), fields);
    await assert.rejects(ctx.requestCode("owner", "ip"));
    assert.equal(ctx.mail.length, 0);
  }
});

test("requires full classic profile, including a phone with country code", async () => {
  for (const fields of [
    { fullName: "" }, { phone: "0700000000" }, { profession: "" }, { registrationConfirmed: false },
  ]) {
    const ctx = setup();
    Object.assign(ctx.store.documents.get("users/owner"), fields);
    await assert.rejects(ctx.requestCode("owner", "ip"), failsWith("failed-precondition"));
    assert.equal(ctx.mail.length, 0);
  }
});

test("a code for the old email cannot verify a changed email", async () => {
  const ctx = setup();
  const { challengeId } = await ctx.requestCode("owner", "ip");
  ctx.users.get("owner").email = "new@example.com";
  await assert.rejects(ctx.verifyCode("owner", challengeId, "012345", "ip"), failsWith("unauthenticated"));
  assert.equal(ctx.updates.length, 0);
});

test("email correction requires recent authentication and an unverified password account", async () => {
  const ctx = setup();
  const args = { auth: ctx.auth, uid: "owner", email: " New@Example.com ", authTime: 990, clock: () => 1000000 };
  await assert.rejects(changeRegistrationEmail({ ...args, uid: null }), failsWith("unauthenticated"));
  await assert.rejects(changeRegistrationEmail({ ...args, authTime: 0 }), failsWith("unauthenticated"));
  await assert.rejects(changeRegistrationEmail({ ...args, email: "Name <a@example.com>" }), failsWith("invalid-argument"));
  assert.deepEqual(await changeRegistrationEmail(args), { updated: true });
  assert.equal(ctx.users.get("owner").email, "new@example.com");
  assert.deepEqual(ctx.users.get("owner").providerData, [{ providerId: "password" }]);
  ctx.users.get("owner").emailVerified = true;
  await assert.rejects(changeRegistrationEmail(args), failsWith("failed-precondition"));
});
