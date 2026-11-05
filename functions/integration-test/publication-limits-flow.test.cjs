const {test}=require('node:test'),assert=require('node:assert/strict');
const {initializeApp,deleteApp}=require('firebase-admin/app');
const {getFirestore}=require('firebase-admin/firestore');
const {getAuth:adminAuth}=require('firebase-admin/auth');
const {createRequestService}=require('../src/request-service');
const enabled=!!(process.env.FIRESTORE_EMULATOR_HOST&&process.env.FIREBASE_AUTH_EMULATOR_HOST);
const day=86400000;
const catalog={enabled:true,categories:[{id:'c',label:'Catégorie',specialties:[{id:'s',label:'Spécialité'}]}],zones:[{id:'z',label:'Zone'}]};
const request={categoryId:'c',specialtyId:'s',zoneId:'z',title:'Publication sécurisée',description:'Demande créée uniquement dans les émulateurs.',budget:null};
const quota=(db,uid)=>db.doc(`requestPublicationLimits/${uid}`);

test('V9.2 real callable uses current Auth verification and preserves idempotence, ownership and existing management',{skip:!enabled||!process.env.FUNCTIONS_EMULATOR_HOST,timeout:150000},async()=>{
 const {initializeApp:clientApp,deleteApp:deleteClient}=require('firebase/app');
 const {getAuth,connectAuthEmulator,signInWithEmailAndPassword}=require('firebase/auth');
 const {getFunctions,connectFunctionsEmulator,httpsCallable}=require('firebase/functions');
 const app=initializeApp({projectId:'demo-foundi'},'publication-auth-'+Date.now()),db=getFirestore(app),auth=adminAuth(app),users=[],apps=[];
 const pair=s=>{const[h,p]=s.split(':');return[h,Number(p)];};
 async function client(name,{verified=false,guest=false}={}){
  const stamp=Date.now(),email=`v92.${name}.${stamp}@example.test`,password='Emulated-Publication-V92-Password42!';
  let user;
  if(!guest){user=await auth.createUser({email,password,emailVerified:verified});users.push(user.uid);}
  const app=clientApp({projectId:'demo-foundi',apiKey:'emulator-only',appId:'v92-'+name},name+stamp);apps.push(app);
  const a=getAuth(app);connectAuthEmulator(a,'http://'+process.env.FIREBASE_AUTH_EMULATOR_HOST,{disableWarnings:true});
  if(user)await signInWithEmailAndPassword(a,email,password);
  const functions=getFunctions(app,'europe-west1');connectFunctionsEmulator(functions,...pair(process.env.FUNCTIONS_EMULATOR_HOST));
  return{uid:user?.uid,call:(name,data)=>httpsCallable(functions,name)(data).then(r=>r.data)};
 }
 const id=()=>db.collection('unused').doc().id;
 try{
  await db.doc('referenceData/professionalOnboarding').set(catalog);
  const guest=await client('guest',{guest:true}),owner=await client('owner'),other=await client('other',{verified:true});
  const rid=id();
  await assert.rejects(guest.call('publishRequest',{requestId:rid,request}),e=>e.code==='functions/unauthenticated');
  await db.doc('users/'+owner.uid).set({registrationConfirmed:true,emailVerified:true});
  await assert.rejects(owner.call('publishRequest',{requestId:rid,request:{...request,emailVerified:true,registrationConfirmed:true}}),e=>e.code==='functions/failed-precondition'&&e.message.includes('Vérifie ton adresse e-mail'));
  assert.equal((await quota(db,owner.uid).get()).exists,false);assert.equal((await db.doc('requests/'+rid).get()).exists,false);
  // No client token refresh: Auth.getUser must decide from the current server account.
  await auth.updateUser(owner.uid,{emailVerified:true});
  const [first,repeated]=await Promise.all([owner.call('publishRequest',{requestId:rid,request}),owner.call('publishRequest',{requestId:rid,request})]);
  assert.deepEqual(first,repeated);
  const initial=(await quota(db,owner.uid).get()).data();assert.deepEqual(initial.createdAtMs,[first.createdAt]);
  assert.equal((await db.doc('requests/'+rid).get()).data().status,'published');
  await assert.rejects(owner.call('publishRequest',{requestId:id(),request}),e=>e.code==='functions/resource-exhausted');
  assert.deepEqual((await quota(db,owner.uid).get()).data(),initial);
  const bad=id();await assert.rejects(other.call('publishRequest',{requestId:bad,request:{...request,budget:-1}}),e=>e.code==='functions/invalid-argument');
  assert.equal((await quota(db,other.uid).get()).exists,false);
  await db.doc('referenceData/professionalOnboarding').update({enabled:false});
  await assert.rejects(other.call('publishRequest',{requestId:bad,request}),e=>e.code==='functions/failed-precondition');
  assert.equal((await quota(db,other.uid).get()).exists,false);
  assert.deepEqual(await owner.call('publishRequest',{requestId:rid,request:null}),first);
  await db.doc('referenceData/professionalOnboarding').update({enabled:true});
  await assert.rejects(other.call('manageRequest',{requestId:rid,action:'close'}),e=>e.code==='functions/permission-denied');
  await auth.updateUser(owner.uid,{emailVerified:false});
  await assert.rejects(owner.call('publishRequest',{requestId:id(),request}),e=>e.code==='functions/failed-precondition');
  await owner.call('manageRequest',{requestId:rid,action:'edit',request:{...request,title:'Titre modifié'},expectedRevision:first.createdAt});
  await owner.call('manageRequest',{requestId:rid,action:'close'});
  await owner.call('manageRequest',{requestId:rid,action:'delete'});
  assert.deepEqual((await quota(db,owner.uid).get()).data(),initial);
  assert.equal((await db.doc(`userRequests/${owner.uid}/items/${rid}`).get()).data().status,'deleted');
  await auth.updateUser(other.uid,{disabled:true});
  await assert.rejects(other.call('publishRequest',{requestId:bad,request}),e=>['functions/permission-denied','functions/unauthenticated'].includes(e.code));
  assert.equal((await quota(db,other.uid).get()).exists,false);
 }finally{await Promise.all(users.map(uid=>auth.deleteUser(uid)));await Promise.all(apps.map(deleteClient));await deleteApp(app);}
});

