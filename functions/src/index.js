const { initializeApp } = require("firebase-admin/app");

const { getAuth } = require("firebase-admin/auth");

const { getFirestore } = require("firebase-admin/firestore");

const { getStorage } = require("firebase-admin/storage");

const { onCall: firebaseOnCall, onRequest, HttpsError } = require("firebase-functions/v2/https");
const { onSchedule } = require('firebase-functions/v2/scheduler');

const { defineSecret, defineString, defineInt, defineBoolean } = require("firebase-functions/params");

const logger = require("firebase-functions/logger");

const nodemailer = require("nodemailer");

const { createOtpService, OtpError } = require("./otp-service");

const { changeRegistrationEmail } = require("./account-service");

const { createProfessionalService } = require("./professional-service");
const { createProfessionalShowcaseService } = require('./professional-showcase-service');



initializeApp();

// Covers every existing callable, including older clients, without trusting token age.
function onCall(options, operation, {allowSuspended=false}={}) {
  return firebaseOnCall(options, request => handle(async () => {
    if (request.auth) {
      const user = await getAuth().getUser(request.auth.uid);
      const restriction = (await getFirestore().doc(`accountSafety/${request.auth.uid}`).get()).data();
      if (user.disabled || (!allowSuspended && restriction?.suspended)) throw new HttpsError('permission-denied','Ce compte est suspendu ou indisponible. Contacte l’assistance.');
    }
    return operation(request);
  }));
}

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
    conversationsForRequest: async (id) => (await transaction.get(getFirestore().collection('conversations').where('requestId', '==', id))).docs.map(d => ({ id: d.id, ...d.data() })),

    set: (path, value) => transaction.set(getFirestore().doc(path), value),
    delete: (path) => transaction.delete(getFirestore().doc(path)),

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

const showcase = createProfessionalShowcaseService({ store, auth: getAuth() });
exports.readProfessionalShowcase = onCall(proOptions, r =>
  handle(() => showcase.read(r.auth?.uid, r.data?.proposalId)));
exports.saveProfessionalShowcase = onCall({ ...proOptions, concurrency: 1, memory: '512MiB' }, r =>
  handle(() => showcase.save(r.auth?.uid, r.data)));

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
const { createRequestPhotoService } = require('./request-photo-service');

const requestPhotos = createRequestPhotoService({
  auth: getAuth(),
  store: {
    ...store,
    expiredRequestPhotos: async (now, size) =>
      (await getFirestore().collection('requestPhotoFiles')
        .where('deleteAt', '<=', now).orderBy('deleteAt').limit(size).get())
        .docs.map((doc) => doc.ref.path),
  },
  files: {
    async save(path, bytes, sha256) {
      const file = getStorage().bucket().file(path);
      try {
        await file.save(bytes, {
          resumable: false, contentType: 'image/webp', timeout: 60000,
          preconditionOpts: { ifGenerationMatch: 0 },
          metadata: { cacheControl: 'private, no-store', metadata: { sha256 } },
        });
      } catch (error) {
        if (Number(error.code) !== 412) throw error;
      }
      const [metadata] = await file.getMetadata();
      if (metadata.metadata?.firebaseStorageDownloadTokens || metadata.metadata?.sha256 !== sha256 ||
          metadata.contentType !== 'image/webp' || Number(metadata.size) !== bytes.length) {
        throw new OtpError('failed-precondition', 'Photo indisponible.');
      }
      return String(metadata.generation);
    },
    async read(path, generation) {
      const file = getStorage().bucket().file(path, { generation });
      const [metadata] = await file.getMetadata();
      if (metadata.metadata?.firebaseStorageDownloadTokens || metadata.contentType !== 'image/webp') {
        throw new OtpError('not-found', 'Cette photo est indisponible.');
      }
      return (await file.download())[0];
    },
    remove: (path) => getStorage().bucket().file(path).delete({ ignoreNotFound: true }),
  },
});
const requestPhotoOptions = {
  region: 'europe-west1', maxInstances: 3, concurrency: 1,
  timeoutSeconds: 120, memory: '512MiB',
};
const requests = createRequestService({ store, auth: getAuth(), photos: requestPhotos });

