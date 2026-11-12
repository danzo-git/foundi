// Default: read-only plan. --apply only fills missing names on reviewed public requests.
const fs=require('node:fs');
const assert=require('node:assert/strict');
const {initializeApp,deleteApp}=require('firebase-admin/app');
const {getFirestore}=require('firebase-admin/firestore');
const {getAuth}=require('firebase-admin/auth');
const {createRequestAuthorRepair}=require('../src/request-author-repair');
const project='foundi-7c837';
async function main(){
  if(process.env.FIRESTORE_EMULATOR_HOST || process.env.FIREBASE_AUTH_EMULATOR_HOST)throw Error('Production tool must not use emulators');
  const args=process.argv.slice(2),option=k=>args.includes(k)?args[args.indexOf(k)+1]:null;
  const app=initializeApp({projectId:project}),db=getFirestore(app),auth=getAuth(app);
  const store={transaction:op=>db.runTransaction(tx=>op({get:async p=>(await tx.get(db.doc(p))).data(),update:(p,v)=>tx.update(db.doc(p),v)}))};
  const repair=createRequestAuthorRepair({store,auth});
  try{
    if(!args.includes('--apply')){
      const docs=await db.collection('requests').where('status','==','published').limit(51).select('createdAt').get();
      if(docs.size>50)throw Error('More than 50 public requests: use a separately reviewed scope');
      const plan={project,createdAt:new Date().toISOString(),...(await repair.plan(docs.docs.map(d=>d.id)))};
      const output=option('--output');assert.ok(output,'--output is required');
      fs.writeFileSync(output,JSON.stringify(plan,null,2),{flag:'wx'});
      console.log(JSON.stringify({mode:'plan',project,scanned:docs.size,candidates:plan.entries.length,entries:plan.entries.map(e=>({requestId:e.requestId,createdAt:e.createdAt})),skipped:plan.skipped}));
      return;
    }
    const input=option('--plan'),output=option('--output');assert.ok(input&&output,'--plan and --output required');
    assert.equal(option('--project'),project,'Explicit production project confirmation required');
    const plan=JSON.parse(fs.readFileSync(input,'utf8'));assert.equal(plan.project,project);
    assert.ok(Array.isArray(plan.entries)&&plan.entries.length<=50);
    assert.ok(Date.now()-Date.parse(plan.createdAt)>=0&&Date.now()-Date.parse(plan.createdAt)<3600000,'Plan must be less than one hour old');
    assert.ok(!fs.existsSync(output),'Refusing to overwrite a repair report');
    const results=[];
    const save=()=>fs.writeFileSync(output,JSON.stringify({project,checkedAt:new Date().toISOString(),plan:input,results},null,2));
    save();
    for(const entry of plan.entries){results.push(await repair.apply(entry));save();}
    console.log(JSON.stringify({project,results}));
    if(results.some(r=>r.state==='conflict'))process.exitCode=2;
  }finally{await deleteApp(app);}
}
main().catch(error=>{console.error(error.message);process.exitCode=1;});
