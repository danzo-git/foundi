const {test}=require('node:test'),assert=require('node:assert/strict');
const {initializeApp,deleteApp}=require('firebase-admin/app');
const {getFirestore}=require('firebase-admin/firestore');
const {getStorage}=require('firebase-admin/storage');
const sharp=require('sharp');
const {createNotificationService}=require('../src/notification-service');
const {createPersonalAvatarService}=require('../src/personal-avatar-service');
const {createPrivacyPurger}=require('../src/privacy-purge');
const {key}=require('../src/notification-policy');
const enabled=!!(process.env.FIRESTORE_EMULATOR_HOST&&process.env.FIREBASE_STORAGE_EMULATOR_HOST);
test('Sprint 2.5 complete paged audience, live eligibility, reclassification, replay and push preferences',{skip:!enabled,timeout:300000},async()=>{
 const app=initializeApp({projectId:'demo-foundi-sprint25'},'sprint25-notifications-'+Date.now()),db=getFirestore(app);
 let now=Date.now();const auth={getUser:async uid=>({emailVerified:true,disabled:uid==='disabled'})};
 const service=createNotificationService({db,auth,clock:()=>now,messaging:{send:async()=>{throw Error('No real push is allowed');}}});
 const base={status:'approved',categoryIds:['c'],specialtyIds:['s1'],zoneIds:['z1','z2','z3']};
 const rid='Sprint25Request00000001';
 const reference={categories:[{id:'c',specialties:[{id:'s1'},{id:'s2'}]},{id:'other',specialties:[]},{id:'foundi_other',requestOnly:true,specialties:[]}]};
 await db.recursiveDelete(db.collection('professionalProfiles'));await db.recursiveDelete(db.collection('users'));await db.recursiveDelete(db.collection('notificationJobs'));
 const inbox=async uid=>(await db.collection(`users/${uid}/notifications`).where('requestId','==',rid).get()).docs;
 async function drainVersion(version) {
   const request=(await db.doc(`requests/${rid}`).get()).data();
   await service.enqueueRequest('matched','author',rid,request,version);
   const id=key('matched','author',rid,String(version));
   // Includes a replay after page work was committed but before the caller received a response.
   for(let page=0;page<8;page++)await Promise.all([service.processJob(id),service.processJob(id)]);
   assert.equal((await db.doc(`notificationJobs/${id}`).get()).data().state,'done');
 }
 try {
  await db.doc('referenceData/professionalOnboarding').set(reference);
  const request={status:'published',categoryId:'c',specialtyId:'s1',zoneId:'z1',zoneIds:['z1','z2','z3'],createdAt:now};
  await db.doc(`requests/${rid}`).set(request);await db.doc(`requestOwnership/${rid}`).set({ownerUid:'author'});
  const eligible=[];
  for(let i=0;i<87;i++){
   const uid=`eligible_${String(i).padStart(3,'0')}`;eligible.push(uid);
   await db.doc(`professionalProfiles/${uid}`).set({...base,categoryIds:i%3===0?['other']:['c'],specialtyIds:i%2?['s2']:['s1']});
  }
  const excluded=['author','outside','pending','rejected','disabled','suspended','deleted','blockedByPro','blockedByAuthor'];
  for(const uid of excluded)await db.doc(`professionalProfiles/${uid}`).set({...base,...(uid==='outside'?{zoneIds:['parent-of-z1']}:{}) ,...(['pending','rejected'].includes(uid)?{status:uid}:{})});
  await db.doc('accountSafety/suspended').set({suspended:true});await db.doc('accountLifecycle/deleted').set({state:'closing'});
  await db.doc('userBlocks/blockedByPro/items/author').set({createdAt:now});await db.doc('userBlocks/author/items/blockedByAuthor').set({createdAt:now});
  await db.doc('users/eligible_001/notificationPreferences/push').set({opportunities:false});
  await service.emit({eventId:`request.matched/${rid}/${request.createdAt}`,type:'request.matched',recipientUid:'eligible_002',actorUid:'author',resourceType:'opportunity',resourceId:rid,requestId:rid});
  await drainVersion(1);
  for(let i=0;i<87;i++)assert.equal((await inbox(eligible[i])).length,i%3!==0&&i%2===0?1:0);
  await db.doc(`requests/${rid}`).update({specialtyId:'',updatedAt:now+1});await drainVersion(2);
  for(let i=0;i<87;i++)assert.equal((await inbox(eligible[i])).length,i%3!==0?1:0);
  await db.doc(`requests/${rid}`).update({categoryId:'foundi_other',serviceDetail:'Service à préciser',updatedAt:now+2});await drainVersion(3);await drainVersion(4);
  for(const uid of eligible)assert.equal((await inbox(uid)).length,1,uid+' must receive exactly one alert');
  for(const uid of excluded)assert.equal((await inbox(uid)).length,0,uid+' must be excluded');
  const notification=(await inbox('eligible_001'))[0];assert.match(notification.data().bodySafe,/nouveau besoin.*zone/i);assert.ok(!notification.data().bodySafe.includes('spécialit'));
  now+=60001;await service.deliver(notification.id);
  assert.equal((await db.doc(`notificationOutbox/${notification.id}`).get()).data().reason,'preference');
 }finally{await deleteApp(app);}
});

