const {test}=require('node:test'),assert=require('node:assert/strict');
const {initializeApp,deleteApp}=require('firebase-admin/app');
const {getFirestore}=require('firebase-admin/firestore');
const {createSafetyService}=require('../src/safety-service');
const {createSafetyStore}=require('../src/safety-store');
const {createNotificationService}=require('../src/notification-service');
const {key}=require('../src/notification-policy');
const enabled=!!process.env.FIRESTORE_EMULATOR_HOST;

test('SEC real transactions: moderation inbox and FCM for suspended members, preferences, privacy and no contact bypass',{skip:!enabled,timeout:90000},async()=>{
  const app=initializeApp({projectId:'demo-foundi-safety-notifications'},'safety-notifications-'+Date.now()),db=getFirestore(app);
  const now=Date.now(),sent=[];
  const auth={getUser:async uid=>({uid,disabled:uid==='disabled',emailVerified:true,customClaims:{admin:uid==='admin'}})};
  const safety=createSafetyService({store:createSafetyStore(db),auth,clock:()=>now});
  const notifications=createNotificationService({db,auth,clock:()=>now,messaging:{send:async p=>{sent.push(p);return 'fake-emulator-fcm';}}});
  const seed=async(action,uid='member')=>{
    const reportId=key(action,uid);
    await db.doc(`safetyReports/${reportId}`).set({reporterUid:'secret-reporter',reportedUid:uid,targetType:'professional',targetId:uid,status:'new',revision:1,comment:'Private report',evidence:{text:'Private proof'}});
    await safety.decide('admin',{admin:true},{reportId,action,expectedRevision:1,decisionId:action+'_'+uid,reason:'Private admin reason'});
    const n=(await db.collection(`users/${uid}/notifications`).where('type','==',({warn:'safety.warned',hide:'safety.content_hidden',suspend:'safety.suspended'})[action]).get()).docs[0];
    return n;
  };
  // Keep the fixture in its own demo project; no production auth, token or FCM.
  try{
    for(const name of ['users','notificationOutbox','notificationTokens','safetyReports','safetyAudit','accountSafety','userBlocks','safetyContent'])await db.recursiveDelete(db.collection(name));
    await notifications.register('member',{deviceId:'phone',token:'emulator-fake-safety-token-1234567890',platform:'android'});
    await db.doc('userBlocks/member/items/admin').set({createdAt:now});
    const warned=await seed('warn');
    await Promise.all([notifications.deliver(warned.id),notifications.deliver(warned.id)]);
    assert.equal(sent.length,1);assert.equal(sent[0].notification.title,'Avertissement Foundi');
    const hidden=await seed('hide');await notifications.deliver(hidden.id);assert.equal(sent.length,2);
    await db.doc('proposals/ordinaryProposal').set({clientUid:'member',professionalUid:'peer'});
    assert.equal(await notifications.emit({eventId:'before-suspension',type:'proposal.created',recipientUid:'member',actorUid:'peer',resourceType:'proposal',resourceId:'ordinaryProposal'}),true);
    const suspended=await seed('suspend');
    assert.equal((await db.doc('accountSafety/member').get()).data().suspended,true);
    const resolved=await notifications.resolve('member',suspended.id);assert.equal(resolved.resourceType,'safetyNotice');
    await notifications.deliver(suspended.id);await notifications.deliver(suspended.id);
    assert.equal(sent.length,3);assert.equal(sent.at(-1).notification.title,'Compte Foundi suspendu');
    await notifications.deliver(key('before-suspension','member'));assert.equal(sent.length,3);
    assert.equal((await db.doc('notificationOutbox/'+key('before-suspension','member')).get()).data().reason,'account');
    await assert.rejects(notifications.resolve('member',key('before-suspension','member')),e=>e.code==='permission-denied');
    assert.equal((await safety.notices('member')).items.length,3);
    // An ordinary account/category job is not entitled to the suspension exception.
    await db.doc('users/member/notifications/forged').set({schemaVersion:9,type:'safety.suspended',resourceType:'safetyNotice',resourceId:'missing',recipientUid:'member',actorUid:null});
    await db.doc('notificationOutbox/forged').set({notificationId:'forged',uid:'member',actorUid:null,category:'account',state:'pending',createdAt:now,dueAt:now});
    await notifications.deliver('forged');assert.equal(sent.length,3);
    assert.equal((await db.doc('notificationOutbox/forged').get()).data().reason,'account');
    await assert.rejects(notifications.resolve('member','forged'),e=>e.code==='permission-denied');
    assert.equal(await notifications.emit({eventId:'ordinary',type:'proposal.created',recipientUid:'member',actorUid:'peer',resourceType:'proposal',resourceId:'p'}),false);
    await assert.rejects(notifications.register('member',{deviceId:'other',token:'emulator-other-device-token-1234567890',platform:'android'}),e=>e.code==='permission-denied');
    await assert.rejects(notifications.resolve('stranger',suspended.id),e=>e.code==='not-found');
    for(const p of sent)for(const secret of ['secret-reporter','Private','admin','evidence'])assert.ok(!JSON.stringify(p).includes(secret));
    assert.equal((await db.doc('users/member/notificationState/inbox').get()).data().unreadCount,4);
    // Preferences suppress only the push; the persistent notice remains.
    await db.doc('users/member/notificationPreferences/push').set({account:false});
    const r=key('restore');await db.doc(`safetyReports/${r}`).set({reportedUid:'member',targetType:'professional',targetId:'member',revision:1,status:'new'});
    await safety.decide('admin',{admin:true},{reportId:r,action:'warn',reason:'Private',expectedRevision:1,decisionId:'warn_preferences'});
    const newest=(await db.collection('users/member/notifications').where('type','==','safety.warned').get()).docs.find(d=>d.id!==warned.id);
    await notifications.deliver(newest.id);assert.equal(sent.length,3);
    assert.equal((await db.doc('notificationOutbox/'+newest.id).get()).data().reason,'preference');
    // A dismissed profile notice remains in history and cancels its queued push.
    const previousIds=new Set((await db.collection('users/member/notifications').get()).docs.map(d=>d.id));
    const ackReport=key('acknowledgement');await db.doc(`safetyReports/${ackReport}`).set({reportedUid:'member',targetType:'professional',targetId:'member',revision:1,status:'new'});
    await safety.decide('admin',{admin:true},{reportId:ackReport,action:'warn',reason:'Private',expectedRevision:1,decisionId:'ack-warning'});
    const ackNotification=(await db.collection('users/member/notifications').get()).docs.find(d=>!previousIds.has(d.id));
    await db.doc('users/member/notificationPreferences/push').set({account:true});
    const count=(await db.doc('users/member/notificationState/inbox').get()).data().unreadCount;
    await safety.acknowledgeNotice('member',{noticeId:ackNotification.data().resourceId});
    const read=(await ackNotification.ref.get()).data();
    await notifications.read('member',ackNotification.id,ackNotification.data(),read);
    await notifications.read('member',ackNotification.id,ackNotification.data(),read);
    assert.equal((await db.doc('users/member/notificationState/inbox').get()).data().unreadCount,count-1);
    await notifications.deliver(ackNotification.id);assert.equal(sent.length,3);
    assert.equal((await db.doc('notificationOutbox/'+ackNotification.id).get()).data().reason,'read');
    const history=(await safety.notices('member')).notices;
    assert.ok(history.find(n=>n.id===ackNotification.data().resourceId).acknowledgedAt);
    assert.equal((await notifications.resolve('member',ackNotification.id)).resourceType,'safetyNotice');
    // Even genuine moderation notices never bypass Firebase Auth disablement.
    await db.doc('users/disabled/devices/phone').set({pushEnabled:true,token:'disabled-emulator-token-1234567890'});
    const disabled=await seed('suspend','disabled');await notifications.deliver(disabled.id);assert.equal(sent.length,3);
  }finally{await deleteApp(app);}
});
