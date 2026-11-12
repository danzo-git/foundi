const {test}=require('node:test');
const assert=require('node:assert/strict');
const {initializeApp,deleteApp}=require('firebase-admin/app');
const {getFirestore}=require('firebase-admin/firestore');
const {createRequestService}=require('../src/request-service');
const {createProposalService}=require('../src/proposal-service');
const {createNotificationService}=require('../src/notification-service');
const {key}=require('../src/notification-policy');

test('direct request commits privately, notifies only its recipient once and resolves a private notification',
 {skip:!process.env.FIRESTORE_EMULATOR_HOST,timeout:90000},async()=>{
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST.startsWith('127.0.0.1:') || process.env.FIRESTORE_EMULATOR_HOST.startsWith('localhost:'));
  const stamp=Date.now(),app=initializeApp({projectId:'demo-foundi'},'direct-'+stamp),db=getFirestore(app);
  const uid='direct-client-'+stamp,pro='direct-pro-'+stamp,other='direct-other-'+stamp,rid='DirectIntegration'+stamp;
  const auth={getUser:async()=>({emailVerified:true,disabled:false})};
  const store={get:async p=>(await db.doc(p).get()).data(),transaction:op=>db.runTransaction(tx=>op({
    get:async p=>(await tx.get(db.doc(p))).data(),set:(p,v)=>tx.set(db.doc(p),v),
  }))};
  const notifications=createNotificationService({db,auth,messaging:{send:async()=>{throw Error('No real push service in emulator test');}}});
  try {
    await db.doc('referenceData/professionalOnboarding').set({enabled:true,categories:[{id:'direct-home',label:'Maison'}],zones:[{id:'direct-zone',label:'Zone de test'}]});
    await db.doc(`professionalProfiles/${pro}`).set({status:'approved',businessName:'Atelier privé',categoryIds:['direct-home'],specialtyIds:[]});
    await db.doc(`users/${uid}`).set({fullName:'Awa Kouassi',email:'private@example.test',phone:'+2250700000000'});
    await db.doc(`professionalProfiles/${other}`).set({status:'approved',businessName:'Autre professionnel'});
    const service=createRequestService({store,auth});
    const draft={categoryId:'direct-home',specialtyId:'',zoneId:'direct-zone',title:'Besoin confidentiel',description:'Une demande privée à ne pas afficher dans le fil.',budget:null};
    const created=await service.publishDirect(uid,rid,pro,draft);
    assert.equal((await db.doc(`requests/${rid}`).get()).exists,false);
    assert.equal((await db.doc(`userRequests/${uid}/items/${rid}`).get()).data().visibility,'direct');
    const value=(await db.doc(`directRequests/${rid}`).get()).data();
    assert.equal(value.requesterName,'Awa Kouassi');
    await db.doc(`directRequests/${rid}`).update({requesterName:require('firebase-admin/firestore').FieldValue.delete(),authorPublicName:'Ancien nom'});
    assert.deepEqual(await service.readDirectAuthors(pro,[rid]),{authors:{[rid]:'Awa Kouassi'}});
    await assert.rejects(service.readDirectAuthors(other,[rid]),e=>e.code==='permission-denied');
    assert.equal(await notifications.directRequest(rid,value),true);
    assert.equal(await notifications.directRequest(rid,value),false);
    const nid=key(`directRequests/${rid}/created`,pro);
    const notification=(await db.doc(`users/${pro}/notifications/${nid}`).get()).data();
    assert.equal(notification.type,'request.direct_received');
    assert.ok(!JSON.stringify(notification).includes(draft.title));
    assert.ok(!JSON.stringify(notification).includes(draft.description));
    assert.equal((await db.doc(`users/${pro}/notificationState/inbox`).get()).data().unreadCount,1);
    assert.equal((await db.doc(`users/${uid}/notifications/${key(`directRequests/${rid}/created`,uid)}`).get()).exists,false);
    assert.deepEqual(await notifications.resolve(pro,nid),{resourceType:'directRequest',resourceId:rid});
    await assert.rejects(notifications.resolve(other,nid),e=>e.code==='not-found');
    const proposals=createProposalService({store,auth});
    const proposal={description:'Je peux réaliser cette prestation privée.',amount:20000,delay:'Deux jours'};
    await assert.rejects(proposals.send(other,rid,proposal),e=>e.code==='permission-denied');
    const response=await proposals.send(pro,rid,proposal);
    await notifications.proposal(response.id,response);
    assert.equal((await db.collection(`users/${uid}/notifications`).get()).size,1);
    await service.manage(uid,rid,'close');
    assert.equal((await db.doc(`directRequests/${rid}`).get()).data().status,'closed');
    assert.equal((await db.doc(`requests/${rid}`).get()).exists,false);
    await service.manage(uid,rid,'delete');
    await assert.rejects(notifications.resolve(pro,nid),e=>e.code==='not-found');
    assert.equal(created.directProfessionalId,pro);
  } finally {await deleteApp(app);}
});
