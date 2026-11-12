// Read-only verification of every repaired document against the reviewed plan.
const fs=require('node:fs');
const assert=require('node:assert/strict');
const {createHash}=require('node:crypto');
const {initializeApp,deleteApp}=require('firebase-admin/app');
const {getFirestore}=require('firebase-admin/firestore');
const digest=value=>createHash('sha256').update(JSON.stringify(value)).digest('hex');
function stable(value){
  if(Array.isArray(value))return value.map(stable);
  if(value&&typeof value==='object')return Object.fromEntries(Object.keys(value).sort().map(k=>[k,stable(value[k])]));
  return value;
}
function restoredHash(data,previous){
  const copy={...data};
  if(previous.present)copy.authorPublicName=previous.value;
  else delete copy.authorPublicName;
  return digest(stable(copy));
}
async function main(){
  if(process.env.FIRESTORE_EMULATOR_HOST)throw Error('Verification must read production');
  const [planPath,resultPath,output]=process.argv.slice(2);assert.ok(planPath&&resultPath&&output);
  const plan=JSON.parse(fs.readFileSync(planPath,'utf8')),result=JSON.parse(fs.readFileSync(resultPath,'utf8'));
  assert.equal(plan.project,'foundi-7c837');assert.equal(result.project,plan.project);
  assert.ok(plan.entries.length<=50);
  const app=initializeApp({projectId:plan.project}),db=getFirestore(app),entries=[];
  try{
    for(const entry of plan.entries){
      assert.ok(result.results.some(r=>r.requestId===entry.requestId&&['repaired','already_current'].includes(r.state)));
      const ownership=(await db.doc(`requestOwnership/${entry.requestId}`).get()).data();
      assert.equal(digest(ownership?.ownerUid),entry.ownerHash,'Owner changed');
      const [publicDoc,ownDoc]=await db.getAll(db.doc(`requests/${entry.requestId}`),db.doc(`userRequests/${ownership.ownerUid}/items/${entry.requestId}`));
      const publicData=publicDoc.data(),ownData=ownDoc.data();
      const namesMatch=digest(publicData?.authorPublicName)===entry.nameHash&&digest(ownData?.authorPublicName)===entry.nameHash;
      const fieldsPreserved=restoredHash(publicData,entry.previousNames.public)===entry.publicHash&&restoredHash(ownData,entry.previousNames.own)===entry.ownHash;
      assert.ok(namesMatch,entry.requestId+': name mismatch');
      assert.ok(fieldsPreserved,entry.requestId+': other fields changed');
      entries.push({requestId:entry.requestId,namesMatch,fieldsPreserved});
    }
    const verification={project:plan.project,checkedAt:new Date().toISOString(),verified:entries.length,entries};
    fs.writeFileSync(output,JSON.stringify(verification,null,2),{flag:'wx'});
    console.log(JSON.stringify(verification));
  }finally{await deleteApp(app);}
}
main().catch(error=>{console.error(error.message);process.exitCode=1;});