exports.publishRequest = onCall({ region: 'europe-west1', maxInstances: 3, timeoutSeconds: 60 },

  r => handle(() => requests.publish(r.auth?.uid, r.data?.requestId, r.data?.request)));

exports.publishDirectRequest = onCall({ region: 'europe-west1', maxInstances: 3, timeoutSeconds: 60 },
  r => handle(() => requests.publishDirect(r.auth?.uid, r.data?.requestId, r.data?.professionalId, r.data?.request)));

exports.readDirectRequestAuthors = onCall({ region: 'europe-west1', maxInstances: 3, timeoutSeconds: 60 },
  r => handle(() => requests.readDirectAuthors(r.auth?.uid, r.data?.requestIds)));



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

const { createProposalService } = require('./proposal-service');
const proposals = createProposalService({auth:getAuth(),store:{...store,
  get:async path=>(await getFirestore().doc(path).get()).data(),
  legacyOwners:async (id,createdAt)=>{
    const docs=await getFirestore().collectionGroup('items').where('createdAt','==',createdAt).limit(50).get();
    return docs.docs.filter(d=>d.id===id && /^userRequests\/[^/]+\/items\/[^/]+$/.test(d.ref.path)).map(d=>d.ref.parent.parent.id);
  },
}});
exports.proposalAccess=onCall({region:'europe-west1',maxInstances:3,timeoutSeconds:60},r=>handle(()=>proposals.access(r.auth?.uid,r.data?.requestId)));
exports.sendProposal=onCall({region:'europe-west1',maxInstances:3,timeoutSeconds:60},r=>handle(()=>proposals.send(r.auth?.uid,r.data?.requestId,r.data?.proposal)));
exports.proposalApproval=onCall({region:'europe-west1',maxInstances:3,timeoutSeconds:60},r=>handle(()=>proposals.approval(r.auth?.uid,r.data?.proposalId)));

const { createRequestRespondentsService } = require('./request-respondents-service');
const requestRespondents = createRequestRespondentsService({ db: getFirestore(), auth: getAuth() });
exports.listRequestRespondents = onCall(proOptions, (r) =>
  handle(() => requestRespondents.list(r.auth?.uid, r.data?.requestId, r.data?.offset)));
exports.readRequestRespondentProfile = onCall(proOptions, (r) =>
  handle(() => requestRespondents.readProfile(r.data?.requestId, r.data?.professionalId)));

const { createRequestEngagementService } = require('./request-engagement-service');
const requestEngagement = createRequestEngagementService({ db: getFirestore() });
exports.readRequestEngagement = onCall(proOptions, (r) =>
  handle(() => requestEngagement.read(r.data?.requestId)));

const {createProfessionalDirectoryStore}=require('./professional-directory-store');
const {createProfessionalDirectoryService,directoryActor}=require('./professional-directory-service');
const professionalDirectory=createProfessionalDirectoryService({store:createProfessionalDirectoryStore(getFirestore()),auth:getAuth()});
exports.listPublicProfessionals=onCall(proOptions,r=>handle(()=>professionalDirectory.search(directoryActor(r),r.data)));
exports.readPublicProfessionalProfile=onCall(proOptions,r=>handle(()=>professionalDirectory.readProfile(directoryActor(r),r.data)));
exports.readPublicProfessionalMedia=onCall({...proOptions,concurrency:1,memory:'512MiB'},r=>handle(()=>professionalDirectory.readMedia(directoryActor(r),r.data)));
exports.checkPublicProfessionals=onCall(proOptions,r=>handle(()=>professionalDirectory.check(directoryActor(r),r.data)));

