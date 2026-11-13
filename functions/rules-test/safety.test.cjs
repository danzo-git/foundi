const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const {initializeTestEnvironment,assertFails,assertSucceeds}=require('@firebase/rules-unit-testing');
const {doc,getDoc,getDocs,collection,query,limit,setDoc,updateDoc,serverTimestamp}=require('firebase/firestore');
const {ref,uploadBytes,getBytes}=require('firebase/storage');
const enabled=!!process.env.FIRESTORE_EMULATOR_HOST;
test('SEC rules: reports, audit, blocks and restrictions are private even to stale admin tokens',{skip:!enabled,timeout:60000},async()=>{
  const env=await initializeTestEnvironment({projectId:'demo-foundi',firestore:{rules:fs.readFileSync(path.join(__dirname,'../../firestore.rules'),'utf8')}});
  try{
    const paths=['safetyReports/private-report','safetyAudit/private-audit','userBlocks/safety-rule-a/items/safety-rule-b','accountSafety/safety-rule-b','safetyRequestSnapshots/hidden-request','safetyContent/request_hidden-request'];
    await env.withSecurityRulesDisabled(async c=>{for(const p of paths)await setDoc(doc(c.firestore(),p),{reporterUid:'safety-rule-a',comment:'private',suspended:true});});
    for(const c of [env.unauthenticatedContext(),env.authenticatedContext('safety-rule-a'),env.authenticatedContext('safety-rule-b'),env.authenticatedContext('rule-admin',{admin:true})])for(const p of paths){await assertFails(getDoc(doc(c.firestore(),p)));await assertFails(setDoc(doc(c.firestore(),p),{status:'resolved'}));}
  }finally{await env.cleanup();}
});
test('SEC rules: preexisting conversation remains readable after personal block, writes never allowed; suspension gates old sessions',{skip:!enabled,timeout:60000},async()=>{
  const env=await initializeTestEnvironment({projectId:'demo-foundi',firestore:{rules:fs.readFileSync(path.join(__dirname,'../../firestore.rules'),'utf8')}});
  try{
    await env.withSecurityRulesDisabled(async c=>{
      await setDoc(doc(c.firestore(),'conversations/safety-rules-chat'),{clientUid:'safety-rule-client',professionalUid:'safety-rule-pro',status:'active'});
      await setDoc(doc(c.firestore(),'conversations/safety-rules-chat/messages/old'),{senderUid:'safety-rule-pro',text:'Historique privé',createdAt:1});
      await setDoc(doc(c.firestore(),'userBlocks/safety-rule-client/items/safety-rule-pro'),{createdAt:2});
    });
    const a=env.authenticatedContext('safety-rule-client').firestore(),b=env.authenticatedContext('safety-rule-pro').firestore(),d=env.authenticatedContext('safety-rule-stranger').firestore();
    for(const db of [a,b]){await assertSucceeds(getDoc(doc(db,'conversations/safety-rules-chat')));await assertSucceeds(getDocs(query(collection(db,'conversations/safety-rules-chat/messages'),limit(30))));await assertFails(setDoc(doc(db,'conversations/safety-rules-chat/messages/forged'),{senderUid:'safety-rule-pro',text:'Bypass'}));}
    await assertFails(getDoc(doc(d,'conversations/safety-rules-chat/messages/old')));
    await env.withSecurityRulesDisabled(c=>setDoc(doc(c.firestore(),'accountSafety/safety-rule-pro'),{suspended:true}));
    await assertFails(getDoc(doc(b,'conversations/safety-rules-chat')));await assertSucceeds(getDoc(doc(a,'conversations/safety-rules-chat')));
  }finally{await env.cleanup();}
});
test('SEC Storage rules: no direct evidence or attachment upload/download, even with forged admin claim',{skip:!enabled||!process.env.FIREBASE_STORAGE_EMULATOR_HOST,timeout:60000},async()=>{
  const env=await initializeTestEnvironment({projectId:'demo-foundi',firestore:{rules:fs.readFileSync(path.join(__dirname,'../../firestore.rules'),'utf8')},storage:{rules:fs.readFileSync(path.join(__dirname,'../../storage.rules'),'utf8')}});
  try{
    for(const context of [env.unauthenticatedContext(),env.authenticatedContext('safety-rule-client'),env.authenticatedContext('rule-admin',{admin:true})])for(const p of ['safetyEvidence/private/photo','conversations/safety-rules-chat/attachments/private/file']){
      const object=ref(context.storage('gs://demo-foundi.appspot.com'),p);
      await assertFails(uploadBytes(object,new Uint8Array([1,2,3])));await assertFails(getBytes(object));
    }
  }finally{await env.cleanup();}
});
test('SEC rules: suspended members can read their own moderation notices and mark inbox read, without any activity bypass',{skip:!enabled,timeout:60000},async()=>{
  const env=await initializeTestEnvironment({projectId:'demo-foundi',firestore:{rules:fs.readFileSync(path.join(__dirname,'../../firestore.rules'),'utf8')}});
  try{
    const uid='suspended-notice-reader',base=`users/${uid}`;
    await env.withSecurityRulesDisabled(async c=>{
      for(const [path,value] of [[`accountSafety/${uid}`,{suspended:true}],[`${base}/notifications/notice`,{schemaVersion:9,recipientUid:uid,type:'safety.suspended',readAt:null}],[`${base}/safetyNotices/decision`,{text:'Compte suspendu'}],[`${base}/notificationState/inbox`,{unreadCount:1}],[`conversations/suspended-notice-chat`,{clientUid:uid,professionalUid:'peer'}]])await setDoc(doc(c.firestore(),path),value);
    });
    const db=env.authenticatedContext(uid).firestore(),other=env.authenticatedContext('other-notice-reader').firestore();
    for(const p of ['notifications/notice','safetyNotices/decision','notificationState/inbox']){
      await assertSucceeds(getDoc(doc(db,`${base}/${p}`)));
      await assertFails(getDoc(doc(other,`${base}/${p}`)));
    }
    await assertSucceeds(getDocs(query(collection(db,`${base}/notifications`),limit(30))));
    await assertSucceeds(updateDoc(doc(db,`${base}/notifications/notice`),{readAt:serverTimestamp()}));
    await assertFails(updateDoc(doc(db,`${base}/notifications/notice`),{type:'safety.account_restored'}));
    await assertFails(setDoc(doc(db,`${base}/safetyNotices/forged`),{text:'Restored'}));
    await assertFails(setDoc(doc(db,`${base}/notificationState/inbox`),{unreadCount:0}));
    await assertFails(getDoc(doc(db,'conversations/suspended-notice-chat')));
    await assertFails(setDoc(doc(db,`${base}/devices/forged`),{token:'forged'}));
  }finally{await env.cleanup();}
});
