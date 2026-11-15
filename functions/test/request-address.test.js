const {test}=require('node:test'),assert=require('node:assert/strict');
const {createRequestService}=require('../src/request-service');
const {createRequestAddressService}=require('../src/request-address-service');
const id='AddressRequestIdentifier01';
const address={line:'10 rue des Ateliers, 35000 Rennes, France',countryCode:'FR',confirmed:true};
const draft={categoryId:'services',specialtyId:'plomberie',zoneId:'rennes',title:'Réparer une fuite',description:'Une fuite à réparer dans ma cuisine.',budget:null,interventionAddress:address};
function fixture(){
 const data=new Map([['referenceData/professionalOnboarding',{enabled:true,categories:[{id:'services',label:'Services',specialties:[{id:'plomberie',label:'Plomberie'}]}],zones:[{id:'rennes',label:'Rennes',countryCode:'FR'},{id:'cocody',label:'Cocody',countryCode:'CI'}]}],['users/client',{fullName:'Awa Kouassi'}],['professionalProfiles/pro',{status:'approved',businessName:'Atelier',categoryIds:['services'],specialtyIds:['plomberie'],zoneIds:['rennes']}]]);
 const account={disabled:false,emailVerified:true};let now=1000,failPath=null;
 const auth={getUser:async()=>account};
 const store={transaction:async operation=>{const copy=structuredClone(data);let writing=false;const result=await operation({get:async p=>{assert.equal(writing,false,'reads must precede writes');return copy.get(p);},set:(p,v)=>{writing=true;if(p===failPath)throw Error('rollback');copy.set(p,v);},delete:p=>{writing=true;copy.delete(p);}});data.clear();for(const [p,v]of copy)data.set(p,v);return result;}};
 return {data,account,...createRequestService({store,auth,clock:()=>now}),capabilities:createRequestAddressService({store,auth}).capabilities,time:n=>now=n,fail:p=>failPath=p};
}
const code=c=>e=>e.code===c;
test('confirmed address is normalized and projected on public request and owner mirror, never coordinates or consent',async()=>{
 const c=fixture();const result=await c.publish('client',id,{...draft,interventionAddress:{...address,line:'  10 rue des Ateliers,\n35000 Rennes, France  '}});
 assert.equal(result.interventionAddressSaved,true);
 const saved=c.data.get('requests/'+id);
 assert.deepEqual(saved.interventionAddress,{line:address.line,countryCode:'FR'});
 assert.deepEqual(saved,c.data.get(`userRequests/client/items/${id}`));
 assert.equal(saved.interventionAddressSaved,undefined);assert.equal(saved.interventionAddress.confirmed,undefined);
 assert.equal([...c.data.keys()].some(p=>p.includes('Addresses/')),false);
});
test('unconfirmed, malformed, excessive and injected GPS address fields never create any request or consume quota',async()=>{
 for(const value of [{...address,confirmed:false},{line:address.line,countryCode:'FR'},{...address,latitude:48},{...address,countryCode:'US'},{...address,line:'x'},{...address,line:'x'.repeat(501)},[],true]){
  const c=fixture(),before=structuredClone(c.data);
  await assert.rejects(c.publish('client',id,{...draft,interventionAddress:value}),code('invalid-argument'));assert.deepEqual(c.data,before);
 }
});
test('country must match at least one selected zone; native location does not expand the catalogue',async()=>{
 const c=fixture();await assert.rejects(c.publish('client',id,{...draft,zoneId:'cocody'}),code('invalid-argument'));
 await assert.rejects(c.publish('client',id,{...draft,zoneId:'paris'}),code('failed-precondition'));
 assert.equal(c.data.has('requests/'+id),false);
});
test('legacy requests stay without address and legacy edits preserve a confirmed address',async()=>{
 const c=fixture();const first=await c.publish('client',id,draft);
 const {interventionAddress,...old}=draft;
 const result=await c.manage('client',id,'edit',old,first.createdAt);
 assert.deepEqual(result.interventionAddress,{line:address.line,countryCode:'FR'});
 assert.equal(result.interventionAddressSaved,undefined);
 const other=fixture();const legacy=await other.publish('client',id,old);assert.equal(legacy.interventionAddress,undefined);
});
test('editing country while preserving an incompatible address fails, explicit removal succeeds',async()=>{
 const c=fixture(),first=await c.publish('client',id,draft);
 const {interventionAddress,...old}=draft;
 await assert.rejects(c.manage('client',id,'edit',{...old,zoneId:'cocody'},first.createdAt),code('invalid-argument'));
 const removed=await c.manage('client',id,'edit',{...old,zoneId:'cocody',interventionAddress:null},first.createdAt);
 assert.equal(removed.interventionAddressSaved,true);assert.equal(removed.interventionAddress,undefined);assert.equal(c.data.get('requests/'+id).interventionAddress,undefined);
});
test('retries acknowledge actual saved address and edit fingerprints include address changes',async()=>{
 const c=fixture(),first=await c.publish('client',id,draft);
 const different={...draft,interventionAddress:{...address,line:'20 rue des Ateliers, Rennes, France'}};
 assert.equal((await c.publish('client',id,draft)).interventionAddressSaved,true);
 assert.equal((await c.publish('client',id,different)).interventionAddressSaved,false);
 c.time(2000);const edited=await c.manage('client',id,'edit',different,first.createdAt);
 assert.equal(edited.interventionAddressSaved,true);
 assert.equal((await c.manage('client',id,'edit',different,first.createdAt)).interventionAddressSaved,true);
 await assert.rejects(c.manage('client',id,'edit',draft,first.createdAt),code('aborted'));
 assert.deepEqual(c.data.get('requestPublicationLimits/client').createdAtMs,[1000]);
});
test('request close retains location for readers of history; request delete removes address from both projections',async()=>{
 const c=fixture();await c.publish('client',id,draft);
 assert.ok((await c.manage('client',id,'close')).interventionAddress);
 await c.manage('client',id,'delete');
 assert.equal(c.data.get('requests/'+id).interventionAddress,undefined);assert.equal(c.data.get(`userRequests/client/items/${id}`).interventionAddress,undefined);
});
test('direct request address stays in private direct projections and is absent from public requests',async()=>{
 const c=fixture(),saved=await c.publishDirect('client',id,'pro',draft);
 assert.equal(saved.interventionAddressSaved,true);assert.equal(c.data.has('requests/'+id),false);
 assert.equal(c.data.get('directRequests/'+id).interventionAddress.line,address.line);
 await assert.rejects(c.manage('pro',id,'edit',draft,saved.createdAt),code('permission-denied'));
 await c.manage('client',id,'delete');assert.equal(c.data.get('directRequests/'+id).interventionAddress,undefined);
});
test('publication and confirmed address are atomic on failed final write',async()=>{
 const c=fixture(),before=structuredClone(c.data);c.fail('requestPublicationLimits/client');
 await assert.rejects(c.publish('client',id,draft),/rollback/);assert.deepEqual(c.data,before);
});
test('capability handshake requires verified active account and exact input',async()=>{
 const c=fixture();assert.deepEqual(await c.capabilities('client',{}),{version:1,supported:true});
 await assert.rejects(c.capabilities(null,{}),code('unauthenticated'));
 await assert.rejects(c.capabilities('client',{line:'private'}),code('invalid-argument'));
 c.account.emailVerified=false;await assert.rejects(c.capabilities('client',{}),code('permission-denied'));
 c.account.emailVerified=true;c.data.set('accountLifecycle/client',{state:'closing'});await assert.rejects(c.capabilities('client',{}),code('permission-denied'));
});
