const {test}=require('node:test');
const assert=require('node:assert/strict');
const {respondentsFixture,authorFixture,directoryFixture}=require('../test-support/backend-loading-fixtures');
const {createRequestRespondentsService}=require('../src/request-respondents-service');
const {createRequestAuthorService}=require('../src/request-author-service');
const {createProfessionalDirectoryService}=require('../src/professional-directory-service');
test('respondent eligibility is bounded, ordered, projected and retains pagination',async()=>{
  const f=respondentsFixture(createRequestRespondentsService,{count:23});
  let release;
  const gate=new Promise(resolve=>{release=resolve;});
  f.beforeRead(async path=>{
    if(path===`accountSafety/${f.ids[0]}`)await gate;
    if(path===`accountLifecycle/${f.ids[1]}`)release();
  });
  const result=await f.service.list('viewer',f.requestId,0);
  assert.equal(result.total,23);assert.equal(result.nextOffset,20);assert.equal(result.canViewProposals,true);
  assert.deepEqual(result.items.map(item=>item.professionalId),f.ids.slice(0,20));
  assert.ok(f.metrics.permissionPeak>3);assert.ok(f.metrics.permissionPeak<=12);
  assert.deepEqual(f.masks,[['status','businessName','categoryIds','specialtyIds']]);
  assert.ok(!JSON.stringify(result).includes('internalNotes'));
  const next=await f.service.list(null,f.requestId,result.nextOffset);
  assert.deepEqual(next.items.map(item=>item.professionalId),f.ids.slice(20));
  assert.equal(next.nextOffset,null);assert.equal(next.canViewProposals,false);
});
test('respondent batches filter suspension, deletion, content hiding, approval and disabled account',async()=>{
  const f=respondentsFixture(createRequestRespondentsService,{count:6});
  f.docs.set(`accountSafety/${f.ids[0]}`,{suspended:true});
  f.docs.set(`accountLifecycle/${f.ids[1]}`,{state:'closing'});
  f.docs.set(`safetyContent/professional_${f.ids[2]}`,{hidden:true});
  f.docs.get(`professionalProfiles/${f.ids[3]}`).status='pending';
  f.accounts.get(f.ids[4]).disabled=true;
  const result=await f.service.list(null,f.requestId);
  assert.deepEqual(result.items.map(item=>item.professionalId),[f.ids[5]]);
});
test('withdrawn parent or failed parallel read never discloses a partial respondent page',async()=>{
  const f=respondentsFixture(createRequestRespondentsService);
  f.beforeRead(async path=>{
    if(path.startsWith('accountSafety/'))f.docs.get(`requests/${f.requestId}`).status='deleted';
  });
  await assert.rejects(f.service.list(null,f.requestId),error=>error.code==='not-found');
  const g=respondentsFixture(createRequestRespondentsService);
  g.beforeRead(async path=>{if(path===`accountSafety/${g.ids[2]}`)throw Error('offline');});
  await assert.rejects(g.service.list(null,g.requestId),/offline/);
});
test('author validation shares repeated checks within a phase, but rechecks live state at disclosure',async()=>{
  const f=authorFixture(createRequestAuthorService);
  await f.service.read('viewer','actor',{requestId:f.requestId});
  assert.equal(f.reads.filter(path=>path==='accountSafety/author').length,2);
  assert.equal(f.reads.filter(path=>path==='accountLifecycle/author').length,2);
  f.directory.readProfile=async()=>{
    f.docs.set('userBlocks/author/items/viewer',{});
    return {name:'Atelier public',professionalId:'author'};
  };
  await assert.rejects(f.service.read('viewer','actor',{requestId:f.requestId}),error=>error.code==='not-found');
});
test('author professional profile waits for legacy identity import before loading its portrait',async()=>{
  const f=authorFixture(createRequestAuthorService);
  let imported=false;
  f.avatars.resolve=async()=>{await new Promise(resolve=>setImmediate(resolve));imported=true;return {avatars:{}};};
  f.directory.readProfile=async()=>{assert.equal(imported,true);return {name:'Atelier public',professionalId:'author'};};
  assert.equal((await f.service.read(null,'actor',{requestId:f.requestId})).professional.professionalId,'author');
});
test('author final permission checks observe restrictions introduced during account verification',async()=>{
  const f=authorFixture(createRequestAuthorService), original=f.auth.getUser;
  let calls=0;
  f.auth.getUser=async uid=>{
    const account=await original(uid);
    if(++calls===2)f.docs.set('accountLifecycle/author',{state:'closing'});
    return account;
  };
  await assert.rejects(f.service.read('viewer','actor',{requestId:f.requestId}),error=>error.code==='not-found');
});
test('directory final eligibility is checked after account lookup and does not reuse earlier flags',async()=>{
  const f=directoryFixture(createProfessionalDirectoryService), original=f.auth.getUser;
  let calls=0;
  f.auth.getUser=async uid=>{
    const account=await original(uid);
    if(++calls===2)f.docs.set(`accountSafety/${uid}`,{suspended:true});
    return account;
  };
  await assert.rejects(f.service.readProfile('actor',{professionalId:f.id}),error=>error.code==='not-found');
});
test('respondent profile keeps membership, account and fresh public visibility checks',async()=>{
  const f=respondentsFixture(createRequestRespondentsService,{count:1});
  assert.equal((await f.service.readProfile(f.requestId,f.ids[0])).professionalId,f.ids[0]);
  const original=f.auth.getUser;
  f.auth.getUser=async uid=>{
    const account=await original(uid);
    f.docs.set(`safetyContent/professional_${uid}`,{hidden:true});
    return account;
  };
  await assert.rejects(f.service.readProfile(f.requestId,f.ids[0]),error=>error.code==='not-found');
  await assert.rejects(f.service.readProfile(f.requestId,'outsider'),error=>error.code==='not-found');
});
