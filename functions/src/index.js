const { initializeApp } = require("firebase-admin/app");
const { getAuth } = require("firebase-admin/auth");
const { getFirestore } = require("firebase-admin/firestore");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret, defineString, defineInt, defineBoolean } = require("firebase-functions/params");
const logger = require("firebase-functions/logger");
const nodemailer = require("nodemailer");
const { createOtpService, OtpError } = require("./otp-service");
const { changeRegistrationEmail } = require("./account-service");

initializeApp();
const smtpPassword = defineSecret("SMTP_PASSWORD");
const smtpUser = defineSecret("SMTP_USER");
const otpKey = defineSecret("OTP_HMAC_KEY");
const smtpHost = defineString("SMTP_HOST");
const smtpPort = defineInt("SMTP_PORT", { default: 587 });
const smtpFrom = defineString("SMTP_FROM");
const smtpRequireTls = defineBoolean("SMTP_REQUIRE_TLS", { default: true });

const store = {
  transaction: (operation) => getFirestore().runTransaction((transaction) => operation({
    get: async (path) => (await transaction.get(getFirestore().doc(path))).data(),
    set: (path, value) => transaction.set(getFirestore().doc(path), value),
  })),
};

function service() {
  const port = smtpPort.value();
  const transport = nodemailer.createTransport({
    host: smtpHost.value(), port, secure: port === 465,
    requireTLS: smtpRequireTls.value(),
    auth: smtpUser.value() ? { user: smtpUser.value(), pass: smtpPassword.value() } : undefined,
    connectionTimeout: 10000, greetingTimeout: 10000, socketTimeout: 15000,
  });
  return createOtpService({
    store, auth: getAuth(), secret: otpKey.value(),
    sendMail: ({ email, code }) => transport.sendMail({
      from: smtpFrom.value(), to: email,
      subject: "Vérifie ton adresse e-mail Foundi",
      text: [
        "Ton code de vérification Foundi : " + code,
        "",
        "Ce code est valable 10 minutes et ne peut être utilisé qu’une fois.",
        "Ne le partage avec personne.",
        "Si tu n’as pas demandé ce code, ignore cet e-mail.",
      ].join("\n"),
    }),
  });
}

async function handle(operation) {
  try {
    return await operation();
  } catch (error) {
    if (error instanceof OtpError) throw new HttpsError(error.code, error.message);
    // Do not log SMTP errors, codes, addresses or tokens.
    logger.error("Email authentication failed.", { code: String(error.code || "internal") });
    throw new HttpsError("internal", "Authentication is temporarily unavailable.");
  }
}

const options = {
  region: "europe-west1", maxInstances: 3, concurrency: 40, timeoutSeconds: 60,
  memory: "256MiB", secrets: [smtpPassword, smtpUser, otpKey],
};

exports.requestEmailCode = onCall(options, (request) =>
  handle(() => service().requestCode(request.auth?.uid, request.rawRequest.ip)));
exports.verifyEmailCode = onCall(options, (request) =>
  handle(() => service().verifyCode(request.auth?.uid, request.data?.challengeId, request.data?.code, request.rawRequest.ip)));
exports.changeRegistrationEmail = onCall({ ...options, secrets: [] }, (request) =>
  handle(() => changeRegistrationEmail({
    auth: getAuth(), uid: request.auth?.uid, email: request.data?.email,
    authTime: request.auth?.token.auth_time,
  })));
