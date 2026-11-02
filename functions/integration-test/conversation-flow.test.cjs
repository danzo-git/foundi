const {test}=require('node:test'),assert=require('node:assert/strict');
const {initializeApp,deleteApp}=require('firebase/app');
const {getAuth,connectAuthEmulator,signInWithEmailAndPassword}=require('firebase/auth');
const {getFirestore,connectFirestoreEmulator,doc,collection,getDoc,getDocs,query,where,orderBy,limit,setDoc,updateDoc,onSnapshot}=require('firebase/firestore');
const {getFunctions,connectFunctionsEmulator,httpsCallable}=require('firebase/functions');
const {initializeApp:initializeAdmin,deleteApp:deleteAdmin}=require('firebase-admin/app');
const {getAuth:adminAuth}=require('firebase-admin/auth'),{getFirestore:adminDb,Timestamp}=require('firebase-admin/firestore');
const {createConversationService}=require('../src/conversation-service');
const {createRequestService}=require('../src/request-service');
const {createProposalService}=require('../src/proposal-service');
const {execFile}=require('node:child_process'),{promisify}=require('node:util'),fs=require('node:fs'),path=require('node:path'),os=require('node:os');
const enabled=!!(process.env.FIREBASE_AUTH_EMULATOR_HOST&&process.env.FIRESTORE_EMULATOR_HOST);
const pair=s=>{const [h,p]=s.split(':');return [h,Number(p)];};
test('V8.1 A01-A10/A12: one client, three pros, multi-chat live, real transaction contention, decisions, closure and privacy',{skip:!enabled,timeout:300000},async()=>{
 const projectId='demo-foundi',stamp=Date.now(),admin=initializeAdmin({projectId},'v81-'+stamp),auth=adminAuth(admin),db=adminDb(admin),users=[],apps=[],stops=[];let count=0;
 async function client(name,credentials){
  const app=initializeApp({projectId,apiKey:'emulator-only',appId:'v81-'+name},name+stamp+(count++));apps.push(app);
  const a=getAuth(app);connectAuthEmulator(a,'http://'+process.env.FIREBASE_AUTH_EMULATOR_HOST,{disableWarnings:true});
  let identity=credentials;if(!identity){const email=`${name}.${stamp}@example.test`,password='Local-V81-Password42!';const u=await auth.createUser({email,password,emailVerified:true});users.push(u.uid);identity={uid:u.uid,email,password};}
  await signInWithEmailAndPassword(a,identity.email,identity.password);const firestore=getFirestore(app);connectFirestoreEmulator(firestore,...pair(process.env.FIRESTORE_EMULATOR_HOST));
  const functions=getFunctions(app,'europe-west1');connectFunctionsEmulator(functions,...pair(process.env.FUNCTIONS_EMULATOR_HOST));
  return {uid:identity.uid,credentials:identity,db:firestore,call:(name,data)=>httpsCallable(functions,name)(data).then(r=>r.data)};
 }
 function live(c,id){return new Promise((resolve,reject)=>{let stop;const timer=setTimeout(()=>{stop?.();reject(Error('Live message timeout'));},30000);stop=onSnapshot(query(collection(c.db,`conversations/${id}/messages`),orderBy('createdAt','asc'),limit(30)),s=>{if(s.size===2){clearTimeout(timer);stop();resolve(s.docs.map(d=>d.data()));}},reject);stops.push(()=>{clearTimeout(timer);stop?.();});});}
 const message=(id,text)=>({conversationId:id,messageId:db.collection('ids').doc().id,text});
 const decision=(rid,pid,action,expected=null)=>({requestId:rid,proposalId:pid,action,expectedRetainedProposalId:expected,decisionId:db.collection('ids').doc().id});
 try{
  const a=await client('v81-author'),b=await client('v81-pro-b'),c=await client('v81-pro-c'),d=await client('v81-pro-d');
  for(const [pro,name]of [[b,'Atelier B'],[c,'Atelier C'],[d,'Atelier D']])await db.doc('professionalProfiles/'+pro.uid).set({status:'approved',businessName:name,categoryIds:['c'],specialtyIds:['s'],zoneIds:['z']});
  await db.doc('users/'+a.uid).set({fullName:'Client V81'});
  await db.doc('referenceData/professionalOnboarding').set({enabled:true,categories:[{id:'c',label:'Service',specialties:[{id:'s',label:'Réparation'}]}],zones:[{id:'z',label:'Cocody'}]});
  const rid=db.collection('requests').doc().id;await a.call('publishRequest',{requestId:rid,request:{title:'Demande V8.1',description:'Une demande pour comparer plusieurs professionnels.',categoryId:'c',specialtyId:'s',zoneId:'z',budget:null}});
  const proposal={description:'Une proposition professionnelle détaillée.',amount:null,delay:''};
  const pb=await b.call('sendProposal',{requestId:rid,proposal}),pc=await c.call('sendProposal',{requestId:rid,proposal});
  await assert.rejects(b.call('selectProposal',{requestId:rid,proposalId:pb.id}),e=>e.code==='functions/permission-denied');
  const [ob,oc,again]=await Promise.all([a.call('selectProposal',{requestId:rid,proposalId:pb.id}),a.call('selectProposal',{requestId:rid,proposalId:pc.id}),a.call('selectProposal',{requestId:rid,proposalId:pb.id})]);
  assert.equal(ob.conversationId,pb.id);assert.equal(oc.conversationId,pc.id);assert.equal(again.conversationId,ob.conversationId);assert.notEqual(pb.id,pc.id);
  assert.equal((await getDoc(doc(a.db,`userRequests/${a.uid}/items/${rid}`))).data().status,'published');
  const feed=await getDocs(query(collection(d.db,'requests'),where('status','==','published'),orderBy('createdAt','desc'),limit(30)));assert.ok(feed.docs.some(x=>x.id===rid));
  const opportunity=await d.call('listOpportunities',{categoryIds:['c'],specialtyIds:['s'],zoneIds:['z']});assert.ok(opportunity.items.some(x=>x.id===rid));
  await assert.rejects(getDoc(doc(c.db,'conversations/'+pb.id)),e=>e.code==='permission-denied');await assert.rejects(getDocs(query(collection(c.db,`conversations/${pb.id}/messages`),limit(30))),e=>e.code==='permission-denied');
  await assert.rejects(setDoc(doc(b.db,`conversations/${pb.id}/messages/forged`),{senderUid:a.uid,text:'Falsifié',createdAt:0}),e=>e.code==='permission-denied');await assert.rejects(updateDoc(doc(a.db,'conversations/'+pb.id),{professionalUid:c.uid}),e=>e.code==='permission-denied');
  const al=live(a,pb.id),bl=live(b,pb.id),m=message(pb.id,'Bonjour depuis le client');
  await Promise.all([a.call('sendConversationMessage',m),a.call('sendConversationMessage',m)]);await b.call('sendConversationMessage',message(pb.id,'Bonjour depuis le professionnel'));
  const [ar,br]=await Promise.all([al,bl]);assert.deepEqual(ar,br);assert.equal(ar.length,2);assert.ok(ar[0].createdAt<ar[1].createdAt);
  // Actual concurrent Firestore transactions, independent of the serialized Functions debugger.
  const store={get:async p=>(await db.doc(p).get()).data(),transaction:op=>db.runTransaction(t=>op({get:async p=>(await t.get(db.doc(p))).data(),set:(p,v)=>t.set(db.doc(p),v),conversationsForRequest:async id=>(await t.get(db.collection('conversations').where('requestId','==',id))).docs.map(d=>({id:d.id,...d.data()}))}))};
  const service=createConversationService({auth,store});
  const race=await Promise.allSettled([service.decide(a.uid,decision(rid,pb.id,'retain')),service.decide(a.uid,decision(rid,pc.id,'retain'))]);assert.equal(race.filter(r=>r.status==='fulfilled').length,1);assert.equal(race.find(r=>r.status==='rejected').reason.code,'failed-precondition');
  const held=(await db.doc(`userRequests/${a.uid}/items/${rid}`).get()).data().retainedProposalId,other=held===pb.id?pc.id:pb.id;
  await assert.rejects(a.call('decideProposal',decision(rid,other,'retain')),e=>e.code==='functions/failed-precondition');
  const replace=decision(rid,other,'retain',held);await a.call('decideProposal',replace);assert.equal((await a.call('decideProposal',replace)).alreadyDecided,true);
  assert.equal((await db.doc('proposals/'+held).get()).data().status,'discussing');assert.equal((await db.doc('proposals/'+other).get()).data().status,'retained');
  const pd=await d.call('sendProposal',{requestId:rid,proposal});assert.equal(pd.status,'sent');assert.equal((await getDoc(doc(d.db,'requests/'+rid))).data().status,'published');
  await assert.rejects(b.call('decideProposal',decision(rid,pb.id,'reject')),e=>e.code==='functions/permission-denied');
  const rejection={...decision(rid,other,'reject'),reason:'Une autre solution convient mieux'};await a.call('decideProposal',rejection);
  assert.equal((await db.doc(`userRequests/${a.uid}/items/${rid}`).get()).data().retainedProposalId,null);assert.equal((await db.doc('conversations/'+other).get()).data().status,'read_only');assert.equal((await db.doc('conversations/'+held).get()).data().status,'active');
  await assert.rejects(a.call('decideProposal',decision(rid,other,'retain')),e=>e.code==='functions/failed-precondition');await assert.rejects(a.call('sendConversationMessage',message(other,'Après refus')),e=>e.code==='functions/failed-precondition');
  const reopen=await client('v81-restart',b.credentials);assert.ok((await getDocs(query(collection(reopen.db,'conversations'),where('professionalUid','==',b.uid),orderBy('updatedAt','desc'),limit(30)))).docs.some(x=>x.id===pb.id));assert.equal((await getDocs(query(collection(reopen.db,`conversations/${pb.id}/messages`),orderBy('createdAt','desc'),limit(100)))).size,2);
  await a.call('manageRequest',{requestId:rid,action:'close'});assert.equal((await db.doc('conversations/'+held).get()).data().status,'active');await a.call('sendConversationMessage',message(held,'Après clôture volontaire'));
  await assert.rejects(d.call('sendProposal',{requestId:rid,proposal}),e=>e.code==='functions/failed-precondition');await assert.rejects(getDoc(doc(d.db,'requests/'+rid)),e=>e.code==='permission-denied');
  await a.call('manageRequest',{requestId:rid,action:'delete'});for(const id of [pb.id,pc.id]){assert.equal((await db.doc('conversations/'+id).get()).data().status,'read_only');await assert.rejects(a.call('sendConversationMessage',message(id,'Après suppression')),e=>e.code==='functions/failed-precondition');}
  const lifecycle=createRequestService({auth,store}),offers=createProposalService({auth,store}),raceRid=db.collection('requests').doc().id;
  await lifecycle.publish(a.uid,raceRid,{title:'Concurrence clôture',description:'Demande locale pour tester les transactions concurrentes.',categoryId:'c',specialtyId:'s',zoneId:'z',budget:null});
  const beforeClose=await offers.send(b.uid,raceRid,proposal);
  const repeated=await Promise.all([service.select(a.uid,{requestId:raceRid,proposalId:beforeClose.id}),service.select(a.uid,{requestId:raceRid,proposalId:beforeClose.id})]);assert.equal(repeated[0].conversationId,repeated[1].conversationId);
  const closeRace=await Promise.allSettled([lifecycle.manage(a.uid,raceRid,'close'),offers.send(d.uid,raceRid,proposal)]);assert.equal(closeRace[0].status,'fulfilled');if(closeRace[1].status==='rejected')assert.equal(closeRace[1].reason.code,'failed-precondition');
  assert.equal((await db.doc('requests/'+raceRid).get()).data().status,'closed');await assert.rejects(offers.send(c.uid,raceRid,proposal),e=>e.code==='failed-precondition');
  await service.send(b.uid,message(beforeClose.id,'Toujours possible après clôture'));
 }finally{stops.forEach(s=>s());await Promise.all(users.map(uid=>auth.deleteUser(uid)));await Promise.all(apps.map(deleteApp));await deleteAdmin(admin);}
});
test('A11: admin migration dry-run/apply/retry/rollback preserve real emulator messages and dates',{skip:!enabled,timeout:120000},async()=>{
 const admin=initializeAdmin({projectId:'demo-foundi'},'migration-'+Date.now()),db=adminDb(admin),folder=fs.mkdtempSync(path.join(os.tmpdir(),'foundi-v81-')),plan=path.join(folder,'backup.json');
 const execute=promisify(execFile),run=(file,args)=>execute(file,args,{timeout:45000}),script=path.join(__dirname,'../scripts/migrate-negotiation-v81.cjs');
 const rid=db.collection('requests').doc().id,pid='e'.repeat(64),uid='migration-client',pub={title:'Ancienne demande',status:'in_discussion',createdAt:1,updatedAt:2};
 try{
  await db.doc('requests/'+rid).set(pub);await db.doc(`userRequests/${uid}/items/${rid}`).set({...pub,selectedProposalId:pid,selectedProfessionalUid:'migration-pro',conversationId:rid});
  await db.doc('proposals/'+pid).set({requestId:rid,clientUid:uid,professionalUid:'migration-pro',status:'selected',conversationId:rid,createdAt:1,selectedAt:2});
  await db.doc('conversations/'+rid).set({requestId:rid,clientUid:uid,professionalUid:'migration-pro',selectedProposalId:pid,status:'active',createdAt:2,updatedAt:3,lastMessageAt:3,requestSnapshot:pub,testTimestamp:Timestamp.fromMillis(1234)});await db.doc(`conversations/${rid}/messages/keep`).set({text:'Conserver',createdAt:3,senderUid:uid});
  const base=[script,'--project','demo-foundi','--verbose'];const dry=await run(process.execPath,[...base,'--dry-run','--output',plan]);assert.equal(JSON.parse(dry.stdout).writes,0);assert.equal((await db.doc('requests/'+rid).get()).data().status,'in_discussion');
  await run(process.execPath,[...base,'--apply','--plan',plan]);assert.equal((await db.doc('requests/'+rid).get()).data().status,'published');assert.equal((await db.doc('requests/'+rid).get()).data().updatedAt,2);
  const repeat=await run(process.execPath,[...base,'--apply','--plan',plan]);assert.equal(JSON.parse(repeat.stdout).changed,0);
  assert.equal((await db.doc('conversations/'+rid).get()).data().testTimestamp.toMillis(),1234);
  const unchanged=(await db.doc('proposals/'+pid).get()).data();await db.doc('proposals/'+pid).update({description:'Edited after migration'});
  await assert.rejects(run(process.execPath,[...base,'--rollback','--plan',plan]));assert.equal((await db.doc('requests/'+rid).get()).data().status,'published');await db.doc('proposals/'+pid).set(unchanged);
  await run(process.execPath,[...base,'--rollback','--plan',plan]);assert.equal((await db.doc('requests/'+rid).get()).data().status,'in_discussion');assert.equal((await db.doc(`conversations/${rid}/messages/keep`).get()).data().text,'Conserver');
 }finally{await deleteAdmin(admin);fs.rmSync(folder,{recursive:true,force:true});}
});
