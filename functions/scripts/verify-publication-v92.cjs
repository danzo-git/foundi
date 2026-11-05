const fs=require('node:fs'),assert=require('node:assert/strict');
const {GoogleAuth}=require('google-auth-library');
const project='foundi-7c837',region='europe-west1';
const normal=value=>value.replace(/\r\n/g,'\n').trim();
async function main(){
 const args=process.argv.slice(2),option=name=>args.includes(name)?args[args.indexOf(name)+1]:null;
 const baseline=option('--before'),output=option('--output');
 const client=await new GoogleAuth({scopes:['https://www.googleapis.com/auth/cloud-platform']}).getClient();
 const get=async url=>(await client.request({url})).data;
 const snapshot={project,region,checkedAt:new Date().toISOString(),functions:[],indexes:[]};
 let token;
 do{
  const page=await get(`https://cloudfunctions.googleapis.com/v2/projects/${project}/locations/${region}/functions?pageSize=100${token?'&pageToken='+encodeURIComponent(token):''}`);
  snapshot.functions.push(...(page.functions || []).map(f=>({name:f.name.split('/').at(-1),state:f.state,revision:f.serviceConfig?.revision,updatedAt:f.updateTime,uri:f.serviceConfig?.uri,runtime:f.buildConfig?.runtime})));
  token=page.nextPageToken;
 }while(token);
 const release=await get(`https://firebaserules.googleapis.com/v1/projects/${project}/releases/cloud.firestore`);
 snapshot.rules=await get(`https://firebaserules.googleapis.com/v1/${release.rulesetName}`);
 token=undefined;
 do{
  const page=await get(`https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/collectionGroups/-/indexes${token?'?pageToken='+encodeURIComponent(token):''}`);
  snapshot.indexes.push(...(page.indexes || []));token=page.nextPageToken;
 }while(token);
 const publish=snapshot.functions.find(f=>f.name==='publishRequest');
 assert.equal(publish?.state,'ACTIVE','publishRequest must be ACTIVE');
 if(baseline){
  const before=JSON.parse(fs.readFileSync(baseline,'utf8'));
  assert.equal(before.project,project);
  assert.notEqual(publish.revision,before.functions.find(f=>f.name==='publishRequest')?.revision,'Publication revision did not change');
  const changed=[];
  for(const prior of before.functions){
   const current=snapshot.functions.find(f=>f.name===prior.name);
   assert.ok(current,'Missing existing function: '+prior.name);
   if(current.revision!==prior.revision)changed.push(prior.name);
  }
  assert.deepEqual(changed.sort(),['publishRequest'],'Unexpected function updates');
  assert.equal(snapshot.functions.length,before.functions.length,'Unexpected new/deleted function');
  assert.deepEqual(snapshot.indexes.map(i=>i.name).sort(),before.indexes.map(i=>i.name).sort(),'Indexes changed');
  assert.equal(normal(snapshot.rules.source.files.find(f=>f.name==='firestore.rules').content),normal(fs.readFileSync('firestore.rules','utf8')),'Published rules differ from validated source');
  const response=await fetch(publish.uri,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({data:{}})});
  const body=await response.json();
  assert.equal(response.status,401,'Unauthenticated publication must fail');
  assert.equal(body.error?.status,'UNAUTHENTICATED');
  snapshot.unauthenticated={status:response.status,error:body.error.status};
  snapshot.changedFunctions=changed;
 }
 if(output)fs.writeFileSync(output,JSON.stringify(snapshot,null,2));
 console.log(JSON.stringify({project,region,publication:{state:publish.state,revision:publish.revision,updatedAt:publish.updatedAt},functionCount:snapshot.functions.length,changedFunctions:snapshot.changedFunctions,indexCount:snapshot.indexes.length,indexStates:snapshot.indexes.reduce((s,i)=>(s[i.state]=(s[i.state]||0)+1,s),{}),rulesSaved:!!snapshot.rules,unauthenticated:snapshot.unauthenticated}));
}
main().catch(e=>{console.error(e.message);process.exitCode=1;});
