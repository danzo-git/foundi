const {test}=require('node:test'),assert=require('node:assert/strict');
const {initializeApp,deleteApp}=require('firebase/app');
const {getAuth,connectAuthEmulator,signInWithEmailAndPassword}=require('firebase/auth');
const {getFirestore,connectFirestoreEmulator,doc,getDoc,getDocs,collection,query,where,orderBy,limit}=require('firebase/firestore');
const {getFunctions,connectFunctionsEmulator,httpsCallable}=require('firebase/functions');
const {initializeApp:adminApp,deleteApp:deleteAdmin}=require('firebase-admin/app');
const {getAuth:adminAuth}=require('firebase-admin/auth'),{getFirestore:adminDb}=require('firebase-admin/firestore');
const {createSafetyService}=require('../src/safety-service'),{createSafetyStore}=require('../src/safety-store');
const {createNotificationService}=require('../src/notification-service');
const {key}=require('../src/notification-policy');
const enabled=!!(process.env.FIRESTORE_EMULATOR_HOST&&process.env.FIREBASE_AUTH_EMULATOR_HOST&&process.env.FUNCTIONS_EMULATOR_HOST);
const pair=v=>{const [h,p]=v.split(':');assert.ok(['localhost','127.0.0.1'].includes(h));return [h,Number(p)];};
test('SEC A/B/C/D: real callables, rules, bidirectional contact refusal, private history, moderation and old clients',{skip:!enabled,timeout:300000},async()=>{
  for(const host of [process.env.FIRESTORE_EMULATOR_HOST,process.env.FIREBASE_AUTH_EMULATOR_HOST,process.env.FUNCTIONS_EMULATOR_HOST])pair(host);
  const projectId='demo-foundi',stamp=Date.now(),root=adminApp({projectId},'safety-'+stamp),db=adminDb(root),auth=adminAuth(root),apps=[],users=[];
  async function client(name,isAdmin=false){const email=`safety.${name}.${stamp}@example.test`,password='Local-Safety-Password42!';const user=await auth.createUser({email,password,emailVerified:true});users.push(user.uid);if(isAdmin)await auth.setCustomUserClaims(user.uid,{admin:true});const app=initializeApp({projectId,apiKey:'emulator-only',appId:'safety-'+name},'safety-'+name+stamp);apps.push(app);const a=getAuth(app);connectAuthEmulator(a,'http://'+process.env.FIREBASE_AUTH_EMULATOR_HOST,{disableWarnings:true});await signInWithEmailAndPassword(a,email,password);const firestore=getFirestore(app);connectFirestoreEmulator(firestore,...pair(process.env.FIRESTORE_EMULATOR_HOST));const f=getFunctions(app,'europe-west1');connectFunctionsEmulator(f,...pair(process.env.FUNCTIONS_EMULATOR_HOST));return {uid:user.uid,db:firestore,call:(name,data={})=>httpsCallable(f,name)(data).then(r=>r.data)};}
  const failCode=code=>e=>e.code===`functions/${code}`;
  const mid=()=>db.collection('ids').doc().id;
  const decide=(id,action,revision=1)=>({reportId:id,action,expectedRevision:revision,reason:'Décision de test après examen humain.',decisionId:mid()});
  try{
    const a=await client('client'),b=await client('pro'),c=await client('admin',true),d=await client('stranger');
    await db.doc(`professionalProfiles/${b.uid}`).set({status:'approved',businessName:'Atelier de sécurité',categoryIds:['c'],specialtyIds:['s'],zoneIds:['z']});await db.doc(`users/${a.uid}`).set({fullName:'Client de test'});
    await db.doc('referenceData/professionalOnboarding').set({enabled:true,categories:[{id:'c',label:'Services',specialties:[{id:'s',label:'Plomberie'}]}],zones:[{id:'z',label:'Zone de test'}]});
    const rid=mid(),input={title:'Besoin de plomberie',description:'Réparer une fuite dans ma cuisine.',categoryId:'c',specialtyId:'s',zoneId:'z',budget:20000};
    await a.call('publishRequest',{requestId:rid,request:input});const p=await b.call('sendProposal',{requestId:rid,proposal:{description:'Une proposition de réparation.',amount:20000,delay:'Demain'}});const {conversationId:cid}=await a.call('selectProposal',{requestId:rid,proposalId:p.id});const messageId=mid();await b.call('sendConversationMessage',{conversationId:cid,messageId,text:'Message conservé comme preuve.'});
    const target={targetType:'professional',targetId:b.uid};
    const r=await a.call('submitSafetyReport',{...target,reason:'harassment',comment:'Examen demandé.'});assert.equal((await a.call('submitSafetyReport',{...target,reason:'harassment',comment:'Examen demandé.'})).reportId,r.reportId);
    const privateTarget={targetType:'message',targetId:messageId,conversationId:cid};await assert.rejects(d.call('submitSafetyReport',{...privateTarget,reason:'fraud'}),failCode('permission-denied'));
    // Real server-owned PDF evidence is readable only by an authorized reviewer
    // through the report-scoped HTTP API, never by a free file path.
    const pdf=require('node:fs').readFileSync(require('node:path').join(__dirname,'../test/fixtures/document.pdf')),pdfId=mid();
    await b.call('prepareConversationAttachment',{conversationId:cid,messageId:pdfId,type:'pdf',originalName:'preuve.pdf',contentType:'application/pdf',sizeBytes:pdf.length,sha256:require('node:crypto').createHash('sha256').update(pdf).digest('hex')});
    const uploadPdf=await fetch(`http://${process.env.FUNCTIONS_EMULATOR_HOST}/${projectId}/europe-west1/uploadConversationAttachment`,{method:'POST',headers:{Authorization:'Bearer '+await getAuth(apps[1]).currentUser.getIdToken(),'x-conversation-id':cid,'x-message-id':pdfId,'Content-Type':'application/octet-stream'},body:pdf});assert.equal(uploadPdf.status,200);
    const pdfReport=await a.call('submitSafetyReport',{targetType:'message',targetId:pdfId,conversationId:cid,reason:'inappropriate'});
    const proofUrl=`http://${process.env.FUNCTIONS_EMULATOR_HOST}/${projectId}/europe-west1/readSafetyReportAttachment?reportId=${pdfReport.reportId}`;
    const authorizedProof=await fetch(proofUrl,{headers:{Authorization:'Bearer '+await getAuth(apps[2]).currentUser.getIdToken()}});assert.equal(authorizedProof.status,200);assert.deepEqual(Buffer.from(await authorizedProof.arrayBuffer()),pdf);
    const deniedProof=await fetch(proofUrl,{headers:{Authorization:'Bearer '+await getAuth(apps[3]).currentUser.getIdToken()}});assert.equal(deniedProof.status,403);
    await assert.rejects(a.call('listSafetyReports',{status:'new'}),failCode('permission-denied'));await assert.rejects(a.call('decideSafetyReport',decide(r.reportId,'suspend')),failCode('permission-denied'));
    const detail=await c.call('readSafetyReport',{reportId:r.reportId});assert.equal(detail.reporterUid,a.uid);assert.equal(detail.reportedUid,b.uid);
    assert.ok((await c.call('listSafetyReports',{status:'new',reason:'harassment',targetType:'professional'})).items.some(v=>v.id===r.reportId));
    const warning=decide(r.reportId,'warn');await c.call('decideSafetyReport',warning);assert.equal((await c.call('decideSafetyReport',warning)).duplicate,true);assert.equal((await b.call('listSafetyNotices')).items.length,1);
    // Queue an existing message before the personal block; a later delivery is suppressed.
    const sent=[],notifications=createNotificationService({db,auth,messaging:{send:async value=>sent.push(value)}});
    await notifications.register(a.uid,{deviceId:'safety-device',token:'safety-token-with-at-least-20-characters',platform:'android'});
    const queuedId=mid();await db.doc(`conversations/${cid}/messages/${queuedId}`).set({senderUid:b.uid,type:'text',text:'Avant le blocage.',createdAt:Date.now()});
    await notifications.message(cid,queuedId,(await db.doc(`conversations/${cid}/messages/${queuedId}`).get()).data());
    const uploadId=mid(),png=require('node:fs').readFileSync(require('node:path').join(__dirname,'../test/fixtures/photo.png'));
    const attachment={conversationId:cid,messageId:uploadId,type:'image',originalName:'photo.png',contentType:'image/png',sizeBytes:png.length,sha256:require('node:crypto').createHash('sha256').update(png).digest('hex')};
    await b.call('prepareConversationAttachment',attachment);
    await a.call('blockUser',target);
    assert.equal((await a.call('listBlockedUsers')).items[0].uid,b.uid);assert.equal((await b.call('readSafetyContext',{targetType:'request',targetId:rid})).contactAllowed,false);
    for(const actor of [a,b])for(const type of ['text','contact']){
      const id=mid();await assert.rejects(actor.call('sendConversationMessage',{conversationId:cid,messageId:id,...(type==='text'?{text:'Interdit.'}:{type:'contact',phoneNumber:'+2250700000000',consent:true})}),failCode('failed-precondition'));assert.equal((await db.doc(`conversations/${cid}/messages/${id}`).get()).exists,false);assert.equal((await db.doc(`notificationOutbox/${key(`messages/${cid}/${id}`,actor===a?b.uid:a.uid)}`).get()).exists,false);
    }
    await assert.rejects(b.call('sendProposal',{requestId:rid,proposal:{description:'Tentative de contournement.',amount:null,delay:''}}),failCode('permission-denied'));
    await assert.rejects(a.call('selectProposal',{requestId:rid,proposalId:p.id}),failCode('permission-denied'));
    await assert.rejects(a.call('publishDirectRequest',{requestId:mid(),professionalId:b.uid,request:input}),failCode('permission-denied'));
    await assert.rejects(b.call('prepareConversationAttachment',{...attachment,messageId:mid()}),failCode('failed-precondition'));
    await assert.rejects(d.call('recommendRequestProfessional',{requestId:rid,professionalId:b.uid}),failCode('permission-denied'));
    const response=await fetch(`http://${process.env.FUNCTIONS_EMULATOR_HOST}/${projectId}/europe-west1/uploadConversationAttachment`,{method:'POST',headers:{Authorization:'Bearer '+await getAuth(apps[1]).currentUser.getIdToken(),'x-conversation-id':cid,'x-message-id':uploadId,'Content-Type':'application/octet-stream'},body:png});assert.equal(response.status,409);
    assert.ok((await getDoc(doc(a.db,`conversations/${cid}/messages/${messageId}`))).exists());assert.ok((await getDoc(doc(b.db,`conversations/${cid}/messages/${messageId}`))).exists());
    await notifications.deliver(key(`messages/${cid}/${queuedId}`,a.uid));assert.equal(sent.length,0);
    assert.equal(await notifications.message(cid,mid(),{senderUid:b.uid,type:'text',text:'Forged event',createdAt:Date.now()}),false);
    await a.call('unblockUser',{blockedUid:b.uid});await b.call('sendConversationMessage',{conversationId:cid,messageId:mid(),text:'Contact rétabli.'});
    // A real Firestore transaction conflict: two authorized decisions on one revision.
    const rr=await b.call('submitSafetyReport',{targetType:'request',targetId:rid,reason:'fraud'});
    const service=createSafetyService({store:createSafetyStore(db),auth});
    const race=await Promise.allSettled([service.decide(c.uid,{admin:true},decide(rr.reportId,'take')),service.decide(c.uid,{admin:true},decide(rr.reportId,'dismiss'))]);assert.equal(race.filter(v=>v.status==='fulfilled').length,1);assert.equal(race.find(v=>v.status==='rejected').reason.code,'aborted');
    const hideReport=await b.call('submitSafetyReport',{targetType:'request',targetId:rid,reason:'inappropriate'});
    await c.call('decideSafetyReport',{...decide(hideReport.reportId,'warn'),publicMessage:'Corrige la description de cette demande.'});
    const ownNotice=(await a.call('listSafetyNotices')).items.find(text=>text.includes(rid));
    assert.ok(ownNotice.includes(input.title));assert.ok(ownNotice.includes(input.description));
    assert.ok(!ownNotice.includes('Décision de test après examen humain.'));
    assert.ok((await c.call('readSafetyReport',{reportId:hideReport.reportId})).availableActions.includes('reopen'));
    await c.call('decideSafetyReport',decide(hideReport.reportId,'reopen',2));
    await c.call('decideSafetyReport',{...decide(hideReport.reportId,'hide',3),publicMessage:'Cette demande reste masquée pendant sa correction.'});
    await assert.rejects(getDoc(doc(d.db,`requests/${rid}`)),e=>e.code==='permission-denied');const feed=await getDocs(query(collection(d.db,'requests'),where('status','==','published'),orderBy('createdAt','desc'),limit(30)));assert.ok(!feed.docs.some(v=>v.id===rid));
    const own=(await db.doc(`userRequests/${a.uid}/items/${rid}`).get()).data();await a.call('manageRequest',{requestId:rid,action:'edit',request:{...input,title:'Texte corrigé'},expectedRevision:own.updatedAt??own.createdAt});assert.equal((await db.doc(`requests/${rid}`).get()).exists,false);assert.equal((await getDoc(doc(a.db,`userRequests/${a.uid}/items/${rid}`))).data().status,'published');await assert.rejects(getDoc(doc(b.db,`userRequests/${a.uid}/items/${rid}`)),e=>e.code==='permission-denied');
    await c.call('decideSafetyReport',decide(hideReport.reportId,'restore_content',4));assert.equal((await getDoc(doc(d.db,`requests/${rid}`))).data().title,'Texte corrigé');
    assert.deepEqual((await c.call('readSafetyReport',{reportId:hideReport.reportId})).audit.map(a=>a.action),['warn','reopen','hide','restore_content']);
    const suspend=await a.call('submitSafetyReport',{...target,reason:'fraud'});await c.call('decideSafetyReport',decide(suspend.reportId,'suspend'));await assert.rejects(b.call('sendConversationMessage',{conversationId:cid,messageId:mid(),text:'Ancienne session.'}),failCode('permission-denied'));await assert.rejects(getDoc(doc(b.db,`conversations/${cid}`)),e=>e.code==='permission-denied');
    const suspensionNotice=(await db.collection(`users/${b.uid}/notifications`).where('type','==','safety.suspended').get()).docs[0];
    assert.equal((await b.call('resolveNotification',{notificationId:suspensionNotice.id})).resourceType,'safetyNotice');
    assert.ok((await b.call('listSafetyNotices')).items.some(text=>text.includes('Compte Foundi suspendu')));
    assert.ok((await getDoc(doc(b.db,suspensionNotice.ref.path))).exists());
    await assert.rejects(d.call('resolveNotification',{notificationId:suspensionNotice.id}),failCode('not-found'));
    const noticeId=suspensionNotice.data().resourceId;
    await assert.rejects(d.call('acknowledgeSafetyNotice',{noticeId}),failCode('not-found'));
    await assert.rejects(b.call('acknowledgeSafetyNotice',{noticeId,uid:d.uid}),failCode('invalid-argument'));
    assert.equal((await b.call('acknowledgeSafetyNotice',{noticeId})).duplicate,false);
    assert.equal((await b.call('acknowledgeSafetyNotice',{noticeId})).duplicate,true);
    const acknowledged=await b.call('listSafetyNotices');assert.ok(acknowledged.notices.find(n=>n.id===noticeId).acknowledgedAt);
    assert.ok(!acknowledged.items.includes(acknowledged.notices.find(n=>n.id===noticeId).text));
    assert.equal((await db.doc(`accountSafety/${b.uid}`).get()).data().suspended,true);
    assert.ok((await suspensionNotice.ref.get()).data().readAt);
    await assert.rejects(a.call('publishDirectRequest',{requestId:mid(),professionalId:b.uid,request:input}),failCode('permission-denied'));assert.equal((await auth.getUser(b.uid)).disabled,false);
    await c.call('decideSafetyReport',decide(suspend.reportId,'restore_account',2));await b.call('sendConversationMessage',{conversationId:cid,messageId:mid(),text:'Restauration contrôlée.'});assert.equal((await c.call('readSafetyReport',{reportId:suspend.reportId})).audit.length,2);
    for(const actor of [a,b,c,d])await assert.rejects(getDoc(doc(actor.db,`safetyReports/${r.reportId}`)),e=>e.code==='permission-denied');
  }finally{await Promise.all(apps.map(deleteApp));await Promise.all(users.map(uid=>auth.deleteUser(uid)));await deleteAdmin(root);}
});
