const {test}=require('node:test');
const assert=require('node:assert/strict');
const {initializeApp,deleteApp}=require('firebase-admin/app');
const {getFirestore}=require('firebase-admin/firestore');
const {createRequestService}=require('../src/request-service');

test('public requests use the authenticated account name in real Firestore transactions, never the client alias',
  {skip:!process.env.FIRESTORE_EMULATOR_HOST,timeout:90000},async()=>{
  assert.match(process.env.FIRESTORE_EMULATOR_HOST,/^(127\.0\.0\.1|localhost):/);
  const stamp=Date.now(),app=initializeApp({projectId:'demo-foundi'},'request-account-name-'+stamp);
  const db=getFirestore(app),uid='account-author-'+stamp,id='AccountAuthorRequest'+stamp;
  const auth={getUser:async()=>({emailVerified:true,disabled:false,displayName:'Autre nom Auth'})};
  const store={transaction:op=>db.runTransaction(tx=>op({
    get:async path=>(await tx.get(db.doc(path))).data(),set:(path,value)=>tx.set(db.doc(path),value),
  }))};
  try {
    await db.doc('referenceData/professionalOnboarding').set({enabled:true,categories:[{id:'home',label:'Maison'}],zones:[{id:'zone',label:'Zone de test'}]});
    await db.doc(`users/${uid}`).set({fullName:'Awa Kouassi',email:'private@example.test',phone:'+2250700000000'});
    const service=createRequestService({store,auth});
    const draft={categoryId:'home',specialtyId:'',zoneId:'zone',title:'Réparer une table',description:'Une table en bois à réparer cette semaine.',budget:null};
    const created=await service.publish(uid,id,{...draft,authorPublicName:{name:'Usurpation'},requesterName:'Faux nom'});
    const publicRef=db.doc(`requests/${id}`),ownRef=db.doc(`userRequests/${uid}/items/${id}`);
    assert.equal(created.authorPublicName,'Awa Kouassi');
    const publicData=(await publicRef.get()).data();
    assert.equal(publicData.authorPublicName,'Awa Kouassi');
    for(const key of ['clientUid','ownerUid','email','phone','requesterName']) assert.equal(key in publicData,false);
    assert.deepEqual((await ownRef.get()).data(),publicData);
    const quota=(await db.doc(`requestPublicationLimits/${uid}`).get()).data();
    // Simulate an existing document saved by the old per-request name feature.
    await publicRef.update({authorPublicName:'Ancien alias'});
    await ownRef.update({authorPublicName:'Ancien alias'});
    const edited=await service.manage(uid,id,'edit',{...draft,title:'Table à restaurer',authorPublicName:''},created.createdAt);
    assert.equal(edited.authorPublicName,'Awa Kouassi');
    assert.equal((await publicRef.get()).data().authorPublicName,'Awa Kouassi');
    assert.equal(edited.id,id);assert.equal(edited.createdAt,created.createdAt);assert.equal(edited.status,'published');
    const retry=await service.manage(uid,id,'edit',{...draft,title:'Table à restaurer',authorPublicName:'Nouvelle usurpation'},created.createdAt);
    assert.deepEqual(retry,edited);
    assert.deepEqual((await db.doc(`requestPublicationLimits/${uid}`).get()).data(),quota);
    await assert.rejects(service.manage('another-account',id,'edit',draft,edited.updatedAt),e=>e.code==='permission-denied');
    assert.equal((await publicRef.get()).data().authorPublicName,'Awa Kouassi');
  } finally {await deleteApp(app);}
});
