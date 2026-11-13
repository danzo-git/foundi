const { createHash } = require('node:crypto');
const { OtpError, requireUid } = require('./auth-validation');
const { contactAllowed, assertActive, publicProfileAllowed } = require('./safety-guard');
const { decisionNotification } = require('./safety-notification');
const { cleanPreview } = require('./notification-policy');
const reasons = ['fraud','harassment','inappropriate','spam','impersonation','other'];
const types = ['request','professional','conversation','message'];
const states = ['new','in_progress','resolved','dismissed'];
const actions = ['take','reopen','dismiss','warn','hide','restore_content','suspend','restore_account'];
const idOK = id => typeof id === 'string' && /^[a-zA-Z0-9_-]{1,128}$/.test(id);
const hash = value => createHash('sha256').update(JSON.stringify(value)).digest('hex');
const fail = (code, message) => { throw new OtpError(code, message); };
function shape(value, keys) {
  if (!value || typeof value !== 'object' || Array.isArray(value) || Object.keys(value).some(k => !keys.includes(k))) fail('invalid-argument','Paramètres de sécurité invalides.');
}
function clean(value, max, required = false) {
  if (typeof value !== 'string' || value.length > max || (required && !value.trim())) fail('invalid-argument',`Texte requis, ${max} caractères maximum.`);
  return value.replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/g,'').trim();
}
function availableActions(report,content,restriction,own,uid,targetUser) {
  const list=[],closed=['resolved','dismissed'].includes(report.status);
  const ownContent=content?.hidden && content.reportId===report.id;
  const ownSuspension=restriction?.suspended && restriction.reportId===report.id;
  if(report.status==='new')list.push('take');
  if(closed)list.push('reopen');
  else{
    if(!ownContent && !ownSuspension)list.push('dismiss');
    list.push('warn');
    if(['request','professional'].includes(report.targetType) && !ownContent && (report.targetType!=='request' || (own && own.visibility!=='direct')))list.push('hide');
    if(targetUser && !ownSuspension && report.reportedUid!==uid && targetUser.customClaims?.admin!==true)list.push('suspend');
  }
  if(ownContent)list.push('restore_content');
  if(ownSuspension && report.reportedUid!==uid && targetUser?.customClaims?.admin!==true)list.push('restore_account');
  return list;
}
function target(input) {
  if (!types.includes(input.targetType) || !idOK(input.targetId) ||
      (input.targetType === 'message' && !idOK(input.conversationId)) ||
      (input.targetType !== 'message' && input.conversationId != null)) fail('invalid-argument','Cible invalide.');
}
function createSafetyService({store, auth, ownerForRequest, evidence, clock = Date.now}) {
  async function account(uid) {
    requireUid(uid);
    const user = await auth.getUser(uid);
    if (user.disabled || !user.emailVerified) fail('permission-denied','Un compte actif et vérifié est nécessaire.');
    return user;
  }
  async function admin(uid, token) {
    const user = await account(uid);
    if (token?.admin !== true || user.customClaims?.admin !== true) fail('permission-denied','Accès administratif requis.');
    await store.transaction(tx => assertActive(tx, uid));
  }
  async function resolve(tx, uid, input, allowOwn = false) {
    target(input);
    let value, reportedUid, evidence, label;
    if (input.targetType === 'professional') {
      value = await tx.get(`professionalProfiles/${input.targetId}`);
      const user = await auth.getUser(input.targetId).catch(e => { if (e.code !== 'auth/user-not-found') throw e; return null; });
      if (value?.status !== 'approved' || !user?.emailVerified || user.disabled || !await publicProfileAllowed(tx,input.targetId)) fail('not-found','Ce profil n’est plus disponible.');
      const profile = await tx.get(`professionalProfiles/${input.targetId}/showcase/profile`);
      reportedUid = input.targetId; label = value.businessName || 'Professionnel';
      evidence = {name:label,bio:profile?.bio || '',trade:profile?.trade || '',photoIds:[profile?.portrait?.id,profile?.cover?.id,...(profile?.gallery || []).map(p=>p.id)].filter(Boolean)};
    } else if (input.targetType === 'request') {
      value = await tx.get(`requests/${input.targetId}`);
      if (!value) {
        value=await tx.get(`directRequests/${input.targetId}`);
        if(!value || ![value.clientUid,value.directProfessionalId].includes(uid))fail('permission-denied','Cette demande est privée.');
        if(uid!==value.clientUid && (await tx.get(`professionalProfiles/${uid}`))?.status!=='approved')fail('permission-denied','Cette demande privée n’est plus accessible.');
      }
      const ownership = await tx.get(`requestOwnership/${input.targetId}`);
      reportedUid = ownership?.ownerUid || (ownerForRequest && await ownerForRequest(input.targetId));
      const own = reportedUid && await tx.get(`userRequests/${reportedUid}/items/${input.targetId}`);
      if (value?.status !== 'published' || !own || own.createdAt !== value.createdAt) fail('not-found','Cette demande n’est plus disponible.');
      label = value.title;
      evidence = {title:value.title,description:value.description,photoIds:value.photoIds || [],createdAt:value.createdAt};
    } else {
      const conversationId = input.targetType === 'message' ? input.conversationId : input.targetId;
      const chat = await tx.get(`conversations/${conversationId}`);
      if (!chat || ![chat.clientUid,chat.professionalUid].includes(uid)) fail('permission-denied','Cette discussion est privée.');
      reportedUid = uid === chat.clientUid ? chat.professionalUid : chat.clientUid;
      label = uid === chat.clientUid ? chat.professionalName : chat.clientName;
      evidence = {conversationId,requestId:chat.requestId,requestTitle:chat.requestTitle};
      if (input.targetType === 'message') {
        value = await tx.get(`conversations/${conversationId}/messages/${input.targetId}`);
        if (!value || ![chat.clientUid,chat.professionalUid].includes(value.senderUid)) fail('not-found','Message indisponible.');
        reportedUid = value.senderUid;
        evidence.message = Object.fromEntries(['senderUid','type','text','createdAt','originalName','contentType','storagePath','generation','attachmentId'].filter(k=>value[k]!==undefined).map(k=>[k,value[k]]));
        // Contact numbers are not copied into moderation evidence.
      }
    }
    if (!idOK(reportedUid) || (!allowOwn && uid === reportedUid)) fail('invalid-argument','Tu ne peux pas signaler ou bloquer ton propre compte.');
    return {reportedUid,label:label || 'Membre Foundi',evidence};
  }
  async function submit(uid, input) {
    await account(uid); shape(input,['targetType','targetId','conversationId','reason','comment']); target(input);
    if (!reasons.includes(input.reason)) fail('invalid-argument','Choisis un motif.');
    const comment = clean(input.comment ?? '',500), now = clock(), day = Math.floor(now/86400000);
    const id = hash([uid,input.targetType,input.targetId,input.conversationId || null,input.reason,day]);
    return store.transaction(async tx => {
      await assertActive(tx,uid);
      const prior = await tx.get(`safetyReports/${id}`);
      if (prior) return {reportId:id,duplicate:true};
      const resolved = await resolve(tx,uid,input);
      const ratePath = `safetyReportLimits/${uid}`, saved = await tx.get(ratePath);
      const count = saved?.day === day ? saved.count : 0;
      const urgent = ['fraud','harassment'].includes(input.reason);
      if (count >= (urgent ? 30 : 20)) fail('resource-exhausted','Limite quotidienne de signalements atteinte. Pour une urgence, utilise les services d’urgence ou l’aide Foundi.');
      if(evidence)resolved.evidence=await evidence.capture(tx,input,resolved);
      tx.set(ratePath,{day,count:count+1});
      tx.set(`safetyReports/${id}`,{reporterUid:uid,targetType:input.targetType,targetId:input.targetId,conversationId:input.conversationId || null,...resolved,reason:input.reason,comment,status:'new',revision:1,createdAt:now,updatedAt:now,priority:urgent?'high':'normal',evidenceExpiresAt:now+90*86400000,deleteAt:new Date(now+365*86400000)});
      return {reportId:id,duplicate:false};
    });
  }
  async function context(uid,input) {
    await account(uid); shape(input,['targetType','targetId','conversationId']);
    return store.transaction(async tx => {
      await assertActive(tx,uid); const resolved = await resolve(tx,uid,input,true);
      const mine = await tx.get(`userBlocks/${uid}/items/${resolved.reportedUid}`);
      return {own:resolved.reportedUid===uid,blocked:!!mine,contactAllowed:await contactAllowed(tx,uid,resolved.reportedUid)};
    });
  }
  async function block(uid,input) {
    await account(uid); shape(input,['targetType','targetId','conversationId']);
    return store.transaction(async tx => {
      await assertActive(tx,uid); const r = await resolve(tx,uid,input);
      const path = `userBlocks/${uid}/items/${r.reportedUid}`, existing = await tx.get(path);
      if (!existing) tx.set(path,{label:r.label,createdAt:clock()});
      return {blocked:true};
    });
  }
  async function unblock(uid,input) {
    await account(uid); shape(input,['blockedUid']);
    if (!idOK(input.blockedUid) || input.blockedUid === uid) fail('invalid-argument','Compte bloqué invalide.');
    return store.transaction(async tx => {
      await assertActive(tx,uid);
      // The only free UID operation deletes an existing relation owned by the caller.
      const path = `userBlocks/${uid}/items/${input.blockedUid}`;
      if (await tx.get(path)) tx.delete(path);
      return {blocked:false};
    });
  }
  async function unblockTarget(uid,input) {
    await account(uid); shape(input,['targetType','targetId','conversationId']);
    return store.transaction(async tx => {
      await assertActive(tx,uid); const r = await resolve(tx,uid,input);
      const path = `userBlocks/${uid}/items/${r.reportedUid}`;
      if (await tx.get(path)) tx.delete(path);
      return {blocked:false};
    });
  }
  async function listBlocks(uid,input={}) {
    await account(uid); shape(input,['cursor']);
    await store.transaction(tx=>assertActive(tx,uid));
    if (input.cursor != null && !idOK(input.cursor)) fail('invalid-argument','Pagination invalide.');
    return store.listBlocks(uid,input.cursor || null);
  }
  async function list(uid,token,input={}) {
    await admin(uid,token); shape(input,['status','reason','targetType','cursor']);
    if (!states.includes(input.status) || (input.reason && !reasons.includes(input.reason)) || (input.targetType && !types.includes(input.targetType))) fail('invalid-argument','Filtres invalides.');
    if(input.cursor != null && (typeof input.cursor !== 'object' || !Number.isSafeInteger(input.cursor.createdAt) || !/^[a-f0-9]{64}$/.test(input.cursor.id))) fail('invalid-argument','Pagination invalide.');
    return store.listReports(input);
  }
  async function detail(uid,token,input) {
    await admin(uid,token); shape(input,['reportId']);
    if (!/^[a-f0-9]{64}$/.test(input.reportId)) fail('invalid-argument','Signalement invalide.');
    const report = await store.transaction(async tx=>{
      await assertActive(tx,uid); const report=await tx.get(`safetyReports/${input.reportId}`);
      if(!report)fail('not-found','Signalement indisponible.');
      const restriction=await tx.get(`accountSafety/${report.reportedUid}`);
      const content=await tx.get(`safetyContent/${report.targetType}_${report.targetId}`);
      const own=report.targetType==='request' ? await tx.get(`userRequests/${report.reportedUid}/items/${report.targetId}`) : null;
      const targetUser=await auth.getUser(report.reportedUid).catch(e=>{if(e.code==='auth/user-not-found')return null;throw e;});
      return {...report,accountSuspended:restriction?.suspended===true,contentHidden:content?.hidden===true,
        availableActions:availableActions({...report,id:input.reportId},content,restriction,own,uid,targetUser)};
    });
    return {id:input.reportId,...report,audit:await store.audit(input.reportId)};
  }
  async function decide(uid,token,input) {
    await admin(uid,token); shape(input,['reportId','action','reason','publicMessage','expectedRevision','decisionId']);
    if (!/^[a-f0-9]{64}$/.test(input.reportId) || !idOK(input.decisionId) || !actions.includes(input.action) || !Number.isSafeInteger(input.expectedRevision)) fail('invalid-argument','Décision invalide.');
    const reason=clean(input.reason,500,true), now=clock();
    const notifying=['warn','hide','suspend','restore_content','restore_account'].includes(input.action);
    const publicMessage=input.publicMessage===undefined ? undefined : clean(cleanPreview(clean(input.publicMessage,500,true),500),500,true);
    if(publicMessage!==undefined && !notifying)fail('invalid-argument','Cette action ne prévoit pas de message à l’utilisateur.');
    return store.transaction(async tx=>{
      await assertActive(tx,uid);
      const decisionKey=hash([uid,input.decisionId]);
      const path=`safetyReports/${input.reportId}`, auditPath=`safetyAudit/${decisionKey}`;
      const [report,prior]=await Promise.all([tx.get(path),tx.get(auditPath)]);
      const fingerprint=hash(input);
      if(prior){if(prior.fingerprint!==fingerprint)fail('already-exists','Identifiant utilisé pour une autre décision.');return {revision:prior.revision,duplicate:true};}
      if(!report)fail('not-found','Signalement indisponible.');
      if(report.revision!==input.expectedRevision)fail('aborted','Ce dossier a changé. Actualise avant de décider.');
      const targetUser=await auth.getUser(report.reportedUid);
      if(['suspend','restore_account'].includes(input.action) && (report.reportedUid===uid || targetUser.customClaims?.admin===true))fail('permission-denied','La restriction d’un administrateur nécessite une procédure distincte.');
      const contentPath=`safetyContent/${report.targetType}_${report.targetId}`;
      const content=await tx.get(contentPath),restriction=await tx.get(`accountSafety/${report.reportedUid}`);
      const own=report.targetType==='request' ? await tx.get(`userRequests/${report.reportedUid}/items/${report.targetId}`) : null;
      const allowed=availableActions({...report,id:input.reportId},content,restriction,own,uid,targetUser);
      if(!allowed.includes(input.action))fail('failed-precondition',['resolved','dismissed'].includes(report.status)
        ? 'Réexamine ce dossier avant de prendre une nouvelle décision. Les mesures actives doivent être levées explicitement depuis leur dossier.'
        : 'Cette action n’est pas disponible dans l’état actuel du dossier. Actualise les mesures actives.');
      if(['hide','restore_content'].includes(input.action)){
        if(!['request','professional'].includes(report.targetType))fail('invalid-argument','Seul un contenu public peut être masqué ici.');
        if(report.targetType==='request'){
          if(!own || own.visibility==='direct')fail('failed-precondition','Demande publique indisponible.');
        }
      }
      const revision=report.revision+1;
      if(input.action==='restore_content' && (!content?.hidden || content.reportId!==input.reportId))fail('failed-precondition','La mesure active doit être restaurée depuis son propre dossier.');
      if(input.action==='restore_account' && (!restriction?.suspended || restriction.reportId!==input.reportId))fail('failed-precondition','La suspension active doit être restaurée depuis son propre dossier.');
      const notice=decisionNotification(input.action,decisionKey,report.reportedUid,now,{report,own,publicMessage});
      const inboxPath=`users/${report.reportedUid}/notificationState/inbox`;
      const inbox=notice ? await tx.get(inboxPath) : null;
      // All reads precede writes, including safeguards against old client republishing.
      if(['hide','restore_content'].includes(input.action)){
        const hidden=input.action==='hide';
        tx.set(contentPath,{hidden,updatedAt:now,reportId:input.reportId});
        if(report.targetType==='request'){
          if(hidden){tx.delete(`requests/${report.targetId}`);}
          else if(own.status==='published'){
            const fields=['title','description','categoryId','categoryLabel','specialtyId','specialtyLabel','zoneId','zoneLabel','budget','status','createdAt','updatedAt','authorPublicName','photoIds','photosPublic'];
            tx.set(`requests/${report.targetId}`,Object.fromEntries(fields.filter(k=>own[k]!==undefined).map(k=>[k,own[k]])));
          }
        }
      }
      if(['suspend','restore_account'].includes(input.action))tx.set(`accountSafety/${report.reportedUid}`,{suspended:input.action==='suspend',updatedAt:now,reportId:input.reportId});
      if(notice){
        // The decision and its notification/outbox commit together. A retry of
        // the same decision returns above without another notice or counter bump.
        tx.set(`users/${report.reportedUid}/safetyNotices/${decisionKey}`,notice.notice);
        tx.set(`users/${report.reportedUid}/notifications/${notice.id}`,notice.notification);
        tx.set(inboxPath,{...inbox,unreadCount:(inbox?.unreadCount || 0)+1});
        tx.set(`notificationOutbox/${notice.id}`,notice.outbox);
      }
      const status=['take','reopen'].includes(input.action)?'in_progress':input.action==='dismiss'?'dismissed':'resolved';
      const heldContent=input.action==='hide' || (input.action!=='restore_content' && content?.hidden && content.reportId===input.reportId);
      const heldAccount=input.action==='suspend' || (input.action!=='restore_account' && restriction?.suspended && restriction.reportId===input.reportId);
      const deleteAt=heldContent || heldAccount ? null : new Date(now+365*86400000);
      tx.set(path,{...report,status,revision,updatedAt:now,assignedAdminUid:uid,lastAction:input.action,deleteAt});
      tx.set(auditPath,{reportId:input.reportId,adminUid:uid,action:input.action,reason,...(publicMessage!==undefined?{publicMessage}:{}),createdAt:now,revision,fingerprint,deleteAt});
      return {revision,duplicate:false};
    });
  }
  async function notices(uid) {
    // A suspended member may still read their own decisions and appeal details.
    await account(uid);
    const notices=await store.notices(uid);
    // Keep the string response for installed clients; acknowledged notices leave
    // their profile too. New clients retain access to the recipient-only history.
    return {items:notices.filter(n=>n.acknowledgedAt==null).map(n=>n.text),notices};
  }
  async function acknowledgeNotice(uid,input) {
    await account(uid);shape(input,['noticeId']);
    if(!/^[a-f0-9]{64}$/.test(input.noticeId))fail('invalid-argument','Avis invalide.');
    return store.transaction(async tx=>{
      const path=`users/${uid}/safetyNotices/${input.noticeId}`,notice=await tx.get(path);
      if(!notice)fail('not-found','Cet avis n’est pas disponible.');
      if(notice.acknowledgedAt!=null)return {acknowledged:true,duplicate:true};
      const notificationPath=/^[a-f0-9]{64}$/.test(notice.notificationId || '') ? `users/${uid}/notifications/${notice.notificationId}` : null;
      const notification=notificationPath ? await tx.get(notificationPath) : null;
      const now=clock();
      tx.set(path,{...notice,acknowledgedAt:now});
      // The existing read trigger owns the exactly-once unread decrement.
      if(notification?.recipientUid===uid && notification.schemaVersion===9 && notification.readAt==null)
        tx.set(notificationPath,{...notification,readAt:new Date(now)});
      return {acknowledged:true,duplicate:false};
    });
  }
  async function readAttachment(uid,token,input){
    const report=await detail(uid,token,input);
    if(!evidence || report.evidenceExpiresAt<=clock() || report.evidence?.expired)fail('not-found','Cette preuve a expiré ou est indisponible.');
    const file=await evidence.attachment(report);
    // Revalidate restriction, claim and retention after the download too.
    const current=await detail(uid,token,input);
    if(current.evidenceExpiresAt<=clock() || current.evidence?.expired)fail('not-found','Cette preuve a expiré.');
    return file;
  }
  async function purgeEvidence() {
    let removed=0;
    for(const id of await store.expiredEvidence(clock()))await store.transaction(async tx=>{
      const path=`safetyReports/${id}`,r=await tx.get(path);
      if(!r || !r.evidenceExpiresAt || r.evidenceExpiresAt>clock())return;
      const next={...r,evidence:{expired:true},comment:'',evidencePurgedAt:clock()};
      delete next.evidenceExpiresAt;tx.set(path,next);removed++;
    });
    // Active measures retain their decision journal. Once the case is archived,
    // the original held entry is removed only after the archive retention ends.
    for(const item of await store.heldAudits?.() || [])await store.transaction(async tx=>{
      const report=await tx.get(`safetyReports/${item.reportId}`);
      const expires=report?.deleteAt?.toMillis?.() ?? report?.deleteAt?.getTime?.();
      if((expires && expires<=clock()) || (!report && item.createdAt+365*86400000<=clock()))tx.delete(`safetyAudit/${item.id}`);
    });
    return {removed};
  }
  return {submit,context,block,unblock,unblockTarget,listBlocks,list,detail,decide,notices,acknowledgeNotice,purgeEvidence,readAttachment};
}
module.exports={createSafetyService,reasons,states};
