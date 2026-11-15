const {test}=require('node:test'),assert=require('node:assert/strict');
const {initializeApp,deleteApp}=require('firebase/app');
const {getAuth,connectAuthEmulator,signInWithEmailAndPassword}=require('firebase/auth');
const {getFirestore,connectFirestoreEmulator,doc,getDoc,setDoc}=require('firebase/firestore');
const {getFunctions,connectFunctionsEmulator,httpsCallable}=require('firebase/functions');
const {initializeApp:adminApp,deleteApp:deleteAdmin}=require('firebase-admin/app');
const {getAuth:adminAuth}=require('firebase-admin/auth'),{getFirestore:adminDb}=require('firebase-admin/firestore');
const enabled=!!(process.env.FIRESTORE_EMULATOR_HOST&&process.env.FIREBASE_AUTH_EMULATOR_HOST&&process.env.FUNCTIONS_EMULATOR_HOST);
const host=value=>{const [h,p]=value.split(':');assert.ok(['127.0.0.1','localhost'].includes(h));return [h,+p];};
test('ADDRESS real callables publish confirmed address publicly, keep direct address private, update and remove without quota duplication',{skip:!enabled,timeout:240000},async()=>{
 const stamp=Date.now(),projectId='demo-foundi',root=adminApp({projectId},'address-admin-'+stamp),db=adminDb(root),auth=adminAuth(root),apps=[],uids=[];
 async function client(name){
  const app=initializeApp({projectId,apiKey:'emulator-only',appId:'address-'+name},'address-'+name+stamp);apps.push(app);
  const a=getAuth(app);connectAuthEmulator(a,'http://'+process.env.FIREBASE_AUTH_EMULATOR_HOST,{disableWarnings:true});
  if(name!=='guest'){
   const email=`address.${name}.${stamp}@example.test`,password='Emulator-Password42!';
   const u=await auth.createUser({email,password,emailVerified:true});uids.push(u.uid);await signInWithEmailAndPassword(a,email,password);
  }
  const d=getFirestore(app);connectFirestoreEmulator(d,...host(process.env.FIRESTORE_EMULATOR_HOST));
  const f=getFunctions(app,'europe-west1');connectFunctionsEmulator(f,...host(process.env.FUNCTIONS_EMULATOR_HOST));
  return {uid:a.currentUser?.uid,db:d,call:(name,data={})=>httpsCallable(f,name)(data).then(r=>r.data)};
 }
 try{
  const owner=await client('owner'),pro=await client('pro'),other=await client('other'),guest=await client('guest');
  await db.doc('referenceData/professionalOnboarding').set({enabled:true,categories:[{id:'services',label:'Services',specialties:[{id:'plomberie',label:'Plomberie'}]}],zones:[{id:'rennes',label:'Rennes',countryCode:'FR',zoneType:'commune'}]});
  await db.doc(`users/${owner.uid}`).set({fullName:'Auteur de recette'});
  await db.doc(`professionalProfiles/${pro.uid}`).set({status:'approved',businessName:'Atelier de recette',categoryIds:['services'],specialtyIds:['plomberie'],zoneIds:['rennes']});
  const id=db.collection('requests').doc().id,directId=db.collection('requests').doc().id;
  const address={line:'10 rue des Ateliers, 35000 Rennes, France',countryCode:'FR',confirmed:true};
  const draft={categoryId:'services',specialtyId:'plomberie',zoneId:'rennes',title:'Réparer une fuite',description:'Une fuite sous mon évier nécessite une réparation.',budget:null,interventionAddress:address};
  assert.deepEqual(await owner.call('getRequestAddressCapabilities'),{version:1,supported:true});
  await assert.rejects(guest.call('getRequestAddressCapabilities'),e=>e.code==='functions/unauthenticated');
  await assert.rejects(owner.call('publishRequest',{requestId:id,request:{...draft,interventionAddress:{...address,confirmed:false}}}),e=>e.code==='functions/invalid-argument');
  assert.equal((await db.doc('requests/'+id).get()).exists,false);
  const result=await owner.call('publishRequest',{requestId:id,request:draft});assert.equal(result.interventionAddressSaved,true);
  const published=(await getDoc(doc(guest.db,'requests/'+id))).data();assert.deepEqual(published.interventionAddress,{line:address.line,countryCode:'FR'});
  assert.equal(published.interventionAddress.confirmed,undefined);assert.equal(published.clientUid,undefined);
  await assert.rejects(setDoc(doc(owner.db,'requests/'+id),published),e=>e.code==='permission-denied');
  assert.equal((await owner.call('publishRequest',{requestId:id,request:draft})).interventionAddressSaved,true);
  assert.equal((await db.doc(`requestPublicationLimits/${owner.uid}`).get()).data().createdAtMs.length,1);
  await assert.rejects(other.call('manageRequest',{requestId:id,action:'edit',expectedRevision:result.createdAt,request:draft}),e=>e.code==='functions/permission-denied');
  const edit=await owner.call('manageRequest',{requestId:id,action:'edit',expectedRevision:result.createdAt,request:{...draft,interventionAddress:{...address,line:'12 rue des Ateliers, 35000 Rennes, France'}}});
  assert.equal((await getDoc(doc(guest.db,'requests/'+id))).data().interventionAddress.line,'12 rue des Ateliers, 35000 Rennes, France');
  await owner.call('manageRequest',{requestId:id,action:'edit',expectedRevision:edit.updatedAt,request:{...draft,interventionAddress:null}});
  assert.equal((await getDoc(doc(guest.db,'requests/'+id))).data().interventionAddress,undefined);
  await assert.rejects(owner.call('publishDirectRequest',{requestId:directId,professionalId:pro.uid,request:draft}),e=>e.code==='functions/resource-exhausted');
  // Advance the quota fixture instead of sleeping; the real 60-second guard remains enabled.
  await db.doc(`requestPublicationLimits/${owner.uid}`).update({createdAtMs:[Date.now()-61000]});
  const direct=await owner.call('publishDirectRequest',{requestId:directId,professionalId:pro.uid,request:draft});assert.equal(direct.interventionAddressSaved,true);
  assert.equal((await db.doc('requests/'+directId).get()).exists,false);
  assert.equal((await getDoc(doc(pro.db,'directRequests/'+directId))).data().interventionAddress.line,address.line);
  for(const c of [guest,other])await assert.rejects(getDoc(doc(c.db,'directRequests/'+directId)),e=>e.code==='permission-denied');
  await owner.call('manageRequest',{requestId:directId,action:'delete'});
  assert.equal((await db.doc('directRequests/'+directId).get()).data().interventionAddress,undefined);
  // Address stays out of notification payloads and conversation snapshots.
  for(const c of ['notificationOutbox','conversations']){
   const rows=await db.collection(c).get();assert.ok(rows.docs.every(d=>!JSON.stringify(d.data()).includes(address.line)&&!JSON.stringify(d.data()).includes('12 rue des Ateliers, 35000 Rennes, France')));
  }
 }finally{
  await Promise.all(apps.map(deleteApp));await Promise.all(uids.map(uid=>auth.deleteUser(uid)));await deleteAdmin(root);
 }
});
