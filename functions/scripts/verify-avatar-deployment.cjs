const fs=require('node:fs'),assert=require('node:assert/strict');
const {randomBytes}=require('node:crypto');
const {GoogleAuth}=require('google-auth-library');
const args=process.argv.slice(2),option=name=>args.includes(name)?args[args.indexOf(name)+1]:null;
const targets=args.includes('--identity')?['savePersonalAvatar','readPersonalAvatarState','removePersonalAvatar','resolveRequestAvatars','readProfessionalShowcase','saveProfessionalShowcase','startProfessionalProfile']:['cleanupPersonalAvatars','savePersonalAvatar','readPersonalAvatarState','removePersonalAvatar','resolveRequestAvatars','readPublicPersonalAvatar','runAccountDeletion'];
async function main(){
 if(option('--project')!=='foundi-7c837'||!option('--before')||!option('--after'))throw Error('Explicit project and before/after metadata snapshots required.');
 const before=JSON.parse(fs.readFileSync(option('--before'),'utf8')),after=JSON.parse(fs.readFileSync(option('--after'),'utf8'));
 assert.equal(before.project,'foundi-7c837');assert.equal(after.project,before.project);
 for(const name of targets){const current=after.functions.find(f=>f.name===name);assert.equal(current?.state,'ACTIVE',name);const prior=before.functions.find(f=>f.name===name);if(prior)assert.notEqual(current.revision,prior.revision,name);}
 for(const prior of before.functions){const current=after.functions.find(f=>f.name===prior.name);assert.ok(current,prior.name);if(!targets.includes(prior.name))assert.equal(current.revision,prior.revision,'Unrelated function changed: '+prior.name);assert.equal(current.serviceAccount,prior.serviceAccount);}
 assert.ok(after.functions.filter(f=>!before.functions.some(p=>p.name===f.name)).every(f=>targets.includes(f.name)));
 const normal=s=>s.replace(/\r\n/g,'\n').trim();
 assert.ok(after.rules.firestore.source.source.files.some(f=>normal(f.content)===normal(fs.readFileSync('firestore.rules','utf8'))));
 assert.equal(after.rules.storage?.release.rulesetName,before.rules.storage?.release.rulesetName);
 assert.deepEqual(after.indexes,before.indexes,'Indexes changed outside photo scope');
 assert.deepEqual(after.policy,before.policy,'Deletion policy changed');
 assert.equal(after.functions.find(f=>f.name==='runAccountDeletion').deletionEnabled,'true');
 const base='https://europe-west1-foundi-7c837.cloudfunctions.net/',checks=[];
 for(const name of ['savePersonalAvatar','readPersonalAvatarState','removePersonalAvatar',...(args.includes('--identity')?['readProfessionalShowcase','saveProfessionalShowcase','startProfessionalProfile']:[])]){
  const response=await fetch(base+name,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({data:{publish:false}}),signal:AbortSignal.timeout(60000)});
  const value=await response.json();assert.equal(response.status,401,name);assert.equal(value.error?.status,'UNAUTHENTICATED',name);checks.push({name,status:response.status});
 }
 const resolution=await fetch(base+'resolveRequestAvatars',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({data:{requestIds:[]}}),signal:AbortSignal.timeout(60000)});
 assert.equal(resolution.status,200);assert.deepEqual((await resolution.json()).result,{avatars:{}});checks.push({name:'resolveRequestAvatars',status:200});
 const id=randomBytes(16).toString('hex'),version=randomBytes(16).toString('hex');
 const media=await fetch(base+`readPublicPersonalAvatar?id=${id}&version=${version}`,{signal:AbortSignal.timeout(60000)});
 assert.equal(media.status,404);assert.equal((await media.json()).error?.code,'not-found');assert.ok(media.headers.get('cache-control').includes('no-store'));checks.push({name:'readPublicPersonalAvatar',status:404});
 const rest='https://firestore.googleapis.com/v1/projects/foundi-7c837/databases/(default)/documents/';
 for(const [path,status]of [[`publicPersonalAvatars/${id}`,404],[`personalAvatars/${id}`,403]]){
  const response=await fetch(rest+path,{signal:AbortSignal.timeout(60000)});assert.equal(response.status,status,path);checks.push({name:path.split('/')[0],status});
 }
 const client=await new GoogleAuth({scopes:['https://www.googleapis.com/auth/cloud-platform']}).getClient();
 const job=(await client.request({url:'https://cloudscheduler.googleapis.com/v1/projects/foundi-7c837/locations/europe-west1/jobs/firebase-schedule-cleanupPersonalAvatars-europe-west1'})).data;
 assert.equal(job.state,'ENABLED');assert.ok(['every 60 minutes','0 * * * *'].includes(job.schedule));
 const result={project:after.project,verifiedAt:new Date().toISOString(),targets,checks,scheduler:{name:job.name,state:job.state,schedule:job.schedule},accountDataModified:false};
 if(option('--output'))fs.writeFileSync(option('--output'),JSON.stringify(result,null,2));
 console.log(JSON.stringify(result,null,2));
}
main().catch(error=>{console.error(error.message);process.exitCode=1;});
