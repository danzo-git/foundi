const {test,before,after}=require('node:test');
const fs=require('node:fs'),path=require('node:path');
const {initializeTestEnvironment,assertFails,assertSucceeds}=require('@firebase/rules-unit-testing');
const {doc,setDoc,getDoc,getDocs,collection,query,where,orderBy,limit,updateDoc,deleteDoc,serverTimestamp,Timestamp}=require('firebase/firestore');
const enabled=!!process.env.FIRESTORE_EMULATOR_HOST;let env;
before(async()=>{
 if(!enabled)return;
 env=await initializeTestEnvironment({projectId:'demo-foundi-notification-rules',firestore:{rules:fs.readFileSync(path.join(__dirname,'../../firestore.rules'),'utf8')}});
 await env.withSecurityRulesDisabled(async c=>{
  const db=c.firestore();
  await setDoc(doc(db,'users/a/notifications/event'),{schemaVersion:9,recipientUid:'a',type:'message.created',category:'messages',title:'Nouveau message',bodySafe:'Résumé neutre',resourceType:'conversation',resourceId:'private',readAt:null,createdAt:Timestamp.now()});
  await setDoc(doc(db,'users/a/notificationState/inbox'),{unreadCount:1});
  await setDoc(doc(db,'users/a/devices/device'),{token:'private-fcm-token',platform:'android'});
  await setDoc(doc(db,'notificationOutbox/private'),{uid:'a',state:'pending'});
  await setDoc(doc(db,'users/a/messageState/inbox'),{unreadCount:5});
  await setDoc(doc(db,'users/a/messageReads/chat'),{readThroughAt:100});
  await setDoc(doc(db,'users/a/messageInbox/private'),{unread:true});
 });
});
after(async()=>{if(env)await env.cleanup();});
const check=(name,fn)=>test(name,{skip:!enabled},fn);
check('V9 owner can read inbox/count; third party/admin/guest cannot read any private notification data',async()=>{
 const db=env.authenticatedContext('a').firestore();
 await assertSucceeds(getDoc(doc(db,'users/a/notifications/event')));
 await assertSucceeds(getDoc(doc(db,'users/a/notificationState/inbox')));
 await assertSucceeds(getDocs(query(collection(db,'users/a/notifications'),where('schemaVersion','==',9),orderBy('createdAt','desc'),limit(30))));
 await assertFails(getDocs(collection(db,'users/a/notifications')));
 await assertFails(getDocs(query(collection(db,'users/a/notifications'),limit(101))));
 for(const context of [env.unauthenticatedContext(),env.authenticatedContext('c'),env.authenticatedContext('admin',{admin:true})]){
  const other=context.firestore();
  for(const p of ['users/a/notifications/event','users/a/notificationState/inbox','users/a/devices/device','notificationOutbox/private'])await assertFails(getDoc(doc(other,p)));
  await assertFails(getDocs(query(collection(other,'users/a/notifications'),limit(30))));
 }
});
check('V9 readAt is the sole client-writable notification field, monotonic and server-timestamped',async()=>{
 const db=env.authenticatedContext('a').firestore(),ref=doc(db,'users/a/notifications/event');
 for(const payload of [{title:'Forged'},{type:'professional.approved'},{recipientUid:'c'},{resourceId:'another'},{createdAt:serverTimestamp()},{readAt:Timestamp.fromMillis(1)},{readAt:serverTimestamp(),bodySafe:'Forged'}])await assertFails(updateDoc(ref,payload));
 await assertFails(updateDoc(doc(env.authenticatedContext('c').firestore(),'users/a/notifications/event'),{readAt:serverTimestamp()}));
 await assertSucceeds(updateDoc(ref,{readAt:serverTimestamp()}));
 await assertFails(updateDoc(ref,{readAt:null}));
 await assertFails(deleteDoc(ref));
 await assertFails(setDoc(doc(db,'users/a/notifications/forged'),{recipientUid:'a',type:'message.created',readAt:null}));
});
check('V9 token registration, recipient spoofing, counter and all push state are backend-only',async()=>{
 for(const uid of ['a','c']){
  const db=env.authenticatedContext(uid).firestore();
  for(const p of ['users/a/notificationState/inbox','users/a/devices/device','users/c/devices/fake','notificationTokens/token','notificationOutbox/private','notificationJobs/fake','notificationReceipts/fake']){
   await assertFails(setDoc(doc(db,p),{uid,token:'fake',state:'pending',unreadCount:999}));
   await assertFails(deleteDoc(doc(db,p)));
  }
 }
});
check('V9 push preferences are four own boolean settings, with no privilege or token fields',async()=>{
 const db=env.authenticatedContext('a').firestore(),ref=doc(db,'users/a/notificationPreferences/push');
 const value={messages:false,proposals:true,opportunities:false,account:false};
 await assertSucceeds(setDoc(ref,value));await assertSucceeds(getDoc(ref));
 await assertSucceeds(setDoc(ref,{...value,messagePreview:true}));
 for(const invalid of [{...value,admin:true},{...value,messages:'false'},{...value,messagePreview:'true'},{messages:true}])await assertFails(setDoc(ref,invalid));
 await assertFails(getDoc(doc(env.authenticatedContext('c').firestore(),'users/a/notificationPreferences/push')));
 await assertFails(setDoc(doc(env.authenticatedContext('c').firestore(),'users/a/notificationPreferences/push'),value));
});
check('V9.1 own message count/cursor are readable but every counter, receipt and cursor write remains server-only',async()=>{
 const own=env.authenticatedContext('a').firestore();
 for(const path of ['users/a/messageState/inbox','users/a/messageReads/chat'])await assertSucceeds(getDoc(doc(own,path)));
 await assertFails(getDoc(doc(own,'users/a/messageInbox/private')));
 for(const context of [env.authenticatedContext('a'),env.authenticatedContext('b'),env.authenticatedContext('admin',{admin:true}),env.unauthenticatedContext()]){
  const db=context.firestore();
  for(const path of ['users/a/messageState/inbox','users/b/messageState/inbox','users/a/messageReads/chat','users/a/messageInbox/private']){
   await assertFails(setDoc(doc(db,path),{unreadCount:0,readThroughAt:999999999}));
   await assertFails(deleteDoc(doc(db,path)));
  }
 }
 for(const context of [env.authenticatedContext('b'),env.authenticatedContext('admin',{admin:true}),env.unauthenticatedContext()]){
  for(const path of ['users/a/messageState/inbox','users/a/messageReads/chat'])await assertFails(getDoc(doc(context.firestore(),path)));
 }
});
