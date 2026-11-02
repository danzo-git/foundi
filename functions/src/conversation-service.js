const {OtpError,requireUid}=require('./auth-validation');
const fail=(code,message)=>{throw new OtpError(code,message);};
const requestIdOK=id=>typeof id==='string'&&/^[a-zA-Z0-9_-]{20,80}$/.test(id);
const proposalIdOK=id=>typeof id==='string'&&/^[a-f0-9]{64}$/.test(id);
const publicFields=['title','description','categoryId','categoryLabel','specialtyId','specialtyLabel','zoneId','zoneLabel','budget','status','createdAt'];
function createConversationService({store,auth,clock=()=>Date.now()}) {
 async function account(uid){requireUid(uid);const a=await auth.getUser(uid);if(a.disabled||!a.emailVerified)fail('permission-denied','Un compte actif et vérifié est nécessaire.');return a;}
 async function select(uid,data){
  const a=await account(uid);
  if(!data||Object.keys(data).some(k=>!['requestId','proposalId'].includes(k))||!requestIdOK(data.requestId)||!proposalIdOK(data.proposalId))fail('invalid-argument','Sélection invalide.');
  const {requestId,proposalId}=data;
  return store.transaction(async tx=>{
   const p=await tx.get(`proposals/${proposalId}`);
   const own=await tx.get(`userRequests/${uid}/items/${requestId}`);
   const pub=await tx.get(`requests/${requestId}`);
   const chat=await tx.get(`conversations/${requestId}`);
   const user=await tx.get(`users/${uid}`);
   const pro=p?await tx.get(`professionalProfiles/${p.professionalUid}`):null;
   if(!own||!p||p.clientUid!==uid||p.requestId!==requestId||p.professionalUid===uid)fail('permission-denied','Seul l’auteur peut choisir une proposition liée à sa demande.');
   if(own.selectedProposalId){
    if(own.selectedProposalId!==proposalId)fail('already-exists','Un autre professionnel est déjà choisi pour cette demande.');
    if(!chat||chat.selectedProposalId!==proposalId||chat.clientUid!==uid||chat.professionalUid!==p.professionalUid)fail('failed-precondition','La discussion liée est indisponible.');
    return {conversationId:requestId,alreadySelected:true};
   }
   if(!pub||pub.status!=='published'||own.status!=='published'||own.createdAt!==pub.createdAt||p.status!=='sent'||chat)fail('failed-precondition','Cette demande ou proposition ne peut plus être sélectionnée.');
   if(pro?.status!=='approved')fail('permission-denied','Ce professionnel n’est plus approuvé.');
   const now=Math.max(clock(),(own.updatedAt??own.createdAt)+1);
   const snapshot=Object.fromEntries(publicFields.map(k=>[k,pub[k]]));snapshot.status='in_discussion';
   const conversation={requestId,selectedProposalId:proposalId,clientUid:uid,professionalUid:p.professionalUid,participantUids:[uid,p.professionalUid],clientName:typeof user?.fullName==='string'&&user.fullName.trim()?user.fullName.trim():a.displayName||'Client',professionalName:pro.businessName||p.professionalName,requestTitle:pub.title,requestSnapshot:snapshot,status:'active',createdAt:now,updatedAt:now,lastMessageAt:now,lastMessagePreview:''};
   tx.set(`userRequests/${uid}/items/${requestId}`,{...own,status:'in_discussion',selectedProposalId:proposalId,selectedProfessionalUid:p.professionalUid,conversationId:requestId,updatedAt:now});
   tx.set(`requests/${requestId}`,{...pub,status:'in_discussion',updatedAt:now});
   tx.set(`proposals/${proposalId}`,{...p,status:'selected',conversationId:requestId,selectedAt:now});
   tx.set(`conversations/${requestId}`,conversation);
   return {conversationId:requestId,alreadySelected:false};
  });
 }
 async function send(uid,data){
  await account(uid);
  if(!data||Object.keys(data).some(k=>!['conversationId','messageId','text'].includes(k))||!requestIdOK(data.conversationId)||!requestIdOK(data.messageId)||typeof data.text!=='string'||!data.text.trim()||data.text.trim().length>2000)fail('invalid-argument','Écris un message de 1 à 2000 caractères.');
  const {conversationId,messageId}=data,text=data.text.trim();
  return store.transaction(async tx=>{
   const chat=await tx.get(`conversations/${conversationId}`);
   if(!chat||![chat.clientUid,chat.professionalUid].includes(uid))fail('permission-denied','Cette discussion est privée.');
   const own=await tx.get(`userRequests/${chat.clientUid}/items/${chat.requestId}`);
   const existing=await tx.get(`conversations/${conversationId}/messages/${messageId}`);
   if(existing){if(existing.senderUid!==uid||existing.text!==text)fail('already-exists','Cet identifiant correspond à un autre message.');return {messageId,createdAt:existing.createdAt};}
   if(chat.status!=='active'||own?.status!=='in_discussion'||own.conversationId!==conversationId||own.selectedProposalId!==chat.selectedProposalId)fail('failed-precondition','Cette discussion est désormais en lecture seule.');
   const now=Math.max(clock(),chat.lastMessageAt+1);
   tx.set(`conversations/${conversationId}/messages/${messageId}`,{senderUid:uid,text,createdAt:now});
   tx.set(`conversations/${conversationId}`,{...chat,lastMessageAt:now,lastMessagePreview:text.slice(0,120),updatedAt:now});
   return {messageId,createdAt:now};
  });
 }
 return {select,send};
}
module.exports={createConversationService};
