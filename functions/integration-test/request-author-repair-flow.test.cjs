const {test}=require('node:test');
const assert=require('node:assert/strict');
const {initializeApp,deleteApp}=require('firebase-admin/app');
const {getFirestore}=require('firebase-admin/firestore');
const {createRequestAuthorRepair}=require('../src/request-author-repair');

test('author repair fills only names on existing public records and owner copies in Firestore',
  {skip:!process.env.FIRESTORE_EMULATOR_HOST,timeout:90000},async()=>{
  assert.match(process.env.FIRESTORE_EMULATOR_HOST,/^(127\.0\.0\.1|localhost):/);
  const stamp=Date.now(),app=initializeApp({projectId:'demo-foundi'},'author-repair-'+stamp),db=getFirestore(app);
  const uid='author-repair-client-'+stamp,id='AuthorRepairRequest'+stamp;
  const request={status:'published',createdAt:123,updatedAt:456,title:'Restaurer une table',budget:12000,
    photoIds:['photo'],photosPublic:true,proposalCount:2};
  const refs=[`requests/${id}`,`userRequests/${uid}/items/${id}`,`requestOwnership/${id}`,`users/${uid}`,`requestPublicationLimits/${uid}`];
  const store={transaction:op=>db.runTransaction(tx=>op({get:async p=>(await tx.get(db.doc(p))).data(),update:(p,v)=>tx.update(db.doc(p),v)}))};
  const service=createRequestAuthorRepair({store,auth:{getUser:async()=>({emailVerified:true,disabled:false})}});
  try{
    await db.doc(refs[0]).set(request);await db.doc(refs[1]).set({...request,lastEdit:{fingerprint:'untouched'}});
    await db.doc(refs[2]).set({ownerUid:uid});await db.doc(refs[3]).set({fullName:'Awa Kouassi',email:'private@example.test'});
    await db.doc(refs[4]).set({createdAtMs:[123]});
    const before=await Promise.all(refs.map(async p=>(await db.doc(p).get()).data()));
    const plan=await service.plan([id]);assert.equal(plan.entries.length,1);
    assert.equal((await service.apply(plan.entries[0])).state,'repaired');
    const after=await Promise.all(refs.map(async p=>(await db.doc(p).get()).data()));
    before[0].authorPublicName='Awa Kouassi';before[1].authorPublicName='Awa Kouassi';
    assert.deepEqual(after,before);
    assert.equal((await service.apply(plan.entries[0])).state,'already_current');
    await db.doc(refs[0]).update({authorPublicName:''});await db.doc(refs[1]).update({authorPublicName:''});
    const next=await service.plan([id]);
    await db.doc(refs[3]).update({fullName:'Nom modifié après le plan'});
    assert.equal((await service.apply(next.entries[0])).state,'conflict');
    assert.equal((await db.doc(refs[0]).get()).data().authorPublicName,'');
    assert.deepEqual((await db.doc(refs[4]).get()).data(),{createdAtMs:[123]});
  }finally{await deleteApp(app);}
});
