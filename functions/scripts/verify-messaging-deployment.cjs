const fs=require('node:fs'),assert=require('node:assert/strict'),{createHash}=require('node:crypto');
const args=process.argv.slice(2),option=name=>args.includes(name)?args[args.indexOf(name)+1]:null;
const services=['resolveConversationAvatars','syncConversationDeletion','notifyMessageCreated','notifyConversationOpened','resolveNotification','deliverNotificationPush','drainNotifications'];
const targets=[...services,'deleteConversation'];
const normalize=text=>text.split(/\r?\n/).map(line=>line.replace(/\r/g,'')).join('\n').trim();
const read=name=>JSON.parse(fs.readFileSync(option(name),'utf8'));
const source=snapshot=>normalize(snapshot.rules.firestore.source.source.files.find(f=>f.name.endsWith('firestore.rules')).content);
const local=()=>normalize(fs.readFileSync(require('node:path').resolve(__dirname,'../../firestore.rules'),'utf8'));
const catalogueUrl='https://firestore.googleapis.com/v1/projects/foundi-7c837/databases/(default)/documents/referenceData/professionalOnboarding';
async function catalogue(){const response=await fetch(catalogueUrl,{signal:AbortSignal.timeout(60000)});assert.equal(response.status,200);return response.json();}
function assertRulesDelta(before){
 const text=local(),start=text.indexOf('      match /deletedConversations/{id} {'),end=text.indexOf('      match /devices/{id}',start);
 assert.ok(start>0&&end>start);
 const additions=text.slice(start,end);
 assert.equal(additions,`      match /deletedConversations/{id} {
        allow get: if owner(uid);
        allow list: if owner(uid) && request.query.limit != null && request.query.limit <= 30;
        allow write: if false;
      }
      match /conversationState/{id} { allow get: if owner(uid) && id == 'inbox'; allow list, write: if false; }
`);
 assert.equal(text.slice(0,start)+text.slice(end),source(before),'Unexpected rules change');
 const needed=['conversationId','unread','createdAt'];
 assert.ok(before.indexes.some(i=>i.name.includes('/messageInbox/')&&i.state==='READY'&&needed.every((f,n)=>i.fields[n]?.fieldPath===f&&i.fields[n]?.order==='ASCENDING')),'Message cleanup index not ready');
 return {allowedRulesAdditions:['users/{uid}/deletedConversations/{id}','users/{uid}/conversationState/inbox'],allOtherRulesUnchanged:true,messageCleanupIndexReady:true,rulesSha256:createHash('sha256').update(text).digest('hex')};
}
async function main(){
 if(option('--project')!=='foundi-7c837'||process.env.FIRESTORE_EMULATOR_HOST)throw Error('Explicit production project required, without emulator.');
 const before=read('--before');assert.equal(before.project,option('--project'));
 const plan=assertRulesDelta(before),phase=option('--phase');
 if(phase==='prepare'){
  const result={project:before.project,checkedAt:new Date().toISOString(),...plan,catalogue:await catalogue()};
  fs.writeFileSync(option('--output'),JSON.stringify(result,null,2));console.log(JSON.stringify({...plan,project:before.project,functionsBefore:before.functions.length}));return;
 }
 const after=read('--after');assert.equal(after.project,before.project);
 const expected=phase==='services'?services:targets;
 for(const name of expected){
  const current=after.functions.find(f=>f.name===name),prior=before.functions.find(f=>f.name===name);
  assert.equal(current?.state,'ACTIVE',name);assert.ok(current.revision,name);
  if(prior){assert.notEqual(current.revision,prior.revision,name);assert.equal(current.serviceAccount,prior.serviceAccount,name);}
  else assert.equal(current.serviceAccount,before.functions.find(f=>f.name==='publishRequest').serviceAccount);
 }
 for(const prior of before.functions.filter(f=>!expected.includes(f.name))){const current=after.functions.find(f=>f.name===prior.name);assert.ok(current,prior.name);assert.equal(current.revision,prior.revision,prior.name+' changed');assert.equal(current.updateTime,prior.updateTime);assert.equal(current.serviceAccount,prior.serviceAccount);}
 assert.equal(after.functions.length,before.functions.length+expected.filter(name=>!before.functions.some(f=>f.name===name)).length);
 assert.equal(source(after),local(),'Deployed rules do not match reviewed local rules');
 assert.notEqual(after.rules.firestore.release.rulesetName,before.rules.firestore.release.rulesetName);
 assert.equal(after.rules.storage?.release.rulesetName,before.rules.storage?.release.rulesetName);
 for(const key of ['indexes','fields','policy','auth','storage'])assert.deepEqual(after[key],before[key],key+' changed');
 const preparation=read('--plan');assert.equal(preparation.project,before.project);assert.deepEqual(await catalogue(),preparation.catalogue,'Catalogue changed');
 if(phase==='services'){console.log('Seven messaging services ACTIVE; reviewed rules deployed; deletion entry point not yet opened.');return;}
 assert.equal(phase,'final');
 const deletion=after.functions.find(f=>f.name==='deleteConversation');
 for(const name of services)assert.ok(Date.parse(deletion.updateTime)>Date.parse(after.functions.find(f=>f.name===name).updateTime),'Deletion must be deployed last');
 const {GoogleAuth}=require('google-auth-library'),client=await new GoogleAuth({scopes:['https://www.googleapis.com/auth/cloud-platform']}).getClient();
 const worker=(await client.request({url:'https://cloudfunctions.googleapis.com/v2/projects/foundi-7c837/locations/europe-west1/functions/syncConversationDeletion'})).data;
 assert.equal(worker.eventTrigger?.eventType,'google.cloud.firestore.document.v1.written');
 assert.ok(worker.eventTrigger.eventFilters.some(f=>f.attribute==='document'&&f.value==='users/{uid}/deletedConversations/{conversationId}'&&f.operator==='match-path-pattern'));
 assert.equal(worker.eventTrigger.retryPolicy,'RETRY_POLICY_RETRY');
 const runtime=read('--runtime-before');
 for(const prior of runtime){const current=(await client.request({url:'https://cloudfunctions.googleapis.com/v2/projects/foundi-7c837/locations/europe-west1/functions/'+prior.name})).data;assert.equal(current.serviceConfig?.environmentVariables?.NOTIFICATION_PUSH_ENABLED??null,prior.push,'Push configuration changed for '+prior.name);}
 const checks=await Promise.all(['resolveConversationAvatars','deleteConversation','resolveNotification'].map(async name=>{
  const response=await fetch('https://europe-west1-foundi-7c837.cloudfunctions.net/'+name,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({data:{}}),signal:AbortSignal.timeout(60000)}),value=await response.json();
  assert.equal(response.status,401,name+': '+JSON.stringify(value));assert.equal(value.error?.status,'UNAUTHENTICATED');return {name,status:response.status,case:'anonymous invocation denied'};
 }));
 for(const path of ['users/deploy_probe_user/deletedConversations/DeployProbeConversation01','users/deploy_probe_user/conversationState/inbox','personalAvatars/deploy_probe_user']){
  const response=await fetch('https://firestore.googleapis.com/v1/projects/foundi-7c837/databases/(default)/documents/'+path,{signal:AbortSignal.timeout(60000)});assert.equal(response.status,403,path);checks.push({path,status:403,case:'anonymous private document read denied'});
 }
 const result={project:after.project,verifiedAt:new Date().toISOString(),...plan,functions:after.functions.filter(f=>targets.includes(f.name)).map(({name,state,revision,updateTime})=>({name,state,revision,updateTime})),deletionDeployedLast:true,workerRetryEnabled:true,pushConfigurationPreserved:true,otherFunctionsUnchanged:before.functions.filter(f=>!targets.includes(f.name)).length,indexesAuthStoragePrivacyPolicyCatalogueUnchanged:true,checks,customerRecordsModified:false,apkDistributed:false};
 fs.writeFileSync(option('--output'),JSON.stringify(result,null,2));console.log(JSON.stringify(result,null,2));
}
main().catch(e=>{console.error(e.message);process.exitCode=1;});