const { createRequestInteractionService } = require('./request-interaction-service');
const requestInteractions = createRequestInteractionService({
  auth: getAuth(),
  ownerForRequest: proposals.owner,
  store: {
    ...store,
    get: async (path) => (await getFirestore().doc(path).get()).data(),
    async approvedPage(cursor, size) {
      let query = getFirestore().collection('professionalProfiles').where('status', '==', 'approved')
        .orderBy('__name__').select('status', 'businessName', 'categoryIds', 'specialtyIds', 'zoneIds');
      if (cursor) query = query.startAfter(getFirestore().doc(`professionalProfiles/${cursor}`));
      return (await query.limit(size).get()).docs.map((doc) => ({ id: doc.id, profile: doc.data() }));
    },
  },
});
exports.setRequestLike = onCall(proOptions, (r) => handle(() =>
  requestInteractions.setLike(r.auth?.uid, r.data?.requestId, r.data?.liked)));
exports.searchRecommendationProfessionals = onCall(proOptions, (r) => handle(() =>
  requestInteractions.search(r.auth?.uid, r.data?.requestId, r.data?.query, r.data?.cursor)));
exports.recommendRequestProfessional = onCall(proOptions, (r) => handle(() =>
  requestInteractions.recommend(r.auth?.uid, r.data?.requestId, r.data?.professionalId)));
exports.readRequestRecommendation = onCall(proOptions, (r) => handle(() =>
  requestInteractions.readRecommendation(r.auth?.uid, r.data?.recommendationId)));

const {createConversationService}=require('./conversation-service');
const conversations=createConversationService({store,auth:getAuth(),onSendTiming:entry=>logger.info('message_send_server_timing',entry)});
exports.selectProposal=onCall({region:'europe-west1',maxInstances:3,timeoutSeconds:60},r=>handle(()=>conversations.select(r.auth?.uid,r.data)));
exports.sendConversationMessage=onCall({region:'europe-west1',maxInstances:3,timeoutSeconds:60},r=>handle(()=>conversations.send(r.auth?.uid,r.data)));
exports.decideProposal=onCall({region:'europe-west1',maxInstances:3,timeoutSeconds:60},r=>handle(()=>conversations.decide(r.auth?.uid,r.data)));

