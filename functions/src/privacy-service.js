const {randomBytes,createHash,timingSafeEqual}=require('node:crypto');
const {OtpError,requireUid}=require('./auth-validation');
const day=86400000;
const digest=value=>createHash('sha256').update(value).digest('hex');
const opaque=value=>typeof value==='string' && /^[a-f0-9]{64}$/.test(value);
const fail=(code,message)=>{throw new OtpError(code,message);};
const phases=['disable_auth','withdraw_requests','discover_requests','withdraw_profile','quiesce','moderation_subject','moderation_reporter','moderation_audits','proposals_sent','proposals_received','conversations_client','conversations_pro','recommendations_actor','recommendations_owner','recommendations_pro','direct_received','notifications_actor','message_receipts','legacy_likes','moderation_admin','moderation_assignee','professional_reviewer','privacy_audit','professional_audit_subject','professional_audit_admin','tokens','outbox_recipient','outbox_actor','notification_jobs','notification_receipts','otp','budgets','incoming_blocks','directory_budgets','photo_drafts','photo_files','related_requests','related_proposals','storage_global','storage_professional','storage_requests','private_trees','verify','delete_auth','purge_targets','complete'];
function shape(input,keys){if(!input || typeof input!=='object' || Array.isArray(input) || Object.keys(input).some(k=>!keys.includes(k)))fail('invalid-argument','Paramètres de suppression invalides.');}
function policy(input){
 if(input?.enabled!==true || input?.approved!==true || !/^[a-zA-Z0-9._-]{1,100}$/.test(input?.version||'') || input.sharedMessages!=='erase_author_keep_counterparty' || input.preserveOtherMembersMeasures!==true || input.providerRetentionAcknowledged!==true)fail('failed-precondition','La suppression attend la validation de la politique de conservation. Contacte l’assistance Foundi.');
 const ranges={receiptSeconds:[3600,365*86400],auditSeconds:[3600,365*86400],tombstoneSeconds:[3900,365*86400],moderationEvidenceDays:[0,90],moderationMetadataDays:[0,365]};
 for(const [key,[min,max]] of Object.entries(ranges))if(!Number.isSafeInteger(input[key]) || input[key]<min || input[key]>max)fail('failed-precondition','Les durées de conservation doivent être validées avant activation.');
 return Object.fromEntries(['version','sharedMessages','preserveOtherMembersMeasures','providerRetentionAcknowledged',...Object.keys(ranges)].map(k=>[k,input[k]]));
}
function publicStatus(job){return {requestId:job.id,state:job.state,step:phases[job.phase]||'complete',createdAt:job.createdAt,updatedAt:job.updatedAt,completedAt:job.completedAt||null,canRetry:job.state==='retry',retainedUntil:job.retainedUntil||null,retainedCategories:job.retainedCategories||[],providerRetentionUntil:job.providerRetentionUntil||null};}
function receiptMatches(job,token){const a=Buffer.from(job?.receiptHash||'0'.repeat(64),'hex'),b=Buffer.from(digest(token),'hex');return a.length===b.length && timingSafeEqual(a,b);}

