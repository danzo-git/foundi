const {test}=require('node:test');
const assert=require('node:assert/strict');
const {createSafetyStore}=require('../src/safety-store');
function database(error,docs=[]){
  const query={where(){return this;},orderBy(){return this;},limit(){return this;},startAfter(){return this;},async get(){if(error)throw error;return {docs,size:docs.length};}};
  return {collection:()=>query};
}
test('moderation queue and audit translate missing production index without leaking console links',async()=>{
  for(const code of [9,'failed-precondition','FAILED_PRECONDITION']){
    const store=createSafetyStore(database(Object.assign(Error('The query requires an index. https://private-console.invalid/create-index'),{code})));
    for(const action of [()=>store.listReports({status:'new'}),()=>store.audit('report')]){
      await assert.rejects(action(),e=>e.code==='failed-precondition' && e.message.includes('index nécessaires') && !e.message.includes('https://'));
    }
  }
});
test('moderation never hides permission failures or unrelated preconditions as missing indexes',async()=>{
  for(const error of [Object.assign(Error('Permission denied'),{code:7}),Object.assign(Error('Database not available'),{code:9})]){
    const store=createSafetyStore(database(error));
    await assert.rejects(store.listReports({status:'new'}),e=>e===error);
    await assert.rejects(store.audit('report'),e=>e===error);
  }
});
test('successful queue stays a minimal projection and paginates with its server cursor',async()=>{
  const docs=Array.from({length:26},(_,i)=>({id:String(i).padStart(64,'0'),data:()=>({targetType:'request',reason:'spam',status:'new',label:'Demande',createdAt:i,priority:'normal',revision:1,reporterUid:'private-reporter',evidence:{text:'private message'}})}));
  const result=await createSafetyStore(database(null,docs)).listReports({status:'new'});
  assert.equal(result.items.length,25);assert.deepEqual(result.cursor,{id:docs[24].id,createdAt:24});
  assert.ok(!JSON.stringify(result).includes('private'));
});
test('recipient notice history exposes only its text, stable id and reading state, including legacy notices',async()=>{
  const docs=[{id:'legacy',data:()=>({text:'Ancien avis',createdAt:1,reporterUid:'private',content:{secret:'private'}})},{id:'new',data:()=>({text:'Nouvel avis',createdAt:2,acknowledgedAt:3,recipientUid:'private'})}];
  const notices=await createSafetyStore(database(null,docs)).notices('owner');
  assert.deepEqual(notices,[{id:'legacy',text:'Ancien avis',createdAt:1,acknowledgedAt:null},{id:'new',text:'Nouvel avis',createdAt:2,acknowledgedAt:3}]);
});