const {createAttachmentService}=require('./attachment-service');
const {createClamScanner}=require('./attachment-scanner');
const scanHost=defineString('ATTACHMENT_SCAN_HOST',{default:'disabled'});
const scanPort=defineInt('ATTACHMENT_SCAN_PORT',{default:3310});
const requireAttachmentScan=defineBoolean('ATTACHMENT_REQUIRE_SCAN',{default:true});
const attachments=createAttachmentService({auth:getAuth(),store:{...store,
  get:async path=>(await getFirestore().doc(path).get()).data(),
  expiredAttachments:async(now,size)=>(await getFirestore().collectionGroup('attachments').where('expiresAt','<=',now).orderBy('expiresAt').limit(size).get()).docs.map(d=>({path:d.ref.path,...d.data()})),
},requireScan:()=>requireAttachmentScan.value(),scan:bytes=>createClamScanner({host:scanHost.value(),port:scanPort.value()})(bytes),files:{
  save:async(path,bytes,contentType,metadata)=>{
    const file=getStorage().bucket().file(path);
    try{await file.save(bytes,{resumable:false,contentType,preconditionOpts:{ifGenerationMatch:0},metadata:{cacheControl:'private, no-store',metadata}});}
    catch(e){if(Number(e.code)!==412)throw e;}
    const [saved]=await file.getMetadata();
    if(saved.metadata?.firebaseStorageDownloadTokens||saved.metadata?.sha256!==metadata.sha256||saved.metadata?.messageid!==metadata.messageid||Number(saved.size)!==bytes.length||saved.contentType!==contentType)throw new OtpError('failed-precondition','Objet de stockage incohérent.');
    return String(saved.generation);
  },
  read:async(path,generation)=>{
    const file=getStorage().bucket().file(path,{generation}),[metadata]=await file.getMetadata();
    if(metadata.metadata?.firebaseStorageDownloadTokens)throw new OtpError('failed-precondition','Fichier indisponible.');
    return (await file.download())[0];
  },
  remove:path=>getStorage().bucket().file(path).delete({ignoreNotFound:true}),
}});
const attachmentOptions={region:'europe-west1',maxInstances:3,concurrency:2,timeoutSeconds:120,memory:'512MiB'};
exports.prepareConversationAttachment=onCall(attachmentOptions,r=>handle(()=>attachments.prepare(r.auth?.uid,r.data)));
exports.cancelConversationAttachment=onCall(attachmentOptions,r=>handle(()=>attachments.cancel(r.auth?.uid,r.data?.conversationId,r.data?.messageId)));
async function mediaHttp(res,operation){
  res.set('Cache-Control','private, no-store');res.set('X-Content-Type-Options','nosniff');
  try{
    await operation();
  }catch(e){
    const codes={'unauthenticated':401,'permission-denied':403,'invalid-argument':400,'not-found':404,'already-exists':409,'failed-precondition':409,'resource-exhausted':429};
    const known=e instanceof OtpError;const code=known?e.code:'unavailable';
    if(!known)logger.warn('Media operation unavailable.',{code:String(e.code||'internal')});
    if(!res.headersSent)res.status(codes[code]||503).json({error:{code,message:known?e.message:'Fichier indisponible. Réessaie plus tard.'}});
  }
}
function authenticatedMediaHttp(req,res,operation){
  return mediaHttp(res, async () => {
    const token=/^Bearer (\S+)$/.exec(req.get('authorization')||'');
    if(!token)throw new OtpError('unauthenticated','Connexion nécessaire.');
    let identity;try{identity=await getAuth().verifyIdToken(token[1],true);}catch{throw new OtpError('unauthenticated','Reconnecte-toi pour continuer.');}
    if ((await getFirestore().doc(`accountSafety/${identity.uid}`).get()).data()?.suspended) throw new OtpError('permission-denied','Ce compte est suspendu.');
    await operation(identity.uid,identity);
  });
}
exports.uploadConversationAttachment=onRequest({...attachmentOptions,cors:true},(req,res)=>authenticatedMediaHttp(req,res,async uid=>{
  if(req.method!=='POST')throw new OtpError('invalid-argument','Méthode invalide.');
  const result=await attachments.upload(uid,req.get('x-conversation-id'),req.get('x-message-id'),req.rawBody);
  res.status(result.state==='ready'?200:202).json(result);
}));
exports.readConversationAttachment=onRequest({...attachmentOptions,cors:true},(req,res)=>authenticatedMediaHttp(req,res,async uid=>{
  if(req.method!=='GET')throw new OtpError('invalid-argument','Méthode invalide.');
  const file=await attachments.read(uid,req.query.conversationId,req.query.messageId);
  res.set('Content-Type',file.contentType);res.set('Content-Disposition',`attachment; filename*=UTF-8''${encodeURIComponent(file.originalName)}`);res.status(200).send(file.bytes);
}));
exports.cleanupConversationAttachments=onSchedule({...attachmentOptions,schedule:'every 24 hours'},()=>attachments.cleanup());

exports.uploadRequestPhoto = onRequest({ ...requestPhotoOptions, cors: true }, (req, res) =>
  authenticatedMediaHttp(req, res, async (uid) => {
    if (req.method !== 'POST') throw new OtpError('invalid-argument', 'Méthode invalide.');
    const result = await requestPhotos.upload(
      uid, req.query.requestId, req.query.photoId, req.rawBody, req.get('content-type'),
    );
    res.status(200).json(result);
  }));
exports.readRequestPhoto = onRequest({ ...requestPhotoOptions, cors: true }, (req, res) =>
  authenticatedMediaHttp(req, res, async (uid) => {
    if (req.method !== 'GET') throw new OtpError('invalid-argument', 'Méthode invalide.');
    const bytes = await requestPhotos.read(uid, req.query.requestId, req.query.photoId);
    res.set('Content-Type', 'image/webp').status(200).send(bytes);
  }));
exports.readPublicRequestPhoto = onRequest({ ...requestPhotoOptions, timeoutSeconds: 30, cors: true }, (req, res) =>
  mediaHttp(res, async () => {
    if (req.method !== 'GET') throw new OtpError('invalid-argument', 'Méthode invalide.');
    const bytes = await requestPhotos.readPublic(req.query.requestId, req.query.photoId);
    res.set('Content-Type', 'image/webp').status(200).send(bytes);
  }));
