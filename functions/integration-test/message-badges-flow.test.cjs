const {test}=require('node:test'),assert=require('node:assert/strict');
const {initializeApp,deleteApp}=require('firebase-admin/app');
const {getFirestore,Timestamp}=require('firebase-admin/firestore');
const {createNotificationService}=require('../src/notification-service');
const {key}=require('../src/notification-policy');
const {migrate}=require('../scripts/migrate-message-badges-v91.cjs');
const enabled=!!process.env.FIRESTORE_EMULATOR_HOST;

test('V9.1 distinct 3+2 unread messages, multi-device cursors, reordered triggers, private contextual push and access checks',{skip:!enabled,timeout:180000},async()=>{
 const app=initializeApp({projectId:'demo-foundi-message-badges'},'badges-'+Date.now()),db=getFirestore(app),sent=[];
 const auth={getUser:async uid=>({disabled:uid==='disabled',emailVerified:true})};
 const deps={db,auth,messaging:{send:async p=>{sent.push(p);return 'sent';}}},service=createNotificationService(deps);
 const count=async(uid,type='messageState')=>(await db.doc(`users/${uid}/${type}/inbox`).get()).data()?.unreadCount || 0;
 const target=(conversationId,messageId)=>({conversationId,messageId});
 async function receive(chat,id,at,{type='text',text='Message privé',senderUid=chat==='ab'?'b':'c'}={}){
   const value={senderUid,type,text,createdAt:at,phoneNumber:'+2250700000000'};
   await db.doc(`conversations/${chat}/messages/${id}`).set(value);
   await Promise.all([service.message(chat,id,value),service.message(chat,id,value)]);
   return key(`messages/${chat}/${id}`,'a');
 }
 try{
  await db.recursiveDelete(db.collection('users'));await db.recursiveDelete(db.collection('conversations'));await db.recursiveDelete(db.collection('notificationOutbox'));
  await db.doc('conversations/ab').set({clientUid:'a',professionalUid:'b',status:'active'});
  await db.doc('conversations/ac').set({clientUid:'a',professionalUid:'c',status:'active'});
  await db.doc('professionalProfiles/b').set({businessName:'AutoLink CI'});
  for(let i=1;i<=3;i++)await receive('ab',`m${i}`,100+i);
  for(let i=1;i<=2;i++)await receive('ac',`m${i}`,200+i);
  for(let i=1;i<=2;i++)await service.emit({eventId:`business${i}`,type:'proposal.created',recipientUid:'a',actorUid:'b',resourceType:'requestProposals',resourceId:`request${i}`});
  assert.equal(await count('a'),5);assert.equal(await count('a','notificationState'),2);
  assert.equal((await db.collection('users/a/notifications').get()).size,2);
  assert.equal((await db.collection('users/b/messageInbox').get()).size,0);
  const restart=createNotificationService(deps);
  await Promise.all([service.markConversationRead('a',target('ab','m3')),restart.markConversationRead('a',target('ab','m3'))]);
  assert.equal(await count('a'),2);assert.equal(await count('a','notificationState'),2);
  await receive('ab','late',90);assert.equal(await count('a'),2);
  await db.doc('conversations/ab/messages/visible').set({senderUid:'b',type:'text',createdAt:104,text:'En direct'});
  await service.markConversationRead('a',target('ab','visible'));
  await service.message('ab','visible',{senderUid:'b',type:'text',createdAt:104});
  assert.equal(await count('a'),2);
  await db.doc('conversations/ac').update({status:'read_only',archivedReason:'proposal_rejected'});
  await service.markConversationRead('a',target('ac','m1'));assert.equal(await count('a'),1);
  for(const uid of ['d','b','admin'])await assert.rejects(service.markConversationRead(uid,target('ac','m2')),e=>e.code==='permission-denied');
  await assert.rejects(service.markConversationRead('a',{...target('ab','m3'),uid:'b'}),e=>e.code==='invalid-argument');
  await assert.rejects(service.markConversationRead('a',target('ab','missing')),e=>e.code==='not-found');
  await assert.rejects(service.markConversationRead('disabled',target('ab','m3')),e=>e.code==='permission-denied');
  // Outgoing messages increment only the recipient, never the authenticated author.
  const before=await count('a');await receive('ab','outgoing',105,{senderUid:'a'});assert.equal(await count('a'),before);assert.equal(await count('b'),1);
  await service.register('a',{deviceId:'phone',token:'emulated-token-a-123456789012345',platform:'android'});
  await db.doc('users/a/notificationPreferences/push').set({messages:true,messagePreview:true});
  const bodies={text:'Bonjour, vous êtes disponible demain ?',image:'📷 Photo',pdf:'📄 Document PDF',contact:'📞 Contact partagé'};
  for(const [type,body]of Object.entries(bodies)){
   const id=await receive('ab',type,300+sent.length,{type,text:bodies.text});
   await Promise.all([service.deliver(id),service.deliver(id)]);
   const payload=sent.at(-1);assert.deepEqual(payload.notification,{title:'AutoLink CI',body});
   assert.equal(payload.data.type,'chat_message');assert.equal(payload.data.conversationId,'ab');assert.equal(payload.data.messageId,type);
   assert.ok(!JSON.stringify(payload.data).includes('Bonjour'));assert.ok(!JSON.stringify(payload).includes('+225'));
   assert.deepEqual(await service.resolve('a',id),{resourceType:'conversation',resourceId:'ab'});
   await assert.rejects(service.resolve('d',id),e=>e.code==='not-found');
  }
  assert.equal(sent.length,4);
  await db.doc('users/a/notificationPreferences/push').set({messages:true,messagePreview:false});
  const hidden=await receive('ab','hidden',400,{text:'NEVER EXPOSE THIS CONTENT'});await service.deliver(hidden);
  assert.deepEqual(sent.at(-1).notification,{title:'AutoLink CI',body:'Nouveau message'});
  assert.ok(!JSON.stringify(sent.at(-1)).includes('NEVER EXPOSE'));
  await db.doc('professionalProfiles/b').delete();
  const fallback=await receive('ab','fallback',401);await service.deliver(fallback);
  assert.equal(sent.at(-1).notification.title,'Un utilisateur Foundi');
  await db.doc('users/a/notificationPreferences/push').set({messages:false,messagePreview:true});
  const muted=await receive('ab','muted',402),sentBefore=sent.length;await service.deliver(muted);assert.equal(sent.length,sentBefore);
  await db.doc('users/a/notificationPreferences/push').set({messages:true,messagePreview:true});
  const revoked=await receive('ab','revoked',403);await db.doc('conversations/ab').update({clientUid:'d'});
  await service.deliver(revoked);assert.equal(sent.length,sentBefore);
  assert.equal((await db.doc('notificationOutbox/'+revoked).get()).data().reason,'target');
  for(const row of (await db.collection('notificationOutbox').get()).docs)assert.ok(!JSON.stringify(row.data()).match(/Bonjour|NEVER EXPOSE|225070/));
  assert.equal((await db.collection('users/a/notifications').get()).size,2);
 }finally{await deleteApp(app);}
});

