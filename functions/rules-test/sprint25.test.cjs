const {test}=require('node:test'),fs=require('node:fs'),path=require('node:path');
const {initializeTestEnvironment,assertFails,assertSucceeds}=require('@firebase/rules-unit-testing');
const {doc,collection,getDoc,getDocs,setDoc}=require('firebase/firestore');
test('Sprint 2.5 public avatar projection is get-only, private account and mappings remain inaccessible',{skip:!process.env.FIRESTORE_EMULATOR_HOST},async()=>{
 const e=await initializeTestEnvironment({projectId:'demo-foundi',firestore:{rules:fs.readFileSync(path.join(__dirname,'../../firestore.rules'),'utf8')}});
 try {
  for(const context of [e.unauthenticatedContext(),e.authenticatedContext('avatar-owner'),e.authenticatedContext('avatar-admin',{admin:true})]) {
   const db=context.firestore();
   await assertSucceeds(getDoc(doc(db,'publicPersonalAvatars/public-key')));
   await assertFails(getDocs(collection(db,'publicPersonalAvatars')));
   await assertFails(setDoc(doc(db,'publicPersonalAvatars/public-key'),{version:'forged'}));
   for(const p of ['personalAvatars/avatar-owner','personalAvatarLookup/public-key','personalAvatarLimits/avatar-owner','personalAvatarGarbage/private-object']){
    await assertFails(getDoc(doc(db,p)));await assertFails(setDoc(doc(db,p),{uid:'forged'}));
   }
  }
  await assertFails(getDoc(doc(e.unauthenticatedContext().firestore(),'users/avatar-owner')));
 }finally{await e.cleanup();}
});
