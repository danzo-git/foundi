const {test}=require('node:test');const assert=require('node:assert/strict');
const {initializeApp,deleteApp}=require('firebase/app');
const {getAuth,connectAuthEmulator,signInWithEmailAndPassword}=require('firebase/auth');
const {getFirestore,connectFirestoreEmulator,doc,collection,getDoc,getDocs,query,where,orderBy,limit,setDoc,updateDoc}=require('firebase/firestore');
const {getFunctions,connectFunctionsEmulator,httpsCallable}=require('firebase/functions');
const {initializeApp:adminApp,deleteApp:deleteAdmin}=require('firebase-admin/app');const {getAuth:adminAuth}=require('firebase-admin/auth');const {getFirestore:adminDb}=require('firebase-admin/firestore');
const enabled=!!(process.env.FIREBASE_AUTH_EMULATOR_HOST&&process.env.FIRESTORE_EMULATOR_HOST);const pair=s=>{const [h,p]=s.split(':');return [h,Number(p)];};
test('V7 real callables: private owner resolution, send exactly once, received/sent histories and immutable state',{skip:!enabled,timeout:180000},async()=>{
 const projectId='demo-foundi',stamp=Date.now(),admin=adminApp({projectId},'proposals-'+stamp),db=adminDb(admin),auth=adminAuth(admin),apps=[],users=[];
 async function client(name,signed=true){const app=initializeApp({projectId,apiKey:'emulator-only',appId:'v7-'+name},name+stamp);apps.push(app);const a=getAuth(app);connectAuthEmulator(a,'http://'+process.env.FIREBASE_AUTH_EMULATOR_HOST,{disableWarnings:true});let uid;
 if(signed){const email=`${name}.${stamp}@example.test`,password='Test-Password-123!';const u=await auth.createUser({email,password,emailVerified:true});uid=u.uid;users.push(uid);await signInWithEmailAndPassword(a,email,password);}
 const firestore=getFirestore(app);connectFirestoreEmulator(firestore,...pair(process.env.FIRESTORE_EMULATOR_HOST));const f=getFunctions(app,'europe-west1');connectFunctionsEmulator(f,...pair(process.env.FUNCTIONS_EMULATOR_HOST));return {uid,db:firestore,call:(name,data)=>httpsCallable(f,name)(data).then(r=>r.data)};}
 try{
  const a=await client('proposal-author'),b=await client('proposal-pro'),c=await client('proposal-third'),guest=await client('proposal-guest',false);
  await db.doc('referenceData/professionalOnboarding').set({enabled:true,categories:[{id:'c',label:'Services',specialties:[{id:'s',label:'Réparation'}]}],zones:[{id:'z',label:'Cocody'}]});
  for(const u of [a,b,c])await db.doc('professionalProfiles/'+u.uid).set({status:'approved',businessName:'Atelier de test'});
  const requestId=doc(collection(a.db,'requests')).id,request={title:'Demande test V7',description:'Description publique de test.',categoryId:'c',specialtyId:'s',zoneId:'z',budget:null};
  await a.call('publishRequest',{requestId,request});
  // Simulate an existing V5 publication with no new private lookup record.
  await db.doc('requestOwnership/'+requestId).delete();
  const proposal={description:'Je peux résoudre ce besoin avec un devis détaillé.',amount:45000,delay:'Sous trois jours'};
  await assert.rejects(guest.call('sendProposal',{requestId,proposal}),e=>e.code==='functions/unauthenticated');
  await assert.rejects(a.call('sendProposal',{requestId,proposal}),e=>e.code==='functions/permission-denied');
  await db.doc('professionalProfiles/'+c.uid).update({status:'pending'});await assert.rejects(c.call('sendProposal',{requestId,proposal}),e=>e.code==='functions/permission-denied');
  assert.equal((await b.call('proposalAccess',{requestId})).canSend,true);
  const [x,y]=await Promise.all([b.call('sendProposal',{requestId,proposal}),b.call('sendProposal',{requestId,proposal})]);assert.equal(x.id,y.id);assert.equal(x.status,'sent');assert.equal(x.clientUid,a.uid);
  assert.equal((await b.call('proposalAccess',{requestId})).proposalId,x.id);
  assert.equal((await getDoc(doc(a.db,`userRequests/${a.uid}/items/${requestId}`))).data().proposalCount,1);
  assert.equal('proposalCount' in (await getDoc(doc(guest.db,'requests/'+requestId))).data(),false);
  assert.equal((await getDocs(query(collection(b.db,'proposals'),where('professionalUid','==',b.uid),orderBy('createdAt','desc'),limit(30)))).size,1);
  assert.equal((await getDocs(query(collection(a.db,'proposals'),where('clientUid','==',a.uid),where('requestId','==',requestId),orderBy('createdAt','desc'),limit(30)))).size,1);
  assert.equal((await getDoc(doc(a.db,'proposals/'+x.id))).data().description,proposal.description);
  await assert.rejects(getDoc(doc(c.db,'proposals/'+x.id)),e=>e.code==='permission-denied');await assert.rejects(getDoc(doc(guest.db,'proposals/'+x.id)),e=>e.code==='permission-denied');
  await assert.rejects(setDoc(doc(b.db,'proposals/forged'),{...x,status:'accepted'}),e=>e.code==='permission-denied');await assert.rejects(updateDoc(doc(a.db,'proposals/'+x.id),{status:'accepted'}),e=>e.code==='permission-denied');
  await a.call('manageRequest',{requestId,action:'close'});await db.doc('professionalProfiles/'+c.uid).update({status:'approved'});await assert.rejects(c.call('sendProposal',{requestId,proposal}),e=>e.code==='functions/failed-precondition');
  await a.call('manageRequest',{requestId,action:'delete'});assert.equal((await getDoc(doc(b.db,'proposals/'+x.id))).exists(),true);
  await db.doc('professionalProfiles/'+b.uid).update({status:'suspended'});assert.equal((await a.call('proposalApproval',{proposalId:x.id})).approved,false);await assert.rejects(c.call('proposalApproval',{proposalId:x.id}),e=>e.code==='functions/permission-denied');
 }finally{await Promise.all(users.map(uid=>auth.deleteUser(uid)));await Promise.all(apps.map(deleteApp));await deleteAdmin(admin);}
});
