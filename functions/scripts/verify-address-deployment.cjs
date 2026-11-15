const fs=require('node:fs'),assert=require('node:assert/strict');
const args=process.argv.slice(2),option=name=>args.includes(name)?args[args.indexOf(name)+1]:null;
const targets=['publishRequest','publishDirectRequest','manageRequest','listOpportunities','decideSafetyReport','getRequestAddressCapabilities'];
async function main(){
 if(option('--project')!=='foundi-7c837'||!option('--before')||!option('--after')||process.env.FIRESTORE_EMULATOR_HOST)throw Error('Explicit production project and snapshots required, without emulator.');
 const read=name=>JSON.parse(fs.readFileSync(option(name),'utf8'));
 const before=read('--before'),after=read('--after');
 assert.equal(before.project,'foundi-7c837');assert.equal(after.project,before.project);
 const deployed=targets.map(name=>{
  const current=after.functions.find(f=>f.name===name),prior=before.functions.find(f=>f.name===name);
  assert.equal(current?.state,'ACTIVE',name);assert.ok(current.revision,name);
  if(prior){assert.notEqual(current.revision,prior.revision,name);assert.equal(current.serviceAccount,prior.serviceAccount,name);}
  else assert.equal(current.serviceAccount,before.functions.find(f=>f.name==='publishRequest').serviceAccount);
  return {name,state:current.state,revision:current.revision,updateTime:current.updateTime};
 });
 const capability=deployed.find(f=>f.name==='getRequestAddressCapabilities');
 for(const f of deployed.filter(f=>f!==capability))assert.ok(Date.parse(capability.updateTime)>Date.parse(f.updateTime),'Capability must be deployed after '+f.name);
 for(const prior of before.functions){
  const current=after.functions.find(f=>f.name===prior.name);assert.ok(current,prior.name);
  if(!targets.includes(prior.name)){assert.equal(current.revision,prior.revision,prior.name+' changed');assert.equal(current.serviceAccount,prior.serviceAccount);assert.equal(current.updateTime,prior.updateTime);}
 }
 assert.equal(after.functions.length,before.functions.length+targets.filter(t=>!before.functions.some(f=>f.name===t)).length);
 for(const key of ['indexes','fields','policy','auth','storage'])assert.deepEqual(after[key],before[key],key+' changed');
 for(const name of ['firestore','storage'])assert.equal(after.rules[name]?.release.rulesetName,before.rules[name]?.release.rulesetName,name+' rules changed');
 const checks=await Promise.all(targets.map(async name=>{
  // No authenticated customer session and no customer data are used in production.
  const response=await fetch('https://europe-west1-foundi-7c837.cloudfunctions.net/'+name,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({data:{}}),signal:AbortSignal.timeout(60000)}),value=await response.json();
  assert.equal(response.status,401,name+': '+JSON.stringify(value));assert.equal(value.error?.status,'UNAUTHENTICATED',name);assert.equal(value.result,undefined);
  return {name,case:'unauthenticated invocation denied',status:response.status};
 }));
 const response=await fetch('https://firestore.googleapis.com/v1/projects/foundi-7c837/databases/(default)/documents/referenceData/professionalOnboarding',{signal:AbortSignal.timeout(60000)});
 assert.equal(response.status,200);const catalogue=await response.json();assert.deepEqual(catalogue,read('--catalogue-before'),'Catalogue changed');
 const result={project:after.project,verifiedAt:new Date().toISOString(),targets:deployed,capabilityDeployedLast:true,otherFunctionsUnchanged:before.functions.filter(f=>!targets.includes(f.name)).length,rulesIndexesAuthStoragePrivacyPolicyUnchanged:true,catalogueUnchanged:true,checks,customerRecordsModified:false,apkDistributed:false};
 if(option('--output'))fs.writeFileSync(option('--output'),JSON.stringify(result,null,2));console.log(JSON.stringify(result,null,2));
}
main().catch(error=>{console.error(error.message);process.exitCode=1;});
