const {test}=require('node:test'),assert=require('node:assert/strict');
const {initializeApp,deleteApp}=require('firebase-admin/app');
const {getFirestore,Timestamp}=require('firebase-admin/firestore');
const {createNotificationService,PAGE}=require('../src/notification-service');
const {key}=require('../src/notification-policy');
const enabled=!!process.env.FIRESTORE_EMULATOR_HOST;

test('V9 durable events, privacy, dedup, pagination, tokens, push preferences, retry and authorization',{skip:!enabled,timeout:180000},async()=>{
 const projectId='demo-foundi-notification-service',app=initializeApp({projectId},'v9-'+Date.now()),db=getFirestore(app);
 let now=10000000;const sent=[];
 const auth={getUser:async uid=>({disabled:uid==='disabled',emailVerified:uid!=='unverified'})};
 let sendError=null;
 const service=createNotificationService({db,auth,clock:()=>now,messaging:{send:async payload=>{sent.push(payload);if(sendError)throw Object.assign(Error('FCM test'),{code:sendError});return 'sent';}}});
 const inbox=uid=>db.collection(`users/${uid}/notifications`);
 const all=async uid=>(await inbox(uid).get()).docs.map(d=>({id:d.id,...d.data()}));
 const request={status:'published',createdAt:1,categoryId:'c',specialtyId:'s',zoneId:'z'};
 const offer={clientUid:'a',professionalUid:'b',requestId:'request',status:'sent',createdAt:2};
 const chat={...offer,proposalId:'proposal',status:'active'};
 const device=(uid,id,token)=>service.register(uid,{deviceId:id,token,platform:'android'});
 try{
  await db.recursiveDelete(db.collection('users'));await db.recursiveDelete(db.collection('notificationOutbox'));await db.recursiveDelete(db.collection('notificationJobs'));await db.recursiveDelete(db.collection('notificationTokens'));await db.recursiveDelete(db.collection('notificationReceipts'));await db.recursiveDelete(db.collection('professionalProfiles'));await db.recursiveDelete(db.collection('proposals'));
  await db.doc('userRequests/a/items/request').set(request);await db.doc('requests/request').set(request);
  await db.doc('proposals/proposal').set({...offer,conversationId:'chat'});await db.doc('conversations/chat').set(chat);
  const audit={uid:'b',adminUid:'admin',from:'pending',to:'approved',createdAt:3};
  await Promise.all([service.professional('review',audit),service.professional('review',audit)]);
  assert.equal((await all('b')).length,1);
  await service.professional('same',{...audit,from:'approved'});assert.equal((await all('b')).length,1);
  await service.professional('reject',{...audit,to:'rejected',reason:'sensitive admin reason'});
  await service.proposal('proposal',offer);await service.proposal('proposal',offer);
  assert.equal((await all('a')).length,1);assert.equal((await all('a'))[0].type,'proposal.created');
  await service.proposal('self',{...offer,professionalUid:'a'});assert.equal((await all('a')).length,1);
  await service.conversation('chat',chat);await service.conversation('chat',chat);
  const initialB=(await all('b')).length;
  for(const type of ['text','image','pdf','contact']){
   const message={senderUid:'a',type,createdAt:4,text:'secret text',phoneNumber:'+2250123456789',originalName:'secret.pdf',storagePath:'secret/path'};
   await db.doc(`conversations/chat/messages/${type}`).set(message);
   await Promise.all([service.message('chat',type,message),service.message('chat',type,message)]);
  }
  assert.equal((await all('b')).length,initialB);assert.equal((await all('a')).length,1);
  assert.equal((await db.doc('users/b/messageState/inbox').get()).data().unreadCount,4);
  await service.message('chat','forged',{senderUid:'c',type:'text'});assert.equal((await all('b')).length,initialB);
  for(const n of await all('b'))assert.ok(!JSON.stringify(n).match(/secret|225012|sensitive/));
  const decision={actorUid:'a',requestId:'request',proposalId:'proposal',action:'retain',status:'retained',previousRetainedProposalId:null,createdAt:5};
  await service.decision('a','request','decision',decision);await service.decision('a','request','decision',decision);
  await service.decision('a','request','nochange',{...decision,previousRetainedProposalId:'proposal'});
  assert.equal((await all('b')).filter(n=>n.type==='proposal.retained').length,1);
  await service.decision('a','request','reject',{...decision,action:'reject',status:'rejected'});
  assert.equal((await all('b')).filter(n=>n.type==='proposal.rejected').length,1);
  await db.doc('conversations/chat').update({status:'read_only',archivedReason:'proposal_rejected'});
  assert.equal((await all('b')).filter(n=>n.type==='conversation.ended').length,0);
  // Closed request fanout is paged and deduplicates a pro with multiple proposals.
  for(let i=0;i<PAGE+3;i++)await db.doc(`proposals/duplicate_${String(i).padStart(3,'0')}`).set({...offer,professionalUid:i<3?'b':`pro_${i}`});
  await service.enqueueRequest('closed','a','request',{...request,status:'closed',updatedAt:6},6);
  const jobId=key('closed','a','request','6');
  await service.processJob(jobId);assert.equal((await db.doc('notificationJobs/'+jobId).get()).data().state,'pending');
  await service.processJob(jobId);await service.processJob(jobId);
  assert.equal((await all('b')).filter(n=>n.type==='request.closed').length,1);assert.equal((await all('c')).length,0);
  assert.equal((await db.doc('conversations/chat').get()).data().status,'read_only');
  // Exact FOUN-52, many values, approval and authorship. Immutable first-publication snapshot.
  const reference={categories:[{id:'c',specialties:[{id:'s'},{id:'s2'}]}]};
  await db.doc('referenceData/professionalOnboarding').set(reference);
  const profile={status:'approved',categoryIds:['c','c'],specialtyIds:['s','s2'],zoneIds:['z','z2']};
  for(const [uid,p]of [['b',profile],['a',profile],['pending',{...profile,status:'pending'}],['outside',{...profile,zoneIds:['parent']}],['disabled',profile]])await db.doc('professionalProfiles/'+uid).set(p);
  for(let i=0;i<2*PAGE+3;i++)await db.doc(`professionalProfiles/volume_${String(i).padStart(3,'0')}`).set(profile);
  await service.enqueueRequest('matched','a','request',request,1);await service.enqueueRequest('matched','a','request',request,1);
  const matchingJob=key('matched','a','request','1');
  await service.processJob(matchingJob);assert.equal((await db.doc('notificationJobs/'+matchingJob).get()).data().state,'pending');
  await service.processJob(matchingJob);await service.processJob(matchingJob);await service.processJob(matchingJob);
  assert.equal((await db.doc('notificationJobs/'+matchingJob).get()).data().state,'done');
  assert.equal((await all('volume_082')).filter(n=>n.type==='request.matched').length,1);
  assert.equal((await all('b')).filter(n=>n.type==='request.matched').length,1);
  for(const uid of ['a','pending','outside','disabled'])assert.equal((await all(uid)).filter(n=>n.type==='request.matched').length,0);
  // Resolve authenticates and authorizes the stored target, even for old pushes.
  const msg={id:key('messages/chat/text','b')};
  assert.deepEqual(await service.resolve('b',msg.id),{resourceType:'conversation',resourceId:'chat'});
  await assert.rejects(service.resolve('c',msg.id),e=>e.code==='not-found');
  await assert.rejects(service.resolve('disabled',msg.id),e=>e.code==='permission-denied');
  await db.doc('conversations/chat').update({professionalUid:'c'});
  await assert.rejects(service.resolve('b',msg.id),e=>e.code==='not-found');
  await db.doc('conversations/chat').update({professionalUid:'b'});
  const closed=(await all('b')).find(n=>n.type==='request.closed');assert.equal((await service.resolve('b',closed.id)).type,undefined);assert.equal((await service.resolve('b',closed.id)).resourceType,'proposal');
  // Recipient scoped unread count decremented exactly once on a repeated read trigger.
  const count=(await db.doc('users/b/notificationState/inbox').get()).data().unreadCount;
  await service.read('b',closed.id,{...closed,readAt:null},{...closed,readAt:Timestamp.now()});await service.read('b',closed.id,{...closed,readAt:null},{...closed,readAt:Timestamp.now()});
  assert.equal((await db.doc('users/b/notificationState/inbox').get()).data().unreadCount,count-1);
  // Multi-device sends, concurrent drain claims, no sender push, generic payload only.
  await device('b','phone1','token-b-device-one-1234567890');await device('b','phone2','token-b-device-two-1234567890');
  const outboxId=key('messages/chat/text','b');
  await Promise.all([service.deliver(outboxId),service.deliver(outboxId)]);assert.equal(sent.length,2);
  for(const p of sent){assert.deepEqual(Object.keys(p.data).sort(),['conversationId','messageId','notificationId','recipientUid','type']);assert.ok(!JSON.stringify(p).match(/secret|225012|sensitive/));}
  await service.deliver(outboxId);assert.equal(sent.length,2);
  await db.doc('users/b/notificationPreferences/push').set({messages:false});
  await service.deliver(key('messages/chat/pdf','b'));assert.equal(sent.length,2);assert.ok(!(await all('b')).some(n=>n.type==='message.created'));
  await db.doc('users/b/notificationPreferences/push').set({messages:true});
  await device('c','new-owner','token-b-device-two-1234567890');
  assert.equal((await db.doc('users/b/devices/phone2').get()).exists,false);
  await device('b','phone1','rotated-b-device-one-1234567890');assert.equal((await db.doc('notificationTokens/'+key('token-b-device-one-1234567890')).get()).exists,false);
  sendError='messaging/registration-token-not-registered';await service.deliver(key('messages/chat/contact','b'));assert.equal((await db.doc('users/b/devices/phone1').get()).exists,false);
  await device('b','phone1','valid-b-device-one-1234567890');sendError='messaging/server-unavailable';
  const retryId=key('messages/chat/image','b');await service.deliver(retryId);assert.equal((await db.doc('notificationOutbox/'+retryId).get()).data().state,'pending');
  now+=60001;sendError=null;await service.deliver(retryId);assert.equal((await db.doc('notificationOutbox/'+retryId).get()).data().state,'done');
  const ambiguousMessage={senderUid:'a',type:'text',createdAt:5,text:'Private text'};
  await db.doc('conversations/chat/messages/ambiguous').set(ambiguousMessage);
  await service.message('chat','ambiguous',ambiguousMessage);sendError='network/timeout';
  const ambiguous=key('messages/chat/ambiguous','b');await service.deliver(ambiguous);const attempts=sent.length;now+=60001;sendError=null;await service.deliver(ambiguous);assert.equal(sent.length,attempts);
  // Opportunity push is delayed and capped per device/hour; every inbox item is retained.
  const opportunity=key('request.matched/request/1','b'),before=sent.length;await service.deliver(opportunity);assert.equal(sent.length,before+1);
  now+=60001;await service.deliver(opportunity);assert.equal(sent.length,before+1);
  await service.emit({eventId:'another-match',type:'request.matched',recipientUid:'b',actorUid:'a',resourceType:'opportunity',resourceId:'request'});
  now+=60001;await service.deliver(key('another-match','b'));assert.equal(sent.length,before+1);
  await service.unregister('b','phone1');assert.equal((await db.doc('users/b/devices/phone1').get()).exists,false);
  await assert.rejects(device('unverified','phone','unverified-token-123456789'),e=>e.code==='permission-denied');

  // A recommendation can reach a verified professional outside the matching filters.
  const recommendation = { ownerUid: 'a', actorUid: 'c', professionalUid: 'outside', requestId: 'request', createdAt: now };
  const recPath = 'requestRecommendations/notify-pro';
  const proNote = key(recPath, 'outside');
  await db.doc(recPath).set(recommendation);
  const proToken = 'token-outside-professional-1234567890';
  await device('outside', 'phone', proToken);
  await Promise.all([service.recommendation('notify-pro', recommendation), service.recommendation('notify-pro', recommendation)]);
  assert.equal((await all('outside')).filter(n => n.type === 'request.recommendation_received').length, 1);
  assert.equal((await all('a')).filter(n => n.type === 'request.recommended').length, 1);
  const sentBeforeRecommendation = sent.length;
  await Promise.all([service.deliver(proNote), service.deliver(proNote)]);
  assert.equal(sent.length, sentBeforeRecommendation + 1);
  assert.equal(sent.at(-1).token, proToken);
  assert.deepEqual(sent.at(-1).data, { notificationId: proNote, recipientUid: 'outside' });
  assert.deepEqual(await service.resolve('outside', proNote), { resourceType: 'opportunity', resourceId: 'request' });

  const mutedPath = 'requestRecommendations/notify-pro-muted';
  await db.doc(mutedPath).set(recommendation);
  await db.doc('users/outside/notificationPreferences/push').set({ proposals: false });
  await service.recommendation('notify-pro-muted', recommendation);
  const mutedNote = key(mutedPath, 'outside');
  await service.deliver(mutedNote);
  assert.equal((await db.doc(`notificationOutbox/${mutedNote}`).get()).data().reason, 'preference');
  assert.equal(sent.length, sentBeforeRecommendation + 1);
  assert.equal((await all('outside')).filter(n => n.type === 'request.recommendation_received').length, 2);
 }finally{await deleteApp(app);}
});

