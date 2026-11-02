const {test}=require('node:test');
const assert=require('node:assert/strict');
const {setup,rid,p1,p2}=require('./helpers/conversation-fixture');
const code=c=>e=>e.code===c;
const choice=(id,proposalId=p1,extra={})=>({requestId:rid,proposalId,action:'retain',decisionId:`DecisionIdentifier${id.toString().padStart(4,'0')}`,expectedRetainedProposalId:null,...extra});
const msg=(conversationId,id=1)=>({conversationId,messageId:`MessageIdentifier${id.toString().padStart(4,'0')}`,text:'Bonjour'});
test('A01-A03: repeated opens are idempotent per proposal, parallel discussions leave publication unchanged and permit new proposals',async()=>{
 const c=setup(),before=structuredClone(c.data.get(`requests/${rid}`));
 const [a,retry,b]=await Promise.all([c.select('client',{requestId:rid,proposalId:p1}),c.select('client',{requestId:rid,proposalId:p1}),c.select('client',{requestId:rid,proposalId:p2})]);
 assert.equal(a.conversationId,p1);assert.equal(retry.alreadySelected,true);assert.equal(b.conversationId,p2);
 assert.deepEqual(c.data.get(`requests/${rid}`),before);assert.equal(c.data.get(`userRequests/client/items/${rid}`).proposalCount,2);
 c.data.set('professionalProfiles/third-pro',{status:'approved',businessName:'Troisième atelier'});
 await c.propose('third-pro',rid,{description:'Une nouvelle proposition détaillée.',amount:null,delay:''});
 assert.equal(c.data.get(`userRequests/client/items/${rid}`).proposalCount,3);
 assert.equal(c.data.get(`proposals/${p1}`).status,'discussing');assert.equal(c.data.get(`proposals/${p2}`).status,'discussing');
});
test('A04-A05: retention is separate, replacement requires exact confirmation, restores previous status and journals decisions',async()=>{
 const c=setup();await c.select('client',{requestId:rid,proposalId:p1});await c.select('client',{requestId:rid,proposalId:p2});
 const first=choice(1);await c.decide('client',first);assert.equal((await c.decide('client',first)).alreadyDecided,true);
 await assert.rejects(c.decide('client',choice(2,p2)),code('failed-precondition'));
 await c.decide('client',choice(2,p2,{expectedRetainedProposalId:p1}));
 assert.equal(c.data.get(`proposals/${p1}`).status,'discussing');assert.equal(c.data.get(`conversations/${p1}`).proposalStatus,'discussing');
 assert.equal(c.data.get(`proposals/${p2}`).status,'retained');assert.equal(c.data.get(`userRequests/client/items/${rid}`).retainedProposalId,p2);
 assert.equal(c.data.get(`requests/${rid}`).status,'published');assert.equal([...c.data.keys()].filter(k=>k.includes('/decisions/')).length,2);
 await assert.rejects(c.decide('client',{...first,reason:'autre'}),code('already-exists'));
});
test('retaining without a chat does not create one; replacement restores received state',async()=>{
 const c=setup();await c.decide('client',choice(1));assert.equal(c.data.has(`conversations/${p1}`),false);
 await c.decide('client',choice(2,p2,{expectedRetainedProposalId:p1}));assert.equal(c.data.get(`proposals/${p1}`).status,'sent');
 const opened=await c.select('client',{requestId:rid,proposalId:p2});assert.equal(opened.conversationId,p2);assert.equal(c.data.get(`conversations/${p2}`).proposalStatus,'retained');
});
test('A06: rejection clears retained reference, archives only its chat, preserves history and cannot be undone',async()=>{
 const c=setup();await c.select('client',{requestId:rid,proposalId:p1});await c.select('client',{requestId:rid,proposalId:p2});await c.send('pro',msg(p1));await c.decide('client',choice(1));
 const reject=choice(2,p1,{action:'reject',reason:'Autre solution retenue'});await c.decide('client',reject);assert.equal((await c.decide('client',reject)).alreadyDecided,true);
 assert.equal(c.data.get(`userRequests/client/items/${rid}`).retainedProposalId,null);assert.equal(c.data.get(`proposals/${p1}`).status,'rejected');assert.equal(c.data.get(`proposals/${p2}`).status,'discussing');
 assert.equal(c.data.get(`conversations/${p1}`).archivedReason,'proposal_rejected');assert.equal(c.data.get(`conversations/${p2}`).status,'active');
 await assert.rejects(c.send('pro',msg(p1,2)),code('failed-precondition'));await c.send('other-pro',msg(p2,2));
 assert.equal((await c.select('client',{requestId:rid,proposalId:p1})).conversationId,p1);
 await assert.rejects(c.decide('client',choice(3)),code('failed-precondition'));assert.equal(c.data.get(`requests/${rid}`).status,'published');
});
test('A07: explicit close stops proposals but preserves active chats; deletion archives every chat',async()=>{
 const c=setup();await c.select('client',{requestId:rid,proposalId:p1});await c.select('client',{requestId:rid,proposalId:p2});
 await c.manage('client',rid,'close');assert.equal(c.data.get(`requests/${rid}`).status,'closed');
 for(const [id,uid] of [[p1,'pro'],[p2,'other-pro']]){assert.equal(c.data.get(`conversations/${id}`).status,'active');await c.send(uid,msg(id));}
 await assert.rejects(c.propose('pro',rid,{description:'Une nouvelle proposition',amount:null,delay:''}),code('failed-precondition'));
 await c.manage('client',rid,'delete');for(const id of [p1,p2]){assert.equal(c.data.get(`conversations/${id}`).status,'read_only');assert.ok(c.data.has(`conversations/${id}/messages/MessageIdentifier0001`));await assert.rejects(c.send('client',msg(id,2)),code('failed-precondition'));}
});
test('A09: author, professional approval, request links and terminal states enforced on server',async()=>{
 const c=setup();for(const uid of [null,'pro','other-pro']){await assert.rejects(c.select(uid,{requestId:rid,proposalId:p1}),code(uid?'permission-denied':'unauthenticated'));await assert.rejects(c.decide(uid,choice(1)),code(uid?'permission-denied':'unauthenticated'));}
 for(const status of ['closed','deleted','in_discussion']){const x=setup();x.data.get(`requests/${rid}`).status=status;await assert.rejects(x.select('client',{requestId:rid,proposalId:p1}),code('failed-precondition'));}
 for(const status of ['pending','draft','needs_changes','rejected','suspended']){const x=setup();x.data.get('professionalProfiles/pro').status=status;await assert.rejects(x.select('client',{requestId:rid,proposalId:p1}),code('permission-denied'));await assert.rejects(x.decide('client',choice(1)),code('permission-denied'));}
 const x=setup();x.data.get(`proposals/${p1}`).requestId='other';await assert.rejects(x.decide('client',choice(1)),code('permission-denied'));
});
test('A10: concurrent unconfirmed retentions have one winner; concurrent reject/send cannot append after rejection',async()=>{
 const c=setup();const r=await Promise.allSettled([c.decide('client',choice(1)),c.decide('client',choice(2,p2))]);assert.equal(r.filter(x=>x.status==='fulfilled').length,1);
 await c.select('client',{requestId:rid,proposalId:p1});const jobs=await Promise.allSettled([c.decide('client',choice(3,p1,{action:'reject'})),c.send('pro',msg(p1))]);assert.equal(jobs[0].status,'fulfilled');assert.equal(jobs[1].status,'rejected');
});
test('two participants exchange idempotent ordered text; forged sender, reused payload, invalid text and outsiders refused',async()=>{
 const c=setup();await c.select('client',{requestId:rid,proposalId:p1});const m=msg(p1);const r=await Promise.all([c.send('client',m),c.send('client',m)]);assert.deepEqual(r[0],r[1]);assert.ok((await c.send('pro',msg(p1,2))).createdAt>r[0].createdAt);
 await assert.rejects(c.send('other-pro',msg(p1,3)),code('permission-denied'));await assert.rejects(c.send('client',{...m,senderUid:'pro'}),code('invalid-argument'));await assert.rejects(c.send('client',{...m,text:'Autre texte'}),code('already-exists'));
 for(const text of [' ','x'.repeat(2001),null])await assert.rejects(c.send('client',{...m,text}),code('invalid-argument'));
});
test('legacy V8 conversation ID and history remain usable without duplication',async()=>{
 const c=setup();await c.select('client',{requestId:rid,proposalId:p1});const chat=c.data.get(`conversations/${p1}`);delete chat.proposalId;delete chat.proposalStatus;delete chat.schemaVersion;c.data.delete(`conversations/${p1}`);c.data.set(`conversations/${rid}`,chat);c.data.get(`proposals/${p1}`).conversationId=rid;c.data.get(`proposals/${p1}`).status='selected';c.data.get(`userRequests/client/items/${rid}`).status='in_discussion';
 assert.equal((await c.select('client',{requestId:rid,proposalId:p1})).conversationId,rid);await c.send('pro',msg(rid));assert.equal(c.data.has(`conversations/${p1}`),false);
});
