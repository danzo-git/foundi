const { test } = require('node:test');
const assert = require('node:assert/strict');
const { createCatalogService, activeZones,validateCatalog,zoneCountry } = require('../src/catalog-service');
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

test('Rennes preset adds one stable French commune, preserves CI, is audited and can be enabled again without duplicates',async()=>{
 const c=setup();await c.update({operation:'zone',value:value('Cocody',{type:'commune'})});
 const ivoirian=structuredClone(c.catalog().zones[0]);
 await c.update({operation:'enableRennes'});await c.update({operation:'enableRennes'});
 assert.deepEqual(c.catalog().zones[0],ivoirian);assert.equal(c.catalog().zones.length,2);
 const rennes=c.catalog().zones.find(z=>z.id==='fr_commune_35238');
 assert.equal(rennes.countryCode,'FR');assert.equal(rennes.label,'Rennes');assert.equal(rennes.parentId,null);
 assert.equal([...c.docs.values()].filter(d=>d.operation==='enableRennes').length,2);
 await c.update({operation:'zone',id:rennes.id,value:{...rennes,active:false}});
 assert.equal(activeZones(c.catalog().zones).some(z=>z.id===rennes.id),false);
 await c.update({operation:'enableRennes'});assert.equal(c.catalog().zones.length,2);
});
test('French country is retained on edit, inherited by children and never attached to an Ivorian parent',async()=>{
 const c=setup();const ci=await c.update({operation:'zone',value:value('Côte d’Ivoire',{type:'country'})});
 const fr=await c.update({operation:'zone',value:value('France',{type:'country',countryCode:'FR'})});
 const city=await c.update({operation:'zone',value:value('Rennes',{type:'commune',parentId:fr.id})});
 const rennes=c.catalog().zones.find(z=>z.id===city.id);assert.equal(rennes.countryCode,'FR');
 await c.update({operation:'zone',id:city.id,value:{...rennes,label:'Rennes actualisé'}});
 assert.equal(c.catalog().zones.find(z=>z.id===city.id).countryCode,'FR');
 await assert.rejects(c.update({operation:'zone',id:city.id,value:{...rennes,parentId:ci.id}}),fails('invalid-argument'));
 await assert.rejects(c.update({operation:'zone',value:value('Autre pays',{type:'country',countryCode:'US'})}),fails('invalid-argument'));
 assert.equal(zoneCountry({id:'legacy'},[]),'CI');
 assert.throws(()=>validateCatalog({categories:[],documentTypes:[],zones:[{id:'ci',label:'CI',countryCode:'CI'},{id:'fr',label:'FR',parentId:'ci',countryCode:'FR'}]}),fails('invalid-argument'));
});
test('reserved Rennes identifier cannot overwrite another location',async()=>{
 const c=setup();c.docs.set('referenceData/professionalOnboarding',{version:'v',enabled:false,categories:[],documentTypes:[],zones:[{id:'fr_commune_35238',label:'Private fixture',countryCode:'CI',type:'commune'}]});
 await assert.rejects(c.update({operation:'enableRennes'}),fails('already-exists'));
 assert.equal(c.catalog().zones[0].label,'Private fixture');
});
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


test('Sprint 2.5 Admin provisions one stable request-only unclassified reference with audit',async()=>{
 const c=setup();await c.update({operation:'enableUnclassified'});await c.update({operation:'enableUnclassified'});
 const categories=c.catalog().categories;assert.equal(categories.length,1);assert.equal(categories[0].id,'foundi_other');assert.equal(categories[0].requestOnly,true);
 await assert.rejects(c.update({operation:'specialty',categoryId:'foundi_other',value:value('Not a profession')}),fails('invalid-argument'));
 assert.equal([...c.docs.values()].filter(d=>d.operation==='enableUnclassified').length,2);
});
