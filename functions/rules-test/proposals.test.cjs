const {test,before,after}=require('node:test');
const fs=require('node:fs');const path=require('node:path');
const {initializeTestEnvironment,assertFails,assertSucceeds}=require('@firebase/rules-unit-testing');
const {doc,setDoc,getDoc,getDocs,collection,query,where,orderBy,limit,updateDoc,deleteDoc}=require('firebase/firestore');
const enabled=!!process.env.FIRESTORE_EMULATOR_HOST;let env;
const proposal={requestId:'RequestIdentifier00001',professionalUid:'pro',clientUid:'client',professionalName:'Atelier',requestTitle:'Demande',description:'Proposition privée',amount:20000,delay:'2 jours',createdAt:1,status:'sent'};
before(async()=>{if(!enabled)return;env=await initializeTestEnvironment({projectId:'demo-foundi-proposals',firestore:{rules:fs.readFileSync(path.join(__dirname,'../../firestore.rules'),'utf8')}});await env.withSecurityRulesDisabled(async c=>{await setDoc(doc(c.firestore(),'proposals/proposal'),proposal);await setDoc(doc(c.firestore(),'requestOwnership/RequestIdentifier00001'),{ownerUid:'client'});});});
after(async()=>{if(env)await env.cleanup();});
const check=(name,fn)=>test(name,{skip:!enabled},fn);
check('only proposal parties can get or query their private proposals, including after suspension or request closure',async()=>{
 for(const uid of ['pro','client']){const db=env.authenticatedContext(uid).firestore();await assertSucceeds(getDoc(doc(db,'proposals/proposal')));await assertSucceeds(getDocs(query(collection(db,'proposals'),where(uid==='pro'?'professionalUid':'clientUid','==',uid),orderBy('createdAt','desc'),limit(30))));}
 for(const c of [env.unauthenticatedContext(),env.authenticatedContext('third'),env.authenticatedContext('another-pro')])await assertFails(getDoc(doc(c.firestore(),'proposals/proposal')));
 const client=env.authenticatedContext('client').firestore();await assertSucceeds(getDocs(query(collection(client,'proposals'),where('clientUid','==','client'),where('requestId','==',proposal.requestId),orderBy('createdAt','desc'),limit(30))));
 await assertFails(getDocs(query(collection(client,'proposals'),limit(30))));await assertFails(getDocs(query(collection(client,'proposals'),where('clientUid','==','client'))));await assertFails(getDocs(query(collection(client,'proposals'),where('clientUid','==','client'),limit(51))));
});
check('no client can create, forge, update status, delete proposals or read private ownership records',async()=>{
 for(const c of [env.unauthenticatedContext(),env.authenticatedContext('client'),env.authenticatedContext('pro'),env.authenticatedContext('admin',{admin:true})]){const db=c.firestore();await assertFails(setDoc(doc(db,'proposals/forged'),proposal));await assertFails(updateDoc(doc(db,'proposals/proposal'),{status:'accepted'}));await assertFails(updateDoc(doc(db,'proposals/proposal'),{clientUid:'third'}));await assertFails(deleteDoc(doc(db,'proposals/proposal')));await assertFails(getDoc(doc(db,'requestOwnership/RequestIdentifier00001')));await assertFails(setDoc(doc(db,'requestOwnership/forged'),{ownerUid:'third'}));}
});
