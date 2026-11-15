const {test}=require('node:test'),assert=require('node:assert/strict');
const {createConversationDeletionService}=require('../src/conversation-deletion-service');
const id='DeleteConversation000001';
function fixture(n=0){
 const data=new Map([[`conversations/${id}`,{clientUid:'client',professionalUid:'pro',status:'active',proposalStatus:'retained'}],['users/client/messageState/inbox',{unreadCount:n+3,schemaVersion:91}]]),accounts=new Map();let now=100,failed=null;
 for(let i=0;i<n;i++)data.set(`users/client/messageInbox/m${i}`,{conversationId:id,createdAt:i+1,unread:true});
 data.set('users/client/messageInbox/other',{conversationId:'AnotherConversation0001',createdAt:1,unread:true});
 const store={transaction:async op=>{const next=structuredClone(data);let writing=false;
  const value=await op({get:async path=>{assert.equal(writing,false);return next.get(path);},unread:async(uid,cid)=>{assert.equal(writing,false);return [...next].filter(([path,value])=>path.startsWith(`users/${uid}/messageInbox/`)&&value.conversationId===cid&&value.unread).sort((a,b)=>a[1].createdAt-b[1].createdAt).slice(0,200).map(([path,value])=>({path,value}));},set:(path,value)=>{writing=true;if(path===failed)throw Error('write failed');next.set(path,value);}});
  data.clear();for(const entry of next)data.set(...entry);return value;
 }};
 const auth={getUser:async uid=>({emailVerified:true,disabled:false,...accounts.get(uid)})};
 const service=createConversationDeletionService({store,auth,clock:()=>now});
 return {...service,data,accounts,removeAs:(uid='client',cid=id)=>service.remove(uid,{conversationId:cid,viewerUid:uid}),time:value=>now=value,fail:path=>failed=path};
}
const code=c=>e=>e.code===c;
test('participant removes only their own inbox entry; shared chat, other participant and proposal remain unchanged',async()=>{
 const c=fixture(4),chat=structuredClone(c.data.get(`conversations/${id}`));
 assert.deepEqual(await c.removeAs(),{deleted:true});
 assert.ok(c.data.has(`users/client/deletedConversations/${id}`));assert.equal(c.data.has(`users/pro/deletedConversations/${id}`),false);
 assert.deepEqual(c.data.get(`conversations/${id}`),chat);assert.equal(c.data.get('users/client/messageState/inbox').unreadCount,3);
 assert.equal(c.data.get('users/client/messageInbox/other').unread,true);
 await c.removeAs('pro');assert.ok(c.data.has(`users/pro/deletedConversations/${id}`));
});
test('repeated deletion is idempotent for timestamp, visibility version and unread counter',async()=>{
 const c=fixture(7);await c.removeAs();c.time(200);await c.removeAs();
 assert.equal(c.data.get(`users/client/deletedConversations/${id}`).deletedAt,100);assert.equal(c.data.get('users/client/conversationState/inbox').revision,1);assert.equal(c.data.get('users/client/messageState/inbox').unreadCount,3);
});
test('outsider, forged viewer, inactive account and non-member admin are denied without writes',async()=>{
 const c=fixture(),before=structuredClone(c.data);
 await assert.rejects(c.remove(null,{conversationId:id,viewerUid:'client'}),code('unauthenticated'));
 for(const uid of ['outsider','admin'])await assert.rejects(c.removeAs(uid),code('permission-denied'));
 await assert.rejects(c.remove('client',{conversationId:id,viewerUid:'pro'}),code('permission-denied'));
 c.accounts.set('client',{disabled:true});await assert.rejects(c.removeAs(),code('permission-denied'));c.accounts.set('client',{emailVerified:false});await assert.rejects(c.removeAs(),code('permission-denied'));assert.deepEqual(c.data,before);
});
test('protected fields and unsafe identifiers cannot select another account or request global erasure',async()=>{
 const c=fixture();for(const input of [{conversationId:'../private',viewerUid:'client'},{conversationId:id,viewerUid:'client',uid:'pro'},{conversationId:id,viewerUid:'client',forEveryone:true}])await assert.rejects(c.remove('client',input),code('invalid-argument'));
});
test('read-only history is removable even after blocking; retained business status is unaffected',async()=>{
 const c=fixture();c.data.get(`conversations/${id}`).status='read_only';c.data.set('userBlocks/client/items/pro',{});await c.removeAs();assert.equal(c.data.get(`conversations/${id}`).proposalStatus,'retained');
});
test('durable cleanup processes more than 200 unread messages without needing the client to retry',async()=>{
 const c=fixture(400);await c.removeAs();assert.equal(c.data.get(`users/client/deletedConversations/${id}`).cleanupPending,true);assert.equal(c.data.get('users/client/messageState/inbox').unreadCount,203);
 await c.cleanup('client',id);await c.cleanup('client',id);await c.cleanup('client',id);
 assert.equal(c.data.get('users/client/messageState/inbox').unreadCount,3);assert.equal(c.data.get(`users/client/deletedConversations/${id}`).cleanupPending,false);
});
test('atomic deletion failure leaves visibility and badge unchanged',async()=>{
 const c=fixture(4),before=structuredClone(c.data);c.fail('users/client/conversationState/inbox');await assert.rejects(c.removeAs(),/write failed/);assert.deepEqual(c.data,before);
});
test('deletion and background cleanup never recreate the private tree during account erasure',async()=>{
 const c=fixture(220);await c.removeAs();c.data.set('accountLifecycle/client',{state:'closing'});const before=structuredClone(c.data);await c.cleanup('client',id);await assert.rejects(c.removeAs(),code('permission-denied'));assert.deepEqual(c.data,before);
 const gone=fixture();await gone.cleanup('client',id);assert.equal(gone.data.has(`users/client/deletedConversations/${id}`),false);
});
