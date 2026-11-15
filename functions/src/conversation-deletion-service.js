const {OtpError,requireUid}=require('./auth-validation');
const {assertActive}=require('./safety-guard');
const fail=(code,message)=>{throw new OtpError(code,message);};
const validId=value=>typeof value==='string'&&/^[a-zA-Z0-9_-]{20,80}$/.test(value);
const markerPath=(uid,id)=>`users/${uid}/deletedConversations/${id}`;
function createConversationDeletionStore(db){
 return {transaction:operation=>db.runTransaction(tx=>operation({
  get:async path=>(await tx.get(db.doc(path))).data(),
  set:(path,value)=>tx.set(db.doc(path),value),
  unread:async(uid,id)=>(await tx.get(db.collection(`users/${uid}/messageInbox`).where('conversationId','==',id).where('unread','==',true).orderBy('createdAt').limit(200))).docs.map(d=>({path:d.ref.path,value:d.data()})),
 }))};
}
function createConversationDeletionService({store,auth,clock=Date.now}){
 async function drain(tx,uid,id,marker){
  const rows=await tx.unread(uid,id),state=await tx.get(`users/${uid}/messageState/inbox`);
  for(const row of rows)tx.set(row.path,{...row.value,unread:false});
  if(rows.length)tx.set(`users/${uid}/messageState/inbox`,{...state,unreadCount:Math.max(0,(state?.unreadCount||0)-rows.length),schemaVersion:91});
  tx.set(markerPath(uid,id),{...marker,cleanupPending:rows.length===200,cleanupRevision:(marker.cleanupRevision||0)+1});
 }
 async function remove(uid,input){
  requireUid(uid);
  if(!input||typeof input!=='object'||Array.isArray(input)||Object.keys(input).some(k=>!['conversationId','viewerUid'].includes(k))||!validId(input.conversationId))fail('invalid-argument','Conversation invalide.');
  if(input.viewerUid!==uid)fail('permission-denied','Le compte a changé. Rouvre ta messagerie.');
  const account=await auth.getUser(uid);
  if(account.disabled||!account.emailVerified)fail('permission-denied','Compte indisponible.');
  return store.transaction(async tx=>{
   await assertActive(tx,uid);
   const id=input.conversationId,chat=await tx.get(`conversations/${id}`);
   if(!chat||![chat.clientUid,chat.professionalUid].includes(uid))fail('permission-denied','Cette conversation est privée.');
   const old=await tx.get(markerPath(uid,id)),state=await tx.get(`users/${uid}/conversationState/inbox`);
   // All transaction reads happen before writes in drain.
   const marker=old||{deletedAt:clock(),cleanupRevision:0};
   await drain(tx,uid,id,marker);
   if(!old)tx.set(`users/${uid}/conversationState/inbox`,{revision:(state?.revision||0)+1,updatedAt:clock()});
   return {deleted:true};
  });
 }
 async function cleanup(uid,id){
  if(!uid||!validId(id))return;
  return store.transaction(async tx=>{
   const marker=await tx.get(markerPath(uid,id));
   // Never recreate a private tree during or after account erasure.
   if(!marker?.cleanupPending||await tx.get(`accountLifecycle/${uid}`))return;
   await drain(tx,uid,id,marker);
  });
 }
 return {remove,cleanup};
}
module.exports={createConversationDeletionService,createConversationDeletionStore,markerPath};
