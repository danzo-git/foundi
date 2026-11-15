const fs=require('node:fs'),assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');
const {initializeApp,applicationDefault,deleteApp}=require('firebase-admin/app');
const {getFirestore}=require('firebase-admin/firestore');
const {validateCatalog,CATALOG_PATH}=require('../src/catalog-service');
const {RENNES_ZONE}=require('../src/geographic-presets');
function prepare(catalog){
 assert.ok(catalog,'The reference catalogue must already exist.');
 validateCatalog(catalog,catalog.enabled===true);
 const previous=catalog.zones.find(z=>z.id===RENNES_ZONE.id);
 if(previous&&(previous.countryCode!=='FR'||previous.type!=='commune'||previous.parentId))throw Error('Reserved Rennes identifier belongs to another location.');
 const otherRennes=catalog.zones.find(z=>z.id!==RENNES_ZONE.id&&z.countryCode==='FR'&&z.label.trim().toLowerCase()==='rennes');
 if(otherRennes)throw Error('Rennes already exists with another identifier; manual reconciliation required.');
 const next={...previous,...RENNES_ZONE};
 const zones=previous?catalog.zones.map(z=>z.id===next.id?next:z):[...catalog.zones,next];
 validateCatalog({...catalog,zones},catalog.enabled===true);
 assert.deepEqual(zones.filter(z=>z.id!==next.id),catalog.zones.filter(z=>z.id!==next.id));
 return {previous:previous||null,next,zones,changed:JSON.stringify(previous)!==JSON.stringify(next)};
}
const stamp=snapshot=>`${snapshot.updateTime.seconds}:${snapshot.updateTime.nanoseconds}`;
async function main(){
 const args=process.argv.slice(2),option=name=>args.includes(name)?args[args.indexOf(name)+1]:null;
 if(option('--project')!=='foundi-7c837')throw Error('Explicit --project foundi-7c837 required.');
 if(process.env.FIRESTORE_EMULATOR_HOST)throw Error('Refusing a production operation with an emulator configured.');
 if(!option('--plan'))throw Error('A local --plan path is required. Default is dry run; --apply requires an unchanged reviewed plan.');
 const app=initializeApp({projectId:option('--project'),credential:applicationDefault()});
 try{
  const db=getFirestore(app),ref=db.doc(CATALOG_PATH),snapshot=await ref.get(),catalog=snapshot.data(),prepared=prepare(catalog);
  if(!args.includes('--apply')){
   const plan={project:option('--project'),expectedVersion:catalog.version||'',expectedUpdateTime:stamp(snapshot),before:catalog,zonesBefore:catalog.zones.length,zonesAfter:prepared.zones.length,zone:prepared.next,changed:prepared.changed};
   fs.writeFileSync(option('--plan'),JSON.stringify(plan,null,2));
   console.log(JSON.stringify({project:plan.project,mode:'dry-run',zone:plan.zone,zonesBefore:plan.zonesBefore,zonesAfter:plan.zonesAfter,changed:plan.changed,remoteChanges:false},null,2));return;
  }
  const plan=JSON.parse(fs.readFileSync(option('--plan'),'utf8'));
  assert.equal(plan.project,option('--project'));assert.deepEqual(plan.zone,prepared.next);
  const auditId=randomUUID();
  const result=await db.runTransaction(async tx=>{
   const current=await tx.get(ref),data=current.data();
   if(stamp(current)!==plan.expectedUpdateTime||(data.version||'')!==plan.expectedVersion)throw Error('Catalogue changed since dry run. Prepare a new plan before applying.');
   const value=prepare(data);
   if(!value.changed)return {changed:false,version:data.version,zones:data.zones};
   const now=Date.now(),version=`${now}_${auditId}`;
   // Authorized project operator through ADC/IAM, not an impersonated Firebase admin.
   tx.update(ref,{zones:value.zones,version,updatedAt:now,updatedBy:'operator_rennes_cli'});
   tx.create(db.doc(`professionalAudit/${auditId}`),{type:'catalog',operation:'enableRennes',adminUid:null,operator:'authorized-project-cli',before:value.previous,after:value.next,version,createdAt:now});
   return {changed:true,version,zones:value.zones};
  });
  const actual=(await ref.get()).data();
  assert.deepEqual(actual.zones,result.zones);assert.equal(actual.version,result.version);
  assert.deepEqual(actual.zones.filter(z=>z.id!==RENNES_ZONE.id),plan.before.zones.filter(z=>z.id!==RENNES_ZONE.id));
  // The update mask deliberately excludes all other catalogue fields.
  const withoutMutable=value=>Object.fromEntries(Object.entries(value).filter(([k])=>!['zones','version','updatedAt','updatedBy'].includes(k)));
  assert.deepEqual(withoutMutable(actual),withoutMutable(catalog));
  const report={project:option('--project'),activatedAt:new Date().toISOString(),changed:result.changed,auditId:result.changed?auditId:null,version:result.version,zonesBefore:plan.zonesBefore,zonesAfter:actual.zones.length,zone:actual.zones.find(z=>z.id===RENNES_ZONE.id),otherZonesUnchanged:true,otherCatalogueFieldsUnchanged:true};
  if(option('--output'))fs.writeFileSync(option('--output'),JSON.stringify(report,null,2));
  console.log(JSON.stringify(report,null,2));
 }finally{await deleteApp(app);}
}
module.exports={prepare};
if(require.main===module)main().catch(error=>{console.error(error.message);process.exitCode=1;});
