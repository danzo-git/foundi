const { initializeApp } = require("firebase-admin/app");

const { getAuth } = require("firebase-admin/auth");

const { getFirestore } = require("firebase-admin/firestore");

const { getStorage } = require("firebase-admin/storage");

const { onCall, HttpsError } = require("firebase-functions/v2/https");

const { defineSecret, defineString, defineInt, defineBoolean } = require("firebase-functions/params");

const logger = require("firebase-functions/logger");

const nodemailer = require("nodemailer");

const { createOtpService, OtpError } = require("./otp-service");

const { changeRegistrationEmail } = require("./account-service");

const { createProfessionalService } = require("./professional-service");



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

    if (error instanceof HttpsError) throw error;

    if (error instanceof OtpError) throw new HttpsError(error.code, error.message);

    // Do not log SMTP errors, codes, addresses or tokens.

    logger.error("Foundi operation failed.", { code: String(error.code || "internal") });

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



const professional = createProfessionalService({

  store, auth: getAuth(), files: {

    save: async (path, bytes, contentType) => {

      const file = getStorage().bucket().file(path);

      await file.save(bytes, { resumable: false, contentType,

        preconditionOpts: { ifGenerationMatch: 0 }, metadata: { cacheControl: 'private, no-store' } });

      const [metadata] = await file.getMetadata();

      return metadata.generation;

    },

    exists: async (path, generation) => {

      try {

        const [metadata] = await getStorage().bucket().file(path).getMetadata();

        return String(metadata.generation) === generation && !metadata.metadata?.firebaseStorageDownloadTokens;

      } catch (error) { if (error.code === 404) return false; throw error; }

    },

    remove: path => getStorage().bucket().file(path).delete({ ignoreNotFound: true }),

  },

});

const proOptions = { region: 'europe-west1', maxInstances: 3, concurrency: 4, timeoutSeconds: 120, memory: '256MiB' };

exports.startProfessionalProfile = onCall(proOptions, r => handle(() => professional.ensureDraft(r.auth?.uid)));

exports.saveProfessionalActivity = onCall(proOptions, r => handle(() => professional.saveActivity(r.auth?.uid, r.data?.activity, r.data?.complete === true)));

exports.uploadProfessionalDocument = onCall(proOptions, r => handle(() => professional.uploadDocument(r.auth?.uid, r.data?.kind, r.data?.name, r.data?.base64)));

exports.submitProfessionalProfile = onCall(proOptions, r => handle(() => professional.submit(r.auth?.uid, r.data?.certified)));

exports.reviewProfessionalProfile = onCall(proOptions, r => handle(() => professional.decide(r.auth?.uid, r.auth?.token, r.data?.uid, r.data?.status, r.data?.reason, r.data?.revision)));

exports.checkProfessionalAccess = onCall(proOptions, r => handle(() => professional.requireApproved(r.auth?.uid)));



exports.readProfessionalDocument = onCall(proOptions, r => handle(async () => {

  if (!r.auth || r.auth.token.admin !== true) throw new HttpsError('permission-denied', 'Accès administratif requis.');

  const user = await getAuth().getUser(r.auth.uid);

  if (user.disabled || user.customClaims?.admin !== true) throw new HttpsError('permission-denied', 'Accès révoqué.');

  const { uid, kind } = r.data || {};

  if (![uid, kind].every(v => typeof v === 'string' && /^[a-zA-Z0-9_-]{1,128}$/.test(v))) throw new HttpsError('invalid-argument', 'Document invalide.');

  const doc = (await getFirestore().doc('professionalProfiles/' + uid + '/documents/' + kind).get()).data();

  if (doc?.state !== 'ready' || doc.objectPath !== 'professionalDocuments/' + uid + '/' + kind + '/' + doc.uploadId || !['application/pdf','image/png','image/jpeg'].includes(doc.contentType) || doc.size > 5242880) throw new HttpsError('failed-precondition', 'Document indisponible.');

  const [bytes] = await getStorage().bucket().file(doc.objectPath, { generation: doc.generation }).download();

  return { base64: bytes.toString('base64'), contentType: doc.contentType };

}));



const { createCatalogService } = require('./catalog-service');

const catalogService = createCatalogService({ store, auth: getAuth() });

exports.updateProfessionalCatalog = onCall(proOptions, r => handle(() => catalogService.update(r.auth?.uid, r.auth?.token, r.data)));



const { createRequestService } = require('./request-service');

const requests = createRequestService({ store, auth: getAuth() });

exports.publishRequest = onCall({ region: 'europe-west1', maxInstances: 3, timeoutSeconds: 60 },

  r => handle(() => requests.publish(r.auth?.uid, r.data?.requestId, r.data?.request)));



exports.manageRequest = onCall({ region: 'europe-west1', maxInstances: 3, timeoutSeconds: 60 },

  r => handle(() => requests.manage(r.auth?.uid, r.data?.requestId, r.data?.action, r.data?.request, r.data?.expectedRevision)));


const { createOpportunityService } = require('./opportunity-service');
const opportunities = createOpportunityService({ auth: getAuth(), store: {
  get: async path => (await getFirestore().doc(path).get()).data(),
  owned: async (uid, ids) => {
    if (!ids.length) return new Set();
    const docs = await getFirestore().getAll(...ids.map(id => getFirestore().doc(`userRequests/${uid}/items/${id}`)));
    return new Set(docs.filter(d => d.exists).map(d => d.id));
  },
  query: async (filters, after, size) => {
    let query = getFirestore().collection('requests').where('status', '==', 'published')
      .where('categoryId', '==', filters.categoryId).where('zoneId', '==', filters.zoneId)
      .where('specialtyId', '==', filters.specialtyId).orderBy('createdAt', 'desc').orderBy('__name__', 'desc');
    if (after) query = query.startAfter(after.createdAt, getFirestore().doc(`requests/${after.id}`));
    return (await query.limit(size).get()).docs.map(d => ({ id: d.id, ...d.data() }));
  },
}});
exports.listOpportunities = onCall({ region: 'europe-west1', maxInstances: 3, timeoutSeconds: 60 },
  r => handle(() => opportunities.list(r.auth?.uid, r.data)));
