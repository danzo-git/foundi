const {test}=require('node:test'),assert=require('node:assert/strict');
const {createRequestAuthorService}=require('../src/request-author-service');
const rid='RequestAuthorFixture001';
test('missing IP metadata shares an anonymous budget; authenticated budgets follow the verified UID',()=>{
 const {requestAuthorActor}=require('../src/request-author-service');
 assert.equal(requestAuthorActor({}),requestAuthorActor({rawRequest:{headers:{'x-forwarded-for':'forged'}}}));
 assert.equal(requestAuthorActor({auth:{uid:'a'},rawRequest:{ip:'1.2.3.4'}}),requestAuthorActor({auth:{uid:'a'},rawRequest:{ip:'5.6.7.8'}}));
 assert.notEqual(requestAuthorActor({auth:{uid:'a'}}),requestAuthorActor({auth:{uid:'b'}}));
});
function fixture(){
 const docs=new Map([[`requests/${rid}`,{status:'published',authorPublicName:'Awa Kouassi',createdAt:123}],[`requestOwnership/${rid}`,{ownerUid:'author'}],['users/author',{email:'private@example.test',phone:'private',fullName:'Private name'}]]);
 let candidates=['author'],enabled=true,verified=true;
 const store={get:async p=>structuredClone(docs.get(p)),charge:async()=>{},legacyOwners:async()=>candidates};
 const profile={name:'Atelier public',trade:'Menuiserie',professionalId:'author'};
 const directory={readProfile:async()=>profile};
 const service=createRequestAuthorService({store,auth:{getUser:async()=>({disabled:!enabled,emailVerified:verified})},directory,avatars:{resolve:async()=>({avatars:{[rid]:'opaque'}})}});
 return {docs,profile,read:()=>service.read('viewer','actor',{requestId:rid}),legacy:value=>candidates=value,disable:()=>enabled=false,unverify:()=>verified=false,service};
}
test('request author exposes public client identity without users, ownership, drafts or contact details',async()=>{
 const f=fixture(),value=await f.read();assert.deepEqual(value,{name:'Awa Kouassi',avatarKey:'opaque',professional:null});
 for(const forbidden of ['private','phone','email','ownerUid','author'])assert.ok(!JSON.stringify(value).includes(forbidden));
 f.docs.set('professionalProfiles/author',{status:'pending',businessName:'Private draft'});assert.equal((await f.read()).professional,null);
 f.docs.get(`requests/${rid}`).authorPublicName='';assert.equal((await f.read()).name,'Demandeur Foundi');
});
test('approved author uses the existing public professional projection',async()=>{
 const f=fixture();f.docs.set('professionalProfiles/author',{status:'approved'});assert.deepEqual((await f.read()).professional,f.profile);
});
for(const [label,path,value]of [
 ['closed',`requests/${rid}`,{status:'closed'}],['private',`requests/${rid}`,{status:'published',visibility:'direct'}],
 ['hidden request',`safetyContent/request_${rid}`,{hidden:true}],['hidden author','safetyContent/professional_author',{hidden:true}],
 ['suspended','accountSafety/author',{suspended:true}],['deleted','accountLifecycle/author',{state:'closing'}],
 ['viewer block','userBlocks/viewer/items/author',{createdAt:1}],['author block','userBlocks/author/items/viewer',{createdAt:1}],
])test('request author unavailable when '+label,async()=>{const f=fixture();f.docs.set(path,value);await assert.rejects(f.read(),e=>e.code==='not-found');});
test('disabled and unverified authors are unavailable, and malformed requests never disclose identity',async()=>{
 const f=fixture();f.disable();await assert.rejects(f.read(),e=>e.code==='not-found');
 const g=fixture();g.unverify();await assert.rejects(g.read(),e=>e.code==='not-found');
 await assert.rejects(g.service.read(null,'actor',{requestId:'../users/author'}),e=>e.code==='invalid-argument');
 await assert.rejects(g.service.read(null,'actor',{requestId:rid,uid:'forged'}),e=>e.code==='invalid-argument');
});
test('historical requests require a unique bounded owner, never a guessed name match',async()=>{
 const f=fixture();f.docs.delete(`requestOwnership/${rid}`);assert.equal((await f.read()).name,'Awa Kouassi');
 f.legacy(['author','other']);await assert.rejects(f.read(),e=>e.code==='not-found');
});
test('a request withdrawn during the directory read cannot disclose the author',async()=>{
 const f=fixture();f.docs.set('professionalProfiles/author',{status:'approved'});
 // Force a state change between the initial access check and the final recheck.
 const service=createRequestAuthorService({store:{get:async p=>f.docs.get(p),charge:async()=>{}},auth:{getUser:async()=>({emailVerified:true})},avatars:{resolve:async()=>({avatars:{}})},directory:{readProfile:async()=>{f.docs.get(`requests/${rid}`).status='deleted';return f.profile;}}});
 await assert.rejects(service.read(null,'actor',{requestId:rid}),e=>e.code==='not-found');
});
