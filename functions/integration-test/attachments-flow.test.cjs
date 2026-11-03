const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),{createHash}=require('node:crypto');
const {initializeApp,deleteApp}=require('firebase/app'),{getAuth,connectAuthEmulator,signInWithEmailAndPassword}=require('firebase/auth');
const {getFirestore,connectFirestoreEmulator,doc,collection,getDoc,getDocs,query,orderBy,limit,onSnapshot}=require('firebase/firestore');
const {getFunctions,connectFunctionsEmulator,httpsCallable}=require('firebase/functions');
const {getStorage,connectStorageEmulator,ref,getBytes,getDownloadURL,uploadBytes}=require('firebase/storage');
const {initializeApp:adminApp,deleteApp:deleteAdmin}=require('firebase-admin/app'),{getAuth:adminAuth}=require('firebase-admin/auth'),{getFirestore:adminDb}=require('firebase-admin/firestore'),{getStorage:adminStorage}=require('firebase-admin/storage');
const sharp=require('sharp');
const enabled=!!(process.env.FIREBASE_AUTH_EMULATOR_HOST&&process.env.FIRESTORE_EMULATOR_HOST&&process.env.FIREBASE_STORAGE_EMULATOR_HOST);
const requireScan=process.env.V82_TEST_REQUIRE_SCAN!=='false';
const pair=s=>{const[h,p]=s.split(':');return[h,Number(p)];},digest=b=>createHash('sha256').update(b).digest('hex');
test('V8.2 real HTTP uploads and reads: A/B image/PDF/contact/text, C denied, validation/quarantine, retry, close and historical media',{skip:!enabled,timeout:240000},async()=>{
 const projectId='demo-foundi',stamp=Date.now(),admin=adminApp({projectId,storageBucket:projectId+'.appspot.com'},'v82-'+stamp),db=adminDb(admin),auth=adminAuth(admin),apps=[],users=[],stops=[];let seq=0;
 const http=`http://${process.env.FUNCTIONS_EMULATOR_HOST}/${projectId}/europe-west1`;
 const file=n=>fs.readFileSync(path.join(__dirname,'../test/fixtures',n)),png=file('photo.png'),pdf=file('document.pdf');
 async function client(name,identity){
  if(!identity){const email=`${name}.${stamp}@example.test`,password='Local-V82-Password42!';const u=await auth.createUser({email,password,emailVerified:true});users.push(u.uid);identity={uid:u.uid,email,password};}
  const app=initializeApp({projectId,apiKey:'emulator-only',appId:'v82-'+name,storageBucket:projectId+'.appspot.com'},name+stamp+(seq++));apps.push(app);
  const a=getAuth(app);connectAuthEmulator(a,'http://'+process.env.FIREBASE_AUTH_EMULATOR_HOST,{disableWarnings:true});await signInWithEmailAndPassword(a,identity.email,identity.password);
  const firestore=getFirestore(app);connectFirestoreEmulator(firestore,...pair(process.env.FIRESTORE_EMULATOR_HOST));const functions=getFunctions(app,'europe-west1');connectFunctionsEmulator(functions,...pair(process.env.FUNCTIONS_EMULATOR_HOST));
  const storage=getStorage(app);connectStorageEmulator(storage,...pair(process.env.FIREBASE_STORAGE_EMULATOR_HOST));
  return {uid:identity.uid,identity,db:firestore,storage,token:()=>a.currentUser.getIdToken(),call:(name,data)=>httpsCallable(functions,name)(data).then(r=>r.data)};
 }
 const mid=()=>db.collection('unused').doc().id;
 async function upload(c,cid,id,bytes){return fetch(http+'/uploadConversationAttachment',{method:'POST',headers:{authorization:'Bearer '+await c.token(),'content-type':'application/octet-stream','x-conversation-id':cid,'x-message-id':id},body:bytes});}
 async function read(c,cid,id){return fetch(`${http}/readConversationAttachment?conversationId=${cid}&messageId=${id}`,{headers:{authorization:'Bearer '+await c.token()}});}
 async function prepare(c,cid,id,bytes,type,name,mime){return c.call('prepareConversationAttachment',{conversationId:cid,messageId:id,type,originalName:name,contentType:mime,sizeBytes:bytes.length,sha256:digest(bytes)});}
 function live(c,cid){return new Promise((resolve,reject)=>{let stop;const timer=setTimeout(()=>{stop?.();reject(Error('Enriched realtime messages timeout'));},30000);stop=onSnapshot(query(collection(c.db,`conversations/${cid}/messages`),orderBy('createdAt','asc'),limit(30)),s=>{if(s.size===5){clearTimeout(timer);stop();resolve(s.docs.map(d=>d.data()));}},reject);stops.push(()=>{clearTimeout(timer);stop?.();});});}
 try{
  const a=await client('v82-client'),b=await client('v82-pro'),c=await client('v82-outsider');
  await db.doc('referenceData/professionalOnboarding').set({enabled:true,categories:[{id:'c',label:'Services',specialties:[{id:'s',label:'Réparation'}]}],zones:[{id:'z',label:'Cocody'}]});
  for(const u of [b,c])await db.doc('professionalProfiles/'+u.uid).set({status:'approved',businessName:'Atelier V82',categoryIds:['c'],specialtyIds:['s'],zoneIds:['z']});
  await db.doc('users/'+a.uid).set({fullName:'Client V82',phone:'+2250100000000'});
  const rid=mid();await a.call('publishRequest',{requestId:rid,request:{title:'Besoin test V82',description:'Une demande pour enrichir la discussion.',categoryId:'c',specialtyId:'s',zoneId:'z',budget:null}});
  const proposal={description:'Une proposition professionnelle détaillée.',amount:45000,delay:'3 jours'},p=await b.call('sendProposal',{requestId:rid,proposal});
  const {conversationId:cid}=await a.call('selectProposal',{requestId:rid,proposalId:p.id});
  await db.doc(`conversations/${cid}/messages/legacy`).set({senderUid:b.uid,text:'Ancien message sans type',createdAt:1});
  const al=live(a,cid),bl=live(b,cid),imageId=mid(),pdfId=mid();
  const image=await prepare(a,cid,imageId,png,'image','photo.png','image/png');
  const u=await upload(a,cid,imageId,png);assert.equal(u.status,200,JSON.stringify(await u.clone().json()));assert.equal((await u.json()).state,'ready');
  assert.equal((await prepare(a,cid,imageId,png,'image','photo.png','image/png')).attachmentId,image.attachmentId);assert.equal((await (await upload(a,cid,imageId,png)).json()).state,'ready');
  await prepare(b,cid,pdfId,pdf,'pdf','fiche.pdf','application/pdf');const pu=await upload(b,cid,pdfId,pdf);assert.equal(pu.status,200,JSON.stringify(await pu.clone().json()));
  const contactId=mid();await assert.rejects(a.call('sendConversationMessage',{conversationId:cid,messageId:contactId,type:'contact',phoneNumber:'+2250700000000',consent:false}),e=>e.code==='functions/invalid-argument');
  await a.call('sendConversationMessage',{conversationId:cid,messageId:contactId,type:'contact',phoneNumber:'+2250700000000',consent:true});await b.call('sendConversationMessage',{conversationId:cid,messageId:mid(),text:'Message texte toujours fonctionnel'});
  const [ar,br]=await Promise.all([al,bl]);assert.deepEqual(ar,br);assert.ok(ar.some(m=>m.type==='image'));assert.ok(ar.some(m=>m.type==='pdf'));assert.ok(ar.some(m=>m.phoneNumber==='+2250700000000'));assert.ok(ar.some(m=>!m.type&&m.text==='Ancien message sans type'));
  assert.equal((await db.doc('users/'+a.uid).get()).data().phone,'+2250100000000');
  for(const actor of [a,b]){const response=await read(actor,cid,pdfId);assert.equal(response.status,200);assert.deepEqual(Buffer.from(await response.arrayBuffer()),pdf);}
  const imageMessage=(await getDoc(doc(a.db,`conversations/${cid}/messages/${imageId}`))).data();
  const [meta]=await adminStorage(admin).bucket().file(imageMessage.storagePath).getMetadata();assert.equal(meta.metadata.firebaseStorageDownloadTokens,undefined);assert.equal(imageMessage.antivirusStatus,requireScan?'clean':'skipped');assert.equal(meta.metadata.validation,requireScan?'clean-v1':'structural-v1');
  for(const actor of [a,b]){
   const response=await read(actor,cid,imageId);assert.equal(response.status,200);assert.equal((await response.arrayBuffer()).byteLength,imageMessage.sizeBytes);
   await assert.rejects(getBytes(ref(actor.storage,imageMessage.storagePath)),e=>e.code==='storage/unauthorized');
   await assert.rejects(getDownloadURL(ref(actor.storage,imageMessage.storagePath)),e=>e.code==='storage/unauthorized');
  }
  const [afterReads]=await adminStorage(admin).bucket().file(imageMessage.storagePath).getMetadata();assert.equal(afterReads.metadata?.firebaseStorageDownloadTokens,undefined);
  await assert.rejects(getBytes(ref(c.storage,imageMessage.storagePath)),e=>e.code==='storage/unauthorized');await assert.rejects(uploadBytes(ref(a.storage,imageMessage.storagePath),png,{contentType:'image/png'}),e=>e.code==='storage/unauthorized');
  assert.equal((await read(c,cid,imageId)).status,403);await assert.rejects(prepare(c,cid,mid(),png,'image','photo.png','image/png'),e=>e.code==='functions/permission-denied');
  const manipulated=await upload(c,cid,imageId,png);assert.equal(manipulated.status,403);
  for(const [type,mime,name,size]of [['image','image/png','a.png',10*1048576+1],['pdf','application/pdf','a.pdf',15*1048576+1],['pdf','application/zip','a.zip',10]])await assert.rejects(a.call('prepareConversationAttachment',{conversationId:cid,messageId:mid(),type,contentType:mime,originalName:name,sizeBytes:size,sha256:digest(png)}),e=>e.code==='functions/invalid-argument');
  const fakeId=mid(),fake=Buffer.from('PK\x03\x04fake');await prepare(a,cid,fakeId,fake,'image','fake.png','image/png');assert.equal((await upload(a,cid,fakeId,fake)).status,400);assert.equal((await db.doc(`conversations/${cid}/messages/${fakeId}`).get()).exists,false);
  const pendingId=mid(),unknown=await sharp({create:{width:8,height:8,channels:3,background:'#112233'}}).png().toBuffer();const pending=await prepare(a,cid,pendingId,unknown,'image','unknown.png','image/png');
  assert.equal((await (await upload(a,cid,pendingId,unknown)).json()).state,requireScan?'awaiting_scan':'ready');assert.equal((await db.doc(`conversations/${cid}/messages/${pendingId}`).get()).exists,!requireScan);assert.equal((await read(a,cid,pendingId)).status,requireScan?404:200);
  if(requireScan)await assert.rejects(getBytes(ref(a.storage,`conversations/${cid}/quarantine/${pending.attachmentId}`)),e=>e.code==='storage/unauthorized');
  else assert.equal((await adminStorage(admin).bucket().file(`conversations/${cid}/quarantine/${pending.attachmentId}`).exists())[0],false);
  assert.equal((await a.call('cancelConversationAttachment',{conversationId:cid,messageId:pendingId})).state,requireScan?'cancelled':'ready');assert.equal((await upload(a,cid,pendingId,unknown)).status,requireScan?409:200);
  const cancelledId=mid();await prepare(a,cid,cancelledId,png,'image','cancel.png','image/png');await a.call('cancelConversationAttachment',{conversationId:cid,messageId:cancelledId});assert.equal((await upload(a,cid,cancelledId,png)).status,409);
  const jpegId=mid(),jpeg=file('photo.jpeg');await prepare(a,cid,jpegId,jpeg,'image','photo.jpeg','image/jpeg');assert.equal((await upload(a,cid,jpegId,jpeg)).status,200);
  const missing=(await db.doc(`conversations/${cid}/messages/${jpegId}`).get()).data();await adminStorage(admin).bucket().file(missing.storagePath).delete();assert.equal((await read(a,cid,jpegId)).status,503);
  const reopened=await client('v82-reopened',b.identity);assert.ok((await getDocs(query(collection(reopened.db,`conversations/${cid}/messages`),orderBy('createdAt','desc'),limit(30)))).docs.some(d=>d.data().type==='contact'));
  assert.equal((await getDoc(doc(c.db,'requests/'+rid))).data().status,'published');assert.ok((await c.call('listOpportunities',{categoryIds:['c'],specialtyIds:['s'],zoneIds:['z']})).items.some(x=>x.id===rid));await c.call('sendProposal',{requestId:rid,proposal});
  await a.call('manageRequest',{requestId:rid,action:'close'});await b.call('sendConversationMessage',{conversationId:cid,messageId:mid(),type:'contact',phoneNumber:'+2250500000000',consent:true});
  await a.call('decideProposal',{requestId:rid,proposalId:p.id,action:'reject',decisionId:mid()});await assert.rejects(prepare(b,cid,mid(),png,'image','photo.png','image/png'),e=>e.code==='functions/failed-precondition');
  assert.equal((await read(b,cid,pdfId)).status,200);await assert.rejects(b.call('sendConversationMessage',{conversationId:cid,messageId:mid(),text:'Après refus'}),e=>e.code==='functions/failed-precondition');
 }finally{stops.forEach(s=>s());await Promise.all(users.map(uid=>auth.deleteUser(uid)));await Promise.all(apps.map(deleteApp));await deleteAdmin(admin);}
});
