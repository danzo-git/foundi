const {OtpError,requireUid}=require('./auth-validation');
const {assertActive,contactAllowed}=require('./safety-guard');
const {forEachBounded}=require('./bounded-work');
const fail=(code,message)=>{throw new OtpError(code,message);};
const validId=value=>typeof value==='string'&&/^[a-zA-Z0-9_-]{1,128}$/.test(value);
const validKey=value=>typeof value==='string'&&/^[a-f0-9]{32}$/.test(value);
function createConversationAvatarService({store,auth,ensureIdentity=async()=>{}}){
 async function account(uid){
  const user=await auth.getUser(requireUid(uid));
  if(user.disabled||!user.emailVerified)fail('permission-denied','Compte indisponible.');
 }
 async function resolve(uid,input){
  requireUid(uid);
  if(!input||typeof input!=='object'||Array.isArray(input)||Object.keys(input).some(k=>k!=='conversationIds')||!Array.isArray(input.conversationIds)||input.conversationIds.length>30||input.conversationIds.some(id=>typeof id!=='string'||!/^[a-zA-Z0-9_-]{20,80}$/.test(id)))fail('invalid-argument','Conversations invalides.');
  await account(uid);await assertActive(store,uid);
  const avatars={},identities=new Map();
  await forEachBounded([...new Set(input.conversationIds)],4,async id=>{
   const chat=await store.get(`conversations/${id}`);
   if(!chat||![chat.clientUid,chat.professionalUid].includes(uid))return;
   const other=chat.clientUid===uid?chat.professionalUid:chat.clientUid;
   if(!validId(other)||other===uid||chat.proposalStatus==='account_deleted'||(other===chat.clientUid?chat.clientDeleted:chat.professionalDeleted))return;
   if(!await contactAllowed(store,uid,other))return;
   try{
    if(!identities.has(other))identities.set(other,(async()=>{await account(other);await ensureIdentity(other);})());
    await identities.get(other);
   }catch(e){if(['permission-denied','auth/user-not-found','auth/invalid-uid'].includes(e.code))return;throw e;}
   const avatar=await store.get(`personalAvatars/${other}`);
   if(!avatar?.published||!validKey(avatar.publicId)||!validKey(avatar.revision))return;
   const projection=await store.get(`publicPersonalAvatars/${avatar.publicId}`);
   if(projection?.version!==avatar.revision)return;
   // Recheck membership and live restrictions after any legacy portrait import.
   const current=await store.get(`conversations/${id}`);
   if(!current||current.clientUid!==chat.clientUid||current.professionalUid!==chat.professionalUid||current.proposalStatus==='account_deleted'||(other===current.clientUid?current.clientDeleted:current.professionalDeleted)||!await contactAllowed(store,uid,other))return;
   avatars[id]=avatar.publicId;
  });
  await assertActive(store,uid);
  return {avatars};
 }
 return {resolve};
}
module.exports={createConversationAvatarService};
