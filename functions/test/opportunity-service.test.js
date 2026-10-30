const { test } = require('node:test');
const assert = require('node:assert/strict');
const { createOpportunityService } = require('../src/opportunity-service');
function setup() {
 const profile = {status: 'approved', categoryIds: ['auto','home'], specialtyIds: ['sale','rent','repair'], zoneIds: ['cocody','bingerville']};
 const rows = [
  {id:'1',categoryId:'auto',specialtyId:'sale',zoneId:'cocody',status:'published',createdAt:3,title:'Car',email:'secret',ownerId:'private'},
  {id:'2',categoryId:'auto',specialtyId:'rent',zoneId:'bingerville',status:'published',createdAt:2},
  {id:'3',categoryId:'home',specialtyId:'repair',zoneId:'cocody',status:'published',createdAt:1},
  {id:'4',categoryId:'auto',specialtyId:'sale',zoneId:'cocody',status:'closed',createdAt:4},
  {id:'5',categoryId:'auto',specialtyId:'sale',zoneId:'cocody',status:'deleted',createdAt:5},
  {id:'own',categoryId:'auto',specialtyId:'sale',zoneId:'cocody',status:'published',createdAt:6},
 ];
 let calls=0;
 const store={get:async path=>path.startsWith('professionalProfiles')?profile:{categories:[{id:'auto',specialties:[{id:'sale'},{id:'rent'}]},{id:'home',specialties:[{id:'repair'}]}]},
 owned:async()=>new Set(['own']),
 query:async (filters,after,size)=>{calls++;return rows.filter(r=>r.status==='published'&&Object.entries(filters).every(([k,v])=>r[k]===v)&&(!after||r.createdAt<after.createdAt||(r.createdAt===after.createdAt&&r.id<after.id))).sort((a,b)=>b.createdAt-a.createdAt||b.id.localeCompare(a.id)).slice(0,size);}};
 return { ...createOpportunityService({store,auth:{getUser:async()=>({disabled:false,emailVerified:true})}}),profile,rows,get calls(){return calls;}};
}
test('approved multi-category union excludes own, closed, deleted and all private metadata',async()=>{
 const c=setup(),page=await c.list('pro'); assert.deepEqual(page.items.map(r=>r.id),['1','2','3']); assert.equal(page.cursor,null);
 assert.equal(new Set(page.items.map(r=>r.id)).size,3); for(const r of page.items){assert.equal('email' in r,false);assert.equal('ownerId' in r,false);}
});
test('filters narrow approved scope, exact zones and empty selections',async()=>{
 const c=setup(); assert.deepEqual((await c.list('pro',{zoneIds:['bingerville']})).items.map(r=>r.id),['2']);
 assert.deepEqual((await c.list('pro',{specialtyIds:['repair']})).items.map(r=>r.id),['3']);
 assert.deepEqual((await c.list('pro',{categoryIds:[]})).items,[]);
 assert.deepEqual((await c.list('pro',{zoneIds:[]})).items,[]);
 for(const input of [{categoryIds:['other']},{specialtyIds:['other']},{zoneIds:['other']},{cursor:{unit:-1}}]) await assert.rejects(c.list('pro',input),e=>e.code==='invalid-argument');
 c.profile.zoneIds=[];assert.deepEqual((await c.list('pro')).items,[]);
});
test('anonymous and every unapproved professional status are rejected on server',async()=>{
 const c=setup(); await assert.rejects(c.list(null),e=>e.code==='unauthenticated');
 for(const status of ['draft','pending','needs_changes','rejected','suspended',undefined]){c.profile.status=status;await assert.rejects(c.list('pro'),e=>e.code==='permission-denied');}
 assert.equal(c.calls,0);
});
test('pagination is bounded, stable for equal dates and does not duplicate results',async()=>{
 const c=setup();c.rows.length=0;
 for(let n=0;n<75;n++)c.rows.push({id:String(n).padStart(3,'0'),categoryId:'auto',specialtyId:'sale',zoneId:'cocody',status:'published',createdAt:1});
 const ids=[];let cursor;let page;
 do{const before=c.calls;page=await c.list('pro',{cursor});assert.ok(c.calls-before<=10);assert.ok(page.items.length<=30);ids.push(...page.items.map(r=>r.id));cursor=page.cursor;}while(cursor);
 assert.equal(ids.length,75);assert.equal(new Set(ids).size,75);
});
