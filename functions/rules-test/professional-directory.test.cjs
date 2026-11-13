const {test}=require('node:test');
const fs=require('node:fs');
const assert=require('node:assert/strict');
const {initializeTestEnvironment,assertFails}=require('@firebase/rules-unit-testing');
const {doc,getDoc,setDoc}=require('firebase/firestore');
test('directory leaves private dossiers, cursors and limits closed to guests and members',
 {skip:!process.env.FIRESTORE_EMULATOR_HOST,timeout:60000},async()=>{
  assert.match(process.env.FIRESTORE_EMULATOR_HOST,/^(127\.0\.0\.1|localhost):/);
  const [host,port]=process.env.FIRESTORE_EMULATOR_HOST.split(':');
  const env=await initializeTestEnvironment({projectId:'demo-foundi',firestore:{host,port:Number(port),rules:fs.readFileSync(require('node:path').join(__dirname,'../../firestore.rules'),'utf8')}});
  try{
    const paths=['professionalProfiles/directory-private','professionalProfiles/directory-private/showcase/profile','professionalDirectoryCursors/opaque','professionalDirectoryLimits/budget'];
    await env.withSecurityRulesDisabled(async c=>{for(const p of paths)await setDoc(doc(c.firestore(),p),{businessName:'Privé',email:'secret@example.test',count:1});});
    for(const c of [env.unauthenticatedContext(),env.authenticatedContext('directory-stranger',{email_verified:true})]){
      for(const p of paths){await assertFails(getDoc(doc(c.firestore(),p)));await assertFails(setDoc(doc(c.firestore(),p),{status:'approved'}));}
    }
  }finally{await env.cleanup();}
});
