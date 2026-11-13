const {test}=require('node:test');
const assert=require('node:assert/strict');
const {setup,rid,pid}=require('./helpers/safety-fixture');
const {createAttachmentService}=require('../src/attachment-service');
const {publicProfileAllowed}=require('../src/safety-guard');
const {readConversation}=require('../src/conversation-service');
const {matchesSafetyNotice}=require('../src/safety-notification');
const pro={targetType:'professional',targetId:'pro'},req={targetType:'request',targetId:rid};
const report=(target=pro)=>({...target,reason:'harassment',comment:'Menaces reçues, à examiner.'});
const rejected=code=>e=>e.code===code;
const decision=(id,action,revision=1)=>({reportId:id,action,reason:'Examen humain et décision motivée.',expectedRevision:revision,decisionId:`decision_${id.slice(0,12)}_${action}_${revision}`});

test('SEC acknowledging an own notice persists across reads, preserves the sanction and audit, and marks only its notification read once',async()=>{
  const c=setup(),id=(await c.safety.submit('pro',report(req))).reportId;
  await c.safety.decide('admin',{admin:true},decision(id,'suspend'));
  const notice=(await c.safety.notices('client')).notices[0],before=structuredClone(c.data.get(`safetyReports/${id}`));
  assert.equal(notice.acknowledgedAt,null);
  assert.equal((await c.safety.acknowledgeNotice('client',{noticeId:notice.id})).duplicate,false);
  const readAt=c.data.get(`users/client/notifications/${c.data.get(`users/client/safetyNotices/${notice.id}`).notificationId}`).readAt;
  assert.ok(readAt instanceof Date);
  c.setTime(200000);
  assert.equal((await c.safety.acknowledgeNotice('client',{noticeId:notice.id})).duplicate,true);
  const after=await c.safety.notices('client');
  assert.deepEqual(after.items,[]);assert.equal(after.notices.length,1);assert.equal(after.notices[0].acknowledgedAt,100000);
  assert.deepEqual(c.data.get(`safetyReports/${id}`),before);assert.equal(c.data.get('accountSafety/client').suspended,true);
  assert.equal((await c.store.audit(id)).length,1);
  assert.equal(c.data.get(`users/client/notifications/${c.data.get(`users/client/safetyNotices/${notice.id}`).notificationId}`).readAt.getTime(),readAt.getTime());
  await c.safety.decide('admin',{admin:true},decision(id,'restore_account',2));
  assert.equal((await c.safety.notices('client')).items.length,1,'a new decision remains visible after closing an older notice');
});
test('SEC acknowledgement is scoped to the authenticated owner, validates input, and supports notices from the first sprint version',async()=>{
  const c=setup(),noticeId='a'.repeat(64);
  c.data.set(`users/client/safetyNotices/${noticeId}`,{text:'Ancien avertissement',createdAt:1});
  await assert.rejects(c.safety.acknowledgeNotice('pro',{noticeId}),rejected('not-found'));
  await assert.rejects(c.safety.acknowledgeNotice(null,{noticeId}),rejected('unauthenticated'));
  for(const input of [{noticeId:'../../client'},{noticeId,uid:'client'},{noticeId:'not-an-id'}])await assert.rejects(c.safety.acknowledgeNotice('client',input),rejected('invalid-argument'));
  c.accounts.set('client',{disabled:true,emailVerified:true});await assert.rejects(c.safety.acknowledgeNotice('client',{noticeId}),rejected('permission-denied'));
  c.accounts.clear();await c.safety.acknowledgeNotice('client',{noticeId});
  assert.equal((await c.safety.notices('client')).notices[0].text,'Ancien avertissement');
  assert.equal(c.data.get(`users/client/safetyNotices/${noticeId}`).acknowledgedAt,100000);
});

