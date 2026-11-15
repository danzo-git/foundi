const {createHash}=require('node:crypto');
const {FieldPath}=require('firebase-admin/firestore');
const {OtpError}=require('./auth-validation');
const size=25,day=86400000;
const key=(...parts)=>createHash('sha256').update(JSON.stringify(parts)).digest('hex');
const conflict=()=>{throw Object.assign(Error('Ownership cannot be established'),{code:'privacy/ownership-conflict'});};
const idOK=value=>typeof value==='string' && /^[a-zA-Z0-9_-]{1,128}$/.test(value);
const goneName='Compte supprimé';
const emptyRequest=now=>({title:'Demande supprimée',description:'',categoryId:'',categoryLabel:'',specialtyId:'',specialtyLabel:'',zoneId:'',zoneLabel:'',status:'deleted',createdAt:now,photoIds:[],photosPublic:false,budget:null,authorPublicName:goneName});
function createPrivacyPurger({db,bucket,clock=Date.now}){
 const ref=path=>db.doc(path);
 const target=(job,kind,id)=>ref(`accountDeletionJobs/${job.id}/${kind}/${key(id)}`);
 async function remember(job,kind,id,data){await db.runTransaction(async tx=>{const r=target(job,kind,id);if(!(await tx.get(r)).exists)tx.set(r,{...data,done:false});});}
 async function tree(r,budget={left:size}){
  for(const collection of await r.listCollections()){
   if(!budget.left)return false;
   for(const row of (await collection.limit(budget.left).get()).docs){if(!await tree(row.ref,budget))return false;}
   if(!(await collection.limit(1).get()).empty)return false;
  }
  if(!budget.left)return false;await r.delete();budget.left--;return true;
 }
 async function drain(collection,field,value,process){
  const rows=await collection.where(field,'==',value).limit(size).get();
  for(const row of rows.docs)await process(row);
  return {done:rows.empty};
 }
 async function ownedObjects(job,prefix,cursor=null,filter=()=>true){
  if(!prefix.startsWith(`personalAvatars/${job.uid}/`) && !prefix.startsWith(`requestPhotos/${job.uid}/`) && !prefix.startsWith(`professionalDocuments/${job.uid}/`) && prefix!=='conversations/' && !/^conversations\/[a-zA-Z0-9_-]{20,80}\/$/.test(prefix))conflict();
  const [files,next]=await bucket.getFiles({prefix,autoPaginate:false,maxResults:size,...(cursor?{pageToken:cursor}:{})});
  for(const file of files){const [meta]=await file.getMetadata();if(await filter(file.name,meta))await removeFile(job,file.name,String(meta.generation));}
  return {done:!next?.pageToken,cursor:next?.pageToken||null};
 }
 async function removeFile(job,path,generation){
  if(typeof path!=='string'||path.includes('..')||!(/^(personalAvatars|requestPhotos|professionalDocuments)\//.test(path)||path.startsWith('conversations/')))conflict();
  let file=bucket.file(path),metadata;
  try{[metadata]=await file.getMetadata();}catch(e){if(Number(e.code)===404)return;throw e;}
  if(metadata.metadata?.owneruid && metadata.metadata.owneruid!==job.uid)conflict();
  if(generation && String(metadata.generation)!==String(generation))conflict();
  const [info]=await bucket.getMetadata();
  const seconds=Number(info.softDeletePolicy?.retentionDurationSeconds||0);
  await bucket.file(path,{generation:String(metadata.generation)}).delete({ifGenerationMatch:String(metadata.generation),ignoreNotFound:true});
  if(seconds>0)await db.runTransaction(async tx=>{const r=ref(`accountDeletionJobs/${job.id}`),j=(await tx.get(r)).data();if(j)tx.set(r,{...j,providerRetentionUntil:Math.max(j.providerRetentionUntil||0,clock()+seconds*1000)});});
 }
 async function removeAttachment(job,cid,row){
  const a=row.data(),mid=row.id;
  if(a.senderUid!==job.uid || !idOK(a.attachmentId) || a.storagePath!==`conversations/${cid}/attachments/${mid}/${a.attachmentId}` || a.quarantinePath!==`conversations/${cid}/quarantine/${a.attachmentId}`)conflict();
  await remember(job,'artifacts',`${cid}:${mid}`,{cid,mid});await remember(job,'artifacts',`${cid}:asset:${a.attachmentId}`,{cid,asset:a.attachmentId});
  await removeFile(job,a.storagePath,a.generation);await removeFile(job,a.quarantinePath);await row.ref.delete();
 }
 async function conversation(job,row){
  const c=row.data(),cid=row.id;
  if(![c.clientUid,c.professionalUid].includes(job.uid))conflict();
  const attachments=await row.ref.collection('attachments').where('senderUid','==',job.uid).limit(size).get();
  if(!attachments.empty){for(const a of attachments.docs)await removeAttachment(job,cid,a);return;}
  const messages=await row.ref.collection('messages').where('senderUid','==',job.uid).limit(size).get();
  if(!messages.empty){for(const m of messages.docs){await remember(job,'artifacts',`${cid}:${m.id}`,{cid,mid:m.id});await m.ref.set({senderUid:job.alias,type:'text',text:'Message supprimé avec le compte',createdAt:m.data().createdAt||clock(),deleted:true});}return;}
  const marker=target(job,'conversationScans',cid),scan=(await marker.get()).data();
  const result=await ownedObjects(job,`conversations/${cid}/`,scan?.cursor,async(name,metadata)=>{
   if(metadata.metadata?.owneruid)return metadata.metadata.owneruid===job.uid;
   const parts=name.split('/');
   const proof=parts[2]==='attachments' ? await target(job,'artifacts',`${cid}:${parts[3]}`).get() : parts[2]==='quarantine' ? await target(job,'artifacts',`${cid}:asset:${parts[3]}`).get() : null;
   if(proof?.exists)return true;
   if(parts[2]==='quarantine'){const other=await row.ref.collection('attachments').where('attachmentId','==',parts[3]).limit(1).get();if(other.docs.some(d=>d.data().senderUid!==job.uid))return false;}
   if(parts[2]==='attachments'){
    const message=(await row.ref.collection('messages').doc(parts[3]).get()).data();
    if(message && message.senderUid!==job.uid)return false;
   }
   // Unknown legacy ownership cannot authorize deleting another member's file.
   throw Object.assign(Error('Legacy object requires ownership review'),{code:'privacy/manual-review',reference:name});
  });
  if(!result.done){await marker.set({cursor:result.cursor});return;}
  const clientDeleted=c.clientUid===job.uid || c.clientDeleted===true,proDeleted=c.professionalUid===job.uid || c.professionalDeleted===true;
  if(clientDeleted && proDeleted){if(await tree(row.ref))await marker.delete();return;}
  await row.ref.set({requestId:c.requestId,proposalId:c.proposalId||c.selectedProposalId,selectedProposalId:c.proposalId||c.selectedProposalId,
   clientUid:c.clientUid===job.uid?job.alias:c.clientUid,professionalUid:c.professionalUid===job.uid?job.alias:c.professionalUid,
   participantUids:[c.clientUid===job.uid?job.alias:c.clientUid,c.professionalUid===job.uid?job.alias:c.professionalUid],
   clientName:clientDeleted?goneName:c.clientName,professionalName:proDeleted?goneName:c.professionalName,
   requestTitle:clientDeleted?'Demande supprimée':c.requestTitle,requestSnapshot:clientDeleted?emptyRequest(c.createdAt||clock()):c.requestSnapshot,
   clientDeleted,professionalDeleted:proDeleted,status:'read_only',archivedReason:'account_deleted',proposalStatus:'account_deleted',schemaVersion:81,
   createdAt:c.createdAt||clock(),updatedAt:clock(),lastMessageAt:c.lastMessageAt||c.createdAt||clock(),lastMessagePreview:''});
  await marker.delete();
 }
 async function hold(job,id,category,data,until){
  if(until<=clock())return;
  const r=ref(`accountDeletionHolds/${key(job.id,category,id)}`);
  await r.set({requestId:job.id,category,data,deleteAt:new Date(until),createdAt:clock(),policyVersion:job.policy.version});
  await db.runTransaction(async tx=>{const jref=ref(`accountDeletionJobs/${job.id}`),j=(await tx.get(jref)).data();if(j)tx.set(jref,{...j,retainedUntil:Math.max(j.retainedUntil||0,until),retainedCategories:[...new Set([...(j.retainedCategories||[]),category])]});});
 }
 async function moderation(job,row){
  const r=row.data(),subject=r.reportedUid,contentPath=`safetyContent/${r.targetType}_${r.targetId}`;
  const evidenceUntil=Math.min(r.evidenceExpiresAt||clock(),(r.createdAt||clock())+job.policy.moderationEvidenceDays*day);
  let evidence=r.evidence||{};
  // A retained proof must survive deletion of its original object. Independent
  // bounded Firestore blobs have their own TTL: deleting a parent never leaves
  // an immortal subcollection or an untracked Storage archive behind.
  if(evidenceUntil>clock() && evidence.message?.type==='pdf'){
   const m=evidence.message,cid=evidence.conversationId;
   if(!idOK(cid)||!idOK(row.id)||!idOK(r.targetId)||!idOK(m.attachmentId)||m.senderUid!==subject||m.storagePath!==`conversations/${cid}/attachments/${r.targetId}/${m.attachmentId}`||!m.generation)conflict();
   try{
    const file=bucket.file(m.storagePath),[meta]=await file.getMetadata();
    if(String(meta.generation)!==String(m.generation)||Number(meta.size)>15*1048576||meta.metadata?.firebaseStorageDownloadTokens||(meta.metadata?.owneruid && meta.metadata.owneruid!==subject))conflict();
    const [bytes]=await bucket.file(m.storagePath,{generation:String(m.generation)}).download();if(bytes.length>15*1048576)conflict();
    const chunks=[];
    for(let offset=0;offset<bytes.length;offset+=384*1024){const id=key(job.id,row.id,offset);chunks.push(id);await ref(`accountDeletionHoldChunks/${id}`).set({requestId:job.id,bytes:bytes.subarray(offset,offset+384*1024),deleteAt:new Date(evidenceUntil),category:'moderation_evidence'});}
    evidence={...evidence,message:{...m,storagePath:null,generation:null,retainedAttachment:{chunks,size:bytes.length,sha256:createHash('sha256').update(bytes).digest('hex'),contentType:m.contentType}}};
   }catch(e){if(Number(e.code)!==404)throw e;evidence={...evidence,attachmentUnavailable:true};}
  }
  await hold(job,`${row.id}:evidence`,'moderation_evidence',{reportId:row.id,evidence,comment:r.comment||''},evidenceUntil);
  const audits=await db.collection('safetyAudit').where('reportId','==',row.id).get();
  await hold(job,`${row.id}:metadata`,'moderation_metadata',{report:{...r,evidence:{expired:true},comment:''},audit:[]},(r.createdAt||clock())+job.policy.moderationMetadataDays*day);
  await db.runTransaction(async tx=>{
   const [current,account,content]=await Promise.all([tx.get(row.ref),tx.get(ref(`accountSafety/${subject}`)),tx.get(ref(contentPath))]);
   if(!current.exists)return;
   const activeAccount=subject!==job.uid && account.data()?.suspended && account.data()?.reportId===row.id;
   const activeContent=subject!==job.uid && content.data()?.hidden && content.data()?.reportId===row.id;
   if(activeAccount||activeContent){
    const id=key('continuation',job.id,row.id),auditId=key('continuation-audit',id);
    // New technical docket contains only the other member's measure, no deleted
    // reporter identity, comment, conversation, evidence or old case reference.
    tx.set(ref(`safetyReports/${id}`),{reportedUid:subject,reporterUid:'deleted-member',targetType:r.targetType,targetId:r.targetId,
     conversationId:null,label:'Mesure conservée après effacement d’un tiers',reason:r.reason,status:'resolved',revision:1,
     createdAt:clock(),updatedAt:clock(),evidence:{expired:true},comment:'',priority:r.priority||'normal',deleteAt:null});
    tx.set(ref(`safetyAudit/${auditId}`),{reportId:id,adminUid:'system',action:'privacy_continuation',reason:'Continuité technique de la mesure, sans levée ni nouvelle sanction.',createdAt:clock(),revision:1,deleteAt:null});
    if(activeAccount)tx.set(ref(`accountSafety/${subject}`),{...account.data(),reportId:id});
    if(activeContent)tx.set(ref(contentPath),{...content.data(),reportId:id});
   }
   tx.delete(row.ref);
  });

 }
 async function requestTargets(job){
  const rows=await ref(`accountDeletionJobs/${job.id}`).collection('requests').where('done','==',false).limit(1).get();
  if(rows.empty)return {done:true};
  const task=rows.docs[0],id=task.data().id;
  for(const [collection,field] of [['requestRecommendations','requestId'],['requestPhotoFiles','requestId']]){
   const related=await db.collection(collection).where(field,'==',id).limit(size).get();
   if(!related.empty){for(const row of related.docs){if(collection==='requestPhotoFiles' && row.data().uid!==job.uid)conflict();await row.ref.delete();}return {done:false};}
  }
  const notices=await db.collectionGroup('notifications').where('requestId','==',id).limit(size).get();
  if(!notices.empty){for(const n of notices.docs)await n.ref.set({...n.data(),title:'Demande indisponible',bodySafe:'Une demande associée à ton activité a été supprimée.',actorUid:null,eventId:`privacy/${n.id}`,resourceType:'unavailable',resourceId:n.id,requestId:null});return {done:false};}
  if(!await tree(ref(`requestEngagement/${id}`)))return {done:false};
  const ownership=await ref(`requestOwnership/${id}`).get();if(ownership.exists && ownership.data().ownerUid!==job.uid)conflict();
  await ref(`requestOwnership/${id}`).delete();await ref(`requestPhotoDrafts/${id}`).delete();await ref(`safetyContent/request_${id}`).delete();await ref(`safetyRequestSnapshots/${id}`).delete();
  await task.ref.set({...task.data(),done:true});return {done:false};
 }
 async function run(job,phase){
  const uid=job.uid,alias=job.alias;
  if(!idOK(uid))conflict();
  if(phase==='withdraw_requests'){
   let q=ref(`userRequests/${uid}`).collection('items').orderBy(FieldPath.documentId());if(job.cursor)q=q.startAfter(job.cursor);
   const rows=await q.limit(size).get();
   for(const row of rows.docs){
    await remember(job,'requests',row.id,{id:row.id});
    await db.runTransaction(async tx=>{const [own,owner,direct,pub]=await Promise.all([tx.get(row.ref),tx.get(ref(`requestOwnership/${row.id}`)),tx.get(ref(`directRequests/${row.id}`)),tx.get(ref(`requests/${row.id}`))]);
     if(owner.exists && owner.data().ownerUid!==uid)conflict();if(direct.exists && direct.data().clientUid!==uid)conflict();
     if(pub.exists && own.data()?.createdAt!==pub.data().createdAt)conflict();
     tx.delete(ref(`requests/${row.id}`));tx.delete(ref(`directRequests/${row.id}`));if(own.exists)tx.set(row.ref,{...own.data(),status:'deleted'});
    });
   }
   return {done:rows.size<size,cursor:rows.docs.at(-1)?.id||null};
  }

  if(phase==='discover_requests'){
   let q=db.collection('requestOwnership').where('ownerUid','==',uid).orderBy(FieldPath.documentId());if(job.cursor)q=q.startAfter(job.cursor);
   const rows=await q.limit(size).get();
   for(const row of rows.docs){await remember(job,'requests',row.id,{id:row.id});await ref(`requests/${row.id}`).delete();const d=await ref(`directRequests/${row.id}`).get();if(d.exists&&d.data().clientUid!==uid)conflict();await d.ref.delete();}
   return {done:rows.size<size,cursor:rows.docs.at(-1)?.id||null};
  }
  if(phase==='moderation_audits'){
   const tasks=await ref(`accountDeletionJobs/${job.id}`).collection('reports').where('done','==',false).limit(1).get();if(tasks.empty)return {done:true};
   const task=tasks.docs[0],rows=await db.collection('safetyAudit').where('reportId','==',task.data().id).limit(size).get();
   for(const row of rows.docs){await hold(job,row.id,'moderation_metadata',row.data(),task.data().createdAt+job.policy.moderationMetadataDays*day);await row.ref.delete();}
   if(rows.empty)await task.ref.set({...task.data(),done:true});return {done:false};
  }
  if(phase==='incoming_blocks'){
   let q=db.collectionGroup('items').orderBy(FieldPath.documentId());if(job.cursor)q=q.startAfter(ref(job.cursor));const rows=await q.limit(size).get();
   for(const row of rows.docs)if(row.id===uid && /^userBlocks\/[^/]+\/items\/[^/]+$/.test(row.ref.path))await row.ref.delete();
   return {done:rows.size<size,cursor:rows.docs.at(-1)?.ref.path||null};
  }
  if(phase==='directory_budgets'){
   for(const name of ['professionalDirectoryLimits','professionalDirectoryCursors']){const rows=await db.collection(name).where('uid','==',uid).limit(size).get();if(!rows.empty){for(const row of rows.docs)await row.ref.delete();return {done:false};}}
   return {done:true};
  }
  if(phase==='photo_files'){const garbage=await drain(db.collection('personalAvatarGarbage'),'uid',uid,row=>row.ref.delete());if(!garbage.done)return garbage;}
  if(phase==='photo_drafts'||phase==='photo_files')return drain(db.collection(phase==='photo_drafts'?'requestPhotoDrafts':'requestPhotoFiles'),'uid',uid,row=>tree(row.ref));
  if(phase==='withdraw_profile'){
   const avatar=(await ref(`personalAvatars/${uid}`).get()).data();if(avatar?.publicId)await ref(`publicPersonalAvatars/${avatar.publicId}`).delete();
const r=ref(`professionalProfiles/${uid}`),p=await r.get();if(p.exists)await r.set({...p.data(),status:'deleting'});return {done:true};}
  if(phase==='proposals_sent')return drain(db.collection('proposals'),'professionalUid',uid,async row=>{await remember(job,'proposals',row.id,{id:row.id});await row.ref.delete();});
  if(phase==='proposals_received')return drain(db.collection('proposals'),'clientUid',uid,row=>row.ref.set({...row.data(),clientUid:alias,requestTitle:'Demande supprimée',status:'account_deleted',clientDeleted:true}));
  if(phase==='conversations_client'||phase==='conversations_pro'){
   const rows=await db.collection('conversations').where(phase==='conversations_client'?'clientUid':'professionalUid','==',uid).limit(1).get();
   if(rows.empty)return {done:true};await conversation(job,rows.docs[0]);return {done:false};
  }
  const recommendations={recommendations_actor:'actorUid',recommendations_owner:'ownerUid',recommendations_pro:'professionalUid'};
  if(recommendations[phase])return drain(db.collection('requestRecommendations'),recommendations[phase],uid,row=>row.ref.delete());
  if(phase==='direct_received')return drain(db.collection('directRequests'),'directProfessionalId',uid,async row=>{
   const r=row.data();await row.ref.set({...r,directProfessionalId:alias,directProfessionalName:goneName,status:'closed'});
   const own=ref(`userRequests/${r.clientUid}/items/${row.id}`),value=(await own.get()).data();if(value)await own.set({...value,directProfessionalId:alias,directProfessionalName:goneName,status:'closed'});
  });
  if(phase==='notifications_actor')return drain(db.collectionGroup('notifications'),'actorUid',uid,row=>{
   const n=row.data(),ownResource=n.resourceId===uid;return row.ref.set({...n,actorUid:null,eventId:`privacy/${row.id}`,...(ownResource?{title:'Compte indisponible',bodySafe:'Le compte associé à cette activité a été supprimé.',resourceType:'unavailable',resourceId:row.id}:{})});
  });
  if(phase==='message_receipts')return drain(db.collectionGroup('messageInbox'),'senderUid',uid,row=>db.runTransaction(async tx=>{
   const owner=row.ref.parent.parent.id,state=ref(`users/${owner}/messageState/inbox`),[current,count]=await Promise.all([tx.get(row.ref),tx.get(state)]);
   if(!current.exists)return;tx.delete(row.ref);if(current.data().unread)tx.set(state,{...count.data(),unreadCount:Math.max(0,(count.data()?.unreadCount||0)-1)});
  }));
  if(phase==='legacy_likes'){
   let q=db.collectionGroup('likes').orderBy(FieldPath.documentId());if(job.cursor)q=q.startAfter(ref(job.cursor));const rows=await q.limit(size).get();
   for(const row of rows.docs)if(row.id===uid && /^requestEngagement\/[^/]+\/likes\/[^/]+$/.test(row.ref.path))await db.runTransaction(async tx=>{const parent=row.ref.parent.parent,[like,count]=await Promise.all([tx.get(row.ref),tx.get(parent)]);if(like.exists){tx.delete(row.ref);tx.set(parent,{...count.data(),likeCount:Math.max(0,(count.data()?.likeCount||0)-1)});}});
   return {done:rows.size<size,cursor:rows.docs.at(-1)?.ref.path||null};
  }
  if(phase==='moderation_subject'||phase==='moderation_reporter')return drain(db.collection('safetyReports'),phase==='moderation_subject'?'reportedUid':'reporterUid',uid,row=>moderation(job,row));
  if(phase==='moderation_admin')return drain(db.collection('safetyAudit'),'adminUid',uid,async row=>{await hold(job,row.id,'moderation_metadata',row.data(),(row.data().createdAt||clock())+job.policy.moderationMetadataDays*day);await row.ref.set({...row.data(),adminUid:alias,reason:'Décision administrative antérieure ; identité effacée.',deleteAt:new Date((row.data().createdAt||clock())+job.policy.moderationMetadataDays*day)});});
  if(phase==='moderation_assignee')return drain(db.collection('safetyReports'),'assignedAdminUid',uid,row=>row.ref.set({...row.data(),assignedAdminUid:alias}));
  if(phase==='privacy_audit')return drain(db.collection('accountDeletionAudit'),'actorUid',uid,row=>row.ref.set({...row.data(),actorUid:alias,reason:'Intervention antérieure ; identité effacée.'}));
  if(phase==='professional_reviewer')return drain(db.collection('professionalProfiles'),'reviewedBy',uid,row=>row.ref.set({...row.data(),reviewedBy:alias,reviewReason:'Examen antérieur ; identité de l’examinateur effacée.'}));
  if(phase==='professional_audit_subject'||phase==='professional_audit_admin')return drain(db.collection('professionalAudit'),phase==='professional_audit_subject'?'uid':'adminUid',uid,async row=>{await hold(job,row.id,'professional_review',row.data(),(row.data().createdAt||clock())+job.policy.moderationMetadataDays*day);if(phase==='professional_audit_subject')await row.ref.delete();else await row.ref.set({...row.data(),adminUid:alias,reason:'Identité de l’administrateur effacée.'});});
  const deletions={tokens:['notificationTokens','uid'],outbox_recipient:['notificationOutbox','uid'],outbox_actor:['notificationOutbox','actorUid'],notification_jobs:['notificationJobs','uid'],notification_receipts:['notificationReceipts','uid']};
  if(deletions[phase]){const [collection,field]=deletions[phase];return drain(db.collection(collection),field,uid,row=>tree(row.ref));}
  if(phase==='otp')return drain(db.collection('authEmailChallenges'),'userId',uid,async row=>{if(/^[a-f0-9]{64}$/.test(row.data().emailKey||''))await ref(`authEmailRateLimits/${row.data().emailKey}`).delete();await row.ref.delete();});
  if(phase==='budgets'){
   for(const name of ['requestPublicationLimits','requestPhotoLimits','conversationAttachmentRates','safetyReportLimits','accountSafety'])await ref(`${name}/${uid}`).delete();
   for(const kind of ['likes','recommendations','directory','incoming'])await ref(`requestInteractionLimits/${createHash('sha256').update([kind,uid].join('\0')).digest('hex')}`).delete();
   if(job.emailKey)await ref(`authEmailRateLimits/${job.emailKey}`).delete();
   return {done:true};
  }
  if(phase==='related_requests')return requestTargets(job);
  if(phase==='related_proposals'){
   const rows=await ref(`accountDeletionJobs/${job.id}`).collection('proposals').where('done','==',false).limit(1).get();if(rows.empty)return {done:true};const t=rows.docs[0],id=t.data().id;
   const references=await db.collectionGroup('items').where('retainedProposalId','==',id).limit(size).get();
   if(!references.empty){for(const r of references.docs)if(/^userRequests\/[^/]+\/items\/[^/]+$/.test(r.ref.path))await r.ref.set({...r.data(),retainedProposalId:null,retainedProfessionalName:null});return {done:false};}
   await t.ref.set({...t.data(),done:true});return {done:false};
  }
  if(phase==='storage_global')return ownedObjects(job,'conversations/',job.cursor,async(name,meta)=>{
   if(meta.metadata?.owneruid)return meta.metadata.owneruid===uid;
   const parts=name.split('/'),cid=parts[1];
   if(!idOK(cid))conflict();
   if(parts[2]==='attachments'){
    if((await target(job,'artifacts',`${cid}:${parts[3]}`).get()).exists)return true;
    const record=(await ref(`conversations/${cid}/messages/${parts[3]}`).get()).data();
    if(record?.senderUid && record.senderUid!==uid)return false;
   }
   if(parts[2]==='quarantine'){
    if((await target(job,'artifacts',`${cid}:asset:${parts[3]}`).get()).exists)return true;
    const records=await ref(`conversations/${cid}`).collection('attachments').where('attachmentId','==',parts[3]).limit(1).get();
    if(records.docs.some(d=>d.data().senderUid && d.data().senderUid!==uid))return false;
   }
   throw Object.assign(Error('Unattributed legacy object'),{code:'privacy/manual-review',reference:name});
  });
  if(phase==='storage_professional'||phase==='storage_requests'){
   if(phase==='storage_requests'){
    const result=await ownedObjects(job,`personalAvatars/${uid}/`);
    if(!result.done)return result;
   }

   const result=await ownedObjects(job,`${phase==='storage_professional'?'professionalDocuments':'requestPhotos'}/${uid}/`);return {done:result.done};
  }
  if(phase==='private_trees'){
   const avatar=(await ref(`personalAvatars/${uid}`).get()).data();
   if(avatar?.publicId){await ref(`publicPersonalAvatars/${avatar.publicId}`).delete();await ref(`personalAvatarLookup/${avatar.publicId}`).delete();}

   const roots=[`personalAvatars/${uid}`,`personalAvatarLimits/${uid}`,`professionalProfiles/${uid}`,`userRequests/${uid}`,`userBlocks/${uid}`,`users/${uid}`];
   for(const path of roots){const r=ref(path);if((await r.get()).exists || (await r.listCollections()).length){await tree(r);return {done:false};}}
   await ref(`safetyContent/professional_${uid}`).delete();return {done:true};
  }
  if(phase==='verify'){
   for(const [collection,field] of [['personalAvatarGarbage','uid'],['requestOwnership','ownerUid'],['requestPhotoFiles','uid'],['requestPhotoDrafts','uid'],['authEmailChallenges','userId'],['notificationJobs','uid'],['notificationReceipts','uid'],['safetyReports','reporterUid'],['safetyReports','reportedUid'],['professionalAudit','uid'],['professionalDirectoryLimits','uid'],['professionalDirectoryCursors','uid']])if(!(await db.collection(collection).where(field,'==',uid).limit(1).get()).empty)throw Object.assign(Error('Residual private reference'),{code:'privacy/verification-failed'});
   for(const [collection,field] of [['proposals','professionalUid'],['proposals','clientUid'],['conversations','clientUid'],['conversations','professionalUid'],['notificationTokens','uid'],['notificationOutbox','uid'],['notificationOutbox','actorUid'],['requestRecommendations','actorUid'],['requestRecommendations','ownerUid'],['requestRecommendations','professionalUid']])if(!(await db.collection(collection).where(field,'==',uid).limit(1).get()).empty)throw Object.assign(Error('Residual owner reference'),{code:'privacy/verification-failed'});
   for(const path of [`users/${uid}`,`professionalProfiles/${uid}`,`userRequests/${uid}`])if((await ref(path).get()).exists || (await ref(path).listCollections()).length)throw Object.assign(Error('Residual owner tree'),{code:'privacy/verification-failed'});
   for(const prefix of [`personalAvatars/${uid}/`,`professionalDocuments/${uid}/`,`requestPhotos/${uid}/`])if((await bucket.getFiles({prefix,autoPaginate:false,maxResults:1}))[0].length)throw Object.assign(Error('Residual owner objects'),{code:'privacy/verification-failed'});
   return {done:true};
  }
  if(phase==='purge_targets'){
   const root=ref(`accountDeletionJobs/${job.id}`),budget={left:size};
   for(const c of await root.listCollections())for(const d of (await c.limit(budget.left||1).get()).docs){if(!budget.left)return {done:false};await tree(d.ref,budget);}
   return {done:(await Promise.all((await root.listCollections()).map(c=>c.limit(1).get()))).every(q=>q.empty)};
  }
  throw new OtpError('failed-precondition','Étape de suppression inconnue.');
 }
 return {run,tree};
}
module.exports={createPrivacyPurger,key,emptyRequest};
