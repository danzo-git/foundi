const {test,before,after}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const {initializeTestEnvironment,assertFails}=require('@firebase/rules-unit-testing');
const {doc,setDoc,getDoc,getDocs,collection,query,limit}=require('firebase/firestore');
const {ref,getBytes,uploadBytes,deleteObject,listAll,getMetadata,getDownloadURL}=require('firebase/storage');
const {initializeApp,deleteApp}=require('firebase-admin/app'),{getStorage}=require('firebase-admin/storage');
const enabled=!!(process.env.FIRESTORE_EMULATOR_HOST&&process.env.FIREBASE_STORAGE_EMULATOR_HOST);let env,admin;
const projectId='demo-foundi',cid='AttachmentChat00000001',mid='AttachmentMessage00001',aid='server-random-attachment-uuid';
const object=`conversations/${cid}/attachments/${mid}/${aid}`,raw=`conversations/${cid}/quarantine/${aid}`;
const bytes=fs.readFileSync(path.join(__dirname,'../test/fixtures/photo.png'));
before(async()=>{if(!enabled)return;
 env=await initializeTestEnvironment({projectId,firestore:{rules:fs.readFileSync(path.join(__dirname,'../../firestore.rules'),'utf8')},storage:{rules:fs.readFileSync(path.join(__dirname,'../../storage.rules'),'utf8')}});
 admin=initializeApp({projectId,storageBucket:projectId+'.appspot.com'},'media-rules');
 await env.withSecurityRulesDisabled(async c=>{
  await setDoc(doc(c.firestore(),`conversations/${cid}`),{clientUid:'alice',professionalUid:'bob',status:'read_only'});
  await setDoc(doc(c.firestore(),`conversations/${cid}/attachments/${mid}`),{state:'ready',attachmentId:aid,storagePath:object,validatedSizeBytes:bytes.length,contentType:'image/png'});
  await setDoc(doc(c.firestore(),`conversations/${cid}/attachments/pending`),{state:'awaiting_scan',attachmentId:'pending',storagePath:`conversations/${cid}/attachments/pending/pending`,validatedSizeBytes:bytes.length,contentType:'image/png'});
 });
 const bucket=getStorage(admin).bucket();
 for(const [p,messageId]of [[object,mid],[`conversations/${cid}/attachments/pending/pending`,'pending'],[raw,mid]]){
  await bucket.file(p).save(bytes,{resumable:false,contentType:'image/png',metadata:{metadata:{messageid:messageId,validation:'clean-v1'}}});
  const [metadata]=await bucket.file(p).getMetadata();assert.equal(metadata.metadata.messageid,messageId);assert.equal(metadata.metadata.validation,'clean-v1');
 }
});
after(async()=>{if(env)await env.cleanup();if(admin)await deleteApp(admin);});
const check=(name,fn)=>test(name,{skip:!enabled},fn);
check('direct reads, metadata, token URLs and listing are denied even to A/B; authorized delivery is tested through HTTP',async()=>{
 for(const c of [env.authenticatedContext('alice'),env.authenticatedContext('bob'),env.unauthenticatedContext(),env.authenticatedContext('charlie'),env.authenticatedContext('admin',{admin:true})]){
  const s=c.storage('gs://'+projectId+'.appspot.com');await assertFails(getBytes(ref(s,object)));await assertFails(getMetadata(ref(s,object)));await assertFails(getDownloadURL(ref(s,object)));await assertFails(listAll(ref(s,`conversations/${cid}/attachments`)));
 }
 const [metadata]=await getStorage(admin).bucket().file(object).getMetadata();assert.equal(metadata.metadata?.firebaseStorageDownloadTokens,undefined);
});
check('quarantine and unvalidated objects are unreadable even to the uploader or other participant',async()=>{
 for(const uid of ['alice','bob'])for(const p of [raw,`conversations/${cid}/attachments/pending/pending`])await assertFails(getBytes(ref(env.authenticatedContext(uid).storage('gs://'+projectId+'.appspot.com'),p)));
});
check('all direct creates, overwrites and deletes are denied, including forged MIME, huge files and manipulated conversation IDs',async()=>{
 for(const uid of ['alice','bob','charlie']){const s=env.authenticatedContext(uid).storage('gs://'+projectId+'.appspot.com');
  await assertFails(uploadBytes(ref(s,object),bytes,{contentType:'image/png'}));
  for(const contentType of ['image/png','application/pdf','application/zip'])await assertFails(uploadBytes(ref(s,`conversations/${cid}/attachments/forged`),bytes,{contentType}));
  await assertFails(uploadBytes(ref(s,`conversations/${cid}/attachments/large`),new Uint8Array(10*1048576+1),{contentType:'image/png'}));
  await assertFails(uploadBytes(ref(s,'conversations/other/attachments/forged'),bytes,{contentType:'image/png'}));await assertFails(deleteObject(ref(s,object)));
 }
});
check('reservation, quota and validation data are server-only; users cannot forge a ready attachment or contact',async()=>{
 for(const uid of ['alice','bob','charlie']){const db=env.authenticatedContext(uid).firestore();
  await assertFails(setDoc(doc(db,`conversations/${cid}/attachments/${mid}`),{state:'ready',senderUid:uid}));
  await assertFails(getDoc(doc(db,`conversations/${cid}/attachments/${mid}`)));
  await assertFails(getDocs(query(collection(db,`conversations/${cid}/attachments`),limit(30))));
  await assertFails(setDoc(doc(db,'conversationAttachmentRates/'+uid),{dayCount:0}));
  await assertFails(setDoc(doc(db,`conversations/${cid}/messages/forged`),{type:'contact',senderUid:'alice',phoneNumber:'+2250700000000'}));
 }
});
