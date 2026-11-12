const {test} = require('node:test');
const assert = require('node:assert/strict');
const {readFileSync} = require('node:fs');
const {createRequestService} = require('../src/request-service');
const {createRequestPhotoService} = require('../src/request-photo-service');
const {createProposalService} = require('../src/proposal-service');
const {createConversationService} = require('../src/conversation-service');
const id = 'DirectRequestIdentifier001';
const draft = {categoryId:'home', specialtyId:'', zoneId:'cocody', title:'Réparer mon meuble', description:'Je souhaite faire réparer mon meuble en bois.', budget:null};
const code = name => error => error.code === name;
function fixture() {
  const data = new Map([
    ['referenceData/professionalOnboarding', {enabled:true, categories:[{id:'home',label:'Maison'}], zones:[{id:'cocody',label:'Cocody'}]}],
    ['professionalProfiles/pro', {status:'approved',businessName:'Atelier Ébène',categoryIds:['home'],specialtyIds:[]}],
    ['professionalProfiles/other', {status:'approved',businessName:'Autre atelier'}],
    ['users/client', {fullName:'Nom civil privé',email:'prive@example.test',phone:'+2250700000000'}],
  ]);
  const accounts = new Map(); let now=1000000, queue=Promise.resolve(), object=0;
  const store={get:async path=>data.get(path), transaction(operation) {
    const job=queue.then(async()=>{
      const copy=structuredClone(data); let writing=false;
      const result=await operation({get:async p=>{assert.equal(writing,false,'all transaction reads precede writes');return copy.get(p);},
        set:(p,v)=>{writing=true;copy.set(p,v);},delete:p=>{writing=true;copy.delete(p);},
        conversationsForRequest:async requestId=>[...copy].filter(([p,v])=>/^conversations\/[^/]+$/.test(p)&&v.requestId===requestId).map(([p,v])=>({id:p.split('/')[1],...v})),
      });
      data.clear();for(const [p,v]of copy)data.set(p,v);return result;
    });queue=job.catch(()=>{});return job;
  }};
  const auth={getUser:async uid=>accounts.get(uid)||{emailVerified:true,disabled:false,displayName:'Nom du compte'} };
  const files={save:async()=> '1',read:async()=>Buffer.from('private photo'),remove:async()=>{}};
  const deps={store,auth,clock:()=>now};
  const photos=createRequestPhotoService({...deps,files,newId:()=>`photo-${++object}`});
  return {data,accounts,photos,requests:createRequestService({...deps,photos}),proposals:createProposalService(deps),conversations:createConversationService(deps),advance:()=>now+=61000};
}

test('direct requests use only private documents, one immutable recipient and the existing quota',async()=>{
  const c=fixture();
  const [a,b]=await Promise.all([c.requests.publishDirect('client',id,'pro',draft),c.requests.publishDirect('client',id,'pro',draft)]);
  assert.deepEqual(a,b);assert.equal(a.status,'published');assert.equal(a.visibility,'direct');
  assert.equal(a.directProfessionalId,'pro');assert.equal(a.directProfessionalName,'Atelier Ébène');
  assert.equal(a.requesterName,'Nom civil privé');
  assert.equal(a.authorPublicName,undefined);
  assert.equal(c.data.get(`directRequests/${id}`).clientUid,'client');
  assert.equal(c.data.has(`requests/${id}`),false);
  assert.deepEqual(c.data.get('requestPublicationLimits/client').createdAtMs,[1000000]);
  assert.ok(!JSON.stringify(a).includes('prive@example.test'));assert.ok(!JSON.stringify(a).includes('+2250700000000'));
  await assert.rejects(c.requests.publish('client',id,draft),code('already-exists'));
  await assert.rejects(c.requests.publishDirect('client',id,'other',draft),code('already-exists'));
  await assert.rejects(c.requests.publishDirect('other-client',id,'pro',draft),code('already-exists'));
  await assert.rejects(c.requests.publish('client',id+'public',draft),code('resource-exhausted'));
  c.advance();await c.requests.publish('client',id+'public',draft);
  assert.equal(c.data.get('requestPublicationLimits/client').createdAtMs.length,2);
});

