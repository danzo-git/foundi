const { createHash } = require('node:crypto');
const { requestRecord } = require('./request-access');
const { OtpError, requireUid } = require('./auth-validation');
const fail = (code, message) => { throw new OtpError(code, message); };
const validId = id => typeof id === 'string' && /^[a-zA-Z0-9_-]{20,80}$/.test(id);
const proposalId = (requestId, uid) => createHash('sha256').update(requestId + '\0' + uid).digest('hex');
function input(data) {
  if (!data || Object.keys(data).some(k => !['description','amount','delay'].includes(k))) fail('invalid-argument', 'Champs de proposition invalides.');
  if (typeof data.description !== 'string' || data.description.trim().length < 10 || data.description.trim().length > 3000) fail('invalid-argument', 'Décris ta proposition en 10 à 3000 caractères.');
  if (data.amount !== null && (!Number.isSafeInteger(data.amount) || data.amount <= 0 || data.amount > 999999999999)) fail('invalid-argument', 'Le montant doit être un entier strictement positif en FCFA.');
  if (typeof data.delay !== 'string' || data.delay.trim().length > 120) fail('invalid-argument', 'Le délai doit être un texte de 120 caractères maximum.');
  return { description:data.description.trim(), amount:data.amount, delay:data.delay.trim() };
}
function createProposalService({store,auth,clock=()=>Date.now()}) {
  async function verified(uid) {
    requireUid(uid); const account=await auth.getUser(uid);
    if(account.disabled || !account.emailVerified) fail('permission-denied','Un compte actif avec une adresse vérifiée est nécessaire.');
  }
  async function owner(requestId) {
    if(!validId(requestId)) fail('invalid-argument','Demande invalide.');
    const mapping=await store.get(`requestOwnership/${requestId}`);
    if(mapping?.ownerUid) return mapping.ownerUid;
    const request=await store.get(`requests/${requestId}`);
    if(!request || request.status!=='published') fail('failed-precondition','Cette demande n’est plus ouverte.');
    // Historical V5 mirrors have no ID field: use a bounded timestamp lookup,
    // then require the exact document ID and the trusted userRequests path.
    const candidates=await store.legacyOwners(requestId,request.createdAt);
    if(candidates.length!==1) fail('failed-precondition','Le propriétaire de cette ancienne demande ne peut pas être confirmé.');
    return candidates[0];
  }
  async function context(tx,uid,requestId,clientUid) {
    const request=await requestRecord(tx,requestId);
    const own=await tx.get(`userRequests/${clientUid}/items/${requestId}`);
    const profile=await tx.get(`professionalProfiles/${uid}`);
    if(profile?.status!=='approved') fail('permission-denied','Un profil professionnel approuvé est requis.');
    if(!request || request.status!=='published' || !own || own.status!=='published' || own.createdAt!==request.createdAt) fail('failed-precondition','Cette demande n’est plus ouverte ou sa propriété ne peut pas être confirmée.');
    if(uid===clientUid) fail('permission-denied','Tu ne peux pas répondre à ta propre demande.');
    if(request.visibility === 'direct' && (request.directProfessionalId !== uid || request.clientUid !== clientUid)) fail('permission-denied','Cette demande est réservée au professionnel choisi.');
    return {request,own,profile};
  }
  async function access(uid,requestId) {
    await verified(uid);const clientUid=await owner(requestId);const id=proposalId(requestId,uid);
    return store.transaction(async tx=>{
      await context(tx,uid,requestId,clientUid);
      const saved=await tx.get(`proposals/${id}`);
      return {canSend:!saved,proposalId:saved?id:null};
    });
  }
  async function send(uid,requestId,data) {
    await verified(uid);const value=input(data);const clientUid=await owner(requestId);const id=proposalId(requestId,uid);
    return store.transaction(async tx=>{
      const {request,own,profile}=await context(tx,uid,requestId,clientUid);
      const existing=await tx.get(`proposals/${id}`);
      if(existing) return {id,...existing};
      const name=profile.businessName;
      if(typeof name!=='string' || !name.trim()) fail('failed-precondition','Ton nom professionnel est indisponible.');
      const saved={...value,requestId,professionalUid:uid,clientUid,professionalName:name.trim(),requestTitle:request.title,status:'sent',createdAt:clock()};
      tx.set(`proposals/${id}`,saved);
      tx.set(`requestOwnership/${requestId}`,{ownerUid:clientUid});
      tx.set(`userRequests/${clientUid}/items/${requestId}`,{...own,proposalCount:(own.proposalCount||0)+1});
      return {id,...saved};
    });
  }
  async function approval(uid,id) {
    await verified(uid);
    if(typeof id!=='string'||!/^[a-f0-9]{64}$/.test(id)) fail('invalid-argument','Proposition invalide.');
    const saved=await store.get(`proposals/${id}`);
    if(!saved || ![saved.professionalUid,saved.clientUid].includes(uid)) fail('permission-denied','Proposition privée.');
    const profile=await store.get(`professionalProfiles/${saved.professionalUid}`);
    return {approved:profile?.status==='approved'};
  }
  return {access,send,approval,owner};
}
module.exports={createProposalService,proposalId};
