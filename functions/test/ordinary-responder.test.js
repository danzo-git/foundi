const {test} = require('node:test');
const assert = require('node:assert/strict');
const {setup, rid} = require('./helpers/conversation-fixture');
const {createProposalService} = require('../src/proposal-service');
const {responderUid} = require('../src/responder');
const draft = {description:'Je propose une solution à cette demande.',amount:null,delay:''};
const code = c => e => e.code === c;

for (const status of [null,'pending','rejected','suspended','needs_changes','approved']) {
  test(`ordinary and professional complete flow, profile status ${status}`, async () => {
    const c = setup(), uid = 'ordinary';
    c.data.set(`users/${uid}`,{fullName:'Awa K.'});
    if (status) c.data.set(`professionalProfiles/${uid}`,{status,businessName:'Atelier Awa'});
    const service = createProposalService(c.deps);
    const [p,retry] = await Promise.all([service.send(uid,rid,draft),service.send(uid,rid,draft)]);
    assert.equal(p.id,retry.id);assert.equal(p.responderUid,uid);
    assert.equal(p.responderName,status==='approved'?'Atelier Awa':'Awa K.');
    assert.equal(p.professionalUid,status==='approved'?uid:undefined);
    assert.equal((await service.approval('client',p.id)).approved,status==='approved');
    const opened = await c.select('client',{requestId:rid,proposalId:p.id});
    const chat = c.data.get(`conversations/${opened.conversationId}`);
    assert.equal(responderUid(chat),uid);assert.equal(chat.professionalUid,status==='approved'?uid:undefined);
    await c.decide('client',{requestId:rid,proposalId:p.id,action:'retain',decisionId:'DecisionIdentifier0001',expectedRetainedProposalId:null});
    for (const actor of [uid,'client']) await c.send(actor,{conversationId:p.id,messageId:`MessageIdentifier${actor.padEnd(10,'0')}`,text:'Bonjour'});
    await assert.rejects(c.send('third',{conversationId:p.id,messageId:'MessageIdentifierThird',text:'Intrusion'}),code('permission-denied'));
    await c.manage('client',rid,'close');
    assert.equal(c.data.get(`proposals/${p.id}`).status,'retained');
    await c.decide('client',{requestId:rid,proposalId:p.id,action:'reject',decisionId:'DecisionIdentifier0002',expectedRetainedProposalId:p.id});
    await assert.rejects(c.send(uid,{conversationId:p.id,messageId:'MessageIdentifierFinal',text:'Refus ignoré'}),code('failed-precondition'));
  });
}

test('ordinary responder safety, lifecycle, identity forgery and private access fail closed without writes',async()=>{
  for(const path of ['accountSafety/ordinary','accountLifecycle/ordinary','userBlocks/client/items/ordinary','userBlocks/ordinary/items/client']) {
    const c=setup();c.data.set('users/ordinary',{fullName:'Awa'});c.data.set(path,path.startsWith('accountSafety')?{suspended:true}:{});
    await assert.rejects(c.propose('ordinary',rid,draft),code('permission-denied'));
    assert.equal([...c.data.values()].filter(p=>p.responderUid==='ordinary').length,0);
  }
  const c=setup();c.data.set('users/ordinary',{fullName:'Awa'});
  for(const change of [{responderUid:'pro'},{responderName:'Atelier'},{certified:true},{approved:true}])await assert.rejects(c.propose('ordinary',rid,{...draft,...change}),code('invalid-argument'));
  const p=await c.propose('ordinary',rid,draft);
  await assert.rejects(createProposalService(c.deps).approval('third',p.id),code('permission-denied'));
});

test('certification is live and independent of immutable historical professional identity',async()=>{
  const c=setup(),s=createProposalService(c.deps),p=await s.send('pro',rid,draft);
  assert.equal((await s.approval('client',p.id)).approved,true);
  c.data.set('accountSafety/pro',{suspended:true});assert.equal((await s.approval('client',p.id)).approved,false);c.data.delete('accountSafety/pro');
  c.data.set('safetyContent/professional_pro',{hidden:true});assert.equal((await s.approval('client',p.id)).approved,false);c.data.delete('safetyContent/professional_pro');
  c.data.get('professionalProfiles/pro').status='rejected';assert.equal((await s.approval('client',p.id)).approved,false);
  assert.equal(c.data.get(`proposals/${p.id}`).professionalUid,'pro');
  await c.select('client',{requestId:rid,proposalId:p.id});
});

test('ordinary public names reuse the existing contact-data sanitization',async()=>{
  for(const fullName of ['private@example.test','+225 0700000000','\u0000Alice','x'.repeat(101)]) {
    const c=setup();c.data.set('users/ordinary',{fullName});
    await assert.rejects(c.propose('ordinary',rid,draft),code('failed-precondition'));
    assert.equal([...c.data.values()].some(p=>p.responderUid==='ordinary'),false);
  }
});

test('pending and revoked professional drafts never supply a public proposal or push name',()=>{
  const {publicResponderName}=require('../src/responder'),user={fullName:'Awa K.'};
  for(const status of ['draft','pending','rejected','suspended'])assert.equal(publicResponderName(user,{status,businessName:'Nom du dossier privé'}),'Awa K.');
  assert.equal(publicResponderName(user,{status:'approved',businessName:'Atelier public'}),'Atelier public');
  assert.equal(publicResponderName({fullName:'private@example.test'},null),null);
});