exports.discardRequestPhotos = onCall(requestPhotoOptions, (r) =>
  handle(() => requestPhotos.discard(r.auth?.uid, r.data?.requestId, r.data?.photoIds)));
exports.cleanupRequestPhotos = onSchedule({
  ...requestPhotoOptions, concurrency: 1, maxInstances: 1, timeoutSeconds: 540, schedule: 'every 60 minutes',
}, async () => {
  const result = await requestPhotos.cleanup();
  if (result.failed) logger.warn('Request photo cleanup deferred.', result);
});

// V9 observes durable server-owned events; business operations remain V8.1/V8.2.
const {onDocumentCreated,onDocumentUpdated,onDocumentWritten}=require('firebase-functions/v2/firestore');
const {getMessaging}=require('firebase-admin/messaging');
const {createNotificationService}=require('./notification-service');
const pushEnabled=defineBoolean('NOTIFICATION_PUSH_ENABLED',{default:false});
const notifications=createNotificationService({db:getFirestore(),auth:getAuth(),messaging:getMessaging(),logger});
const eventOptions={region:'europe-west1',maxInstances:3,retry:true,timeoutSeconds:120};
exports.notifyDirectRequestCreated = onDocumentCreated({...eventOptions, document:'directRequests/{requestId}'},
  e => e.data && notifications.directRequest(e.params.requestId, e.data.data()));
exports.syncRequestResponseCount = onDocumentWritten({ ...eventOptions, document: 'proposals/{id}' },
  (event) => requestEngagement.changed(event.data));
exports.syncRequestRecommendationCount = onDocumentWritten({ ...eventOptions, document: 'requestRecommendations/{id}' },
  (event) => requestEngagement.changed(event.data));
exports.notifyProfessionalDecision=onDocumentCreated({...eventOptions,document:'professionalAudit/{id}'},e=>e.data && notifications.professional(e.params.id,e.data.data()));
exports.notifyProposalCreated=onDocumentCreated({...eventOptions,document:'proposals/{id}'},e=>e.data && notifications.proposal(e.params.id,e.data.data()));
exports.notifyRequestRecommendation = onDocumentCreated({ ...eventOptions, document: 'requestRecommendations/{id}' },
  (e) => e.data && notifications.recommendation(e.params.id, e.data.data()));
exports.notifyProposalDecision=onDocumentCreated({...eventOptions,document:'userRequests/{uid}/items/{requestId}/decisions/{id}'},e=>e.data && notifications.decision(e.params.uid,e.params.requestId,e.params.id,e.data.data()));
exports.notifyConversationOpened=onDocumentCreated({...eventOptions,document:'conversations/{id}'},e=>e.data && notifications.conversation(e.params.id,e.data.data()));
exports.notifyMessageCreated=onDocumentCreated({...eventOptions,document:'conversations/{conversationId}/messages/{id}'},e=>e.data && notifications.message(e.params.conversationId,e.params.id,e.data.data()));
exports.notifyRequestPublished=onDocumentCreated({...eventOptions,document:'requests/{requestId}'},async e=>{
  if (!e.data || e.data.data().status!=='published')return;
  const owner=(await getFirestore().doc(`requestOwnership/${e.params.requestId}`).get()).data();
  if(owner?.ownerUid)await notifications.enqueueRequest('matched',owner.ownerUid,e.params.requestId,e.data.data(),e.data.data().createdAt);
});
exports.notifyRequestClosed=onDocumentUpdated({...eventOptions,document:'userRequests/{uid}/items/{requestId}'},e=>{
  const before=e.data.before.data(),after=e.data.after.data();
  if(['published','in_discussion'].includes(before.status)&&after.status==='closed')return notifications.enqueueRequest('closed',e.params.uid,e.params.requestId,after,after.updatedAt);
});
exports.countNotificationRead=onDocumentUpdated({...eventOptions,document:'users/{uid}/notifications/{id}'},e=>notifications.read(e.params.uid,e.params.id,e.data.before.data(),e.data.after.data()));
exports.runNotificationJob=onDocumentCreated({...eventOptions,document:'notificationJobs/{id}'},e=>notifications.processJob(e.params.id));
exports.deliverNotificationPush=onDocumentCreated({...eventOptions,document:'notificationOutbox/{id}'},e=>pushEnabled.value()?notifications.deliver(e.params.id):undefined);
exports.drainNotifications=onSchedule({region:'europe-west1',schedule:'every 1 minutes',maxInstances:1,timeoutSeconds:540},()=>notifications.drain({push:pushEnabled.value()}));
exports.registerNotificationDevice=onCall(proOptions,r=>handle(()=>notifications.register(r.auth?.uid,r.data)));
exports.unregisterNotificationDevice=onCall(proOptions,r=>handle(()=>notifications.unregister(r.auth?.uid,r.data?.deviceId)));
exports.resolveNotification=onCall(proOptions,r=>handle(()=>notifications.resolve(r.auth?.uid,r.data?.notificationId)),{allowSuspended:true});
exports.markConversationRead=onCall({region:'europe-west1',maxInstances:3,timeoutSeconds:60},r=>handle(()=>notifications.markConversationRead(r.auth?.uid,r.data)));