test('Sprint 2.5 avatar explicit consent, stripped image, revocation, replacement, private fallback and erasure',{skip:!enabled,timeout:180000},async()=>{
 const app=initializeApp({projectId:'demo-foundi-sprint25-avatar',storageBucket:'demo-foundi.appspot.com'},'sprint25-avatar-'+Date.now()),db=getFirestore(app),real=getStorage(app).bucket();
 const bucket={file:(...args)=>real.file(...args),getFiles:(...args)=>real.getFiles(...args),getMetadata:async()=>[{softDeletePolicy:{retentionDurationSeconds:0}}]};
 const auth={getUser:async()=>({emailVerified:true,disabled:false,photoURL:'https://google.example/private.jpg'})};
 const service=createPersonalAvatarService({db,auth,bucket});
 const uid='sprint25-avatar-'+Date.now(),rid='Sprint25AvatarRequest01';
 try {
  assert.equal((await service.state(uid)).hasPhoto,false);
  assert.deepEqual((await service.resolve(null,[rid])).avatars,{});
  const bytes=await sharp({create:{width:400,height:300,channels:3,background:'#176a56'}}).jpeg().withMetadata().toBuffer();
  await assert.rejects(service.save(uid,{image:bytes.toString('base64'),contentType:'image/jpeg'}));
  const saved=await service.save(uid,{image:bytes.toString('base64'),contentType:'image/jpeg',publish:true});
  await db.doc(`requests/${rid}`).set({status:'published'});await db.doc(`requestOwnership/${rid}`).set({ownerUid:uid});
  assert.deepEqual((await service.resolve(null,[rid])).avatars,{[rid]:saved.publicId});
  const legacyId='Sprint25LegacyRequest01';await db.doc(`requests/${legacyId}`).set({status:'published',createdAt:123});await db.doc(`userRequests/${uid}/items/${legacyId}`).set({status:'published',createdAt:123});assert.deepEqual((await service.resolve(null,[legacyId])).avatars,{[legacyId]:saved.publicId});
  const publicDoc=(await db.doc(`publicPersonalAvatars/${saved.publicId}`).get()).data();assert.deepEqual(Object.keys(publicDoc),['version']);
  const result=await service.read(saved.publicId,saved.version),info=await sharp(result).metadata();assert.equal(info.width,256);assert.equal(info.height,256);assert.equal(info.exif,undefined);
  await service.save(uid,{publish:false});assert.equal((await db.doc(`publicPersonalAvatars/${saved.publicId}`).get()).exists,false);
  await assert.rejects(service.read(saved.publicId,saved.version),e=>e.code==='not-found');assert.deepEqual((await service.resolve(null,[rid])).avatars,{});
  const next=await service.save(uid,{image:bytes.toString('base64'),contentType:'image/jpeg',publish:true});assert.notEqual(next.version,saved.version);await assert.rejects(service.read(saved.publicId,saved.version));
  await db.doc(`userBlocks/viewer/items/${uid}`).set({createdAt:1});assert.deepEqual((await service.resolve('viewer',[rid])).avatars,{});
  const purger=createPrivacyPurger({db,bucket}),job={id:'a'.repeat(64),uid,alias:'deleted_fixture',policy:{}};
  await purger.run(job,'withdraw_profile');assert.equal((await db.doc(`publicPersonalAvatars/${next.publicId}`).get()).exists,false);
  await purger.run(job,'storage_requests');
  for(let i=0;i<10;i++)if((await purger.run(job,'private_trees')).done)break;
  assert.equal((await db.doc(`personalAvatarLookup/${next.publicId}`).get()).exists,false);
  assert.equal((await bucket.getFiles({prefix:`personalAvatars/${uid}/` }))[0].length,0);
  assert.equal((await db.doc(`personalAvatars/${uid}`).get()).exists,false);
  const another=await service.save(uid,{image:bytes.toString('base64'),contentType:'image/jpeg',publish:true});await service.remove(uid);await assert.rejects(service.read(another.publicId,another.version));
  let time=Date.now(),failDelete=true;
  const unreliable={...bucket,file:(...args)=>{const file=bucket.file(...args),remove=file.delete.bind(file);file.delete=async(...options)=>{if(failDelete){failDelete=false;throw Error('Temporary Storage outage');}return remove(...options);};return file;}};
  const recovering=createPersonalAvatarService({db,auth,bucket:unreliable,clock:()=>time});
  const pending=await recovering.save(uid,{image:bytes.toString('base64'),contentType:'image/jpeg',publish:true});
  const removed=await recovering.remove(uid);assert.equal(removed.cleanupPending,true);
  assert.equal((await db.doc(`publicPersonalAvatars/${pending.publicId}`).get()).exists,false);
  assert.equal((await db.collection('personalAvatarGarbage').where('uid','==',uid).get()).empty,false);
  time+=3600001;const repaired=await recovering.cleanup();assert.equal(repaired.failed,0);
  assert.equal((await db.collection('personalAvatarGarbage').where('uid','==',uid).get()).empty,true);
  assert.equal((await bucket.getFiles({prefix:`personalAvatars/${uid}/`}))[0].length,0);

 }finally{await deleteApp(app);}
});

