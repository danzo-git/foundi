// Synthetic stores used by tests and the local benchmark. No Firebase/network.
const { Buffer } = require('node:buffer');
const { proposalId } = require('../src/proposal-service');
const requestId = 'RespondentsLoadingFixture001';
const authorRequestId = 'AuthorLoadingFixture00001';
const catalog = { enabled: true,
  categories: [{id:'home',label:'Maison',specialties:[{id:'wood',label:'Menuiserie'}]}],
  zones:[{id:'zone',label:'Zone de test'}] };
const profile = name => ({status:'approved',businessName:name,
  categoryIds:['home'],specialtyIds:['wood'],zoneIds:['zone'],internalNotes:'x'.repeat(1024)});
const showcase = {revision:1,name:'Atelier public',trade:'Menuiserie',area:'Zone de test',bio:'Présentation publique',gallery:[]};
function metrics(delayMs = 0) {
  const counters = {documentReads:0,queryCalls:0,aggregationCalls:0,authCalls:0,rateCharges:0,returnedBytes:0,permissionPeak:0};
  let permissionRunning = 0;
  async function pause(permission = false) {
    if (permission) {
      permissionRunning++;
      counters.permissionPeak = Math.max(counters.permissionPeak,permissionRunning);
    }
    if (delayMs) await new Promise(resolve => setTimeout(resolve,delayMs));
    else await new Promise(resolve => setImmediate(resolve));
    if (permission) permissionRunning--;
  }
  function transfer(value) {
    if (value !== undefined) counters.returnedBytes += Buffer.byteLength(JSON.stringify(value));
    return structuredClone(value);
  }
  return {counters,pause,transfer};
}
function respondentsFixture(createService,{count=20,delayMs=0}={}) {
  const m=metrics(delayMs), docs=new Map([
    [`requests/${requestId}`,{status:'published',createdAt:123}],
    [`userRequests/viewer/items/${requestId}`,{status:'published',createdAt:123}],
    ['referenceData/professionalOnboarding',catalog],
  ]), accounts=new Map();
  const ids=Array.from({length:count},(_,i)=>`professional${String(i).padStart(4,'0')}`);
  for(const id of ids) {
    docs.set(`professionalProfiles/${id}`,profile(`Atelier ${id}`));
    docs.set(`proposals/${proposalId(requestId,id)}`,{requestId,professionalUid:id});
    docs.set(`professionalProfiles/${id}/showcase/profile`,showcase);
    accounts.set(id,{uid:id,emailVerified:true,disabled:false});
  }
  const masks=[]; let beforeRead=async()=>{};
  const snap=(path,value)=>{
    const data=m.transfer(value);
    return {id:path.split('/').at(-1),exists:value!==undefined,data:()=>structuredClone(data)};
  };
  const db={doc:path=>({path,id:path.split('/').at(-1),async get(){
    m.counters.documentReads++; await beforeRead(path);
    await m.pause(/^(accountSafety|accountLifecycle|safetyContent)\//.test(path));
    return snap(path,docs.get(path));
  }}),
  async getAll(...args) {
    const options=args.at(-1)?.fieldMask?args.pop():{};
    masks.push(options.fieldMask);m.counters.documentReads+=args.length;await m.pause();
    return args.map(ref=>{
      const raw=docs.get(ref.path), value=raw&&options.fieldMask
        ?Object.fromEntries(options.fieldMask.filter(k=>raw[k]!==undefined).map(k=>[k,raw[k]])):raw;
      return snap(ref.path,value);
    });
  }, collection(name) {
    if(name!=='proposals')throw Error('Unexpected fixture collection');
    const query={skip:0,size:20,where(){return this;},orderBy(){return this;},
      offset(value){this.skip=value;return this;},limit(value){this.size=value;return this;},
      select(){return this;}, count(){return {get:async()=>{
        m.counters.aggregationCalls++;await m.pause();return {data:()=>({count:ids.length})};
      }};},async get(){m.counters.queryCalls++;await m.pause();
        const selected=ids.slice(this.skip,this.skip+this.size);
        m.counters.documentReads+=selected.length;
        return {size:selected.length,docs:selected.map(id=>snap(`proposals/${proposalId(requestId,id)}`,{professionalUid:id}))};
      }};return query;
  },async runTransaction(action){return action({get:ref=>ref.get()});}};
  const auth={async getUsers(requests){m.counters.authCalls++;await m.pause();return {users:requests.map(({uid})=>accounts.get(uid)).filter(Boolean)};},
    async getUser(uid){m.counters.authCalls++;await m.pause();if(!accounts.has(uid))throw Object.assign(Error('missing'),{code:'auth/user-not-found'});return accounts.get(uid);}};
  return {service:createService({db,auth}),db,auth,docs,accounts,ids,masks,metrics:m.counters,
    beforeRead(fn){beforeRead=fn;}, requestId};
}
function directoryFixture(createService,{delayMs=0}={}) {
  const m=metrics(delayMs),id='professional0000',docs=new Map([
    ['referenceData/professionalOnboarding',catalog],
    [`professionalProfiles/${id}`,profile('Atelier public')],
    [`professionalProfiles/${id}/showcase/profile`,showcase],
  ]);
  const store={async get(path){m.counters.documentReads++;await m.pause();return m.transfer(docs.get(path));},
    async profiles(ids){await m.pause();m.counters.documentReads+=ids.length;
      return ids.filter(uid=>docs.has(`professionalProfiles/${uid}`)).map(uid=>({id:uid,profile:m.transfer(
        Object.fromEntries(['status','businessName','categoryIds','specialtyIds','zoneIds'].map(k=>[k,docs.get(`professionalProfiles/${uid}`)[k]]))
      )}));},
    async charge(){m.counters.rateCharges++;await m.pause();}};
  const auth={async getUser(uid){m.counters.authCalls++;await m.pause();return {uid,emailVerified:true,disabled:false};}};
  return {service:createService({store,auth}),store,auth,docs,id,metrics:m.counters};
}
function authorFixture(createService,{delayMs=0}={}) {
  const m=metrics(delayMs),docs=new Map([
    [`requests/${authorRequestId}`,{status:'published',createdAt:123,authorPublicName:'Membre public'}],
    [`requestOwnership/${authorRequestId}`,{ownerUid:'author'}],
    ['professionalProfiles/author',profile('Atelier public')],
  ]);
  const reads=[];
  const store={async get(path){reads.push(path);m.counters.documentReads++;await m.pause();return m.transfer(docs.get(path));},
    async charge(){m.counters.rateCharges++;await m.pause();}};
  const auth={async getUser(uid){m.counters.authCalls++;await m.pause();return {uid,emailVerified:true,disabled:false};}};
  const avatars={async resolve(){await m.pause();return {avatars:{[authorRequestId]:'public-avatar-key'}};}};
  const directory={async readProfile(){await m.pause();return {name:'Atelier public',trade:'Menuiserie',professionalId:'author'};}};
  return {service:createService({store,auth,avatars,directory}),store,auth,avatars,directory,docs,reads,metrics:m.counters,requestId:authorRequestId};
}
module.exports={respondentsFixture,directoryFixture,authorFixture};