test('V9 real callables and Firestore triggers: admin, A/B/C, one inbox, deep links and read counter',{skip:!process.env.FUNCTIONS_EMULATOR_HOST,timeout:180000},async()=>{
 const {getAuth:adminAuth}=require('firebase-admin/auth');
 const {initializeApp:clientApp,deleteApp:deleteClient}=require('firebase/app');
 const {getAuth,connectAuthEmulator,signInWithEmailAndPassword}=require('firebase/auth');
 const {getFirestore:clientDb,connectFirestoreEmulator,doc,updateDoc,setDoc,serverTimestamp}=require('firebase/firestore');
 const {getFunctions,connectFunctionsEmulator,httpsCallable}=require('firebase/functions');
 const app=initializeApp({projectId:'demo-foundi'},'v9-trigger-'+Date.now()),db=getFirestore(app),auth=adminAuth(app),apps=[],users=[];
 const pair=s=>{const[h,p]=s.split(':');return[h,Number(p)];};
 async function client(role){
  const email=`v9.${role}.${Date.now()}@example.test`,password='V9-Emulated-Password42!';
  const u=await auth.createUser({email,password,emailVerified:true});users.push(u.uid);
  if(role==='admin')await auth.setCustomUserClaims(u.uid,{admin:true});
  const app=clientApp({projectId:'demo-foundi',apiKey:'emulator-only',appId:'v9-'+role},'v9-'+u.uid);apps.push(app);
  const a=getAuth(app);connectAuthEmulator(a,'http://'+process.env.FIREBASE_AUTH_EMULATOR_HOST,{disableWarnings:true});await signInWithEmailAndPassword(a,email,password);
  const firestore=clientDb(app);connectFirestoreEmulator(firestore,...pair(process.env.FIRESTORE_EMULATOR_HOST));
  const functions=getFunctions(app,'europe-west1');connectFunctionsEmulator(functions,...pair(process.env.FUNCTIONS_EMULATOR_HOST));
  return{uid:u.uid,db:firestore,call:(name,data)=>httpsCallable(functions,name)(data).then(r=>r.data)};
 }
 async function until(read,predicate){
  for(let i=0;i<100;i++){const value=await read();if(predicate(value))return value;await new Promise(r=>setTimeout(r,300));}
  assert.fail('V9 trigger did not produce the expected durable state');
 }
 const inbox=uid=>db.collection(`users/${uid}/notifications`).where('schemaVersion','==',9).get().then(s=>s.docs.map(d=>({id:d.id,...d.data()})));
 try{
  const a=await client('a'),b=await client('b'),c=await client('c'),admin=await client('admin');
  const profile={status:'pending',businessName:'Atelier V9',revision:1,categoryIds:['v9-c'],specialtyIds:['v9-s'],zoneIds:['v9-z']};
  await db.doc('professionalProfiles/'+b.uid).set(profile);await db.doc('professionalProfiles/'+c.uid).set({...profile,status:'approved',zoneIds:['other-zone']});
  await admin.call('reviewProfessionalProfile',{uid:b.uid,status:'approved',revision:1});
  const approved=(await until(()=>inbox(b.uid),rows=>rows.some(n=>n.type==='professional.approved'))).find(n=>n.type==='professional.approved');
  assert.deepEqual(await b.call('resolveNotification',{notificationId:approved.id}),{resourceType:'professional',resourceId:b.uid});
  await db.doc('referenceData/professionalOnboarding').set({enabled:true,categories:[{id:'v9-c',label:'Services V9',specialties:[{id:'v9-s',label:'Spécialité V9'}]}],zones:[{id:'v9-z',label:'Zone V9'}]});
  const rid=db.collection('unused').doc().id;
  await a.call('publishRequest',{requestId:rid,request:{title:'Besoin V9 local',description:'Description du parcours émulé V9.',categoryId:'v9-c',specialtyId:'v9-s',zoneId:'v9-z',budget:null}});
  await until(()=>inbox(b.uid),rows=>rows.some(n=>n.type==='request.matched'&&n.requestId===rid));
  assert.equal((await inbox(c.uid)).length,0);
  const data={requestId:rid,proposal:{description:'Une proposition détaillée de test.',amount:null,delay:''}};
  const p=await b.call('sendProposal',data);assert.equal((await b.call('sendProposal',data)).id,p.id);
  await until(()=>inbox(a.uid),rows=>rows.some(n=>n.type==='proposal.created'));
  const chat=await a.call('selectProposal',{requestId:rid,proposalId:p.id});await a.call('selectProposal',{requestId:rid,proposalId:p.id});
  await until(()=>inbox(b.uid),rows=>rows.filter(n=>n.type==='conversation.opened').length===1);
  const mid=db.collection('unused').doc().id;
  const message={conversationId:chat.conversationId,messageId:mid,type:'contact',phoneNumber:'+2250700000000',consent:true};
  await a.call('sendConversationMessage',message);await a.call('sendConversationMessage',message);
  const receiptRows=()=>db.collection(`users/${b.uid}/messageInbox`).get().then(s=>s.docs.map(d=>({id:d.id,...d.data()})));
  const notification=(await until(receiptRows,rows=>rows.some(n=>n.messageId===mid))).find(n=>n.messageId===mid);
  assert.equal((await inbox(b.uid)).filter(n=>n.type==='message.created').length,0);
  assert.ok(!JSON.stringify(notification).includes('2250700000000'));
  assert.deepEqual(await b.call('resolveNotification',{notificationId:notification.id}),{resourceType:'conversation',resourceId:chat.conversationId});
  await assert.rejects(c.call('resolveNotification',{notificationId:notification.id}),e=>e.code==='functions/not-found');
  await a.call('decideProposal',{requestId:rid,proposalId:p.id,action:'retain',decisionId:db.collection('unused').doc().id,expectedRetainedProposalId:null});
  await until(()=>inbox(b.uid),rows=>rows.some(n=>n.type==='proposal.retained'));
  await a.call('manageRequest',{requestId:rid,action:'close'});await a.call('manageRequest',{requestId:rid,action:'close'});
  const closed=(await until(()=>inbox(b.uid),rows=>rows.some(n=>n.type==='request.closed'))).find(n=>n.type==='request.closed');
  assert.deepEqual(await b.call('resolveNotification',{notificationId:closed.id}),{resourceType:'proposal',resourceId:p.id});
  assert.equal((await db.doc('conversations/'+chat.conversationId).get()).data().status,'active');
  assert.equal((await inbox(b.uid)).filter(n=>n.type==='request.closed').length,1);assert.equal((await inbox(c.uid)).length,0);
  await assert.rejects(c.call('sendProposal',{...data}),e=>e.code==='functions/failed-precondition');
  await b.call('sendConversationMessage',{conversationId:chat.conversationId,messageId:db.collection('unused').doc().id,text:'Discussion encore active après clôture.'});
  await a.call('decideProposal',{requestId:rid,proposalId:p.id,action:'reject',decisionId:db.collection('unused').doc().id});
  await until(()=>inbox(b.uid),rows=>rows.some(n=>n.type==='proposal.rejected'));
  assert.equal((await inbox(b.uid)).filter(n=>n.type==='conversation.ended').length,0);
  const before=(await db.doc(`users/${b.uid}/notificationState/inbox`).get()).data().unreadCount;
  await updateDoc(doc(b.db,`users/${b.uid}/notifications/${closed.id}`),{readAt:serverTimestamp()});
  await until(()=>db.doc(`users/${b.uid}/notificationState/inbox`).get().then(s=>s.data().unreadCount),value=>value===before-1);
  await assert.rejects(c.call('markConversationRead',{conversationId:chat.conversationId,messageId:mid}),e=>e.code==='functions/permission-denied');
  await b.call('markConversationRead',{conversationId:chat.conversationId,messageId:mid});
  assert.equal((await db.doc(`users/${b.uid}/messageState/inbox`).get()).data().unreadCount,0);
  await setDoc(doc(b.db,`users/${b.uid}/notificationPreferences/push`),{messages:false,proposals:false,opportunities:false,account:false});
  await b.call('registerNotificationDevice',{deviceId:'phone-v9',token:'emulated-token-b-12345678901234567890',platform:'android'});
  assert.equal((await db.doc(`users/${b.uid}/devices/phone-v9`).get()).data().pushEnabled,true);
  await b.call('unregisterNotificationDevice',{deviceId:'phone-v9'});assert.equal((await db.doc(`users/${b.uid}/devices/phone-v9`).get()).exists,false);
 }finally{await Promise.all(users.map(uid=>auth.deleteUser(uid)));await Promise.all(apps.map(deleteClient));await deleteApp(app);}
});