function createPrivacyService({store,auth,purger,clock=Date.now,enabled=()=>false,quiescenceMs=180000,emailKey=()=>null}){
 async function requireEnabled(){if(!await enabled())fail('failed-precondition','La suppression automatique n’est pas encore activée. Contacte kouamedenzel09@gmail.com.');}
 async function request(uid,authTime,input){
  requireUid(uid);await requireEnabled();shape(input,['requestId','receiptToken','confirm']);
  if(!opaque(input.requestId)||!opaque(input.receiptToken)||input.requestId===input.receiptToken||input.confirm!==true)fail('invalid-argument','Confirme explicitement la suppression de ton compte.');
  const now=clock();if(!Number.isFinite(authTime)||authTime>now/1000+30||now/1000-authTime>300)fail('unauthenticated','Vérifie à nouveau ton identité avant de supprimer le compte.');
  const user=await auth.getUser(uid);if(user.disabled)fail('permission-denied','Ce compte est indisponible. Utilise le suivi déjà enregistré ou l’assistance.');
  return store.transaction(async tx=>{
   const [configuration,life,prior]=await Promise.all([tx.get('privacyConfiguration/current'),tx.get(`accountLifecycle/${uid}`),tx.get(`accountDeletionJobs/${input.requestId}`)]);
   const adopted=policy(configuration);
   if(prior){if(prior.uid!==uid||!receiptMatches(prior,input.receiptToken))fail('already-exists','Cette référence ne peut pas être utilisée.');return publicStatus(prior);}
   if(life?.state==='closing'||life?.state==='deleted')fail('failed-precondition','Une demande existe déjà. Reprends le suivi enregistré sur ton appareil ou contacte l’assistance.');
   const job={id:input.requestId,uid,alias:`deleted_${input.requestId.slice(0,32)}`,receiptHash:digest(input.receiptToken),emailKey:emailKey(user.email),policy:adopted,state:'queued',phase:0,cursor:null,runnable:true,dueAt:now,lease:null,leaseUntil:0,attempts:0,createdAt:now,updatedAt:now,quiesceUntil:now+quiescenceMs,retainedUntil:null,retainedCategories:[]};
   tx.set(`accountLifecycle/${uid}`,{state:'closing',requestId:job.id,startedAt:now});tx.set(`accountDeletionJobs/${job.id}`,job);
   return publicStatus(job);
  });
 }
 async function status(input){
  shape(input,['requestId','receiptToken']);if(!opaque(input.requestId)||!opaque(input.receiptToken))fail('not-found','Suivi indisponible. Vérifie le code enregistré sur cet appareil.');
  return store.transaction(async tx=>{const job=await tx.get(`accountDeletionJobs/${input.requestId}`);if(!job||!receiptMatches(job,input.receiptToken))fail('not-found','Suivi indisponible. Vérifie le code enregistré sur cet appareil.');return publicStatus(job);});
 }
 async function retry(input){
  await requireEnabled();await status(input);
  return store.transaction(async tx=>{
   const path=`accountDeletionJobs/${input.requestId}`,job=await tx.get(path);
   if(!job||!receiptMatches(job,input.receiptToken))fail('not-found','Suivi indisponible.');
   if(job.state==='retry'){tx.set(path,{...job,state:'queued',attempts:0,runnable:true,dueAt:clock(),updatedAt:clock()});}
   return {requested:true};
  });
 }
 async function tick(id){
  if(!await enabled())return {skipped:true};
  const lease=randomBytes(16).toString('hex'),path=`accountDeletionJobs/${id}`,now=clock();
  const job=await store.transaction(async tx=>{
   const [j,configuration]=await Promise.all([tx.get(path),tx.get('privacyConfiguration/current')]);
   if(configuration?.enabled!==true || !j?.runnable || j.dueAt>now || j.leaseUntil>now || j.state==='completed')return null;
   if(!j.uid || !j.policy)fail('failed-precondition','Dossier de suppression incomplet.');
   tx.set(path,{...j,state:'processing',lease,leaseUntil:now+600000,updatedAt:now});return j;
  });
  if(!job)return {skipped:true};
  try{
   const phase=phases[job.phase];let outcome={done:true,cursor:null};
   if(phase==='disable_auth'){
    try{await auth.updateUser(job.uid,{disabled:true});await auth.revokeRefreshTokens(job.uid);}catch(e){if(e.code!=='auth/user-not-found')throw e;}
   }else if(phase==='quiesce' && clock()<job.quiesceUntil)outcome={done:false,cursor:null,waitUntil:job.quiesceUntil};
   else if(phase==='delete_auth'){
    try{await auth.deleteUser(job.uid);}catch(e){if(e.code!=='auth/user-not-found')throw e;}
   }else if(phase!=='complete' && phase!=='quiesce')outcome=await purger.run(job,phase);
   return store.transaction(async tx=>{
    const current=await tx.get(path);if(current?.lease!==lease)return {skipped:true};
    const finished=phase==='complete';
    const next={...current,...(outcome.patch||{}),state:finished?'completed':outcome.waitUntil?'waiting':'queued',phase:current.phase+(outcome.done?1:0),cursor:outcome.done?null:outcome.cursor??current.cursor,runnable:!finished,dueAt:outcome.waitUntil||clock(),lease:null,leaseUntil:0,attempts:0,updatedAt:clock()};
    if(finished){delete next.uid;delete next.alias;delete next.emailKey;delete next.reviewReference;delete next.cursor;next.completedAt=clock();next.deleteAt=new Date(clock()+job.policy.receiptSeconds*1000);tx.set(`accountLifecycle/${job.uid}`,{state:'deleted',requestId:job.id,completedAt:clock(),deleteAt:new Date(clock()+job.policy.tombstoneSeconds*1000)});}
    tx.set(path,next);return {done:finished,waiting:!!outcome.waitUntil};
   });
  }catch(error){
   await store.transaction(async tx=>{
    const current=await tx.get(path);if(current?.lease!==lease)return;
    const attempts=(current.attempts||0)+1,review=attempts>=5 || error.code==='privacy/manual-review';
    tx.set(path,{...current,state:review?'needs_review':'retry',runnable:!review,attempts,reviewReference:typeof error.reference==='string' && /^[a-zA-Z0-9_/-]{1,512}$/.test(error.reference)?error.reference:null,lastErrorCode:['privacy/manual-review','privacy/ownership-conflict','privacy/verification-failed'].includes(error.code)?error.code:'step-failed',dueAt:clock()+Math.min(3600000,1000*2**attempts),lease:null,leaseUntil:0,updatedAt:clock()});
   });
   return {failed:true};
  }
 }
 async function run(id,pages=20){for(let i=0;i<pages;i++){const result=await tick(id);if(result.done||result.waiting||result.failed||result.skipped)return result;}return {yielded:true};}
 async function drain(){if(!await enabled())return {disabled:true};for(const id of await store.pending(clock(),2))await run(id);return {processed:true};}
 async function requireAdmin(uid,token){requireUid(uid);const a=await auth.getUser(uid);if(a.disabled||!token?.admin||a.customClaims?.admin!==true)fail('permission-denied','Accès administratif requis.');const life=await store.transaction(tx=>tx.get(`accountLifecycle/${uid}`));if(life)fail('permission-denied','Compte indisponible.');}
 async function list(uid,token,input={}){await requireAdmin(uid,token);shape(input,['cursor']);if(input.cursor!=null&&!opaque(input.cursor))fail('invalid-argument','Pagination invalide.');const result=await store.list(input.cursor||null);await store.audit({actorUid:uid,kind:'list',createdAt:clock()});return result;}
 async function detail(uid,token,input){
  await requireAdmin(uid,token);shape(input,['requestId']);
  if(!opaque(input.requestId))fail('invalid-argument','Référence invalide.');
  const j=await store.transaction(tx=>tx.get(`accountDeletionJobs/${input.requestId}`));
  if(!j)fail('not-found','Dossier indisponible.');
  await store.audit({actorUid:uid,requestId:j.id,kind:'read',createdAt:clock()});
  return {...publicStatus(j),attempts:j.attempts,lastErrorCode:j.lastErrorCode||null,subjectUid:j.uid||null,reviewReference:j.reviewReference||null};
 }

 async function resume(uid,token,input){await requireAdmin(uid,token);shape(input,['requestId','reason']);if(!opaque(input.requestId)||typeof input.reason!=='string'||!input.reason.trim()||input.reason.length>500)fail('invalid-argument','Justifie la reprise du dossier existant.');await requireEnabled();await store.transaction(async tx=>{const path=`accountDeletionJobs/${input.requestId}`,j=await tx.get(path);if(!j||!['retry','needs_review'].includes(j.state))fail('failed-precondition','Ce dossier ne peut pas être repris.');tx.set(path,{...j,state:'queued',attempts:0,runnable:true,dueAt:clock(),updatedAt:clock()});});await store.audit({actorUid:uid,requestId:input.requestId,kind:'resume',reason:input.reason.trim(),createdAt:clock()});return {resumed:true};}
 return {request,status,retry,tick,run,drain,list,detail,resume};
}
module.exports={createPrivacyService,phases,policy,digest,publicStatus};