test('SEC report resolves every author server-side and snapshots only minimal private evidence',async()=>{
  const c=setup();await c.chat.select('client',{requestId:rid,proposalId:pid});
  const mid='SafetyMessageIdentifier001';await c.chat.send('pro',{conversationId:pid,messageId:mid,text:'Message abusif à examiner.'});
  for(const [uid,target,expected] of [['client',pro,'pro'],['pro',req,'client'],['client',{targetType:'conversation',targetId:pid},'pro'],['client',{targetType:'message',targetId:mid,conversationId:pid},'pro']]){
    const result=await c.safety.submit(uid,report(target)),saved=c.data.get(`safetyReports/${result.reportId}`);
    assert.equal(saved.reportedUid,expected);assert.equal(saved.reporterUid,uid);assert.equal(saved.status,'new');assert.equal(saved.createdAt,100000);
  }
  assert.equal(c.data.get('accountSafety/pro'),undefined,'one complaint never suspends');
  assert.equal([...c.data.keys()].filter(k=>k.includes('notifications')).length,0);
});
test('SEC unauthenticated, disabled, suspended and unverified reporters cannot submit',async()=>{
  const c=setup();await assert.rejects(c.safety.submit(undefined,report()),rejected('unauthenticated'));
  for(const flags of [{disabled:true,emailVerified:true},{disabled:false,emailVerified:false}]){c.accounts.set('client',flags);await assert.rejects(c.safety.submit('client',report()),rejected('permission-denied'));}
  c.accounts.clear();c.data.set('accountSafety/client',{suspended:true});await assert.rejects(c.safety.submit('client',report()),rejected('permission-denied'));
});
test('SEC private request context follows the same recipient approval restriction as Firestore reads',async()=>{
  const c=setup(),publicRequest=c.data.get(`requests/${rid}`);
  c.data.delete(`requests/${rid}`);c.data.set(`directRequests/${rid}`,{...publicRequest,visibility:'direct',clientUid:'client',directProfessionalId:'pro'});
  c.data.get('professionalProfiles/pro').status='pending';
  await assert.rejects(c.safety.context('pro',req),rejected('permission-denied'));
  await assert.rejects(c.safety.submit('pro',report(req)),rejected('permission-denied'));
  await assert.rejects(c.safety.submit('stranger',report(req)),rejected('permission-denied'));
  c.data.get('professionalProfiles/pro').status='approved';assert.equal((await c.safety.submit('pro',report(req))).duplicate,false);
});
test('SEC rejects target spoofing, own content, invalid reasons/comments and nonparticipants',async()=>{
  const c=setup();await c.chat.select('client',{requestId:rid,proposalId:pid});
  await c.chat.send('pro',{conversationId:pid,messageId:'SafetyMessageIdentifier001',text:'Historique privé.'});
  for(const input of [{...report(),targetUid:'victim'},{...report(),reason:'fake'},{...report(),comment:'x'.repeat(501)},{...report(),targetId:'../users/private'}])await assert.rejects(c.safety.submit('client',input),rejected('invalid-argument'));
  await assert.rejects(c.safety.submit('pro',report()),rejected('invalid-argument'));
  await assert.rejects(c.safety.submit('client',report(req)),rejected('invalid-argument'));
  await assert.rejects(c.safety.submit('stranger',report({targetType:'message',targetId:'SafetyMessageIdentifier001',conversationId:pid})),rejected('permission-denied'));
  await assert.rejects(c.safety.submit('stranger',report({targetType:'conversation',targetId:pid})),rejected('permission-denied'));
});
test('SEC report retries are idempotent; daily budget preserves extra capacity for severe complaints',async()=>{
  const c=setup();const first=await c.safety.submit('client',report());
  const retries=await Promise.all(Array.from({length:20},()=>c.safety.submit('client',report())));
  assert.ok(retries.every(r=>r.duplicate&&r.reportId===first.reportId));assert.equal(c.data.get('safetyReportLimits/client').count,1);
  c.data.set('safetyReportLimits/client',{day:0,count:20});
  await assert.rejects(c.safety.submit('client',{...pro,reason:'spam'}),rejected('resource-exhausted'));
  assert.equal((await c.safety.submit('client',{...pro,reason:'fraud'})).duplicate,false);
  c.setTime(86400001);assert.equal((await c.safety.submit('client',report())).duplicate,false,'renewed abuse can be reported on a later day');
});
test('SEC block uses a resolved relationship, forbids self-block and never discloses the reverse block list',async()=>{
  const c=setup();await assert.rejects(c.safety.block('client',{...pro,targetUid:'stranger'}),rejected('invalid-argument'));
  await assert.rejects(c.safety.block('pro',pro),rejected('invalid-argument'));
  await c.safety.block('client',pro);await c.safety.block('client',pro);
  assert.equal(c.data.get('userBlocks/client/items/pro').label,'Atelier Test');
  assert.deepEqual(await c.safety.context('pro',req),{own:false,blocked:false,contactAllowed:false});
  await c.safety.unblock('stranger',{blockedUid:'pro'});assert.ok(c.data.get('userBlocks/client/items/pro'));
});
test('SEC bidirectional block prevents old-client proposal access, opening, text and contact while history survives',async()=>{
  for(const blocker of ['client','pro']){
    const c=setup();await c.chat.select('client',{requestId:rid,proposalId:pid});
    await c.safety.block(blocker,{targetType:'conversation',targetId:pid});
    for(const uid of ['client','pro']){
      await assert.rejects(c.chat.send(uid,{conversationId:pid,messageId:'BlockedTextIdentifier001',text:'Contournement.'}),rejected('failed-precondition'));
      await assert.rejects(c.chat.send(uid,{conversationId:pid,messageId:'BlockedPhoneIdentifier01',type:'contact',phoneNumber:'+2250700000000',consent:true}),rejected('failed-precondition'));
    }
    await assert.rejects(c.chat.select('client',{requestId:rid,proposalId:pid}),rejected('permission-denied'));
    await assert.rejects(c.proposals.access('pro',rid),rejected('permission-denied'));
    await assert.rejects(c.proposals.send('pro',rid,{description:'Proposition de contournement.',amount:20000,delay:''}),rejected('permission-denied'));
    assert.ok(c.data.get(`conversations/${pid}`));assert.ok(c.data.get(`proposals/${pid}`));
    assert.equal([...c.data.keys()].filter(k=>k.includes('/messages/')).length,0);
    await c.safety.unblockTarget(blocker,{targetType:'conversation',targetId:pid});
    await c.chat.send('pro',{conversationId:pid,messageId:'AllowedTextIdentifier001',text:'Contact rétabli.'});
  }
});
test('SEC direct request cannot bypass block from either side or account suspension',async()=>{
  for(const path of ['userBlocks/client/items/pro','userBlocks/pro/items/client','accountSafety/client','accountSafety/pro']){
    const c=setup();c.data.set(path,{suspended:true});
    await assert.rejects(c.requests.publishDirect('client','DirectSafetyRequest00001','pro',{categoryId:'c',specialtyId:'s',zoneId:'z',title:'Une fuite',description:'Réparation de ma cuisine.',budget:null}),rejected('permission-denied'));
    assert.equal(c.data.get('directRequests/DirectSafetyRequest00001'),undefined);assert.equal(c.data.get('requestPublicationLimits/client'),undefined);
  }
});
test('SEC attachment reservation and final upload revalidate block, including a prepared file',async()=>{
  const c=setup();await c.chat.select('client',{requestId:rid,proposalId:pid});
  const fs=require('node:fs'),bytes=fs.readFileSync(require('node:path').join(__dirname,'fixtures/photo.png'));
  const svc=createAttachmentService({...c.deps,files:{save:async()=>1,remove:async()=>{},read:async()=>bytes},requireScan:false});
  const data={conversationId:pid,messageId:'SafetyAttachmentIdent001',type:'image',originalName:'photo.png',contentType:'image/png',sizeBytes:bytes.length,sha256:require('node:crypto').createHash('sha256').update(bytes).digest('hex')};
  await svc.prepare('pro',data);await c.safety.block('client',pro);
  await assert.rejects(svc.upload('pro',pid,data.messageId,bytes),rejected('failed-precondition'));
  await assert.rejects(svc.prepare('pro',{...data,messageId:'SafetyAttachmentIdent002'}),rejected('failed-precondition'));
  assert.equal(c.data.get(`conversations/${pid}/messages/${data.messageId}`),undefined);
});
test('SEC fresh admin claim and active account required for both reads and decisions',async()=>{
  const c=setup(),id=(await c.safety.submit('client',report())).reportId;
  for(const [uid,token] of [['client',{admin:true}],['admin',{}]])await assert.rejects(c.safety.decide(uid,token,decision(id,'warn')),rejected('permission-denied'));
  c.data.set('accountSafety/admin',{suspended:true});await assert.rejects(c.safety.detail('admin',{admin:true},{reportId:id}),rejected('permission-denied'));
});
test('SEC concurrent admin decisions conflict, retries are stable, and audit is append-only',async()=>{
  const c=setup(),id=(await c.safety.submit('client',report())).reportId;
  const [a,b]=await Promise.allSettled([c.safety.decide('admin',{admin:true},decision(id,'warn')),c.safety.decide('admin2',{admin:true},decision(id,'suspend'))]);
  assert.equal(a.status,'fulfilled');assert.equal(b.status,'rejected');assert.equal(b.reason.code,'aborted');
  assert.equal((await c.safety.decide('admin',{admin:true},decision(id,'warn'))).duplicate,true);
  const audits=await c.store.audit(id);assert.equal(audits.length,1);assert.equal(audits[0].adminUid,'admin');assert.ok(audits[0].reason);
  assert.equal(c.data.get('accountSafety/pro'),undefined);assert.equal([...c.data.keys()].filter(p=>p.startsWith('users/pro/safetyNotices/')).length,1);
  await assert.rejects(c.safety.decide('admin',{admin:true},{...decision(id,'dismiss',2),reason:''}),rejected('invalid-argument'));
});
test('SEC decisions atomically notify only the affected member, retry once, and disclose no report or private reason',async()=>{
  for(const action of ['warn','hide','suspend']){
    const c=setup(),id=(await c.safety.submit('client',report())).reportId;
    c.data.set('users/pro/notificationState/inbox',{unreadCount:3,other:'preserved'});
    const input=decision(id,action);
    await c.safety.decide('admin',{admin:true},input);
    await c.safety.decide('admin',{admin:true},input);
    const rows=[...c.data].filter(([p])=>p.startsWith('users/pro/notifications/'));
    assert.equal(rows.length,1);
    const [path,n]=rows[0],nid=path.split('/').at(-1);
    const notice=c.data.get(`users/pro/safetyNotices/${n.resourceId}`);
    assert.ok(matchesSafetyNotice('pro',nid,n,notice));
    assert.equal(matchesSafetyNotice('client',nid,n,notice),false);
    assert.equal(matchesSafetyNotice('pro',nid,{...n,type:'safety.account_restored'},notice),false);
    assert.ok(c.data.get(`notificationOutbox/${nid}`));
    assert.deepEqual(c.data.get('users/pro/notificationState/inbox'),{unreadCount:4,other:'preserved'});
    assert.equal([...c.data.keys()].filter(p=>p.startsWith('users/client/notifications/')).length,0);
    const publicData=JSON.stringify({n,notice,outbox:c.data.get(`notificationOutbox/${nid}`)});
    for(const secret of [id,input.reason,'Menaces reçues','client','admin'])assert.ok(!publicData.includes(secret));
    if(action!=='warn'){
      await c.safety.decide('admin',{admin:true},decision(id,action==='hide'?'restore_content':'restore_account',2));
      assert.equal([...c.data.keys()].filter(p=>p.startsWith('users/pro/notifications/')).length,2);
    }
  }
});
test('SEC beginning an examination is internal, cannot be repeated, and leaves a later decision possible',async()=>{
  const c=setup(),id=(await c.safety.submit('client',report())).reportId;
  await c.safety.decide('admin',{admin:true},decision(id,'take'));
  assert.equal(c.data.get(`safetyReports/${id}`).status,'in_progress');
  assert.equal(c.data.get(`safetyReports/${id}`).assignedAdminUid,'admin');
  assert.equal([...c.data.keys()].filter(p=>p.includes('/notifications/')||p.startsWith('notificationOutbox/')).length,0);
  await assert.rejects(c.safety.decide('admin2',{admin:true},decision(id,'take',2)),rejected('failed-precondition'));
  await c.safety.decide('admin',{admin:true},decision(id,'dismiss',2));
  assert.equal([...c.data.keys()].filter(p=>p.includes('/notifications/')||p.startsWith('notificationOutbox/')).length,0);
});
test('SEC warning can be reviewed, escalated to hiding and suspension, then restored with full audit and active retention',async()=>{
  const c=setup(),id=(await c.safety.submit('pro',report(req))).reportId;
  await c.safety.decide('admin',{admin:true},{...decision(id,'warn'),publicMessage:'Corrige cette publication.'});
  assert.deepEqual((await c.safety.detail('admin',{admin:true},{reportId:id})).availableActions,['reopen']);
  await assert.rejects(c.safety.decide('admin',{admin:true},decision(id,'hide',2)),rejected('failed-precondition'));
  const reopen=decision(id,'reopen',2);
  await c.safety.decide('admin',{admin:true},reopen);
  assert.ok((await c.safety.detail('admin',{admin:true},{reportId:id})).availableActions.includes('hide'));
  assert.equal(c.data.get('users/client/notificationState/inbox').unreadCount,1);
  await c.safety.decide('admin',{admin:true},decision(id,'hide',3));
  await c.safety.decide('admin',{admin:true},decision(id,'reopen',4));
  assert.equal(c.data.get(`requests/${rid}`),undefined,'review does not republish hidden content');
  assert.equal(c.data.get(`safetyReports/${id}`).deleteAt,null);
  await assert.rejects(c.safety.decide('admin',{admin:true},decision(id,'dismiss',5)),rejected('failed-precondition'));
  await c.safety.decide('admin',{admin:true},decision(id,'suspend',5));
  await c.safety.decide('admin',{admin:true},decision(id,'restore_account',6));
  assert.equal(c.data.get(`safetyReports/${id}`).deleteAt,null,'hidden content still needs its dossier after account restoration');
  await c.safety.decide('admin',{admin:true},decision(id,'restore_content',7));
  assert.ok(c.data.get(`safetyReports/${id}`).deleteAt instanceof Date);
  assert.ok(c.data.get(`requests/${rid}`));
  assert.equal(c.data.get('accountSafety/client').suspended,false);
  assert.deepEqual((await c.store.audit(id)).map(a=>a.action),['warn','reopen','hide','reopen','suspend','restore_account','restore_content']);
  assert.equal((await c.store.audit(id))[0].publicMessage,'Corrige cette publication.');
  assert.equal((await c.safety.decide('admin',{admin:true},reopen)).duplicate,true);
  assert.equal(c.data.get(`safetyReports/${id}`).revision,8);
  assert.equal(c.data.get('users/client/notificationState/inbox').unreadCount,5);
});
test('SEC own publication title, reference and excerpt identify a decision, while private reasons and lock-screen pushes stay separate',async()=>{
  const c=setup(),id=(await c.safety.submit('pro',report(req))).reportId;
  const input={...decision(id,'warn'),publicMessage:'Cette demande contient une publicité sans rapport avec le service recherché.'};
  await c.safety.decide('admin',{admin:true},input);
  const n=[...c.data].find(([p])=>p.startsWith('users/client/notifications/'))[1];
  const notice=c.data.get(`users/client/safetyNotices/${n.resourceId}`);
  assert.ok(n.bodySafe.includes('Réparer une fuite'));
  assert.ok(notice.text.includes(rid));assert.ok(notice.text.includes('Une fuite dans la cuisine à réparer.'));
  assert.ok(notice.text.includes(input.publicMessage));
  assert.ok(!notice.text.includes(input.reason));assert.ok(!notice.text.includes('Menaces reçues'));
  assert.deepEqual(notice.content,{type:'request',id:rid,title:'Demande « Réparer une fuite »',excerpt:'Une fuite dans la cuisine à réparer.',createdAt:1});
  const push=c.data.get(`notificationOutbox/${notice.notificationId}`);
  assert.ok(!push.bodySafe.includes('Réparer une fuite'));assert.ok(!push.bodySafe.includes(input.publicMessage));
  for(const publicMessage of ['', 'x'.repeat(501)])await assert.rejects(c.safety.decide('admin',{admin:true},{...decision(id,'reopen',2),publicMessage}),rejected('invalid-argument'));
});
test('SEC dismissed reports can be reviewed concurrently, without losing their first decision or sending a notice',async()=>{
  const c=setup(),id=(await c.safety.submit('client',report())).reportId;
  await c.safety.decide('admin',{admin:true},decision(id,'dismiss'));
  const outcomes=await Promise.allSettled(['admin','admin2'].map(uid=>c.safety.decide(uid,{admin:true},decision(id,'reopen',2))));
  assert.equal(outcomes.filter(r=>r.status==='fulfilled').length,1);
  assert.equal(outcomes.find(r=>r.status==='rejected').reason.code,'aborted');
  assert.equal((await c.store.audit(id)).length,2);
  assert.equal([...c.data.keys()].filter(p=>p.includes('/notifications/')).length,0);
});
test('SEC notice context never copies another sender, raw evidence or a reporter into the recipient view',()=>{
  const {decisionNotification}=require('../src/safety-notification');
  const payload=decisionNotification('warn','decision','pro',1000,{report:{reportedUid:'pro',targetType:'message',targetId:'message',reporterUid:'secret-reporter',comment:'secret-comment',evidence:{message:{senderUid:'other',text:'secret-other-message'},images:[{base64:'secret-image'}]}}});
  const ownView=JSON.stringify(payload);
  for(const secret of ['secret-reporter','secret-comment','secret-other-message','secret-image'])assert.ok(!ownView.includes(secret));
  const expired=decisionNotification('hide','decision2','client',1000,{report:{reportedUid:'client',targetType:'request',targetId:'request',evidence:{expired:true}},own:{title:'Titre toujours identifiable',description:'Mon texte actuel',createdAt:25}});
  assert.ok(expired.notice.text.includes('Titre toujours identifiable'));assert.ok(expired.notice.text.includes('Mon texte actuel'));
});
test('SEC hiding removes legacy public projection; edits cannot resurrect it; restore preserves lifecycle/quota',async()=>{
  const c=setup(),id=(await c.safety.submit('pro',report(req))).reportId;
  await c.safety.decide('admin',{admin:true},decision(id,'hide'));
  assert.equal(c.data.get(`requests/${rid}`),undefined);assert.equal(c.data.get(`userRequests/client/items/${rid}`).status,'published');
  const current=c.data.get(`userRequests/client/items/${rid}`);
  await c.requests.manage('client',rid,'edit',{categoryId:'c',specialtyId:'s',zoneId:'z',title:'Contenu modifié',description:'Un nouveau texte utile.',budget:null},current.createdAt);
  assert.equal(c.data.get(`requests/${rid}`),undefined);
  await c.safety.decide('admin',{admin:true},decision(id,'restore_content',2));
  assert.equal(c.data.get(`requests/${rid}`).title,'Contenu modifié');assert.equal(c.data.get('requestPublicationLimits/client'),undefined);
});
test('SEC professional masking survives public profile changes and is reversible independently of approval',async()=>{
  const c=setup(),id=(await c.safety.submit('client',report())).reportId;
  await c.safety.decide('admin',{admin:true},decision(id,'hide'));
  assert.equal(await publicProfileAllowed(c.store,'pro'),false);assert.equal(c.data.get('professionalProfiles/pro').status,'approved');
  await c.safety.decide('admin',{admin:true},decision(id,'restore_content',2));assert.equal(await publicProfileAllowed(c.store,'pro'),true);
});
test('SEC suspension and restoration gate existing sessions and contacts without altering Auth state or business records',async()=>{
  const c=setup();await c.chat.select('client',{requestId:rid,proposalId:pid});const id=(await c.safety.submit('client',report())).reportId;
  await c.safety.decide('admin',{admin:true},decision(id,'suspend'));
  assert.equal((await c.store.transaction(t=>readConversation(t,'client',pid))).writable,false);
  await assert.rejects(c.chat.send('pro',{conversationId:pid,messageId:'SuspendedMessageIdent01',text:'Test.'}),rejected('failed-precondition'));
  assert.equal(c.data.get('professionalProfiles/pro').status,'approved');
  await c.safety.decide('admin',{admin:true},decision(id,'restore_account',2));
  await c.chat.send('pro',{conversationId:pid,messageId:'RestoredMessageIdent001',text:'Retour autorisé.'});
  c.accounts.set('pro',{disabled:true,emailVerified:true});await assert.rejects(c.chat.send('pro',{conversationId:pid,messageId:'DisabledMessageIdent001',text:'Test.'}),rejected('permission-denied'));
});
test('SEC dismissing never penalizes the target; retention purges message/comment evidence after 90 days',async()=>{
  const c=setup(),id=(await c.safety.submit('client',report())).reportId;
  await c.safety.decide('admin',{admin:true},decision(id,'dismiss'));assert.equal(await publicProfileAllowed(c.store,'pro'),true);
  c.setTime(91*86400000);assert.equal((await c.safety.purgeEvidence()).removed,1);const r=c.data.get(`safetyReports/${id}`);assert.deepEqual(r.evidence,{expired:true});assert.equal(r.comment,'');assert.equal(r.revision,2);assert.equal((await c.store.audit(id)).length,1);
});
test('SEC prepublication rejects mechanical repetition without keyword censorship',async()=>{
  const c=setup();const input={categoryId:'c',specialtyId:'s',zoneId:'z',title:'Réparation',description:'x'.repeat(100),budget:null};
  await assert.rejects(c.requests.publish('client','RepetitionRequestIdent001',input),rejected('invalid-argument'));
  await c.requests.publish('client','LegitimateRequestIdent001',{...input,description:'Besoin d’une caméra de sécurité après une tentative de fraude.'});
});
test('SEC visual evidence is private, bounded, frozen and removable without reading arbitrary files',async()=>{
  const {createSafetyEvidence}=require('../src/safety-evidence'),{createSafetyService}=require('../src/safety-service');
  const c=setup(),bytes=require('node:fs').readFileSync(require('node:path').join(__dirname,'fixtures/photo.png'));
  const photo={id:require('node:crypto').createHash('sha256').update(bytes).digest('hex'),base64:bytes.toString('base64')};
  c.data.set('professionalProfiles/pro/showcase/profile',{bio:'Présentation signalée.',portrait:photo,gallery:[photo]});
  const evidence=createSafetyEvidence({files:{read:async()=>{throw Error('No arbitrary storage reads');}}});const service=createSafetyService({...c.deps,evidence});
  const id=(await service.submit('client',report())).reportId,saved=c.data.get(`safetyReports/${id}`);
  assert.equal(saved.evidence.images.length,2);assert.ok(Buffer.from(saved.evidence.images[0].base64,'base64').length<=32768);
  c.data.delete('professionalProfiles/pro/showcase/profile');assert.equal(saved.evidence.bio,'Présentation signalée.');
  await assert.rejects(evidence.attachment(saved),rejected('not-found'));
  await assert.rejects(service.readAttachment('client',{admin:true},{reportId:id}),rejected('permission-denied'));
  c.setTime(91*86400000);await service.purgeEvidence();assert.deepEqual(c.data.get(`safetyReports/${id}`).evidence,{expired:true});
});
test('SEC an older case cannot restore a newer sanction; active measures keep their restoration dossier',async()=>{
  const c=setup(),first=(await c.safety.submit('client',report())).reportId;
  const second=(await c.safety.submit('client',{...report(),reason:'fraud'})).reportId;
  await c.safety.decide('admin',{admin:true},decision(first,'suspend'));
  await c.safety.decide('admin',{admin:true},decision(second,'suspend'));
  assert.equal(c.data.get(`safetyReports/${second}`).deleteAt,null);
  await assert.rejects(c.safety.decide('admin',{admin:true},decision(first,'restore_account',2)),rejected('failed-precondition'));
  await c.safety.decide('admin',{admin:true},decision(second,'restore_account',2));assert.equal(c.data.get('accountSafety/pro').suspended,false);
});