test('V9.2 real concurrent Firestore transactions cannot overspend cooldown, daily or weekly quota',{skip:!enabled,timeout:180000},async()=>{
 const app=initializeApp({projectId:'demo-foundi-publication-races'},'publication-races-'+Date.now()),db=getFirestore(app);
 let now=10*day;
 const store={transaction:op=>db.runTransaction(tx=>op({get:async p=>(await tx.get(db.doc(p))).data(),set:(p,v)=>tx.set(db.doc(p),v)}),{maxAttempts:10})};
 const auth={getUser:async()=>({disabled:false,emailVerified:true})};
 const service=createRequestService({auth,store,clock:()=>now});
 const id=()=>db.collection('unused').doc().id;
 async function race(uid,seed){
  if(seed)await quota(db,uid).set({schemaVersion:92,createdAtMs:seed});
  const ids=[id(),id()];
  const jobs=await Promise.allSettled(ids.map(rid=>service.publish(uid,rid,request)));
  assert.equal(jobs.filter(r=>r.status==='fulfilled').length,1);
  assert.equal(jobs.find(r=>r.status==='rejected').reason.code,'resource-exhausted');
  const winner=jobs.find(r=>r.status==='fulfilled').value;
  assert.deepEqual((await quota(db,uid).get()).data().createdAtMs,[...(seed||[]),now]);
  for(let i=0;i<ids.length;i++){
   for(const path of [`requests/${ids[i]}`,`userRequests/${uid}/items/${ids[i]}`,`requestOwnership/${ids[i]}`])assert.equal((await db.doc(path).get()).exists,jobs[i].status==='fulfilled');
  }
  return winner;
 }
 try{
  await db.doc('referenceData/professionalOnboarding').set(catalog);
  const first=await race('cooldown');
  const oldQuota=(await quota(db,'cooldown').get()).data();
  now+=8*day;
  await db.doc('referenceData/professionalOnboarding').update({enabled:false});
  assert.deepEqual(await service.publish('cooldown',first.id,null),first);
  assert.deepEqual((await quota(db,'cooldown').get()).data(),oldQuota);
  await db.doc('referenceData/professionalOnboarding').update({enabled:true});
  await race('daily',Array.from({length:4},(_,i)=>now-(4-i)*60000));
  await race('weekly',Array.from({length:19},(_,i)=>now-(19-i)*6*60*60000));
  await service.publish('independent',id(),request);
  assert.equal((await quota(db,'independent').get()).data().createdAtMs.length,1);
 }finally{await deleteApp(app);}
});

test('V9.2 real Firestore rolling boundaries and pruning use the injected server clock',{skip:!enabled,timeout:120000},async()=>{
 const app=initializeApp({projectId:'demo-foundi-publication-boundaries'},'publication-boundaries-'+Date.now()),db=getFirestore(app);
 let now=10*day;
 const store={transaction:op=>db.runTransaction(tx=>op({get:async p=>(await tx.get(db.doc(p))).data(),set:(p,v)=>tx.set(db.doc(p),v)}))};
 const service=createRequestService({store,auth:{getUser:async()=>({disabled:false,emailVerified:true})},clock:()=>now});
 const id=()=>db.collection('unused').doc().id;
 try{
  await db.doc('referenceData/professionalOnboarding').set(catalog);
  const start=now;
  await service.publish('minute',id(),request);now=start+59999;
  await assert.rejects(service.publish('minute',id(),request),e=>e.code==='resource-exhausted');
  now=start+60000;await service.publish('minute',id(),request);
  const daily=Array.from({length:5},(_,i)=>start+i*60000);
  await quota(db,'day').set({schemaVersion:92,createdAtMs:daily});now=start+day-1;
  await assert.rejects(service.publish('day',id(),request),e=>e.code==='resource-exhausted');
  now=start+day;await service.publish('day',id(),request);
  const weekly=Array.from({length:20},(_,i)=>start+Math.floor(i/5)*day+(i%5)*60000);
  await quota(db,'week').set({schemaVersion:92,createdAtMs:weekly});now=start+7*day-1;
  await assert.rejects(service.publish('week',id(),request),e=>e.code==='resource-exhausted');
  now=start+7*day;await service.publish('week',id(),request);
  const recent=(await quota(db,'week').get()).data().createdAtMs;assert.equal(recent.length,20);assert.ok(!recent.includes(start));
  now=start+15*day;await service.publish('week',id(),request);
  assert.deepEqual((await quota(db,'week').get()).data().createdAtMs,[now]);
 }finally{await deleteApp(app);}
});