test('V9.1 migration keeps legacy documents, excludes their general count once and backfills messages without sending historical push',{skip:!enabled,timeout:120000},async()=>{
 const app=initializeApp({projectId:'demo-foundi-message-migration'},'migration-'+Date.now()),db=getFirestore(app);
 const service=createNotificationService({db,auth:{getUser:async()=>({disabled:false,emailVerified:true})},messaging:{send:()=>{assert.fail('Migration sent a push');}}});
 try{
  for(const collection of ['users','conversations','notificationReceipts','notificationOutbox'])await db.recursiveDelete(db.collection(collection));
  await db.doc('conversations/chat').set({clientUid:'a',professionalUid:'b',status:'read_only'});
  for(let i=1;i<=3;i++){
   const id=`old${i}`,eventId=`messages/chat/${id}`,hash=key(eventId,'a'),readAt=i===3?Timestamp.now():null;
   await db.doc(`conversations/chat/messages/${id}`).set({senderUid:'b',createdAt:i,type:'text',text:'Legacy private content'});
   await db.doc(`users/a/notifications/${hash}`).set({type:i===2?'chat_message':'message.created',schemaVersion:9,eventId,recipientUid:'a',resourceId:'chat',readAt});
   if(readAt)await db.doc('notificationReceipts/'+key('a',hash)).set({uid:'a'});
   if(!readAt)await db.doc('notificationOutbox/'+hash).set({uid:'a',notificationId:hash,category:'messages',state:'pending',createdAt:1,dueAt:1});
  }
  for(let i=1;i<=2;i++)await db.doc(`users/a/notifications/general${i}`).set({type:'proposal.created',schemaVersion:9,readAt:null});
  await db.doc('users/a/notificationState/inbox').set({unreadCount:4});
  const dry=await migrate({db,service});assert.equal(dry.privateNotifications,3);assert.equal((await db.doc('users/a/notificationState/inbox').get()).data().unreadCount,4);
  for(let i=0;i<2;i++)await migrate({db,service,apply:true});
  assert.equal((await db.doc('users/a/notificationState/inbox').get()).data().unreadCount,2);
  assert.equal((await db.doc('users/a/messageState/inbox').get()).data().unreadCount,2);
  const rows=await db.collection('users/a/notifications').get();assert.equal(rows.size,5);assert.equal(rows.docs.filter(d=>d.data().isGeneral).length,2);
  assert.equal((await db.collection('notificationOutbox').get()).size,2);
  for(const row of (await db.collection('notificationOutbox').get()).docs)assert.equal(row.data().kind,'chat_message');
  const hash=key('messages/chat/old1','a');
  await service.read('a',hash,{readAt:null},{readAt:Timestamp.now(),schemaVersion:9,type:'message.created'});
  assert.equal((await db.doc('users/a/notificationState/inbox').get()).data().unreadCount,2);
 }finally{await deleteApp(app);}
});
