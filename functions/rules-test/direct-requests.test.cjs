const {test,before,after}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs'),path=require('node:path');
const {initializeTestEnvironment,assertFails,assertSucceeds}=require('@firebase/rules-unit-testing');
const {doc,setDoc,getDoc,getDocs,collection,query,where,orderBy,limit,updateDoc,deleteDoc}=require('firebase/firestore');
const enabled=!!process.env.FIRESTORE_EMULATOR_HOST;
let env;
const privateRequest={visibility:'direct',clientUid:'direct-client',directProfessionalId:'direct-pro',status:'published',createdAt:1,title:'Contenu strictement privé'};
const target='directRequests/direct-request';
const inbox=db=>query(collection(db,'directRequests'),where('directProfessionalId','==','direct-pro'),where('status','in',['published','closed','in_discussion']),orderBy('createdAt','desc'),limit(50));
before(async()=>{
 if(!enabled)return;
 env=await initializeTestEnvironment({projectId:'demo-foundi',firestore:{rules:fs.readFileSync(path.join(__dirname,'../../firestore.rules'),'utf8')}});
 await env.withSecurityRulesDisabled(async c=>{
  const db=c.firestore();await setDoc(doc(db,target),privateRequest);
  await setDoc(doc(db,'professionalProfiles/direct-pro'),{status:'approved'});
  await setDoc(doc(db,'professionalProfiles/direct-other'),{status:'approved'});
  await setDoc(doc(db,'userRequests/direct-client/items/direct-request'),privateRequest);
 });
});
after(async()=>{if(env)await env.cleanup();});
const check=(name,body)=>test(name,{skip:!enabled},body);
check('only the owner and chosen approved professional can read; guests and other approved pros cannot',async()=>{
 for(const context of [env.unauthenticatedContext(),env.authenticatedContext('direct-other'),env.authenticatedContext('unrelated')]){
  const db=context.firestore();await assertFails(getDoc(doc(db,target)));await assertFails(getDocs(inbox(db)));
 }
 await assertSucceeds(getDoc(doc(env.authenticatedContext('direct-client').firestore(),target)));
 const db=env.authenticatedContext('direct-pro').firestore();await assertSucceeds(getDoc(doc(db,target)));
 const received=await assertSucceeds(getDocs(inbox(db)));assert.deepEqual(received.docs.map(d=>d.id),['direct-request']);
 await assertFails(getDocs(query(collection(db,'directRequests'),limit(50))));
 await assertFails(getDocs(query(collection(db,'directRequests'),where('directProfessionalId','==','direct-pro'))));
 await assertFails(getDoc(doc(db,'userRequests/direct-client/items/direct-request')));
 await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(),'requests/direct-request')));
});
check('client writes cannot forge a recipient, publish a direct request, or modify a private record',async()=>{
 for(const who of ['direct-client','direct-pro','direct-other','admin']){
  const db=env.authenticatedContext(who,{admin:true}).firestore();
  await assertFails(setDoc(doc(db,'directRequests/forged'),privateRequest));
  await assertFails(updateDoc(doc(db,target),{directProfessionalId:who}));
  await assertFails(deleteDoc(doc(db,target)));
  await assertFails(setDoc(doc(db,'requests/direct-request'),privateRequest));
 }
});
check('suspension and deletion revoke recipient access and remove deleted requests from the inbox',async()=>{
 const db=env.authenticatedContext('direct-pro').firestore();
 await env.withSecurityRulesDisabled(c=>updateDoc(doc(c.firestore(),'professionalProfiles/direct-pro'),{status:'suspended'}));
 await assertFails(getDoc(doc(db,target)));await assertFails(getDocs(inbox(db)));
 await env.withSecurityRulesDisabled(async c=>{
  await updateDoc(doc(c.firestore(),'professionalProfiles/direct-pro'),{status:'approved'});
  await updateDoc(doc(c.firestore(),target),{status:'deleted'});
 });
 await assertFails(getDoc(doc(db,target)));
 assert.equal((await assertSucceeds(getDocs(inbox(db)))).empty,true);
 await assertSucceeds(getDoc(doc(env.authenticatedContext('direct-client').firestore(),target)));
});
