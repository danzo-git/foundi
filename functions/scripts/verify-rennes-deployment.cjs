const fs=require('node:fs'),assert=require('node:assert/strict');
const {initializeApp,applicationDefault,deleteApp}=require('firebase-admin/app');
const {getFirestore}=require('firebase-admin/firestore');
const {RENNES_ZONE}=require('../src/geographic-presets');
async function main(){
 const args=process.argv.slice(2),option=name=>args.includes(name)?args[args.indexOf(name)+1]:null;
 if(option('--project')!=='foundi-7c837'||process.env.FIRESTORE_EMULATOR_HOST)throw Error('Explicit production project without emulator required.');
 const read=name=>JSON.parse(fs.readFileSync(option(name),'utf8'));
 const before=read('--before'),after=read('--after'),plan=read('--plan'),activation=read('--activation'),target='updateProfessionalCatalog';
 for(const snapshot of [before,after,plan,activation])assert.equal(snapshot.project,option('--project'));
 const current=after.functions.find(f=>f.name===target),prior=before.functions.find(f=>f.name===target);
 assert.equal(current?.state,'ACTIVE');assert.notEqual(current.revision,prior.revision);assert.equal(current.serviceAccount,prior.serviceAccount);
 assert.equal(after.functions.length,before.functions.length);
 for(const f of before.functions){
  const next=after.functions.find(n=>n.name===f.name);assert.ok(next,f.name);
  if(f.name!==target){assert.equal(next.revision,f.revision,f.name+' changed');assert.equal(next.serviceAccount,f.serviceAccount);}
 }
 for(const key of ['indexes','fields','policy','auth','storage'])assert.deepEqual(after[key],before[key],key+' changed');
 for(const name of ['firestore','storage'])assert.equal(after.rules[name]?.release.rulesetName,before.rules[name]?.release.rulesetName,name+' rules changed');
 const checks=[];
 for(const data of [{operation:'enableRennes',expectedVersion:''},{operation:'enableRennes',expectedVersion:'',admin:true}]){
  const response=await fetch('https://europe-west1-foundi-7c837.cloudfunctions.net/'+target,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({data}),signal:AbortSignal.timeout(60000)}),value=await response.json();
  assert.equal(response.status,401,JSON.stringify(value));assert.equal(value.error?.status,'UNAUTHENTICATED');checks.push({case:data.admin?'forged admin in payload':'anonymous catalogue mutation',status:401});
 }
 const publicResponse=await fetch('https://firestore.googleapis.com/v1/projects/foundi-7c837/databases/(default)/documents/referenceData/professionalOnboarding',{signal:AbortSignal.timeout(60000)});
 assert.equal(publicResponse.status,200);const publicDoc=await publicResponse.json();
 const publicZones=publicDoc.fields.zones.arrayValue.values.map(z=>z.mapValue.fields);
 const publicRennes=publicZones.filter(z=>z.id?.stringValue===RENNES_ZONE.id);
 assert.equal(publicRennes.length,1);assert.equal(publicRennes[0].countryCode.stringValue,'FR');assert.equal(publicRennes[0].active.booleanValue,true);checks.push({case:'public catalogue includes one active Rennes',status:200});
 const app=initializeApp({projectId:option('--project'),credential:applicationDefault()});
 try{
  const db=getFirestore(app),actual=JSON.parse(JSON.stringify((await db.doc('referenceData/professionalOnboarding').get()).data()));
  const oldZones=plan.before.zones.filter(z=>z.id!==RENNES_ZONE.id);
  assert.deepEqual(actual.zones.filter(z=>z.id!==RENNES_ZONE.id),oldZones);
  assert.equal(actual.zones.length,oldZones.length+1);assert.equal(actual.version,activation.version);
  assert.deepEqual(actual.zones.filter(z=>z.countryCode==='FR'),[RENNES_ZONE]);
  const stripped=value=>Object.fromEntries(Object.entries(value).filter(([k])=>!['zones','version','updatedAt','updatedBy'].includes(k)));
  assert.deepEqual(stripped(actual),stripped(plan.before));
  if(activation.auditId){const audit=(await db.doc('professionalAudit/'+activation.auditId).get()).data();assert.equal(audit.operation,'enableRennes');assert.deepEqual(audit.after,RENNES_ZONE);assert.equal(audit.version,activation.version);}
  const result={project:after.project,verifiedAt:new Date().toISOString(),target,state:current.state,revision:current.revision,otherFunctionsUnchanged:before.functions.length-1,zonesBefore:plan.zonesBefore,zonesAfter:actual.zones.length,rennes:RENNES_ZONE,existingZonesUnchanged:true,otherCatalogueFieldsUnchanged:true,checks,customerAccountsOrRequestsModified:false};
  if(option('--output'))fs.writeFileSync(option('--output'),JSON.stringify(result,null,2));console.log(JSON.stringify(result,null,2));
 }finally{await deleteApp(app);}
}
main().catch(error=>{console.error(error.message);process.exitCode=1;});
