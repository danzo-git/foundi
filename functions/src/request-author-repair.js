const {createHash}=require('node:crypto');
const {accountRequesterName}=require('./direct-request-context');
const digest=value=>createHash('sha256').update(JSON.stringify(value)).digest('hex');
function stable(value){
  if(Array.isArray(value))return value.map(stable);
  if(value&&typeof value==='object')return Object.fromEntries(Object.keys(value).sort().map(k=>[k,stable(value[k])]));
  return value;
}
const fingerprint=value=>digest(stable(value));
const missing=value=>value==null || (typeof value==='string'&&!value.trim());

function createRequestAuthorRepair({store,auth}){
  async function inspect(tx,id){
    if(typeof id!=='string'||!/^[a-zA-Z0-9_-]{20,80}$/.test(id))throw Error('Invalid request ID');
    const request=await tx.get(`requests/${id}`);
    if(!request || request.status!=='published' || request.directProfessionalId || request.visibility==='direct')return {state:'skip',reason:'not_public'};
    const owner=await tx.get(`requestOwnership/${id}`),uid=owner?.ownerUid;
    if(typeof uid!=='string'||!/^[a-zA-Z0-9_-]{1,128}$/.test(uid))return {state:'skip',reason:'missing_owner'};
    const ownPath=`userRequests/${uid}/items/${id}`,own=await tx.get(ownPath);
    if(!own || own.status!=='published' || own.createdAt!==request.createdAt || own.directProfessionalId || own.visibility==='direct')return {state:'skip',reason:'inconsistent_owner_copy'};
    const profile=await tx.get(`users/${uid}`);
    let account;
    try{account=await auth.getUser(uid);}catch(error){if(error.code==='auth/user-not-found')return {state:'skip',reason:'missing_account'};throw error;}
    if(account.disabled || !account.emailVerified)return {state:'skip',reason:'inactive_account'};
    const name=accountRequesterName(profile,account);
    if(!name)return {state:'skip',reason:'missing_account_name'};
    if(request.authorPublicName===name && own.authorPublicName===name)return {state:'current'};
    // Only fill absent names. Never replace an existing public name in this repair.
    if(!missing(request.authorPublicName))return {state:'skip',reason:'public_name_present'};
    return {state:'candidate',name,ownPath,request,own,
      guard:{requestId:id,ownerHash:digest(uid),nameHash:digest(name),
        publicHash:fingerprint(request),ownHash:fingerprint(own),createdAt:request.createdAt,
        previousNames:{public:{present:Object.hasOwn(request,'authorPublicName'),value:request.authorPublicName??null},
          own:{present:Object.hasOwn(own,'authorPublicName'),value:own.authorPublicName??null}}}};
  }
  async function plan(ids){
    if(!Array.isArray(ids)||ids.length>50)throw Error('Repair is limited to 50 requests');
    const entries=[],skipped=[];
    for(const id of new Set(ids)){
      const result=await store.transaction(tx=>inspect(tx,id));
      if(result.state==='candidate')entries.push(result.guard);
      else skipped.push({requestId:id,reason:result.reason||result.state});
    }
    return {entries,skipped};
  }
  async function apply(entry){
    return store.transaction(async tx=>{
      const result=await inspect(tx,entry.requestId);
      if(result.state==='current')return {requestId:entry.requestId,state:'already_current'};
      if(result.state!=='candidate')return {requestId:entry.requestId,state:'conflict',reason:result.reason};
      if(['ownerHash','nameHash','publicHash','ownHash','createdAt'].some(k=>entry[k]!==result.guard[k])){
        return {requestId:entry.requestId,state:'conflict',reason:'changed_since_plan'};
      }
      tx.update(`requests/${entry.requestId}`,{authorPublicName:result.name});
      tx.update(result.ownPath,{authorPublicName:result.name});
      return {requestId:entry.requestId,state:'repaired'};
    });
  }
  return {plan,apply};
}
module.exports={createRequestAuthorRepair};
