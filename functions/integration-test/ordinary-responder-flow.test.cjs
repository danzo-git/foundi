const {test} = require('node:test');
const assert = require('node:assert/strict');
const {initializeApp,deleteApp} = require('firebase/app');
const {getAuth,connectAuthEmulator,signInWithEmailAndPassword} = require('firebase/auth');
const {getFirestore,connectFirestoreEmulator,doc,getDoc,getDocs,collection,query,where,or,orderBy,limit,setDoc,updateDoc} = require('firebase/firestore');
const {getFunctions,connectFunctionsEmulator,httpsCallable} = require('firebase/functions');
const {initializeApp:adminApp,deleteApp:deleteAdmin} = require('firebase-admin/app');
const {getAuth:adminAuth} = require('firebase-admin/auth');
const {getFirestore:adminDb} = require('firebase-admin/firestore');
const {key} = require('../src/notification-policy');
const enabled = !!(process.env.FIREBASE_AUTH_EMULATOR_HOST && process.env.FIRESTORE_EMULATOR_HOST && process.env.FUNCTIONS_EMULATOR_HOST);
const pair = s => {const [host,port]=s.split(':');return [host,Number(port)];};

test('ordinary/professional: real callables, mixed respondents, legacy history, notifications and private rules',{skip:!enabled,timeout:240000},async()=>{
  const stamp=Date.now(),admin=adminApp({projectId:'demo-foundi'},`ordinary-${stamp}`),db=adminDb(admin),auth=adminAuth(admin),apps=[],users=[],requests=[],proposals=[];
  async function client(name,{signed=true,verified=true}={}) {
    const app=initializeApp({projectId:'demo-foundi',apiKey:'emulator-only',appId:`ordinary-${name}`},`${name}-${stamp}`);apps.push(app);
    const a=getAuth(app);connectAuthEmulator(a,'http://'+process.env.FIREBASE_AUTH_EMULATOR_HOST,{disableWarnings:true});
    let uid;
    if(signed){const email=`${name}-${stamp}@example.test`,password='Test-Password-123!';const user=await auth.createUser({email,password,emailVerified:verified});uid=user.uid;users.push(uid);await db.doc(`users/${uid}`).set({fullName:`Public ${name}`});await signInWithEmailAndPassword(a,email,password);}
    const firestore=getFirestore(app);connectFirestoreEmulator(firestore,...pair(process.env.FIRESTORE_EMULATOR_HOST));
    const functions=getFunctions(app,'europe-west1');connectFunctionsEmulator(functions,...pair(process.env.FUNCTIONS_EMULATOR_HOST));
    return {uid,db:firestore,call:(name,data)=>httpsCallable(functions,name)(data).then(result=>result.data)};
  }
  async function waitFor(fn) {
    const deadline=Date.now()+30000;
    while(Date.now()<deadline){if(await fn())return;await new Promise(resolve=>setTimeout(resolve,200));}
    assert.fail('Expected emulator trigger result was not received');
  }
  const denied=code=>error=>error.code===`functions/${code}`;
  const draft={description:'Une proposition privée avec une solution.',amount:12500,delay:'Deux jours'};
  try {
    const owner=await client('owner'),ordinary=await client('ordinary'),pro=await client('approved'),pending=await client('pending'),third=await client('third'),unverified=await client('unverified',{verified:false}),guest=await client('guest',{signed:false});
    await db.doc(`professionalProfiles/${pro.uid}`).set({status:'approved',businessName:'Atelier certifié',categoryIds:['service'],specialtyIds:['repair'],zoneIds:['zone']});
    await db.doc(`professionalProfiles/${pending.uid}`).set({status:'pending',businessName:'Dossier en attente'});
    const requestId=db.collection('requests').doc().id;requests.push(requestId);
    const request={title:'Besoin ouvert à tous',description:'Description du besoin accessible.',status:'published',createdAt:stamp,updatedAt:stamp,categoryId:'service',categoryLabel:'Services',specialtyId:'repair',specialtyLabel:'Réparation',zoneId:'zone',zoneLabel:'Zone',budget:null};
    await Promise.all([db.doc(`requests/${requestId}`).set(request),db.doc(`requestOwnership/${requestId}`).set({ownerUid:owner.uid}),db.doc(`userRequests/${owner.uid}/items/${requestId}`).set(request)]);
    for(const [who,code] of [[guest,'unauthenticated'],[unverified,'permission-denied'],[owner,'permission-denied']])await assert.rejects(who.call('sendProposal',{requestId,proposal:draft}),denied(code));
    for(const fields of [{responderUid:pro.uid},{professionalUid:pro.uid},{certified:true}])await assert.rejects(ordinary.call('sendProposal',{requestId,proposal:{...draft,...fields}}),denied('invalid-argument'));
    const rows=[];
    for(const responder of [ordinary,pro,pending]) {
      const [p,retry]=await Promise.all([responder.call('sendProposal',{requestId,proposal:draft}),responder.call('sendProposal',{requestId,proposal:draft})]);
      proposals.push(p.id);rows.push({p,responder});assert.equal(p.id,retry.id);assert.equal(p.responderUid,responder.uid);
      assert.equal(p.professionalUid,responder===pro?pro.uid:undefined);
      assert.equal((await getDoc(doc(owner.db,`proposals/${p.id}`))).data().description,draft.description);
      await assert.rejects(getDoc(doc(third.db,`proposals/${p.id}`)),{code:'permission-denied'});
      await assert.rejects(updateDoc(doc(responder.db,`proposals/${p.id}`),{responderUid:third.uid}),{code:'permission-denied'});
      await waitFor(async()=> (await db.doc(`users/${owner.uid}/notifications/${key(`proposals/${p.id}/created`,owner.uid)}`).get()).exists);
      assert.equal((await db.collection(`users/${owner.uid}/notifications`).where('proposalId','==',p.id).where('type','==','proposal.created').get()).size,1);
    }
    assert.equal((await db.doc(`userRequests/${owner.uid}/items/${requestId}`).get()).data().proposalCount,3);
    const publicRows=await guest.call('listRequestRespondents',{requestId});
    assert.equal(publicRows.total,3);assert.equal(publicRows.items.length,3);assert.equal(publicRows.canViewProposals,false);
    assert.equal(publicRows.items.filter(row=>row.certified).length,1);assert.equal(publicRows.items.find(row=>row.responderId===ordinary.uid).professionalId,null);
    assert.ok(!JSON.stringify(publicRows).includes(draft.description));
    const certifications=(await owner.call('resolveProposalCertifications',{proposalIds:proposals})).certifications;
    assert.deepEqual(proposals.map(id=>certifications[id]),[false,true,false]);
    assert.deepEqual((await third.call('resolveProposalCertifications',{proposalIds:proposals})).certifications,{});
    // Rewrite one approved proposal to the exact historical shape to exercise fallback reads.
    const legacy=rows[1].p;const old={...legacy};delete old.id;delete old.responderUid;delete old.responderName;
    await db.doc(`proposals/${legacy.id}`).set(old);
    let retained=null;
    for(const {p,responder} of rows) {
      const opened=await owner.call('selectProposal',{requestId,proposalId:p.id});assert.equal(opened.conversationId,p.id);
      const chat=(await getDoc(doc(responder.db,`conversations/${p.id}`))).data();assert.equal(chat.responderUid,responder.uid);
      await owner.call('decideProposal',{requestId,proposalId:p.id,action:'retain',decisionId:db.collection('ids').doc().id,expectedRetainedProposalId:retained});retained=p.id;
      await responder.call('sendConversationMessage',{conversationId:p.id,messageId:'MessageIdentifier0001',text:'Bonjour auteur'});
      await owner.call('sendConversationMessage',{conversationId:p.id,messageId:'MessageIdentifier0002',text:'Bonjour répondant'});
      await assert.rejects(getDoc(doc(third.db,`conversations/${p.id}`)),{code:'permission-denied'});
      await assert.rejects(third.call('sendConversationMessage',{conversationId:p.id,messageId:'MessageIdentifier0003',text:'Intrusion'}),denied('permission-denied'));
      await waitFor(async()=> (await db.doc(`users/${responder.uid}/messageInbox/${key(`messages/${p.id}/MessageIdentifier0002`,responder.uid)}`).get()).exists);
      const sent=await getDocs(query(collection(responder.db,'proposals'),or(where('responderUid','==',responder.uid),where('professionalUid','==',responder.uid)),orderBy('createdAt','desc'),limit(30)));
      assert.equal(sent.size,1);
      assert.equal((await getDocs(query(collection(responder.db,'conversations'),or(where('responderUid','==',responder.uid),where('professionalUid','==',responder.uid)),orderBy('updatedAt','desc'),orderBy('__name__','desc'),limit(30)))).size,1);
    }
    const ordinaryId=rows[0].p.id;
    await db.doc(`userBlocks/${owner.uid}/items/${ordinary.uid}`).set({createdAt:Date.now()});
    await assert.rejects(ordinary.call('sendConversationMessage',{conversationId:ordinaryId,messageId:'MessageIdentifier0004',text:'Blocage ignoré'}),denied('failed-precondition'));
    await db.doc(`userBlocks/${owner.uid}/items/${ordinary.uid}`).delete();
    await db.doc(`professionalProfiles/${pro.uid}`).update({status:'rejected'});
    assert.equal((await owner.call('resolveProposalCertifications',{proposalIds:[legacy.id]})).certifications[legacy.id],false);
    assert.equal((await guest.call('listRequestRespondents',{requestId})).items.filter(row=>row.certified).length,0);
    await assert.rejects(setDoc(doc(ordinary.db,`professionalProfiles/${ordinary.uid}`),{status:'approved'}),{code:'permission-denied'});
    await owner.call('manageRequest',{requestId,action:'close'});
    await assert.rejects(third.call('sendProposal',{requestId,proposal:draft}),denied('failed-precondition'));
    await owner.call('decideProposal',{requestId,proposalId:ordinaryId,action:'reject',decisionId:db.collection('ids').doc().id,expectedRetainedProposalId:retained});
    await assert.rejects(ordinary.call('sendConversationMessage',{conversationId:ordinaryId,messageId:'MessageIdentifier0005',text:'Refus ignoré'}),denied('failed-precondition'));
    assert.equal((await getDoc(doc(ordinary.db,`conversations/${ordinaryId}/messages/MessageIdentifier0001`))).exists(),true);
    // Privacy worker must discover neutral fields, erase the sender's messages,
    // preserve the other participant's history, and remain idempotent.
    const deletionJob={id:'ordinary-'+stamp,uid:ordinary.uid,alias:'deleted-'+stamp};
    const purger=require('../src/privacy-purge').createPrivacyPurger({db,bucket:{getFiles:async()=>[[],null]}});
    for(let i=0;i<8;i++)if((await purger.run(deletionJob,'conversations_pro')).done)break;
    const erased=(await db.doc(`conversations/${ordinaryId}`).get()).data();
    assert.equal(erased.responderUid,deletionJob.alias);assert.equal(erased.professionalUid,undefined);assert.equal(erased.responderName,'Compte supprimé');
    assert.equal((await db.doc(`conversations/${ordinaryId}/messages/MessageIdentifier0002`).get()).data().senderUid,owner.uid);
    for(let i=0;i<5;i++)if((await purger.run(deletionJob,'proposals_sent')).done)break;
    assert.equal((await db.doc(`proposals/${ordinaryId}`).get()).exists,false);
    assert.equal((await purger.run(deletionJob,'conversations_pro')).done,true);
    await db.recursiveDelete(db.doc(`accountDeletionJobs/${deletionJob.id}`));
  } finally {
    await Promise.allSettled(apps.map(deleteApp));
    for(const id of proposals){await db.recursiveDelete(db.doc(`conversations/${id}`));await db.doc(`proposals/${id}`).delete();}
    for(const id of requests){await db.doc(`requests/${id}`).delete();await db.doc(`requestOwnership/${id}`).delete();}
    for(const uid of users){await db.recursiveDelete(db.doc(`users/${uid}`));await db.recursiveDelete(db.doc(`userRequests/${uid}`));await db.recursiveDelete(db.doc(`userBlocks/${uid}`));await db.doc(`professionalProfiles/${uid}`).delete();await auth.deleteUser(uid);}
    await deleteAdmin(admin);
  }
});
