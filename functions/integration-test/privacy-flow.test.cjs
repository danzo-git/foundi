const {test}=require('node:test'),assert=require('node:assert/strict'),{randomBytes}=require('node:crypto');
const {initializeApp,deleteApp}=require('firebase/app'),{getAuth,connectAuthEmulator,signInWithEmailAndPassword}=require('firebase/auth');
const {getFirestore,connectFirestoreEmulator,doc,getDoc,setDoc}=require('firebase/firestore'),{getFunctions,connectFunctionsEmulator,httpsCallable}=require('firebase/functions');
const {initializeApp:adminApp,deleteApp:deleteAdmin}=require('firebase-admin/app'),{getAuth:adminAuth}=require('firebase-admin/auth'),{getFirestore:adminDb}=require('firebase-admin/firestore'),{getStorage}=require('firebase-admin/storage');
const {createPrivacyService}=require('../src/privacy-service'),{createPrivacyStore}=require('../src/privacy-store'),{createPrivacyPurger}=require('../src/privacy-purge');
const active=!!(process.env.FIRESTORE_EMULATOR_HOST&&process.env.FIREBASE_AUTH_EMULATOR_HOST&&process.env.FUNCTIONS_EMULATOR_HOST&&process.env.FIREBASE_STORAGE_EMULATOR_HOST);
const host=v=>{const [h,p]=v.split(':');assert.ok(['127.0.0.1','localhost'].includes(h));return [h,+p];};
test('PRIVACY A/B: verified callable, old tokens denied, real Firestore/Storage erasure, B history and sanction preserved, Auth last',{skip:!active,timeout:300000},async()=>{
 for(const v of [process.env.FIRESTORE_EMULATOR_HOST,process.env.FIREBASE_AUTH_EMULATOR_HOST,process.env.FUNCTIONS_EMULATOR_HOST,process.env.FIREBASE_STORAGE_EMULATOR_HOST])host(v);
 const stamp=Date.now(),projectId='demo-foundi',root=adminApp({projectId,storageBucket:'demo-foundi.appspot.com'},'privacy-'+stamp),db=adminDb(root),auth=adminAuth(root),realBucket=getStorage(root).bucket();
 // Storage Emulator has no provider recovery window. Actual object operations
 // still hit its HTTP API; production uses the bucket's real metadata instead.
 const bucket={getFiles:(...a)=>realBucket.getFiles(...a),file:(...a)=>realBucket.file(...a),getMetadata:async()=>[{softDeletePolicy:{retentionDurationSeconds:0}}]};
 const apps=[],uids=[];
 async function client(name,admin=false){const email=`privacy.${name}.${stamp}@example.test`,password='Emulator-Password42!';const u=await auth.createUser({email,password,emailVerified:true});uids.push(u.uid);if(admin)await auth.setCustomUserClaims(u.uid,{admin:true});const app=initializeApp({projectId,apiKey:'emulator-only',appId:'privacy-'+name},'privacy-'+name+stamp);apps.push(app);const a=getAuth(app);connectAuthEmulator(a,'http://'+process.env.FIREBASE_AUTH_EMULATOR_HOST,{disableWarnings:true});await signInWithEmailAndPassword(a,email,password);const f=getFunctions(app,'europe-west1');connectFunctionsEmulator(f,...host(process.env.FUNCTIONS_EMULATOR_HOST));const d=getFirestore(app);connectFirestoreEmulator(d,...host(process.env.FIRESTORE_EMULATOR_HOST));return {uid:u.uid,email,password,auth:a,db:d,call:(name,data={})=>httpsCallable(f,name)(data).then(r=>r.data)};}
 const mid=()=>db.collection('ids').doc().id,base=`http://${process.env.FUNCTIONS_EMULATOR_HOST}/${projectId}/europe-west1`;
 const http=(name,input)=>fetch(base+'/'+name,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(input)});
 try {
  const a=await client('A'),b=await client('B'),admin=await client('admin',true),rid=mid(),cid=mid(),pid=mid(),aid=mid(),bid=mid();
  const config={enabled:true,approved:true,version:'emulator-only-fixture',receiptSeconds:3600,auditSeconds:3600,tombstoneSeconds:3900,moderationEvidenceDays:1,moderationMetadataDays:1,sharedMessages:'erase_author_keep_counterparty',preserveOtherMembersMeasures:true,providerRetentionAcknowledged:true};await db.doc('privacyConfiguration/current').set(config);
  await db.doc(`users/${a.uid}`).set({fullName:'Alice private',phone:'+2250700000001'});await db.doc(`users/${b.uid}`).set({fullName:'Benoît',termsVersion:'historique'});
  await db.doc(`professionalProfiles/${a.uid}`).set({status:'approved',businessName:'Atelier Alice'});await db.doc(`professionalProfiles/${b.uid}`).set({status:'approved',businessName:'Atelier B'});
  const request={title:'Publication Alice',description:'Texte personnel Alice',status:'published',createdAt:stamp};
  await db.doc(`userRequests/${a.uid}/items/${rid}`).set(request);await db.doc(`requestOwnership/${rid}`).set({ownerUid:a.uid});await db.doc(`requests/${rid}`).set({...request,authorPublicName:'Alice private'});
  await db.doc(`proposals/${pid}`).set({clientUid:a.uid,professionalUid:b.uid,requestId:rid,description:'Proposition conservée de B',requestTitle:request.title,status:'selected',conversationId:cid});
  await db.doc(`conversations/${cid}`).set({clientUid:a.uid,professionalUid:b.uid,requestId:rid,proposalId:pid,clientName:'Alice private',professionalName:'Benoît',requestTitle:request.title,requestSnapshot:request,status:'open',createdAt:stamp,updatedAt:stamp});
  await db.doc(`conversations/${cid}/messages/${aid}`).set({senderUid:a.uid,type:'text',text:'Texte de Alice à effacer',createdAt:stamp});await db.doc(`conversations/${cid}/messages/${bid}`).set({senderUid:b.uid,type:'text',text:'Texte de B à conserver',createdAt:stamp+1});
  const asset=mid(),pathA=`conversations/${cid}/attachments/${aid}/${asset}`,pathB=`conversations/${cid}/attachments/${bid}/${mid()}`;
  for(const [path,uid] of [[pathA,a.uid],[pathB,b.uid],[`requestPhotos/${a.uid}/${rid}/orphan/photo.webp`,a.uid],[`professionalDocuments/${a.uid}/identity/orphan`,a.uid]])await realBucket.file(path).save(Buffer.from('Emulator bytes'),{resumable:false,metadata:{metadata:{owneruid:uid}}});
  const [meta]=await realBucket.file(pathA).getMetadata();await db.doc(`conversations/${cid}/attachments/${aid}`).set({senderUid:a.uid,attachmentId:asset,storagePath:pathA,quarantinePath:`conversations/${cid}/quarantine/${asset}`,generation:String(meta.generation)});
  const report=mid();await db.doc(`safetyReports/${report}`).set({reporterUid:a.uid,reportedUid:b.uid,targetType:'professional',targetId:b.uid,status:'resolved',revision:1,reason:'fraud',createdAt:stamp,evidence:{text:'Alice proof'},evidenceExpiresAt:stamp+86400000,deleteAt:null});await db.doc(`safetyAudit/${mid()}`).set({reportId:report,adminUid:admin.uid,action:'suspend',createdAt:stamp,reason:'Examen',deleteAt:null});await db.doc(`accountSafety/${b.uid}`).set({suspended:true,reportId:report});
  // B's suspension does not affect the right of A to erase their own account.
  const proofReport=mid();await db.doc(`safetyReports/${proofReport}`).set({reporterUid:b.uid,reportedUid:a.uid,targetType:'message',targetId:aid,status:'new',revision:1,reason:'fraud',createdAt:stamp,evidenceExpiresAt:stamp+86400000,evidence:{conversationId:cid,message:{type:'pdf',senderUid:a.uid,attachmentId:asset,storagePath:pathA,generation:String(meta.generation),contentType:'application/pdf'}},deleteAt:new Date(stamp+86400000)});
  // A deliberately unattributed legacy fixture must pause the worker safely.
  // Its actual creator B is known by this test, not guessed by the product.
  const legacyPath=`conversations/${mid()}/quarantine/${mid()}`;await realBucket.file(legacyPath).save(Buffer.from('Legacy B fixture'),{resumable:false});
  const requestId=randomBytes(32).toString('hex'),receiptToken=randomBytes(32).toString('hex'),cap={requestId,receiptToken};
  await assert.rejects(a.call('requestAccountDeletion',{...cap,confirm:true,uid:b.uid}),e=>e.code==='functions/invalid-argument');
  const result=await a.call('requestAccountDeletion',{...cap,confirm:true});assert.equal(result.state,'queued');
  await assert.rejects(a.call('sendConversationMessage',{conversationId:cid,messageId:mid(),text:'Old token attack'}),e=>e.code==='functions/permission-denied');await assert.rejects(getDoc(doc(a.db,`users/${a.uid}`)),e=>e.code==='permission-denied');await assert.rejects(setDoc(doc(a.db,`users/${a.uid}`),{fullName:'Resurrection'}),e=>e.code==='permission-denied');
  await assert.rejects(getDoc(doc(b.db,`accountDeletionJobs/${requestId}`)),e=>e.code==='permission-denied');assert.equal((await http('readAccountDeletionStatus',{...cap,receiptToken:'0'.repeat(64)})).status,404);
  const service=createPrivacyService({store:createPrivacyStore(db),auth,purger:createPrivacyPurger({db,bucket}),enabled:()=>true,clock:()=>Date.now()+240000});
  let reviewedLegacy=false;
  for(let i=0;i<15;i++){
   await service.run(requestId,100);const j=(await db.doc(`accountDeletionJobs/${requestId}`).get()).data();if(j.state==='completed')break;
   if(j.state==='needs_review' && !reviewedLegacy){
    assert.equal(j.lastErrorCode,'privacy/manual-review');assert.equal((await realBucket.file(legacyPath).exists())[0],true);assert.equal((await auth.getUser(a.uid)).disabled,true);assert.equal((await service.status(cap)).canRetry,false);
    const privateDetail=await admin.call('readAccountDeletion',{requestId});assert.equal(privateDetail.reviewReference,legacyPath);assert.ok(!('reviewReference' in await service.status(cap)));
    await realBucket.file(legacyPath).setMetadata({metadata:{owneruid:b.uid}});
    await admin.call('resumeAccountDeletion',{requestId,reason:'Fixture : attribution vérifiée à B depuis la création contrôlée du fichier.'});reviewedLegacy=true;continue;
   }
   assert.notEqual(j.state,'needs_review',JSON.stringify({phase:j.phase,error:j.lastErrorCode}));assert.notEqual(j.state,'retry',JSON.stringify({phase:j.phase,error:j.lastErrorCode}));
  }
  assert.equal(reviewedLegacy,true);assert.equal((await realBucket.file(legacyPath).exists())[0],true);

  const job=(await db.doc(`accountDeletionJobs/${requestId}`).get()).data();assert.equal(job.state,'completed');assert.ok(!job.uid);await assert.rejects(auth.getUser(a.uid),e=>e.code==='auth/user-not-found');
  assert.equal((await db.doc(`requests/${rid}`).get()).exists,false);assert.equal((await db.doc(`users/${a.uid}`).get()).exists,false);assert.equal((await db.doc(`professionalProfiles/${a.uid}`).get()).exists,false);
  assert.equal((await db.doc(`conversations/${cid}/messages/${bid}`).get()).data().text,'Texte de B à conserver');const tombstone=(await db.doc(`conversations/${cid}/messages/${aid}`).get()).data();assert.equal(tombstone.deleted,true);assert.ok(!JSON.stringify(tombstone).includes(a.uid));
  const chat=(await db.doc(`conversations/${cid}`).get()).data();assert.equal(chat.status,'read_only');assert.ok(!JSON.stringify(chat).includes('Alice'));assert.equal((await db.doc(`proposals/${pid}`).get()).data().description,'Proposition conservée de B');
  assert.equal((await realBucket.file(pathA).exists())[0],false);assert.equal((await realBucket.file(pathB).exists())[0],true);assert.equal((await realBucket.getFiles({prefix:`requestPhotos/${a.uid}/` }))[0].length,0);
  const restriction=(await db.doc(`accountSafety/${b.uid}`).get()).data();assert.equal(restriction.suspended,true);assert.notEqual(restriction.reportId,report);assert.equal((await db.doc(`safetyReports/${report}`).get()).exists,false);const continuation=(await db.doc(`safetyReports/${restriction.reportId}`).get()).data();assert.ok(!JSON.stringify(continuation).includes(a.uid));
  const holds=await db.collection('accountDeletionHolds').where('requestId','==',requestId).get();const proof=holds.docs.map(d=>d.data()).find(h=>h.data?.reportId===proofReport);assert.ok(proof.deleteAt.toMillis()<=stamp+86400000);const chunkIds=proof.data.evidence.message.retainedAttachment.chunks;const chunks=await db.getAll(...chunkIds.map(id=>db.doc(`accountDeletionHoldChunks/${id}`)));assert.deepEqual(Buffer.concat(chunks.map(c=>c.data().bytes)),Buffer.from('Emulator bytes'));assert.ok(chunks.every(c=>c.data().deleteAt.toMillis()===proof.deleteAt.toMillis()));
  const status=await (await http('readAccountDeletionStatus',cap)).json();assert.equal(status.state,'completed');assert.ok(!JSON.stringify(status).includes(a.uid));
  // The original B restriction remains reversible from its technical docket.
  await admin.call('decideSafetyReport',{reportId:restriction.reportId,expectedRevision:1,action:'restore_account',decisionId:mid(),reason:'Contrôle de continuité du dossier technique.'});assert.equal((await db.doc(`accountSafety/${b.uid}`).get()).data().suspended,false);
  // A changed object generation must stop completion, never erase that object
  // or delete Auth. A suspended account still has the right to initiate erasure.
  const stopped=await client('stopped'),stopCid=mid(),stopMid=mid(),stopAsset=mid(),stopPath=`conversations/${stopCid}/attachments/${stopMid}/${stopAsset}`;
  await db.doc(`accountSafety/${stopped.uid}`).set({suspended:true});
  await db.doc(`conversations/${stopCid}`).set({clientUid:stopped.uid,professionalUid:b.uid,requestId:mid(),proposalId:mid(),clientName:'Stop',professionalName:'B',requestTitle:'Test',requestSnapshot:request,status:'active',createdAt:stamp,updatedAt:stamp});
  await realBucket.file(stopPath).save(Buffer.from('Changed generation'),{resumable:false,metadata:{metadata:{owneruid:stopped.uid}}});
  await db.doc(`conversations/${stopCid}/attachments/${stopMid}`).set({senderUid:stopped.uid,attachmentId:stopAsset,storagePath:stopPath,quarantinePath:`conversations/${stopCid}/quarantine/${stopAsset}`,generation:'0'});
  const stoppedCap={requestId:randomBytes(32).toString('hex'),receiptToken:randomBytes(32).toString('hex')};await stopped.call('requestAccountDeletion',{...stoppedCap,confirm:true});
  await service.run(stoppedCap.requestId,100);const stoppedJob=(await db.doc(`accountDeletionJobs/${stoppedCap.requestId}`).get()).data();assert.equal(stoppedJob.state,'retry');assert.equal(stoppedJob.lastErrorCode,'privacy/ownership-conflict');assert.equal((await auth.getUser(stopped.uid)).disabled,true);assert.equal((await realBucket.file(stopPath).exists())[0],true);assert.equal((await realBucket.file(pathB).exists())[0],true);assert.equal((await service.status(stoppedCap)).canRetry,true);
  // The public website uses the same password sign-in REST API and callable
  // protocol, then keeps tracking without an authenticated session or app.
  const web=await client('web'),signed=await fetch(`http://${process.env.FIREBASE_AUTH_EMULATOR_HOST}/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=emulator-only`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({email:web.email,password:web.password,returnSecureToken:true})});assert.equal(signed.status,200);const webIdentity=await signed.json();
  const webCap={requestId:randomBytes(32).toString('hex'),receiptToken:randomBytes(32).toString('hex')};
  const submitted=await fetch(base+'/requestAccountDeletion',{method:'POST',headers:{'Content-Type':'application/json',Authorization:'Bearer '+webIdentity.idToken},body:JSON.stringify({data:{...webCap,confirm:true}})});assert.equal(submitted.status,200);
  for(let i=0;i<6;i++){await service.run(webCap.requestId,100);if((await service.status(webCap)).state==='completed')break;}
  assert.equal((await(await http('readAccountDeletionStatus',webCap)).json()).state,'completed');await assert.rejects(auth.getUser(web.uid),e=>e.code==='auth/user-not-found');
 } finally {await Promise.all(apps.map(deleteApp));await Promise.all(uids.map(uid=>auth.deleteUser(uid).catch(e=>{if(e.code!=='auth/user-not-found')throw e;})));await deleteAdmin(root);}
});
