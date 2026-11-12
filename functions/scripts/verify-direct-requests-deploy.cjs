const fs = require('node:fs');
const assert = require('node:assert/strict');
const {GoogleAuth} = require('google-auth-library');
const project = 'foundi-7c837', region = 'europe-west1';
const privateUx = process.argv.includes('--private-ux');
const accountName = process.argv.includes('--account-name');
const targets = accountName ? ['publishRequest','manageRequest'] : privateUx
  ? ['publishDirectRequest','manageRequest','readProfessionalShowcase','readRequestRecommendation','readRequestRespondentProfile','readDirectRequestAuthors']
  : ['publishDirectRequest','publishRequest','manageRequest','proposalAccess','sendProposal','selectProposal','uploadRequestPhoto','readRequestPhoto','notifyDirectRequestCreated','resolveNotification','deliverNotificationPush','drainNotifications','readRequestRecommendation'];
const normal = value => value.replace(/\r\n/g,'\n').trim();
function indexKey(value) {
  const group = value.collectionGroup || value.name.split('/collectionGroups/')[1].split('/')[0];
  return JSON.stringify([group,value.queryScope,value.fields.filter(f=>f.fieldPath!=='__name__').map(f=>[f.fieldPath,f.order||null,f.arrayConfig||null,f.vectorConfig||null])]);
}
async function main() {
  const args=process.argv.slice(2), option=name=>args.includes(name)?args[args.indexOf(name)+1]:null;
  const beforePath=option('--before'), output=option('--output');
  const client=await new GoogleAuth({scopes:['https://www.googleapis.com/auth/cloud-platform']}).getClient();
  const get=async url=>(await client.request({url})).data;
  if(args.includes('--index-only')) {
    const page=await get(`https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/collectionGroups/directRequests/indexes`);
    const wanted=JSON.parse(fs.readFileSync('firestore.indexes.json','utf8')).indexes.find(i=>i.collectionGroup==='directRequests');
    const actual=(page.indexes||[]).find(i=>indexKey(i)===indexKey(wanted));
    console.log(JSON.stringify({project,index:actual?.name,state:actual?.state||'MISSING'}));
    if(actual?.state!=='READY')process.exitCode=2;
    return;
  }
  const snapshot={project,region,checkedAt:new Date().toISOString(),functions:[],indexes:[]};
  let token;
  do {
    const page=await get(`https://cloudfunctions.googleapis.com/v2/projects/${project}/locations/${region}/functions?pageSize=100${token?'&pageToken='+encodeURIComponent(token):''}`);
    snapshot.functions.push(...(page.functions||[]).map(f=>({name:f.name.split('/').at(-1),state:f.state,revision:f.serviceConfig?.revision,
      uri:f.serviceConfig?.uri,updatedAt:f.updateTime,runtime:f.buildConfig?.runtime,serviceAccount:f.serviceConfig?.serviceAccountEmail,
      pushEnabled:f.serviceConfig?.environmentVariables?.NOTIFICATION_PUSH_ENABLED})));
    token=page.nextPageToken;
  } while(token);
  const release=await get(`https://firebaserules.googleapis.com/v1/projects/${project}/releases/cloud.firestore`);
  snapshot.rulesRelease=release;
  snapshot.rules=await get(`https://firebaserules.googleapis.com/v1/${release.rulesetName}`);
  token=undefined;
  do {
    const page=await get(`https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/collectionGroups/-/indexes${token?'?pageToken='+encodeURIComponent(token):''}`);
    snapshot.indexes.push(...(page.indexes||[]));token=page.nextPageToken;
  } while(token);
  if(output)fs.writeFileSync(output,JSON.stringify(snapshot,null,2));
  const localRules=fs.readFileSync('firestore.rules','utf8');
  const remoteRules=snapshot.rules.source.files.find(f=>f.name==='firestore.rules').content;
  const localIndexes=JSON.parse(fs.readFileSync('firestore.indexes.json','utf8')).indexes;
  const remoteKeys=new Set(snapshot.indexes.map(indexKey)), localKeys=new Set(localIndexes.map(indexKey));
  const drift={remoteIndexesMissingLocally:snapshot.indexes.filter(i=>!localKeys.has(indexKey(i))).map(i=>i.name),
    localIndexesMissingRemotely:localIndexes.filter(i=>!remoteKeys.has(indexKey(i))).map(i=>({collectionGroup:i.collectionGroup,fields:i.fields}))};
  if(!beforePath) {
    const priorRules=normal(localRules).replace(/\n    match \/directRequests\/\{id\} \{[\s\S]*?\n    \}/,'');
    assert.ok(normal(remoteRules)===normal(priorRules)||normal(remoteRules)===normal(localRules),'Remote rules have unrelated changes; refusing to overwrite them');
    assert.equal(drift.remoteIndexesMissingLocally.length,0,'Remote indexes absent locally; refusing an index deletion');
    assert.ok(drift.localIndexesMissingRemotely.every(i=>i.collectionGroup==='directRequests'),'Unrelated indexes would be created');
  } else {
    const before=JSON.parse(fs.readFileSync(beforePath,'utf8'));
    assert.equal(before.project,project);
    const expected=args.includes('--prerequisites')?targets.filter(name=>name!=='publishDirectRequest'):targets;
    for(const name of expected) {
      const current=snapshot.functions.find(f=>f.name===name), prior=before.functions.find(f=>f.name===name);
      assert.equal(current?.state,'ACTIVE',name+' is not ACTIVE');
      if(prior)assert.notEqual(current.revision,prior.revision,name+' did not receive the deployed revision');
    }
    assert.equal(normal(remoteRules),normal(localRules),'Published Firestore rules differ from source');
    const direct=snapshot.indexes.find(i=>indexKey(i)===indexKey(localIndexes.find(j=>j.collectionGroup==='directRequests')));
    assert.equal(direct?.state,'READY','Direct request index is not READY');
    for(const old of before.indexes) assert.ok(snapshot.indexes.some(i=>i.name===old.name),'An existing index was removed');
    snapshot.changedFunctions=[];
    for(const old of before.functions) {
      const current=snapshot.functions.find(f=>f.name===old.name);
      assert.ok(current,'Missing existing function '+old.name);
      if(current.revision!==old.revision) {
        assert.ok(targets.includes(old.name),'Unrelated function was updated: '+old.name);
        snapshot.changedFunctions.push(old.name);
      }
    }
    snapshot.createdFunctions=snapshot.functions.filter(f=>!before.functions.some(old=>old.name===f.name)).map(f=>f.name);
    assert.ok(snapshot.createdFunctions.every(name=>targets.includes(name)),'Unrelated function was created');
    for(const name of ['deliverNotificationPush','drainNotifications']) {
      assert.equal(snapshot.functions.find(f=>f.name===name).pushEnabled,before.functions.find(f=>f.name===name).pushEnabled,'Push setting changed');
    }
    if(privateUx || accountName) {
      assert.equal(snapshot.rulesRelease.rulesetName,before.rulesRelease.rulesetName,'Firestore rules release changed');
      assert.deepEqual(snapshot.indexes.map(indexKey).sort(),before.indexes.map(indexKey).sort(),'Firestore indexes changed');
    }
    if(accountName) {
      assert.deepEqual(snapshot.createdFunctions,[],'Unexpected function creation');
      for(const name of targets) assert.equal(snapshot.functions.find(f=>f.name===name).serviceAccount,
        before.functions.find(f=>f.name===name).serviceAccount,'Function service account changed: '+name);
    }
    if(privateUx) {
      assert.equal(snapshot.functions.find(f=>f.name==='readDirectRequestAuthors').serviceAccount,
        snapshot.functions.find(f=>f.name==='manageRequest').serviceAccount,'Private name reader service account differs');
    }
    if(!args.includes('--prerequisites')) {
      assert.equal(snapshot.functions.find(f=>f.name==='publishDirectRequest').serviceAccount,
        snapshot.functions.find(f=>f.name==='publishRequest').serviceAccount,'Publisher service account differs');
      assert.equal(snapshot.functions.find(f=>f.name==='notifyDirectRequestCreated').serviceAccount,
        snapshot.functions.find(f=>f.name==='notifyRequestPublished').serviceAccount,'Notification service account differs');
    }
    snapshot.unauthenticated=[];
    const authenticated = accountName ? targets : privateUx
      ? ['publishDirectRequest','manageRequest','readProfessionalShowcase','readRequestRecommendation','readDirectRequestAuthors']
      : ['publishDirectRequest','proposalAccess','resolveNotification'];
    for(const name of authenticated) {
      if(!expected.includes(name))continue;
      const response=await fetch(`https://${region}-${project}.cloudfunctions.net/${name}`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({data:{}}),signal:AbortSignal.timeout(45000)});
      const data=await response.json();
      assert.equal(response.status,401,name+' accepted an unauthenticated call');
      assert.equal(data.error?.status,'UNAUTHENTICATED');
      snapshot.unauthenticated.push({name,status:response.status});
    }
    if(privateUx) {
      const response=await fetch(`https://${region}-${project}.cloudfunctions.net/readRequestRespondentProfile`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({data:{}}),signal:AbortSignal.timeout(45000)});
      const data=await response.json();
      assert.equal(response.status,400,'Public respondent reader did not reject invalid arguments');
      assert.equal(data.error?.status,'INVALID_ARGUMENT');
      snapshot.publicProfileValidation={status:response.status,error:data.error.status};
    }
    if(output)fs.writeFileSync(output,JSON.stringify(snapshot,null,2));
  }
  console.log(JSON.stringify({project,checkedAt:snapshot.checkedAt,functionCount:snapshot.functions.length,
    selected:snapshot.functions.filter(f=>targets.includes(f.name)).map(({name,state,revision,pushEnabled})=>({name,state,revision,pushEnabled})),
    indexes:snapshot.indexes.length,directIndexes:snapshot.indexes.filter(i=>i.name.includes('/collectionGroups/directRequests/')).map(i=>({name:i.name,state:i.state})),
    drift,changedFunctions:snapshot.changedFunctions,createdFunctions:snapshot.createdFunctions,unauthenticated:snapshot.unauthenticated,publicProfileValidation:snapshot.publicProfileValidation}));
}
main().catch(error=>{console.error(error.message);process.exitCode=1;});
