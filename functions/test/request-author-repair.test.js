const {test}=require('node:test');
const assert=require('node:assert/strict');
const {createRequestAuthorRepair}=require('../src/request-author-repair');
const id='RepairAuthorRequest001',uid='client';
function fixture(){
  const request={title:'Réparer une table',status:'published',createdAt:123,updatedAt:456,budget:10000,photoIds:['photo'],proposalCount:2};
  const data=new Map([[`requests/${id}`,{...request}],[`userRequests/${uid}/items/${id}`,{...request,lastEdit:{fingerprint:'saved'}}],
    [`requestOwnership/${id}`,{ownerUid:uid}],[`users/${uid}`,{fullName:'Awa Kouassi',email:'private@example.test'}],
    [`requestPublicationLimits/${uid}`,{createdAtMs:[123]}]]);
  const account={emailVerified:true,disabled:false,displayName:'Autre nom'};
  const writes=[];let failSecond=false;
  const store={transaction:async op=>{
    const copy=structuredClone(data),pending=[];let writing=false;
    const result=await op({get:async p=>{assert.equal(writing,false);return copy.get(p);},update:(p,v)=>{
      writing=true;if(failSecond&&pending.length)throw Error('Write failed');
      copy.set(p,{...copy.get(p),...v});pending.push({p,v});
    }});
    data.clear();for(const [p,v]of copy)data.set(p,v);writes.push(...pending);return result;
  }};
  return {data,writes,account,...createRequestAuthorRepair({store,auth:{getUser:async()=>account}}),fail:()=>failSecond=true};
}
test('author repair plans without writes and updates only the two name fields atomically',async()=>{
  const c=fixture(),before=structuredClone(c.data),plan=await c.plan([id]);
  assert.equal(plan.entries.length,1);assert.deepEqual(c.data,before);assert.deepEqual(c.writes,[]);
  assert.ok(!JSON.stringify(plan).includes('Awa Kouassi'));
  assert.equal((await c.apply(plan.entries[0])).state,'repaired');
  assert.deepEqual(c.writes.map(w=>Object.keys(w.v)),[['authorPublicName'],['authorPublicName']]);
  before.get(`requests/${id}`).authorPublicName='Awa Kouassi';
  before.get(`userRequests/${uid}/items/${id}`).authorPublicName='Awa Kouassi';
  assert.deepEqual(c.data,before);
  assert.equal((await c.apply(plan.entries[0])).state,'already_current');assert.equal(c.writes.length,2);
});
test('author repair fails closed if the source identity, ownership or either request copy changed',async()=>{
  for(const change of [
    c=>c.data.get(`users/${uid}`).fullName='Autre personne',
    c=>c.data.get(`requestOwnership/${id}`).ownerUid='other',
    c=>c.data.get(`requests/${id}`).title='Titre modifié',
    c=>c.data.get(`userRequests/${uid}/items/${id}`).proposalCount=3,
    c=>c.data.get(`requests/${id}`).status='closed',
  ]){
    const c=fixture(),plan=await c.plan([id]);change(c);const before=structuredClone(c.data);
    assert.equal((await c.apply(plan.entries[0])).state,'conflict');assert.deepEqual(c.data,before);assert.deepEqual(c.writes,[]);
  }
});
test('repair skips named, closed, deleted, private or unresolved records and inactive accounts',async()=>{
  for(const change of [
    c=>c.data.get(`requests/${id}`).authorPublicName='Nom déjà présent',
    c=>c.data.get(`requests/${id}`).status='closed',
    c=>c.data.get(`requests/${id}`).status='deleted',
    c=>c.data.get(`requests/${id}`).directProfessionalId='pro',
    c=>c.data.get(`userRequests/${uid}/items/${id}`).createdAt=0,
    c=>c.data.delete(`requestOwnership/${id}`),
    c=>c.account.disabled=true,
    c=>c.account.emailVerified=false,
  ]){const c=fixture();change(c);assert.equal((await c.plan([id])).entries.length,0);assert.deepEqual(c.writes,[]);}
});
test('a second write failure rolls back the public name as well',async()=>{
  const c=fixture(),plan=await c.plan([id]),before=structuredClone(c.data);c.fail();
  await assert.rejects(c.apply(plan.entries[0]),/Write failed/);assert.deepEqual(c.data,before);assert.deepEqual(c.writes,[]);
});
test('repair never accepts a name supplied in a plan and bounds the scope',async()=>{
  const c=fixture(),plan=await c.plan([id]);
  assert.equal((await c.apply({...plan.entries[0],name:'Usurpation'})).state,'repaired');
  assert.equal(c.data.get(`requests/${id}`).authorPublicName,'Awa Kouassi');
  await assert.rejects(c.plan(Array(51).fill(id)),/limited/);
  await assert.rejects(c.plan(['../users/client']),/Invalid request ID/);
});
