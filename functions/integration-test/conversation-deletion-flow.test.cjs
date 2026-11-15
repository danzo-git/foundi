const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const {initializeApp,deleteApp}=require('firebase-admin/app'),{getFirestore}=require('firebase-admin/firestore');
const {createConversationDeletionService,createConversationDeletionStore}=require('../src/conversation-deletion-service');
const {createNotificationService}=require('../src/notification-service');
const {initializeTestEnvironment,assertFails,assertSucceeds}=require('@firebase/rules-unit-testing');
const {doc,getDoc,getDocs,setDoc,deleteDoc,collection,query,where,limit}=require('firebase/firestore');
const enabled=!!process.env.FIRESTORE_EMULATOR_HOST;
const id='DeleteConversation000001',other='DeleteConversation000002';
test('DELETE own inbox only, unread cleanup, no resurrection or push, SDK rules and preserved counterpart history',{skip:!enabled,timeout:180000},async()=>{
 const projectId='demo-foundi-conversation-delete',app=initializeApp({projectId},'conversation-delete-'+Date.now()),db=getFirestore(app);
 const env=await initializeTestEnvironment({projectId,firestore:{rules:fs.readFileSync(path.join(__dirname,'../../firestore.rules'),'utf8')}});
 const auth={getUser:async()=>({emailVerified:true,disabled:false})},sent=[];
 const deletion=createConversationDeletionService({store:createConversationDeletionStore(db),auth}),notifications=createNotificationService({db,auth,messaging:{send:async value=>{sent.push(value);return 'fake-delivered';}}});
 const get=async p=>(await db.doc(p).get()).data(),count=async uid=>(await get(`users/${uid}/messageState/inbox`))?.unreadCount||0;
 async function receive(cid,mid,at,senderUid='pro'){
  const value={type:'text',senderUid,createdAt:at,text:'Message de recette'};await db.doc(`conversations/${cid}/messages/${mid}`).set(value);await notifications.message(cid,mid,value);
 }
 try{
  for(const cid of [id,other])await db.doc(`conversations/${cid}`).set({clientUid:'client',professionalUid:'pro',status:'active',proposalStatus:'retained',requestId:'DeleteRequestIdentifier01'});
  await notifications.register('client',{deviceId:'device',token:'emulator-fake-token-not-a-real-device-12345',platform:'android'});
  for(let i=0;i<3;i++)await receive(id,'message'+i,i+1);for(let i=0;i<2;i++)await receive(other,'other'+i,i+5);
  assert.equal(await count('client'),5);
  const original=await get(`conversations/${id}`),queued=(await db.collection('notificationOutbox').where('conversationId','==',id).get()).docs;
  await deletion.remove('client',{conversationId:id,viewerUid:'client'});assert.equal(await count('client'),2);assert.deepEqual(await get(`conversations/${id}`),original);
  assert.equal((await db.collection(`conversations/${id}/messages`).get()).size,3);assert.equal((await db.doc(`users/pro/deletedConversations/${id}`).get()).exists,false);
  await receive(id,'late-trigger',0);await receive(id,'new-message',Date.now());assert.equal(await count('client'),2);
  for(const row of queued){await notifications.deliver(row.id);assert.equal((await row.ref.get()).data().state,'skipped');await assert.rejects(notifications.resolve('client',row.id),e=>e.code==='not-found');}
  assert.equal(sent.length,0);
  const open=(await db.collection('notificationOutbox').where('conversationId','==',other).get()).docs[0];await notifications.deliver(open.id);assert.equal(sent.length,1);
  await receive(id,'outgoing',Date.now()+1,'client');assert.equal(await count('pro'),1);
  const owner=env.authenticatedContext('client').firestore();
  await assertSucceeds(getDoc(doc(owner,`users/client/deletedConversations/${id}`)));
  await assertSucceeds(getDocs(query(collection(owner,'users/client/deletedConversations'),where('__name__','in',[id]),limit(30))));
  await assertSucceeds(getDoc(doc(owner,'users/client/conversationState/inbox')));
  await assertFails(setDoc(doc(owner,`users/client/deletedConversations/${other}`),{deletedAt:1}));await assertFails(deleteDoc(doc(owner,`users/client/deletedConversations/${id}`)));
  await assertFails(deleteDoc(doc(owner,`conversations/${id}`)));
  for(const context of [env.unauthenticatedContext(),env.authenticatedContext('pro'),env.authenticatedContext('admin',{admin:true})])await assertFails(getDoc(doc(context.firestore(),`users/client/deletedConversations/${id}`)));
  await assertSucceeds(getDoc(doc(env.authenticatedContext('pro').firestore(),`conversations/${id}`)));
  await db.recursiveDelete(db.doc('users/client'));await deletion.cleanup('client',id);assert.equal((await db.doc('users/client').listCollections()).length,0);
 }finally{await env.cleanup();await deleteApp(app);}
});