test('private identity comes from the account, ignores forged names and never enters the public projection', async()=>{
  const c=fixture();
  const created=await c.requests.publishDirect('client',id,'pro',{...draft,authorPublicName:'Faux nom',requesterName:'Usurpation'});
  assert.equal(created.requesterName,'Nom civil privé');
  assert.equal(c.data.get(`userRequests/client/items/${id}`).requesterName,'Nom civil privé');
  assert.equal(c.data.get(`directRequests/${id}`).authorPublicName,undefined);
  const edited=await c.requests.manage('client',id,'edit',{...draft,authorPublicName:'Autre faux nom'},created.createdAt);
  assert.equal(edited.requesterName,'Nom civil privé');
  assert.equal(edited.authorPublicName,undefined);
  assert.equal(c.data.has(`requests/${id}`),false);
  c.advance();
  const pub=await c.requests.publish('client',id+'public',{...draft,authorPublicName:'Nom public choisi'});
  assert.equal(pub.authorPublicName,'Nom civil privé');
  assert.equal(pub.requesterName,undefined);
});

test('private activity is selected by the professional and cannot be changed on creation or edit',async()=>{
  const c=fixture(),catalog=c.data.get('referenceData/professionalOnboarding');
  catalog.categories.push({id:'other-category',label:'Autre activité'});
  await assert.rejects(c.requests.publishDirect('client',id,'pro',{...draft,categoryId:'other-category'}),code('failed-precondition'));
  assert.equal(c.data.has('requestPublicationLimits/client'),false);
  const created=await c.requests.publishDirect('client',id,'pro',draft);
  await assert.rejects(c.requests.manage('client',id,'edit',{...draft,categoryId:'other-category'},created.createdAt),code('invalid-argument'));
  assert.equal(c.data.get(`directRequests/${id}`).categoryId,'home');
  assert.equal(c.data.get('requestPublicationLimits/client').createdAtMs.length,1);
});

test('legacy author lookup checks each private request, exposes only names and never writes documents',async()=>{
  const c=fixture();await c.requests.publishDirect('client',id,'pro',draft);
  delete c.data.get(`directRequests/${id}`).requesterName;
  c.data.get(`directRequests/${id}`).authorPublicName='Ancien nom abrégé';
  const before=JSON.stringify([...c.data]);
  assert.deepEqual(await c.requests.readDirectAuthors('pro',[id,id]),{authors:{[id]:'Nom civil privé'}});
  assert.deepEqual(await c.requests.readDirectAuthors('client',[id]),{authors:{[id]:'Nom civil privé'}});
  assert.equal(JSON.stringify([...c.data]),before);
  await assert.rejects(c.requests.readDirectAuthors('other',[id]),code('permission-denied'));
  await assert.rejects(c.requests.readDirectAuthors(null,[id]),code('unauthenticated'));
  await assert.rejects(c.requests.readDirectAuthors('pro',[id,'../users/client']),code('invalid-argument'));
  await assert.rejects(c.requests.readDirectAuthors('pro',Array(51).fill(id)),code('invalid-argument'));
  c.data.get('professionalProfiles/pro').status='suspended';
  await assert.rejects(c.requests.readDirectAuthors('pro',[id]),code('permission-denied'));
  c.data.get('professionalProfiles/pro').status='approved';
  c.data.get(`directRequests/${id}`).status='deleted';
  await assert.rejects(c.requests.readDirectAuthors('pro',[id]),code('permission-denied'));
});

test('private names fall back to Auth displayName, never to email or phone',async()=>{
  const c=fixture();c.data.delete('users/client');
  c.accounts.set('client',{emailVerified:true,displayName:'Élodie N’Guessan',email:'private@example.test',phoneNumber:'+2250700000000'});
  assert.equal((await c.requests.publishDirect('client',id,'pro',draft)).requesterName,'Élodie N’Guessan');
  const missing=fixture();missing.data.delete('users/client');
  missing.accounts.set('client',{emailVerified:true,email:'private@example.test',phoneNumber:'+2250700000000'});
  await assert.rejects(missing.requests.publishDirect('client',id,'pro',draft),code('failed-precondition'));
  assert.equal(missing.data.has('requestPublicationLimits/client'),false);
});

