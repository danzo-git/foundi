const {test}=require('node:test'),assert=require('node:assert/strict');
const {initializeApp,deleteApp}=require('firebase-admin/app');
const {getFirestore}=require('firebase-admin/firestore');
const {createRequestAuthorService,createRequestAuthorStore}=require('../src/request-author-service');
const {createProfessionalDirectoryService}=require('../src/professional-directory-service');
const {directoryActor}=require('../src/professional-directory-service');
const enabled=!!process.env.FIRESTORE_EMULATOR_HOST;
test('AUTHOR public identity, approved activity, bounded legacy ownership, live blocks and authenticated callable',{skip:!enabled,timeout:180000},async()=>{
 const app=initializeApp({projectId:'demo-foundi-authors'},'authors-'+Date.now()),db=getFirestore(app);
 const auth={getUser:async uid=>({uid,disabled:false,emailVerified:true}),getUsers:async ids=>({users:ids.map(({uid})=>({uid,disabled:false,emailVerified:true}))})};
 const store=createRequestAuthorStore(db),directory=createProfessionalDirectoryService({store,auth});
 const service=createRequestAuthorService({store,auth,directory,avatars:{resolve:async()=>({avatars:{}})}});
 const rid='AuthorPublicRequest00001',uid='author',read=()=>service.read('viewer','author-integration',{requestId:rid});
 try{
  await db.doc(`requests/${rid}`).set({status:'published',authorPublicName:'Awa Kouassi',createdAt:123});
  await db.doc(`userRequests/${uid}/items/${rid}`).set({status:'published',createdAt:123});
  await db.doc(`users/${uid}`).set({fullName:'Private',email:'private@example.test',phone:'private-phone'});
  assert.deepEqual(await read(),{name:'Awa Kouassi',avatarKey:null,professional:null});
  await db.doc('referenceData/professionalOnboarding').set({enabled:true,categories:[{id:'c',label:'Artisanat',specialties:[{id:'s',label:'Menuiserie'}]}],zones:[{id:'z',label:'Cocody'}]});
  await db.doc(`professionalProfiles/${uid}`).set({status:'approved',businessName:'Atelier Awa',categoryIds:['c'],specialtyIds:['s'],zoneIds:['z'],privateContact:'private'});
  const result=await read();assert.equal(result.professional.name,'Atelier Awa');assert.match(result.professional.trade,/Menuiserie/);assert.ok(!JSON.stringify(result).includes('private'));
  await db.doc('userBlocks/viewer/items/author').set({createdAt:1});await assert.rejects(read(),e=>e.code==='not-found');await db.doc('userBlocks/viewer/items/author').delete();
  await db.doc(`professionalProfiles/${uid}`).update({status:'pending'});assert.equal((await read()).professional,null);
  // More than the bounded historical scan must fail closed, even if our document is among the first 50.
  const batch=db.batch();for(let i=0;i<51;i++)batch.set(db.doc(`userRequests/noise_${i}/items/NoiseRequest${String(i).padStart(20,'0')}`),{createdAt:123});await batch.commit();
  await assert.rejects(read(),e=>e.code==='not-found');
  await db.doc(`requestOwnership/${rid}`).set({ownerUid:uid});assert.equal((await read()).name,'Awa Kouassi');
  await db.doc(`requests/${rid}`).update({status:'deleted'});await assert.rejects(read(),e=>e.code==='not-found');
  // Exercise the actual new callable with no real account, on the demo project only.
  if(process.env.FUNCTIONS_EMULATOR_HOST){
   const base=`http://${process.env.FUNCTIONS_EMULATOR_HOST}/demo-foundi/europe-west1/readRequestAuthorProfile`;
   const response=await fetch(base,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({data:{requestId:'../private'}})});
   const body=await response.json();assert.equal(response.status,400,JSON.stringify(body));assert.equal(body.error.status,'INVALID_ARGUMENT');
   const callableApp=initializeApp({projectId:'demo-foundi'},'author-callable-'+Date.now()),liveDb=getFirestore(callableApp),liveAuth=require('firebase-admin/auth').getAuth(callableApp);
   const liveUid='author_callable_'+Date.now(),liveId='AuthorCallableRequest'+Date.now();
   try{
    await liveAuth.createUser({uid:liveUid,email:`${liveUid}@example.test`,emailVerified:true});
    await liveDb.doc(`requests/${liveId}`).set({status:'published',authorPublicName:'Auteur de recette',createdAt:Date.now()});
    await liveDb.doc(`requestOwnership/${liveId}`).set({ownerUid:liveUid});
    const live=await fetch(base,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({data:{requestId:liveId}})}),value=await live.json();
    assert.equal(live.status,200,JSON.stringify(value));assert.deepEqual(value.result,{name:'Auteur de recette',avatarKey:null,professional:null});
    await liveDb.doc(`accountLifecycle/${liveUid}`).set({state:'closing'});
    const closed=await fetch(base,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({data:{requestId:liveId}})});assert.equal(closed.status,404);
   }finally{await liveAuth.deleteUser(liveUid);await deleteApp(callableApp);}
  }
  assert.ok(directoryActor({rawRequest:{ip:'127.0.0.1'}}));
 }finally{await deleteApp(app);}
});
