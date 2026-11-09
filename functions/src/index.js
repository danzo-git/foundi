const { initializeApp } = require("firebase-admin/app");

const { getAuth } = require("firebase-admin/auth");

const { getFirestore } = require("firebase-admin/firestore");

const { getStorage } = require("firebase-admin/storage");

const { onCall, onRequest, HttpsError } = require("firebase-functions/v2/https");
const { onSchedule } = require('firebase-functions/v2/scheduler');

const { defineSecret, defineString, defineInt, defineBoolean } = require("firebase-functions/params");

const logger = require("firebase-functions/logger");

const nodemailer = require("nodemailer");

const { createOtpService, OtpError } = require("./otp-service");

const { changeRegistrationEmail } = require("./account-service");

const { createProfessionalService } = require("./professional-service");
const { createProfessionalShowcaseService } = require('./professional-showcase-service');



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
    conversationsForRequest: async (id) => (await transaction.get(getFirestore().collection('conversations').where('requestId', '==', id))).docs.map(d => ({ id: d.id, ...d.data() })),

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
async function attachmentHttp(req,res,operation){
  res.set('Cache-Control','private, no-store');res.set('X-Content-Type-Options','nosniff');
  try{
    const token=/^Bearer (\S+)$/.exec(req.get('authorization')||'');
    if(!token)throw new OtpError('unauthenticated','Connexion nécessaire.');
    let identity;try{identity=await getAuth().verifyIdToken(token[1],true);}catch{throw new OtpError('unauthenticated','Reconnecte-toi pour continuer.');}
    await operation(identity.uid);
  }catch(e){
    const codes={'unauthenticated':401,'permission-denied':403,'invalid-argument':400,'not-found':404,'already-exists':409,'failed-precondition':409,'resource-exhausted':429};
    const known=e instanceof OtpError;const code=known?e.code:'unavailable';
    if(!known)logger.warn('Attachment operation unavailable.',{code:String(e.code||'internal')});
    if(!res.headersSent)res.status(codes[code]||503).json({error:{code,message:known?e.message:'Fichier indisponible. Réessaie plus tard.'}});
  }
}
exports.uploadConversationAttachment=onRequest({...attachmentOptions,cors:true},(req,res)=>attachmentHttp(req,res,async uid=>{
  if(req.method!=='POST')throw new OtpError('invalid-argument','Méthode invalide.');
  const result=await attachments.upload(uid,req.get('x-conversation-id'),req.get('x-message-id'),req.rawBody);
  res.status(result.state==='ready'?200:202).json(result);
}));
exports.readConversationAttachment=onRequest({...attachmentOptions,cors:true},(req,res)=>attachmentHttp(req,res,async uid=>{
  if(req.method!=='GET')throw new OtpError('invalid-argument','Méthode invalide.');
  const file=await attachments.read(uid,req.query.conversationId,req.query.messageId);
  res.set('Content-Type',file.contentType);res.set('Content-Disposition',`attachment; filename*=UTF-8''${encodeURIComponent(file.originalName)}`);res.status(200).send(file.bytes);
}));
exports.cleanupConversationAttachments=onSchedule({...attachmentOptions,schedule:'every 24 hours'},()=>attachments.cleanup());

// V9 observes durable server-owned events; business operations remain V8.1/V8.2.
const {onDocumentCreated,onDocumentUpdated}=require('firebase-functions/v2/firestore');
const {getMessaging}=require('firebase-admin/messaging');
const {createNotificationService}=require('./notification-service');
const pushEnabled=defineBoolean('NOTIFICATION_PUSH_ENABLED',{default:false});
const notifications=createNotificationService({db:getFirestore(),auth:getAuth(),messaging:getMessaging(),logger});
const eventOptions={region:'europe-west1',maxInstances:3,retry:true,timeoutSeconds:120};
exports.notifyProfessionalDecision=onDocumentCreated({...eventOptions,document:'professionalAudit/{id}'},e=>e.data && notifications.professional(e.params.id,e.data.data()));
exports.notifyProposalCreated=onDocumentCreated({...eventOptions,document:'proposals/{id}'},e=>e.data && notifications.proposal(e.params.id,e.data.data()));
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
exports.resolveNotification=onCall(proOptions,r=>handle(()=>notifications.resolve(r.auth?.uid,r.data?.notificationId)));
exports.markConversationRead=onCall({region:'europe-west1',maxInstances:3,timeoutSeconds:60},r=>handle(()=>notifications.markConversationRead(r.auth?.uid,r.data)));
