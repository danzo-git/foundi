const {test}=require('node:test'),assert=require('node:assert/strict');
const {prepare}=require('../scripts/activate-rennes.cjs');
const {RENNES_ZONE}=require('../src/geographic-presets');
const fixture=()=>({enabled:false,version:'before',categories:[],documentTypes:[],zones:[{id:'ci-zone',label:'Zone CI',countryCode:'CI',active:false}],custom:{preserved:true}});
test('Rennes operator plan preserves catalogue, old zones and disabled state; replay is unchanged',()=>{
 const catalog=fixture(),before=structuredClone(catalog),plan=prepare(catalog);
 assert.deepEqual(catalog,before);assert.equal(plan.zones.length,2);assert.deepEqual(plan.zones[0],before.zones[0]);assert.deepEqual(plan.next,RENNES_ZONE);
 assert.equal(prepare({...catalog,zones:plan.zones}).changed,false);
});
test('Rennes operator plan refuses conflicting identifiers and existing French Rennes under another ID',()=>{
 const catalog=fixture();catalog.zones.push({...RENNES_ZONE,countryCode:'CI'});assert.throws(()=>prepare(catalog),/Reserved/);
 const other=fixture();other.zones.push({...RENNES_ZONE,id:'existing-rennes'});assert.throws(()=>prepare(other),/already exists/);
});