test('DELETE authenticated callable and durable background cleanup finish 450 unread messages after caller disconnects',{skip:!enabled||!process.env.FUNCTIONS_EMULATOR_HOST||!process.env.FIREBASE_AUTH_EMULATOR_HOST,timeout:180000},async()=>{
 const {getAuth:adminAuth}=require('firebase-admin/auth');
 const {initializeApp:clientApp,deleteApp:deleteClient}=require('firebase/app'),{getAuth,connectAuthEmulator,signInWithEmailAndPassword}=require('firebase/auth'),{getFunctions,connectFunctionsEmulator,httpsCallable}=require('firebase/functions');
 const stamp=Date.now(),root=initializeApp({projectId:'demo-foundi'},'delete-callable-'+stamp),db=getFirestore(root),auth=adminAuth(root),email=`delete.${stamp}@example.test`,password='Emulator-Password42!';
 let client,user;
 try{
  user=await auth.createUser({email,password,emailVerified:true});client=clientApp({projectId:'demo-foundi',apiKey:'emulator-only',appId:'delete-test'},'delete-client-'+stamp);
  const a=getAuth(client);connectAuthEmulator(a,'http://'+process.env.FIREBASE_AUTH_EMULATOR_HOST,{disableWarnings:true});await signInWithEmailAndPassword(a,email,password);
  const f=getFunctions(client,'europe-west1'),[host,port]=process.env.FUNCTIONS_EMULATOR_HOST.split(':');connectFunctionsEmulator(f,host,+port);
  const cid=db.collection('conversations').doc().id;
  await db.doc(`conversations/${cid}`).set({clientUid:user.uid,professionalUid:'fixture-pro',status:'read_only'});
  const batch=db.batch();for(let i=0;i<450;i++)batch.set(db.doc(`users/${user.uid}/messageInbox/message${i}`),{conversationId:cid,createdAt:i+1,unread:true});batch.set(db.doc(`users/${user.uid}/messageState/inbox`),{unreadCount:450,schemaVersion:91});await batch.commit();
  const call=data=>httpsCallable(f,'deleteConversation')(data).then(r=>r.data);
  await assert.rejects(call({conversationId:cid,viewerUid:'another-account'}),e=>e.code==='functions/permission-denied');
  assert.deepEqual(await call({conversationId:cid,viewerUid:user.uid}),{deleted:true});
  // No second client call: the durable marker drives all remaining pages.
  let done=false;
  for(let i=0;i<150;i++){
   const [marker,state]=await db.getAll(db.doc(`users/${user.uid}/deletedConversations/${cid}`),db.doc(`users/${user.uid}/messageState/inbox`));
   if(marker.data()?.cleanupPending===false&&state.data()?.unreadCount===0){done=true;break;}
   await new Promise(resolve=>setTimeout(resolve,200));
  }
  assert.ok(done,'background worker must finish remaining unread pages');assert.equal((await db.collection(`users/${user.uid}/messageInbox`).where('unread','==',true).get()).empty,true);
  assert.equal((await db.doc(`conversations/${cid}`).get()).exists,true);
 }finally{if(client)await deleteClient(client);if(user)await auth.deleteUser(user.uid);await deleteApp(root);}
});
