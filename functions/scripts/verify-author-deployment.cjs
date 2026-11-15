const fs=require('node:fs'),assert=require('node:assert/strict'),{randomBytes}=require('node:crypto');
const args=process.argv.slice(2),option=name=>args.includes(name)?args[args.indexOf(name)+1]:null;
async function main(){
 if(option('--project')!=='foundi-7c837'||!option('--before')||!option('--after'))throw Error('Explicit project and before/after snapshots required.');
 const before=JSON.parse(fs.readFileSync(option('--before'),'utf8')),after=JSON.parse(fs.readFileSync(option('--after'),'utf8')),target='readRequestAuthorProfile';
 assert.equal(before.project,'foundi-7c837');assert.equal(after.project,before.project);
 const current=after.functions.find(f=>f.name===target),prior=before.functions.find(f=>f.name===target);
 assert.equal(current?.state,'ACTIVE');assert.ok(current.revision);
 if(prior)assert.notEqual(current.revision,prior.revision);
 assert.equal(current.serviceAccount,before.functions.find(f=>f.name==='readPublicProfessionalProfile').serviceAccount);
 for(const f of before.functions){
  const next=after.functions.find(n=>n.name===f.name);assert.ok(next,f.name);
  if(f.name!==target){assert.equal(next.revision,f.revision,f.name+' changed');assert.equal(next.serviceAccount,f.serviceAccount);}
 }
 assert.ok(after.functions.filter(f=>!before.functions.some(p=>p.name===f.name)).every(f=>f.name===target));
 for(const key of ['indexes','fields','policy','auth','storage'])assert.deepEqual(after[key],before[key],key+' changed');
 for(const name of ['firestore','storage'])assert.equal(after.rules[name]?.release.rulesetName,before.rules[name]?.release.rulesetName,name+' rules changed');
 const url='https://europe-west1-foundi-7c837.cloudfunctions.net/'+target,checks=[];
 for(const [data,status,code]of [
  [{requestId:'../private'},400,'INVALID_ARGUMENT'],
  [{requestId:'AuthorSmoke'+randomBytes(12).toString('hex'),uid:'forged'},400,'INVALID_ARGUMENT'],
  [{requestId:'AuthorSmoke'+randomBytes(12).toString('hex')},404,'NOT_FOUND'],
 ]){
  const response=await fetch(url,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({data}),signal:AbortSignal.timeout(60000)}),value=await response.json();
  assert.equal(response.status,status,JSON.stringify(value));assert.equal(value.error?.status,code);
  assert.equal(value.result,undefined);checks.push({case:status===404?'nonexistent request':data.uid?'forged owner':'invalid request',status,code});
 }
 const result={project:after.project,verifiedAt:new Date().toISOString(),target,state:current.state,revision:current.revision,otherFunctionsUnchanged:before.functions.filter(f=>f.name!==target).length,checks,customerRecordsModified:false};
 if(option('--output'))fs.writeFileSync(option('--output'),JSON.stringify(result,null,2));
 console.log(JSON.stringify(result,null,2));
}
main().catch(error=>{console.error(error.message);process.exitCode=1;});
