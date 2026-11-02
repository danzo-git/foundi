const {test}=require('node:test');
const assert=require('node:assert/strict');
const {createProposalService,proposalId}=require('../src/proposal-service');
const requestId='RequestIdentifier00001';
const draft={description:'Je peux réaliser cette prestation.',amount:25000,delay:'Sous deux jours'};
function setup({legacy=false}={}) {
 const request={title:'Besoin de test',status:'published',createdAt:123};
 const data=new Map([[`requests/${requestId}`,request],[`userRequests/client/items/${requestId}`,{...request}],['professionalProfiles/pro',{status:'approved',businessName:'Atelier de test'}]]);
 if(!legacy)data.set(`requestOwnership/${requestId}`,{ownerUid:'client'});
 let pending=Promise.resolve(); const account={emailVerified:true,disabled:false};
 const store={get:async p=>data.get(p),legacyOwners:async()=>[...data.keys()].filter(p=>p.startsWith('userRequests/')&&p.endsWith('/'+requestId)).map(p=>p.split('/')[1]),transaction(operation){
  const job=pending.then(async()=>{const copy=structuredClone(data);let writing=false;const result=await operation({get:async p=>{assert.equal(writing,false);return copy.get(p);},set:(p,v)=>{writing=true;copy.set(p,v);}});data.clear();for(const [p,v]of copy)data.set(p,v);return result;});pending=job.catch(()=>{});return job;
 }};
 return {...createProposalService({store,auth:{getUser:async()=>account},clock:()=>456}),data,account};
}
const code=name=>e=>e.code===name;
test('approved pro sends once atomically, immutable private fields and private count, even across devices',async()=>{
 const c=setup();assert.deepEqual(await c.access('pro',requestId),{canSend:true,proposalId:null});
 const [a,b]=await Promise.all([c.send('pro',requestId,draft),c.send('pro',requestId,draft)]);assert.deepEqual(a,b);
 assert.equal(a.id,proposalId(requestId,'pro'));assert.equal(a.clientUid,'client');assert.equal(a.professionalUid,'pro');assert.equal(a.createdAt,456);assert.equal(a.status,'sent');
 assert.equal(c.data.get(`userRequests/client/items/${requestId}`).proposalCount,1);assert.equal(c.data.get(`requests/${requestId}`).proposalCount,undefined);
 assert.equal([...c.data.keys()].filter(p=>p.startsWith('proposals/')).length,1);
 assert.equal((await c.access('pro',requestId)).canSend,false);
 assert.deepEqual(await c.approval('client',a.id),{approved:true});c.data.get('professionalProfiles/pro').status='suspended';assert.deepEqual(await c.approval('client',a.id),{approved:false});
 await assert.rejects(c.approval('third',a.id),code('permission-denied'));
});
test('legacy owner is resolved privately; absence or ambiguity fails closed',async()=>{
 const c=setup({legacy:true});await c.send('pro',requestId,draft);assert.deepEqual(c.data.get(`requestOwnership/${requestId}`),{ownerUid:'client'});
 const missing=setup({legacy:true});missing.data.delete(`userRequests/client/items/${requestId}`);await assert.rejects(missing.send('pro',requestId,draft),code('failed-precondition'));
 const ambiguous=setup({legacy:true});ambiguous.data.set(`userRequests/other/items/${requestId}`,{status:'published',createdAt:123});await assert.rejects(ambiguous.send('pro',requestId,draft),code('failed-precondition'));
});
test('anonymous, unapproved, disabled, unverified and own request cannot send',async()=>{
 const c=setup();await assert.rejects(c.send(null,requestId,draft),code('unauthenticated'));
 for(const status of ['draft','pending','needs_changes','rejected','suspended',undefined]){c.data.get('professionalProfiles/pro').status=status;await assert.rejects(c.send('pro',requestId,draft),code('permission-denied'));}
 c.data.set('professionalProfiles/client',{status:'approved',businessName:'Client pro'});await assert.rejects(c.send('client',requestId,draft),code('permission-denied'));
 c.account.disabled=true;await assert.rejects(c.send('pro',requestId,draft),code('permission-denied'));c.account.disabled=false;c.account.emailVerified=false;await assert.rejects(c.send('pro',requestId,draft),code('permission-denied'));
 assert.equal([...c.data.keys()].some(p=>p.startsWith('proposals/')),false);
});
test('closed, deleted, draft, missing requests and unconfirmed ownership refuse without partial writes',async()=>{
 for(const status of ['closed','deleted','draft']){const c=setup();c.data.get(`requests/${requestId}`).status=status;await assert.rejects(c.send('pro',requestId,draft),code('failed-precondition'));assert.equal(c.data.get(`userRequests/client/items/${requestId}`).proposalCount,undefined);}
 const c=setup();c.data.get(`userRequests/client/items/${requestId}`).createdAt=999;await assert.rejects(c.send('pro',requestId,draft),code('failed-precondition'));
});
test('invalid input and spoofed fields cannot create a proposal',async()=>{
 const c=setup();for(const change of [{description:''},{description:'x'.repeat(3001)},{delay:5},{delay:'x'.repeat(121)},{amount:0},{amount:-1},{amount:1.5},{amount:'1'},{amount:1000000000000},{clientUid:'victim'},{professionalUid:'other'},{createdAt:0},{status:'accepted'},{requestId:'other'}])await assert.rejects(c.send('pro',requestId,{...draft,...change}),code('invalid-argument'));
 const sent=await c.send('pro',requestId,{...draft,amount:null,delay:''});assert.equal(sent.amount,null);assert.equal(sent.delay,'');
});
