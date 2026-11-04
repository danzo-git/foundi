const fs=require('node:fs'),assert=require('node:assert/strict');
const {GoogleAuth}=require('google-auth-library');
const project='foundi-7c837';
const names=['notifyProfessionalDecision','notifyProposalCreated','notifyProposalDecision','notifyConversationOpened','notifyMessageCreated','notifyRequestPublished','notifyRequestClosed','countNotificationRead','runNotificationJob','deliverNotificationPush','drainNotifications','resolveNotification','markConversationRead'];
async function main(){
 const args=process.argv.slice(2),after=args.includes('--after'),output=args.includes('--output')?args[args.indexOf('--output')+1]:null;
 const client=await new GoogleAuth({scopes:['https://www.googleapis.com/auth/cloud-platform']}).getClient();
 const get=async url=>(await client.request({url})).data;
 const snapshot={project,at:new Date().toISOString(),functions:[],indexes:[],rules:null};
 for(const name of names){
  let f;try{f=await get(`https://cloudfunctions.googleapis.com/v2/projects/${project}/locations/europe-west1/functions/${name}`);}catch(e){if(e.response?.status!==404)throw e;f={state:'MISSING'};}
  const row={name,state:f.state,revision:f.serviceConfig?.revision,uri:f.serviceConfig?.uri,updatedAt:f.updateTime,pushEnabled:f.serviceConfig?.environmentVariables?.NOTIFICATION_PUSH_ENABLED};
  snapshot.functions.push(row);
  if(after){assert.equal(row.state,'ACTIVE',name);if(['deliverNotificationPush','drainNotifications'].includes(name))assert.equal(row.pushEnabled,'true',name);}
 }
 const release=await get(`https://firebaserules.googleapis.com/v1/projects/${project}/releases/cloud.firestore`);
 snapshot.rules=await get(`https://firebaserules.googleapis.com/v1/${release.rulesetName}`);
 if(after){const normal=s=>s.replace(/\r\n/g,'\n').trim();assert.equal(normal(snapshot.rules.source.files.find(f=>f.name==='firestore.rules').content),normal(fs.readFileSync('firestore.rules','utf8')));}
 let token;
 do{const page=await get(`https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/collectionGroups/-/indexes${token?'?pageToken='+encodeURIComponent(token):''}`);snapshot.indexes.push(...(page.indexes || []));token=page.nextPageToken;}while(token);
 const local=JSON.parse(fs.readFileSync('firestore.indexes.json','utf8'));
 const wanted=local.indexes.filter(i=>i.collectionGroup==='messageInbox'||i.fields.some(f=>f.fieldPath==='isGeneral'));
 if(after)for(const i of wanted){
  const actual=snapshot.indexes.find(r=>r.name.includes(`/collectionGroups/${i.collectionGroup}/`)&&i.fields.every(f=>r.fields.some(g=>g.fieldPath===f.fieldPath&&g.order===f.order)));
  assert.equal(actual?.state,'READY','Index '+i.collectionGroup+': '+i.fields.map(f=>f.fieldPath).join(','));
 }
 if(after){
  snapshot.unauthenticated=[];
  for(const name of ['markConversationRead','resolveNotification']){
   const response=await fetch(snapshot.functions.find(f=>f.name===name).uri,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({data:{}})});
   assert.ok([401,403].includes(response.status),'Unauthenticated '+name);
   snapshot.unauthenticated.push({name,status:response.status});
  }
 }
 if(output)fs.writeFileSync(output,JSON.stringify(snapshot,null,2));
 console.log(JSON.stringify({project,after,functions:snapshot.functions.map(f=>({name:f.name,state:f.state})),indexes:snapshot.indexes.length,indexStates:snapshot.indexes.reduce((s,i)=>(s[i.state]=(s[i.state]||0)+1,s),{}),rulesSaved:!!snapshot.rules,unauthenticated:snapshot.unauthenticated}));
}
main().catch(e=>{console.error(e.message);process.exitCode=1;});
