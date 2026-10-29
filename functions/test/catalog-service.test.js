const { test } = require('node:test');
const assert = require('node:assert/strict');
const { createCatalogService, activeZones } = require('../src/catalog-service');
function setup() {
 const docs=new Map();let counter=0,queue=Promise.resolve();
 const user={customClaims:{admin:true}};
 const store={transaction(fn){const job=queue.then(async()=>{const next=structuredClone(docs);const value=await fn({get:async p=>structuredClone(next.get(p)),set:(p,v)=>next.set(p,structuredClone(v))});docs.clear();for(const [p,v] of next)docs.set(p,v);return value;});queue=job.catch(()=>{});return job;}};
 const service=createCatalogService({store,auth:{getUser:async()=>user},clock:()=>100,generateId:()=>`id_${++counter}`});
 const catalog=()=>docs.get('referenceData/professionalOnboarding');
 const update=input=>service.update('admin',{admin:true},{expectedVersion:catalog()?.version||'',...input});
 return {docs,user,catalog,update,service};
}
const value=(label,extra={})=>({label,active:true,description:'',...extra});
const category=value('Artisanat',{icon:'build',requirements:{independent:[],company:[]}});
const fails=code=>e=>e.code===code;
test('bootstrap, stable IDs, rename, specialties, parent zones, publication and audit use the existing document',async()=>{
 const c=setup();await c.update({operation:'documentType',value:value('Identité',{id:'identity'})});
 const {id}=await c.update({operation:'category',value:category});
 await c.update({operation:'specialty',categoryId:id,value:value('Plomberie')});
 const country=await c.update({operation:'zone',value:value('Côte d’Ivoire',{type:'country'})});
 await c.update({operation:'zone',value:value('Zone test',{type:'commune',parentId:country.id})});
 await c.update({operation:'publish',enabled:true});
 await c.update({operation:'category',id,value:{...category,label:'Artisans et services'}});
 assert.equal(c.catalog().categories[0].id,id);assert.equal(c.catalog().categories[0].specialties.length,1);
 assert.equal(c.catalog().enabled,true);assert.equal(c.docs.size,8);
 assert.equal([...c.docs.values()].filter(d=>d.type==='catalog').length,7);
});
test('unauthorized, revoked and disabled administrators cannot mutate catalog',async()=>{
 const c=setup();await assert.rejects(c.service.update(null,{admin:true},{}),fails('unauthenticated'));
 await assert.rejects(c.service.update('u',{},{}),fails('permission-denied'));
 c.user.customClaims={};await assert.rejects(c.update({operation:'publish',enabled:false}),fails('permission-denied'));
 c.user.customClaims={admin:true};c.user.disabled=true;await assert.rejects(c.update({}),fails('permission-denied'));assert.equal(c.docs.size,0);
});
test('concurrent edits cannot silently overwrite references',async()=>{
 const c=setup();const results=await Promise.allSettled([c.update({operation:'documentType',value:value('Identité',{id:'identity'})}),c.update({operation:'zone',value:value('Zone',{type:'intervention'})})]);
 assert.equal(results.filter(r=>r.status==='fulfilled').length,1);assert.equal(results.find(r=>r.status==='rejected').reason.code,'aborted');
});
test('cycles, invalid levels, unknown requirements and injected status are rejected or ignored',async()=>{
 const c=setup();const root=await c.update({operation:'zone',value:value('Pays',{type:'country'})});
 const child=await c.update({operation:'zone',value:value('Commune',{type:'commune',parentId:root.id})});
 await assert.rejects(c.update({operation:'zone',id:root.id,value:value('Pays',{type:'country',parentId:child.id})}),fails('invalid-argument'));
 await assert.rejects(c.update({operation:'category',value:{...category,requirements:{independent:['unknown'],company:[]}}}),fails('invalid-argument'));
 const cat=await c.update({operation:'category',value:{...category,status:'approved',admin:true}});
 assert.equal(c.catalog().categories.find(x=>x.id===cat.id).status,undefined);
});
test('activation fails closed until references and identity are configured; duplicate IDs cannot overwrite',async()=>{
 const c=setup();await assert.rejects(c.update({operation:'publish',enabled:true}),fails('failed-precondition'));
 await c.update({operation:'documentType',value:value('Identité',{id:'identity'})});
 await assert.rejects(c.update({operation:'documentType',value:value('Autre',{id:'identity'})}),fails('already-exists'));
 assert.equal(c.catalog().documentTypes[0].label,'Identité');
});
test('deactivated ancestors hide children; flat legacy zones and unknown metadata remain compatible',async()=>{
 assert.deepEqual(activeZones([{id:'a',active:false},{id:'b',parentId:'a'},{id:'legacy'}]).map(z=>z.id),['legacy']);
 const c=setup();c.docs.set('referenceData/professionalOnboarding',{enabled:false,version:'old',customField:'preserved',categories:[],zones:[{id:'legacy',label:'Ancienne zone'}],documentTypes:[]});
 await c.update({operation:'documentType',value:value('Identité',{id:'identity'})});assert.equal(c.catalog().customField,'preserved');assert.equal(c.catalog().zones[0].type,undefined);
});