const {createSafetyService}=require('./safety-service');
const {createSafetyStore}=require('./safety-store');
const {createSafetyEvidence}=require('./safety-evidence');
const safetyEvidence=createSafetyEvidence({files:{read:async(path,generation)=>{
  const file=getStorage().bucket().file(path,{generation}),[metadata]=await file.getMetadata();
  if(metadata.metadata?.firebaseStorageDownloadTokens || Number(metadata.size)>15*1048576)throw new OtpError('not-found','Preuve indisponible.');
  return (await file.download())[0];
}}});
const safety=createSafetyService({store:createSafetyStore(getFirestore()),auth:getAuth(),ownerForRequest:proposals.owner,evidence:safetyEvidence});
exports.submitSafetyReport=onCall(proOptions,r=>handle(()=>safety.submit(r.auth?.uid,r.data)));
exports.readSafetyContext=onCall(proOptions,r=>handle(()=>safety.context(r.auth?.uid,r.data)));
exports.blockUser=onCall(proOptions,r=>handle(()=>safety.block(r.auth?.uid,r.data)));
exports.unblockUser=onCall(proOptions,r=>handle(()=>safety.unblock(r.auth?.uid,r.data)));
exports.unblockSafetyTarget=onCall(proOptions,r=>handle(()=>safety.unblockTarget(r.auth?.uid,r.data)));
exports.listBlockedUsers=onCall(proOptions,r=>handle(()=>safety.listBlocks(r.auth?.uid,r.data)));
exports.listSafetyReports=onCall(proOptions,r=>handle(()=>safety.list(r.auth?.uid,r.auth?.token,r.data)));
exports.readSafetyReport=onCall(proOptions,r=>handle(()=>safety.detail(r.auth?.uid,r.auth?.token,r.data)));
exports.decideSafetyReport=onCall(proOptions,r=>handle(()=>safety.decide(r.auth?.uid,r.auth?.token,r.data)));
exports.listSafetyNotices=onCall(proOptions,r=>handle(()=>safety.notices(r.auth?.uid)),{allowSuspended:true});
exports.acknowledgeSafetyNotice=onCall(proOptions,r=>handle(()=>safety.acknowledgeNotice(r.auth?.uid,r.data)),{allowSuspended:true});
exports.cleanupSafetyEvidence=onSchedule({...proOptions,maxInstances:1,schedule:'every 24 hours'},()=>safety.purgeEvidence());
exports.readSafetyReportAttachment=onRequest({...attachmentOptions,cors:true},(req,res)=>authenticatedMediaHttp(req,res,async(uid,token)=>{
  if(req.method!=='GET')throw new OtpError('invalid-argument','Méthode invalide.');
  const file=await safety.readAttachment(uid,token,{reportId:req.query.reportId});
  res.set('Content-Type',file.contentType);res.set('Content-Disposition',`attachment; filename*=UTF-8''${encodeURIComponent(file.originalName)}`);res.status(200).send(file.bytes);
}));