test('invalid recipients, self-sending, unverified accounts and public-photo injection fail without quota writes',async()=>{
  for(const status of ['pending','suspended','rejected','draft']) {
    const c=fixture();c.data.get('professionalProfiles/pro').status=status;
    await assert.rejects(c.requests.publishDirect('client',id,'pro',draft),code('failed-precondition'));
    assert.equal(c.data.has('requestPublicationLimits/client'),false);
  }
  for(const account of [{emailVerified:false},{emailVerified:true,disabled:true}]) {
    const c=fixture();c.accounts.set('pro',account);
    await assert.rejects(c.requests.publishDirect('client',id,'pro',draft),code('failed-precondition'));
  }
  const c=fixture();
  await assert.rejects(c.requests.publishDirect(null,id,'pro',draft),code('unauthenticated'));
  await assert.rejects(c.requests.publishDirect('pro',id,'pro',draft),code('permission-denied'));
  await assert.rejects(c.requests.publishDirect('client',id,undefined,draft),code('invalid-argument'));
  c.accounts.set('client',{emailVerified:false});
  await assert.rejects(c.requests.publishDirect('client',id,'pro',draft),code('failed-precondition'));
  c.accounts.delete('client');
  await assert.rejects(c.requests.publishDirect('client',id,'pro',{...draft,photoIds:['a'.repeat(32)],photosPublic:true}),code('invalid-argument'));
  assert.equal(c.data.has('requestPublicationLimits/client'),false);
});

test('only the chosen approved professional can propose; discussion and decisions retain their private lifecycle',async()=>{
  const c=fixture();await c.requests.publishDirect('client',id,'pro',draft);
  const value={description:'Je peux réparer votre meuble.',amount:15000,delay:'Cette semaine'};
  await assert.rejects(c.proposals.send('other',id,value),code('permission-denied'));
  const p=await c.proposals.send('pro',id,value);
  assert.equal(c.data.get(`userRequests/client/items/${id}`).proposalCount,1);
  const chat=await c.conversations.select('client',{requestId:id,proposalId:p.id});
  await c.conversations.send('pro',{conversationId:chat.conversationId,messageId:'MessageIdentifier00001',text:'Bonjour, voici mes disponibilités.'});
  await assert.rejects(c.conversations.send('other',{conversationId:chat.conversationId,messageId:'MessageIdentifier00002',text:'Intrusion'}),code('permission-denied'));
  await c.conversations.decide('client',{requestId:id,proposalId:p.id,action:'retain',decisionId:'DecisionIdentifier00001'});
  assert.equal(c.data.get(`proposals/${p.id}`).status,'retained');
  await c.requests.manage('client',id,'delete');
  assert.equal(c.data.get(`directRequests/${id}`).status,'deleted');
  assert.equal(c.data.get(`conversations/${chat.conversationId}`).status,'read_only');
  assert.equal(c.data.has(`requests/${id}`),false);
});

test('private photos cannot be read publicly or by another approved professional; edits never publish the request',async()=>{
  const c=fixture(),photo='a'.repeat(32),second='b'.repeat(32);
  const raw=readFileSync(require('node:path').join(__dirname,'fixtures/photo.png'));
  await c.photos.upload('client',id,photo,raw,'image/png');
  const created=await c.requests.publishDirect('client',id,'pro',{...draft,photoIds:[photo]});
  assert.equal((await c.photos.read('pro',id,photo)).toString(),'private photo');
  await assert.rejects(c.photos.readPublic(id,photo),code('not-found'));
  await assert.rejects(c.photos.read('other',id,photo),code('permission-denied'));
  c.data.get('professionalProfiles/pro').status='suspended';
  await assert.rejects(c.photos.read('pro',id,photo),code('permission-denied'));
  c.data.get('professionalProfiles/pro').status='approved';
  await c.photos.upload('client',id,second,raw,'image/png');
  const saved=await c.requests.manage('client',id,'edit',{...draft,title:'Autre titre privé',photoIds:[second],photosPublic:false},created.createdAt);
  assert.equal(c.data.get(`directRequests/${id}`).directProfessionalId,'pro');
  assert.equal(c.data.get(`requestPhotoFiles/${id}_${photo}`).state,'discarded');
  assert.equal(c.data.has(`requests/${id}`),false);
  await assert.rejects(c.requests.manage('client',id,'edit',{...draft,photoIds:[second],photosPublic:true},saved.updatedAt),code('invalid-argument'));
  await assert.rejects(c.requests.manage('client',id,'edit',{...draft,directProfessionalId:'other'},saved.updatedAt),code('invalid-argument'));
});
