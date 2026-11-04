const {FieldValue, FieldPath} = require('firebase-admin/firestore');
const {OtpError, requireUid} = require('./auth-validation');
const {key, internalId, catalog, matchesOpportunity, professionalType, decisionType, isPrivateMessage, messagePushContent} = require('./notification-policy');
const PAGE = 40, MAX_DEVICES = 10, WINDOW = 60 * 60 * 1000;
const fail = (code, message) => {throw new OtpError(code, message);};

function createNotificationService({db, auth, messaging, clock = Date.now, logger = {info(){}, warn(){}}}) {
  const doc = path => db.doc(path);
  async function active(uid) {
    if (!internalId(uid)) return false;
    try { const user = await auth.getUser(uid); return !user.disabled && user.emailVerified; }
    catch(e) { if (e.code === 'auth/user-not-found') return false; throw e; }
  }
  async function requireAccount(uid) {
    requireUid(uid);
    if (!await active(uid)) fail('permission-denied', 'Un compte actif et vérifié est nécessaire.');
  }
  async function emit({eventId, type, recipientUid, actorUid, resourceType, resourceId, requestId = null, proposalId = null, conversationId = null, occurredAt}) {
    if (isPrivateMessage({type}) || !catalog[type] || ![recipientUid,resourceId].every(internalId) || !await active(recipientUid)) return false;
    const id = key(eventId, recipientUid), ref = doc(`users/${recipientUid}/notifications/${id}`);
    return db.runTransaction(async tx => {
      const existing = await tx.get(ref);
      if (existing.exists) return false;
      const [category,title,bodySafe] = catalog[type];
      const value = {eventId, type, category, title, bodySafe, recipientUid, actorUid:actorUid || null,
        resourceType, resourceId, requestId, proposalId, conversationId, occurredAt:occurredAt || clock(),
        createdAt:FieldValue.serverTimestamp(), readAt:null, schemaVersion:9, isGeneral:true};
      tx.create(ref, value);
      tx.set(doc(`users/${recipientUid}/notificationState/inbox`), {unreadCount:FieldValue.increment(1)}, {merge:true});
      if (recipientUid !== actorUid) tx.create(doc(`notificationOutbox/${id}`), {
        notificationId:id, uid:recipientUid, category, title, bodySafe, conversationId,
        state:'pending', dueAt:clock() + (category === 'opportunities' ? 60000 : 0), createdAt:clock(),
      });
      return true;
    });
  }
  async function professional(id, audit) {
    const type = professionalType(audit);
    if (!type || !internalId(audit.adminUid)) return;
    // Only the existing server-owned admin decision journal is an event source.
    return emit({eventId:`professionalAudit/${id}`,type,recipientUid:audit.uid,actorUid:audit.adminUid,
      resourceType:'professional',resourceId:audit.uid,occurredAt:audit.createdAt});
  }
  async function proposal(id, value) {
    if (value.status !== 'sent' || value.clientUid === value.professionalUid) return;
    const own = (await doc(`userRequests/${value.clientUid}/items/${value.requestId}`).get()).data();
    if (!own) return;
    return emit({eventId:`proposals/${id}/created`,type:'proposal.created',recipientUid:value.clientUid,
      actorUid:value.professionalUid,resourceType:'requestProposals',resourceId:value.requestId,requestId:value.requestId,proposalId:id,occurredAt:value.createdAt});
  }
  async function decision(uid, requestId, id, audit) {
    const type = decisionType(audit);
    if (!type || audit.actorUid !== uid || audit.requestId !== requestId) return;
    const p = (await doc(`proposals/${audit.proposalId}`).get()).data();
    if (!p || p.clientUid !== uid || p.requestId !== requestId || p.professionalUid === uid) return;
    return emit({eventId:`decisions/${uid}/${requestId}/${id}`,type,recipientUid:p.professionalUid,actorUid:uid,
      resourceType:'proposal',resourceId:audit.proposalId,requestId,proposalId:audit.proposalId,conversationId:p.conversationId || null,occurredAt:audit.createdAt});
  }
  async function conversation(id, chat) {
    if (chat.status !== 'active' || chat.clientUid === chat.professionalUid) return;
    const p = (await doc(`proposals/${chat.proposalId || chat.selectedProposalId}`).get()).data();
    if (!p || p.conversationId !== id || p.requestId !== chat.requestId || p.clientUid !== chat.clientUid || p.professionalUid !== chat.professionalUid) return;
    return emit({eventId:`conversations/${id}/created`,type:'conversation.opened',recipientUid:chat.professionalUid,actorUid:chat.clientUid,
      resourceType:'conversation',resourceId:id,requestId:chat.requestId,conversationId:id,occurredAt:chat.createdAt});
  }
  async function message(conversationId, id, value, {push=true, legacyRead=false}={}) {
    if (!['text','image','pdf','contact'].includes(value.type || 'text')) return;
    const chat = (await doc(`conversations/${conversationId}`).get()).data();
    if (!chat || ![chat.clientUid,chat.professionalUid].includes(value.senderUid) || chat.clientUid === chat.professionalUid) return;
    const uid=value.senderUid===chat.clientUid?chat.professionalUid:chat.clientUid;
    if(!await active(uid) || !Number.isSafeInteger(value.createdAt))return;
    const eventId=`messages/${conversationId}/${id}`, eventKey=key(eventId,uid);
    const receipt=doc(`users/${uid}/messageInbox/${eventKey}`), cursor=doc(`users/${uid}/messageReads/${conversationId}`);
    return db.runTransaction(async tx=>{
      const outbox=doc(`notificationOutbox/${eventKey}`);
      const [existing,read,queued]=await Promise.all([tx.get(receipt),tx.get(cursor),tx.get(outbox)]);
      if(existing.exists)return false;
      const unread=!legacyRead && value.createdAt>(read.data()?.readThroughAt || 0);
      tx.create(receipt,{conversationId,messageId:id,senderUid:value.senderUid,createdAt:value.createdAt,unread,eventId,recipientUid:uid,schemaVersion:91});
      if(unread)tx.set(doc(`users/${uid}/messageState/inbox`),{unreadCount:FieldValue.increment(1),schemaVersion:91},{merge:true});
      if(push && !queued.exists)tx.create(outbox,{notificationId:eventKey,uid,category:'messages',kind:'chat_message',conversationId,messageId:id,state:'pending',dueAt:clock(),createdAt:clock()});
      return true;
    });
  }
  async function markConversationRead(uid, input) {
    await requireAccount(uid);
    const {conversationId,messageId}=input || {};
    if(!internalId(conversationId)||!internalId(messageId)||Object.keys(input).some(k=>!['conversationId','messageId'].includes(k)))fail('invalid-argument','Lecture invalide.');
    const cursor=doc(`users/${uid}/messageReads/${conversationId}`);
    const through=await db.runTransaction(async tx=>{
      const [chat,target,read]=await Promise.all([tx.get(doc(`conversations/${conversationId}`)),tx.get(doc(`conversations/${conversationId}/messages/${messageId}`)),tx.get(cursor)]);
      const c=chat.data(),m=target.data();
      if(!c || ![c.clientUid,c.professionalUid].includes(uid))fail('permission-denied','Cette discussion est privée.');
      if(!m || !Number.isSafeInteger(m.createdAt))fail('not-found','Message indisponible.');
      const at=Math.max(m.createdAt,read.data()?.readThroughAt || 0);
      tx.set(cursor,{readThroughAt:at,updatedAt:clock()},{merge:true});
      return at;
    });
    // A bounded page; clients repeat while more remains. The durable cursor also
    // prevents a late/out-of-order create trigger from incrementing read messages.
    return db.runTransaction(async tx=>{
      const query=db.collection(`users/${uid}/messageInbox`).where('conversationId','==',conversationId).where('unread','==',true).where('createdAt','<=',through).orderBy('createdAt').limit(200);
      const [rows,state]=await Promise.all([tx.get(query),tx.get(doc(`users/${uid}/messageState/inbox`))]);
      for(const row of rows.docs)tx.update(row.ref,{unread:false});
      if(rows.size)tx.set(doc(`users/${uid}/messageState/inbox`),{unreadCount:Math.max(0,(state.data()?.unreadCount || 0)-rows.size),schemaVersion:91},{merge:true});
      return {readThroughAt:through,more:rows.size===200};
    });
  }
  async function excludeLegacyMessage(uid,id) {
    return db.runTransaction(async tx=>{
      const ref=doc(`users/${uid}/notifications/${id}`), receipt=doc(`notificationReceipts/${key(uid,id)}`), counter=doc(`users/${uid}/notificationState/inbox`);
      const [notification,prior,state]=await Promise.all([tx.get(ref),tx.get(receipt),tx.get(counter)]);
      const n=notification.data();
      if(!n || !isPrivateMessage(n))return false;
      tx.update(ref,{isGeneral:false});
      // This is the same decrement receipt used by V9 read triggers. Claiming it
      // also protects against late V9 trigger retries and concurrent migrations.
      if(n.schemaVersion===9 && !prior.exists){
        tx.create(receipt,{uid,notificationId:id,createdAt:clock(),reason:'private-message-excluded'});
        tx.set(counter,{unreadCount:Math.max(0,(state.data()?.unreadCount || 0)-1)},{merge:true});
      }
      return true;
    });
  }
  // No conversation update trigger: read_only means rejection/deletion in V8.1, never shared ending.
  async function read(uid, id, before, after) {
    if (before.readAt != null || after.readAt == null || after.schemaVersion !== 9) return;
    if(isPrivateMessage(after))return excludeLegacyMessage(uid,id);
    const receipt = doc(`notificationReceipts/${key(uid,id)}`);
    await db.runTransaction(async tx => {
      if ((await tx.get(receipt)).exists) return;
      tx.create(receipt,{uid,notificationId:id,createdAt:clock()});
      tx.set(doc(`users/${uid}/notificationState/inbox`),{unreadCount:FieldValue.increment(-1)},{merge:true});
    });
  }
  async function enqueueRequest(kind, uid, requestId, request, version) {
    if (!['matched','closed'].includes(kind) || !internalId(uid)) return;
    const id = key(kind,uid,requestId,String(version));
    const ref = doc(`notificationJobs/${id}`);
    await db.runTransaction(async tx => {
      if ((await tx.get(ref)).exists) return;
      tx.create(ref,{kind,uid,requestId,request,version,cursor:null,state:'pending',dueAt:clock(),createdAt:clock()});
    });
  }
  async function processJob(id) {
    const ref = doc(`notificationJobs/${id}`);
    // Page claims prevent overlapping schedulers. Retrying a page is safe: every recipient has a stable ID.
    const job = await db.runTransaction(async tx => {
      const j = (await tx.get(ref)).data();
      if (!j || j.state === 'done' || (j.leaseUntil || 0) > clock()) return null;
      tx.update(ref,{leaseUntil:clock()+120000}); return j;
    });
    if (!job) return;
    try {
      let query = job.kind === 'matched'
        ? db.collection('professionalProfiles').where('status','==','approved').orderBy(FieldPath.documentId())
        : db.collection('proposals').where('requestId','==',job.requestId).orderBy(FieldPath.documentId());
      if (job.cursor) query = query.startAfter(job.cursor);
      const rows = await query.limit(PAGE).get();
      const reference = job.kind === 'matched' ? (await doc('referenceData/professionalOnboarding').get()).data() : null;
      const current = job.kind === 'matched' ? (await doc(`requests/${job.requestId}`).get()).data() : null;
      for (const row of rows.docs) {
        const value = row.data(), uid = job.kind === 'matched' ? row.id : value.professionalUid;
        if (uid === job.uid || (job.kind === 'closed' && value.clientUid !== job.uid)) continue;
        if (job.kind === 'matched' && (current?.status !== 'published' || !matchesOpportunity(job.request,value,reference) ||
            (await doc(`userRequests/${uid}/items/${job.requestId}`).get()).exists)) continue;
        await emit({eventId:`request.${job.kind}/${job.requestId}/${job.version}`,type:`request.${job.kind}`,recipientUid:uid,actorUid:job.uid,
          resourceType:job.kind === 'matched' ? 'opportunity' : 'participatedRequest',resourceId:job.requestId,requestId:job.requestId,
          occurredAt:job.request.updatedAt || job.request.createdAt});
      }
      await ref.update({cursor:rows.docs.at(-1)?.id || job.cursor,state:rows.size < PAGE ? 'done':'pending',leaseUntil:0,dueAt:clock()});
      logger.info('notification_job_page',{kind:job.kind,count:rows.size});
    } catch(e) { await ref.update({leaseUntil:0,dueAt:clock()+60000}); throw e; }
  }
  async function register(uid, input) {
    await requireAccount(uid);
    const {deviceId,token,platform} = input || {};
    if (!internalId(deviceId) || typeof token !== 'string' || token.length < 20 || token.length > 4096 || !['android','ios'].includes(platform)) fail('invalid-argument','Appareil invalide.');
    const ref=doc(`users/${uid}/devices/${deviceId}`), registry=doc(`notificationTokens/${key(token)}`);
    await db.runTransaction(async tx => {
      const [oldDevice,oldOwner,devices] = await Promise.all([tx.get(ref),tx.get(registry),tx.get(db.collection(`users/${uid}/devices`).limit(MAX_DEVICES))]);
      if (!oldDevice.exists && devices.size >= MAX_DEVICES) fail('resource-exhausted','Trop d’appareils enregistrés.');
      const old = oldDevice.data(), owner = oldOwner.data();
      const previousRegistry = old?.token && old.token !== token ? doc(`notificationTokens/${key(old.token)}`) : null;
      const previous = previousRegistry ? (await tx.get(previousRegistry)).data() : null;
      if (previousRegistry && previous?.uid === uid && previous.deviceId === deviceId) tx.delete(previousRegistry);
      if (owner && (owner.uid !== uid || owner.deviceId !== deviceId)) tx.delete(doc(`users/${owner.uid}/devices/${owner.deviceId}`));
      tx.set(registry,{uid,deviceId});
      tx.set(ref,{token,platform,pushEnabled:true,updatedAt:clock()});
    });
    return {registered:true};
  }
  async function unregister(uid, deviceId) {
    requireUid(uid);
    if (!internalId(deviceId)) fail('invalid-argument','Appareil invalide.');
    await db.runTransaction(async tx => {
      const ref=doc(`users/${uid}/devices/${deviceId}`), device=(await tx.get(ref)).data();
      if (!device) return;
      const registry=doc(`notificationTokens/${key(device.token)}`), owner=(await tx.get(registry)).data();
      if (owner?.uid === uid && owner.deviceId === deviceId) tx.delete(registry);
      tx.delete(ref);
    });
    return {removed:true};
  }
  async function resolve(uid, id) {
    await requireAccount(uid);
    if (!internalId(id)) fail('invalid-argument','Notification invalide.');
    let n=(await doc(`users/${uid}/notifications/${id}`).get()).data();
    if(!n){
      const job=(await doc(`notificationOutbox/${id}`).get()).data();
      if(job?.kind==='chat_message' && job.uid===uid){
        await messageContext(job);
        return {resourceType:'conversation',resourceId:job.conversationId};
      }
    }
    const unavailable=()=>fail('not-found','Ce contenu n’est plus disponible.');
    if (!n || n.recipientUid !== uid || n.schemaVersion !== 9 || !internalId(n.resourceId)) return unavailable();
    const resourceId=n.resourceId;
    switch(n.resourceType) {
      case 'professional':
        if(resourceId!==uid || !(await doc(`professionalProfiles/${uid}`).get()).exists)return unavailable();
        break;
      case 'conversation': {
        const c=(await doc(`conversations/${resourceId}`).get()).data();
        if(!c || ![c.clientUid,c.professionalUid].includes(uid))return unavailable();
        break;
      }
      case 'proposal': {
        const p=(await doc(`proposals/${resourceId}`).get()).data();
        if(!p || ![p.clientUid,p.professionalUid].includes(uid))return unavailable();
        break;
      }
      case 'requestProposals':
        if(!(await doc(`userRequests/${uid}/items/${resourceId}`).get()).exists)return unavailable();
        break;
      case 'participatedRequest': {
        // A closed public request cannot be read. Use the recipient's private proposal/history.
        const p=await db.collection('proposals').where('requestId','==',resourceId).where('professionalUid','==',uid).limit(1).get();
        if(p.empty)return unavailable();
        return {resourceType:'proposal',resourceId:p.docs[0].id};
      }
      case 'opportunity': {
        const [r,p,c,own]=await Promise.all([doc(`requests/${resourceId}`).get(),doc(`professionalProfiles/${uid}`).get(),doc('referenceData/professionalOnboarding').get(),doc(`userRequests/${uid}/items/${resourceId}`).get()]);
        if(own.exists || !matchesOpportunity(r.data(),p.data(),c.data()))return unavailable();
        break;
      }
      default:return unavailable();
    }
    return {resourceType:n.resourceType,resourceId};
  }
  async function messageContext(job) {
    if(!internalId(job.conversationId)||!internalId(job.messageId))fail('not-found','Message indisponible.');
    const [chat,message]=await Promise.all([doc(`conversations/${job.conversationId}`).get(),doc(`conversations/${job.conversationId}/messages/${job.messageId}`).get()]);
    const c=chat.data(),m=message.data();
    if(!c||!m||![c.clientUid,c.professionalUid].includes(job.uid)||![c.clientUid,c.professionalUid].includes(m.senderUid)||m.senderUid===job.uid)fail('not-found','Cette discussion est privée.');
    return {chat:c,message:m};
  }
  async function pushContent(job,prefs) {
    if(job.kind!=='chat_message')return {title:job.title,body:job.bodySafe};
    const {chat,message}=await messageContext(job);
    const [user,pro]=await Promise.all([doc(`users/${message.senderUid}`).get(),message.senderUid===chat.professionalUid?doc(`professionalProfiles/${message.senderUid}`).get():Promise.resolve(null)]);
    return messagePushContent(message,pro?.data()?.businessName || user.data()?.fullName,prefs?.messagePreview===true);
  }
  async function deliver(id) {
    const ref=doc(`notificationOutbox/${id}`);
    const job=await db.runTransaction(async tx=>{
      const j=(await tx.get(ref)).data();
      if (!j || j.state !== 'pending' || j.dueAt > clock() || (j.leaseUntil || 0) > clock()) return null;
      tx.update(ref,{leaseUntil:clock()+120000});return j;
    });
    if(!job)return;
    if(job.createdAt<clock()-24*60*60*1000){await ref.update({state:'skipped',reason:'expired'});return;}
    if (!await active(job.uid)) {await ref.update({state:'skipped',reason:'account'});return;}
    if(job.kind==='chat_message'){
      const receipt=(await doc(`users/${job.uid}/messageInbox/${id}`).get()).data();
      if(receipt && !receipt.unread){await ref.update({state:'skipped',reason:'read'});return;}
    }
    try {await resolve(job.uid,job.notificationId);}
    catch(e){
      if(e instanceof OtpError && ['not-found','permission-denied'].includes(e.code)){
        await ref.update({state:'skipped',reason:'target'});return;
      }
      throw e;
    }
    const prefs=(await doc(`users/${job.uid}/notificationPreferences/push`).get()).data();
    if (prefs?.[job.category] === false) {await ref.update({state:'skipped',reason:'preference'});return;}
    const devices=await db.collection(`users/${job.uid}/devices`).limit(MAX_DEVICES).get();
    let retry=false;
    for (const device of devices.docs) {
      const value=device.data(); if (!value.pushEnabled) continue;
      const attempt=doc(`notificationOutbox/${id}/deliveries/${device.id}`);
      const claimed=await db.runTransaction(async tx => {
        const [a,owner,latestDevice,latestPrefs] = await Promise.all([tx.get(attempt),tx.get(doc(`notificationTokens/${key(value.token)}`)),tx.get(device.ref),tx.get(doc(`users/${job.uid}/notificationPreferences/push`))]);
        const prior=a.data();
        if (prior && (prior.state !== 'retry' || prior.attempts >= 3)) {
          if(prior.state==='sending' && prior.claimedAt<=clock()-120000)tx.update(attempt,{state:'unknown',code:'interrupted',finishedAt:clock()});
          return false;
        }
        if (owner.data()?.uid !== job.uid || owner.data()?.deviceId !== device.id || latestDevice.data()?.token !== value.token || latestPrefs.data()?.[job.category] === false) return false;
        let quota;
        if (job.category === 'opportunities') {
          quota=doc(`users/${job.uid}/notificationState/opportunityPush_${device.id}`);
          const q=(await tx.get(quota)).data();
          if (q && q.notificationId !== id && q.lastSentAt > clock()-WINDOW) {
            tx.set(attempt,{state:'grouped',attempts:0});return false;
          }
        }
        if (quota) tx.set(quota,{lastSentAt:clock(),notificationId:id});
        tx.set(attempt,{state:'sending',attempts:(prior?.attempts || 0)+1,claimedAt:clock()});return true;
      });
      if (!claimed) continue;
      try {
        // Read the current preference again just before constructing display data.
        const currentPrefs=(await doc(`users/${job.uid}/notificationPreferences/push`).get()).data();
        if(currentPrefs?.[job.category]===false){await attempt.update({state:'skipped',reason:'preference'});continue;}
        const notification=await pushContent(job,currentPrefs);
        await messaging.send({token:value.token,notification,
          data:{notificationId:job.notificationId,recipientUid:job.uid,...(job.kind==='chat_message'?{type:'chat_message',conversationId:job.conversationId,messageId:job.messageId}:{})},
          android:{priority:'normal',collapseKey:job.category === 'opportunities' ? 'foundi-opportunities' : id,notification:{tag:id}},
          apns:{headers:{'apns-collapse-id':job.category === 'opportunities' ? 'foundi-opportunities' : id,'apns-priority':'5'},payload:{aps:{sound:'default'}}}});
        await attempt.update({state:'sent',finishedAt:clock()});
      } catch(e) {
        const code=String(e.code || 'unknown');
        const invalid=['messaging/registration-token-not-registered','messaging/invalid-registration-token'].includes(code);
        // Only explicit rejection can be retried. A timeout/crash has an ambiguous send result: never blindly resend.
        const transient=['messaging/server-unavailable','messaging/quota-exceeded'].includes(code);
        const attempts=(await attempt.get()).data().attempts;
        retry ||= transient && attempts < 3;
        await attempt.update({state:transient && attempts < 3 ? 'retry':invalid?'invalid':'unknown',code,finishedAt:clock()});
        if (invalid) await db.runTransaction(async tx => {
          const latest=(await tx.get(device.ref)).data();
          const registry=doc(`notificationTokens/${key(value.token)}`), owner=(await tx.get(registry)).data();
          if (latest?.token === value.token) tx.delete(device.ref);
          if (owner?.uid === job.uid && owner?.deviceId === device.id) tx.delete(registry);
        });
        logger.warn('notification_push_failure',{code});
      }
    }
    await ref.update({state:retry?'pending':'done',dueAt:clock()+60000,finishedAt:clock(),leaseUntil:0});
  }
  async function drain({push=true}={}) {
    const jobs=await db.collection('notificationJobs').where('state','==','pending').where('dueAt','<=',clock()).orderBy('dueAt').limit(10).get();
    for (const job of jobs.docs) await processJob(job.id);
    if(push){
      const pushes=await db.collection('notificationOutbox').where('state','==','pending').where('dueAt','<=',clock()).orderBy('dueAt').limit(100).get();
      for (const item of pushes.docs) await deliver(item.id);
      logger.info('notification_drain',{jobs:jobs.size,pushes:pushes.size});
    }
  }
  return {emit,professional,proposal,decision,conversation,message,read,markConversationRead,excludeLegacyMessage,enqueueRequest,processJob,register,unregister,resolve,deliver,drain};
}
module.exports={createNotificationService,PAGE};
