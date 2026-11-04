const {test}=require('node:test');
const assert=require('node:assert/strict');
const {createConversationService}=require('../src/conversation-service');
const {setup,rid,p1}=require('./helpers/conversation-fixture');
const message={conversationId:p1,messageId:'MessageTimingIdentifier001',text:'Private test payload'};

test('send timings separate account validation, transaction and authoritative return without private payload',async()=>{
  const c=setup();await c.select('client',{requestId:rid,proposalId:p1});
  const entries=[];
  const service=createConversationService({...c.deps,onSendTiming:e=>entries.push(e)});
  await service.send('client',message);
  assert.deepEqual(entries.map(e=>e.stage),['S0_handler','S1_account_validated','S2_payload_validated','S3_transaction_reads','S4_committed']);
  for(let i=0;i<entries.length;i++) {
    assert.equal(entries[i].messageId,message.messageId);
    assert.ok(entries[i].elapsedMs>=0);
    if(i)assert.ok(entries[i].elapsedMs>=entries[i-1].elapsedMs);
    assert.deepEqual(Object.keys(entries[i]).sort(),['event','messageId','stage','elapsedMs',...(entries[i].attempt?['attempt']:[])].sort());
  }
  const logs=JSON.stringify(entries);
  for(const secret of [message.text,'client','pro','token'])assert.ok(!logs.includes(secret));
});

test('no successful timing on validation/privacy failure; logger failure cannot break delivery or deduplication',async()=>{
  const c=setup();await c.select('client',{requestId:rid,proposalId:p1});
  const entries=[];
  const service=createConversationService({...c.deps,onSendTiming:e=>entries.push(e)});
  await assert.rejects(service.send('other-pro',message),e=>e.code==='permission-denied');
  assert.equal(entries.at(-1).stage,'S_failed');
  assert.equal(entries.some(e=>e.stage==='S4_committed'),false);
  assert.equal(c.data.has(`conversations/${p1}/messages/${message.messageId}`),false);
  const noisy=createConversationService({...c.deps,onSendTiming:()=>{throw Error('log sink down');}});
  const results=await Promise.all([noisy.send('client',message),noisy.send('client',message)]);
  assert.deepEqual(results[0],results[1]);
  assert.equal([...c.data.keys()].filter(k=>k.startsWith(`conversations/${p1}/messages/`)).length,1);
});
