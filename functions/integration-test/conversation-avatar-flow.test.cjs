const {test}=require('node:test'),assert=require('node:assert/strict');
const {initializeApp,deleteApp}=require('firebase/app');
const {getAuth,connectAuthEmulator,signInWithEmailAndPassword}=require('firebase/auth');
const {getFunctions,connectFunctionsEmulator,httpsCallable}=require('firebase/functions');
const {initializeApp:adminApp,deleteApp:deleteAdmin}=require('firebase-admin/app');
const {getAuth:adminAuth}=require('firebase-admin/auth'),{getFirestore}=require('firebase-admin/firestore');
const sharp=require('sharp');
const enabled=!!(process.env.FIRESTORE_EMULATOR_HOST&&process.env.FIREBASE_AUTH_EMULATOR_HOST&&process.env.FUNCTIONS_EMULATOR_HOST&&process.env.FIREBASE_STORAGE_EMULATOR_HOST);
const host=value=>{const [h,p]=value.split(':');assert.ok(['127.0.0.1','localhost'].includes(h));return [h,+p];};
test('CONVERSATION PHOTO real callable reuses existing profile photo, scopes both roles, respects revocation, block and deletion',{skip:!enabled,timeout:180000},async()=>{
 const stamp=Date.now(),projectId='demo-foundi',root=adminApp({projectId,storageBucket:projectId+'.appspot.com'},'conversation-photo-admin-'+stamp),db=getFirestore(root),auth=adminAuth(root),apps=[],uids=[];
 async function client(name){
  const app=initializeApp({projectId,apiKey:'emulator-only',appId:'conversation-photo-'+name},name+stamp);apps.push(app);
  const a=getAuth(app);connectAuthEmulator(a,'http://'+process.env.FIREBASE_AUTH_EMULATOR_HOST,{disableWarnings:true});
  if(name!=='guest'){
   const email=`conversation.photo.${name}.${stamp}@example.test`,password='Emulator-Password42!';
   const user=await auth.createUser({email,password,emailVerified:true});uids.push(user.uid);await signInWithEmailAndPassword(a,email,password);
  }
  const f=getFunctions(app,'europe-west1');connectFunctionsEmulator(f,...host(process.env.FUNCTIONS_EMULATOR_HOST));
  return {uid:a.currentUser?.uid,call:(name,data)=>httpsCallable(f,name)(data).then(r=>r.data)};
 }
 try{
  const owner=await client('owner'),pro=await client('pro'),outsider=await client('outsider'),guest=await client('guest');
  const id=db.collection('conversations').doc().id,other=db.collection('conversations').doc().id;
  const photo=await sharp({create:{width:80,height:100,channels:3,background:'#28735e'}}).jpeg().toBuffer();
  // Existing personal photos are chosen once, independently of this conversation.
  const a=await owner.call('savePersonalAvatar',{publish:true,image:photo.toString('base64'),contentType:'image/jpeg'});
  const b=await pro.call('savePersonalAvatar',{publish:true,image:photo.toString('base64'),contentType:'image/jpeg'});
  const records=await db.getAll(db.doc(`personalAvatars/${owner.uid}`),db.doc(`personalAvatars/${pro.uid}`));
  await db.doc(`conversations/${id}`).set({clientUid:owner.uid,professionalUid:pro.uid,status:'active',proposalStatus:'retained'});
  await db.doc(`conversations/${other}`).set({clientUid:owner.uid,professionalUid:pro.uid,status:'read_only'});
  const data={conversationIds:[id,other,id]};
  assert.deepEqual(await owner.call('resolveConversationAvatars',data),{avatars:{[id]:b.publicId,[other]:b.publicId}});
  assert.deepEqual(await pro.call('resolveConversationAvatars',data),{avatars:{[id]:a.publicId,[other]:a.publicId}});
  assert.deepEqual(await outsider.call('resolveConversationAvatars',data),{avatars:{}});
  await assert.rejects(guest.call('resolveConversationAvatars',data),e=>e.code==='functions/unauthenticated');
  await assert.rejects(outsider.call('resolveConversationAvatars',{...data,uid:owner.uid}),e=>e.code==='functions/invalid-argument');
  const after=await db.getAll(...records.map(d=>d.ref));after.forEach((d,i)=>assert.deepEqual(d.data(),records[i].data(),'Lookup must reuse the photo without uploading it again'));
  await pro.call('savePersonalAvatar',{publish:false});assert.deepEqual(await owner.call('resolveConversationAvatars',data),{avatars:{}});
  await pro.call('savePersonalAvatar',{publish:true});
  await db.doc(`userBlocks/${pro.uid}/items/${owner.uid}`).set({createdAt:1});assert.deepEqual(await owner.call('resolveConversationAvatars',data),{avatars:{}});await db.doc(`userBlocks/${pro.uid}/items/${owner.uid}`).delete();
  await db.doc(`accountLifecycle/${pro.uid}`).set({state:'closing'});assert.deepEqual(await owner.call('resolveConversationAvatars',data),{avatars:{}});await db.doc(`accountLifecycle/${pro.uid}`).delete();
  await pro.call('removePersonalAvatar',{});assert.deepEqual(await owner.call('resolveConversationAvatars',data),{avatars:{}});
  const actual=(await db.doc(`conversations/${id}`).get()).data();assert.equal(actual.avatarKey,undefined);assert.equal(actual.photo,undefined);
 }finally{await Promise.all(apps.map(deleteApp));await Promise.all(uids.map(uid=>auth.deleteUser(uid)));await deleteAdmin(root);}
});
