const {test} = require('node:test');
const assert = require('node:assert/strict');
const {forEachBounded} = require('../src/bounded-work');
test('independent I/O is bounded, every value is processed once', async () => {
  let running=0, peak=0;
  const seen=[];
  await forEachBounded(Array.from({length:30},(_,i)=>i),4,async value=>{
    running++; peak=Math.max(peak,running);
    await new Promise(resolve=>setImmediate(resolve));
    seen.push(value); running--;
  });
  assert.equal(peak,4); assert.equal(running,0);
  assert.deepEqual(seen.sort((a,b)=>a-b),Array.from({length:30},(_,i)=>i));
});
test('failure stops new work and waits for active work to finish', async () => {
  let running=0, started=0;
  await assert.rejects(forEachBounded(Array.from({length:30},(_,i)=>i),4,async value=>{
    started++; running++;
    try { if(value===0)throw Error('network'); await new Promise(resolve=>setImmediate(resolve)); }
    finally { running--; }
  }),/network/);
  assert.ok(started<=4); assert.equal(running,0);
  await assert.rejects(forEachBounded([],0,async()=>{}),RangeError);
});
