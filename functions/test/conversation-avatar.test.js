const {test}=require('node:test'),assert=require('node:assert/strict');
const {createConversationAvatarService}=require('../src/conversation-avatar-service');
const id='ConversationIdentifier001',second='ConversationIdentifier002',publicId='a'.repeat(32),revision='b'.repeat(32);
function fixture(){
 const docs=new Map([[`conversations/${id}`,{clientUid:'client',professionalUid:'pro',status:'active'}],[`conversations/${second}`,{clientUid:'client',professionalUid:'pro',status:'read_only'}],['personalAvatars/pro',{published:true,publicId,revision,objectPath:'private-object'}],[`publicPersonalAvatars/${publicId}`,{version:revision}],['personalAvatars/client',{published:true,publicId:'c'.repeat(32),revision}],['publicPersonalAvatars/'+'c'.repeat(32),{version:revision}]]);
 const accounts=new Map(),imports=[];let importer=async()=>{};
 const service=createConversationAvatarService({store:{get:async path=>docs.get(path)},auth:{getUser:async uid=>{const a=accounts.get(uid);if(a instanceof Error)throw a;return {emailVerified:true,disabled:false,...a};}},ensureIdentity:async uid=>{imports.push(uid);await importer(uid);}});
 return {docs,accounts,imports,importWith:fn=>importer=fn,read:(uid='client',ids=[id])=>service.resolve(uid,{conversationIds:ids}),raw:service.resolve};
}
const code=expected=>e=>e.code===expected;
test('conversation photos resolve the counterpart in both roles and expose only opaque keys',async()=>{
 const c=fixture();assert.deepEqual(await c.read(),{avatars:{[id]:publicId}});
 assert.deepEqual(await c.read('pro'),{avatars:{[id]:'c'.repeat(32)}});
 const response=JSON.stringify(await c.read());for(const text of ['objectPath','private-object','client','revision','email'])assert.ok(!response.includes(text));
});
test('outsider and forged administrator cannot discover either participant photo',async()=>{
 const c=fixture();assert.deepEqual(await c.read('outsider'),{avatars:{}});assert.equal(c.imports.length,0);
 await assert.rejects(c.raw('outsider',{conversationIds:[id],admin:true}),code('invalid-argument'));
 assert.deepEqual(await c.read('admin'),{avatars:{}});
});
test('photo lookup requires a verified active authenticated account',async()=>{
 const c=fixture();await assert.rejects(c.read(null),code('unauthenticated'));
 for(const value of [{disabled:true},{emailVerified:false}]){c.accounts.set('client',value);await assert.rejects(c.read(),code('permission-denied'));}
 c.accounts.clear();for(const [path,value]of [['accountSafety/client',{suspended:true}],['accountLifecycle/client',{state:'closing'}]]){
  c.docs.set(path,value);await assert.rejects(c.read(),code('permission-denied'));c.docs.delete(path);
 }
});
test('only a bounded list of conversation identifiers is accepted',async()=>{
 const c=fixture();for(const input of [{},{conversationIds:'all'},{conversationIds:['../users/client']},{conversationIds:Array(31).fill(id)},[],true,{conversationIds:[id],uid:'client'}])await assert.rejects(c.raw('client',input),code('invalid-argument'));
 assert.deepEqual(await c.read('client',[]),{avatars:{}});
 assert.deepEqual(await c.read('client',['MissingConversation0001']),{avatars:{}});
});
test('closed conversations keep approved public identity and repeated counterpart import is deduplicated',async()=>{
 const c=fixture();assert.deepEqual(await c.read('client',[id,second,id]),{avatars:{[id]:publicId,[second]:publicId}});assert.deepEqual(c.imports,['pro']);
});
test('unpublished, revoked, malformed or mismatched projections never expose a photo',async()=>{
 for(const change of [c=>c.docs.get('personalAvatars/pro').published=false,c=>c.docs.delete('personalAvatars/pro'),c=>c.docs.delete(`publicPersonalAvatars/${publicId}`),c=>c.docs.get(`publicPersonalAvatars/${publicId}`).version='d'.repeat(32),c=>c.docs.get('personalAvatars/pro').publicId='../private']){
  const c=fixture();change(c);assert.deepEqual(await c.read(),{avatars:{}});
 }
});
test('blocks in either direction, suspension, deletion and disabled counterpart suppress photos',async()=>{
 for(const [path,value]of [['userBlocks/client/items/pro',{}],['userBlocks/pro/items/client',{}],['accountSafety/pro',{suspended:true}],['accountLifecycle/pro',{state:'closing'}]]){
  const c=fixture();c.docs.set(path,value);assert.deepEqual(await c.read(),{avatars:{}});assert.equal(c.imports.length,0);
 }
 for(const account of [{disabled:true},{emailVerified:false},Object.assign(Error('gone'),{code:'auth/user-not-found'})]){
  const c=fixture();c.accounts.set('pro',account);assert.deepEqual(await c.read(),{avatars:{}});
 }
});
test('deleted and aliased participants are never reconstructed from names or legacy portraits',async()=>{
 for(const value of [{professionalDeleted:true},{proposalStatus:'account_deleted'},{professionalUid:'deleted_alias',professionalDeleted:true}]){
  const c=fixture();Object.assign(c.docs.get(`conversations/${id}`),value);assert.deepEqual(await c.read(),{avatars:{}});assert.equal(c.imports.length,0);
 }
});
test('existing identity reuse still rechecks blocks and membership after import',async()=>{
 for(const change of [c=>c.docs.set('userBlocks/pro/items/client',{}),c=>c.docs.set(`conversations/${id}`,{clientUid:'other',professionalUid:'pro'}),c=>c.docs.get(`conversations/${id}`).professionalDeleted=true]){
  const c=fixture();c.importWith(async()=>change(c));assert.deepEqual(await c.read(),{avatars:{}});
 }
 const c=fixture();c.docs.delete('personalAvatars/pro');c.importWith(async()=>c.docs.set('personalAvatars/pro',{publicId,revision,published:true}));assert.deepEqual(await c.read(),{avatars:{[id]:publicId}});
});