test('Sprint 2.5 avatar shared identity migrates existing portrait, covers old requests, seeds future pro and stays deleted',{skip:!enabled,timeout:180000},async()=>{
 const {createHash}=require('node:crypto');
 const app=initializeApp({projectId:'demo-foundi-shared-avatar',storageBucket:'demo-foundi.appspot.com'},'shared-avatar-'+Date.now()),db=getFirestore(app),bucket=getStorage(app).bucket();
 const service=createPersonalAvatarService({db,auth:{getUser:async()=>({emailVerified:true,disabled:false})},bucket});
 const photo=async color=>{const bytes=await sharp({create:{width:96,height:96,channels:3,background:color}}).jpeg().toBuffer();return{id:createHash('sha256').update(bytes).digest('hex'),base64:bytes.toString('base64')};};
 const uid='existing-pro',rid='SharedAvatarOldRequest01',portrait=await photo('#116b59'),cover=await photo('#abcdef');
 try{
  await assert.rejects(service.ensureIdentity(undefined),e=>e.code==='unauthenticated');
  await db.doc(`professionalProfiles/${uid}`).set({status:'approved',businessName:'Atelier existant'});
  await db.doc(`professionalProfiles/${uid}/showcase/profile`).set({name:'Mon atelier',trade:'Artisan',area:'Cocody',bio:'Mon activité',portrait,cover,gallery:[cover],revision:3});
  await db.doc(`requests/${rid}`).set({status:'published',createdAt:123456});
  await db.doc(`userRequests/${uid}/items/${rid}`).set({status:'published',createdAt:123456});
  // First public card also migrates the existing portrait, without a new client upload.
  const resolved=await service.resolve(null,[rid]);assert.ok(resolved.avatars[rid]);
  const [a,b]=await Promise.all([service.state(uid),service.state(uid)]);
  assert.equal(a.hasPhoto,true);assert.equal(a.published,true);assert.ok(a.preview);assert.equal(a.version,b.version);
  assert.equal(resolved.avatars[rid],a.publicId);
  let profile=(await db.doc(`professionalProfiles/${uid}/showcase/profile`).get()).data();
  assert.equal(profile.portrait.base64,a.preview);assert.equal(profile.name,'Mon atelier');assert.deepEqual(profile.cover,cover);assert.deepEqual(profile.gallery,[cover]);
  const revision=profile.revision;await service.state(uid);assert.equal((await db.doc(`professionalProfiles/${uid}/showcase/profile`).get()).data().revision,revision);
  const changed=await service.save(uid,{image:(await photo('#bf7644')).base64,contentType:'image/jpeg',publish:true});
  assert.notEqual(changed.version,a.version);assert.equal(changed.publicId,a.publicId);
  profile=(await db.doc(`professionalProfiles/${uid}/showcase/profile`).get()).data();assert.equal(profile.portrait.base64,changed.preview);assert.deepEqual(profile.gallery,[cover]);
  await service.remove(uid);assert.equal((await service.state(uid)).hasPhoto,false);assert.deepEqual((await service.resolve(null,[rid])).avatars,{});
  assert.equal((await db.doc(`professionalProfiles/${uid}/showcase/profile`).get()).data().portrait,null);
  // A stale legacy profile cannot resurrect a deliberately removed identity.
  await db.doc(`professionalProfiles/${uid}/showcase/profile`).update({portrait});assert.equal((await service.state(uid)).hasPhoto,false);
  const client='client-without-pro';
  const saved=await service.save(client,{image:portrait.base64,contentType:'image/jpeg',publish:true});
  assert.equal((await db.doc(`professionalProfiles/${client}`).get()).exists,false);
  await db.doc(`professionalProfiles/${client}`).set({status:'draft',businessName:'Nouvelle activité'});
  await service.syncProfessional(client);
  const future=(await db.doc(`professionalProfiles/${client}/showcase/profile`).get()).data();assert.equal(future.portrait.base64,saved.preview);assert.equal(future.name,'Nouvelle activité');assert.equal(future.identityOnly,true);
  assert.equal((await db.doc(`professionalProfiles/${client}`).get()).data().status,'draft');
  await service.remove(client);assert.equal((await service.state(client)).hasPhoto,false);
 }finally{await deleteApp(app);}
});
