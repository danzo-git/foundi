const {OtpError}=require('./auth-validation');
const {contactAllowed,publicProfileAllowed}=require('./safety-guard');
const {internalId}=require('./notification-policy');
const idPattern=/^[a-zA-Z0-9_-]{20,80}$/;
function requestAuthorActor(request) {
  const ip=request.rawRequest?.ip||request.rawRequest?.socket?.remoteAddress;
  // Some runtimes omit socket metadata. Share a strict anonymous budget then;
  // never trust a client-provided forwarded-IP header to create a fresh budget.
  const identity=request.auth?.uid||(typeof ip==='string'&&ip.length<=100?ip:'unidentified-visitor');
  return require('node:crypto').createHash('sha256').update(JSON.stringify(['foundi-request-author',identity])).digest('hex');
}
const unavailable=()=>{throw new OtpError('not-found','Le profil de cet auteur n’est plus disponible.');};
function createRequestAuthorService({store,auth,avatars,directory}) {
  async function context(viewer,requestId) {
    const request=await store.get(`requests/${requestId}`);
    if(request?.status!=='published'||request.visibility==='direct'||request.directProfessionalId)unavailable();
    const [hidden,mapping]=await Promise.all([
      store.get(`safetyContent/request_${requestId}`),
      store.get(`requestOwnership/${requestId}`),
    ]);
    if(hidden?.hidden)unavailable();
    let owner=mapping?.ownerUid;
    if(!owner&&Number.isSafeInteger(request.createdAt)) {
      const candidates=await store.legacyOwners(requestId,request.createdAt);
      if(candidates.length===1)owner=candidates[0];
    }
    if(!internalId(owner))unavailable();
    // Deduplicate identical reads only within this validation phase. The final
    // context() call has a new reader and must observe revocations afresh.
    const pending=new Map(),reader={get:path=>{
      if(!pending.has(path))pending.set(path,store.get(path));
      return pending.get(path);
    }};
    const account=await auth.getUser(owner).catch(e=>{if(e.code==='auth/user-not-found')unavailable();throw e;});
    if(account.disabled||!account.emailVerified)unavailable();
    const [allowed,contact]=await Promise.all([
      publicProfileAllowed(reader,owner),
      viewer?contactAllowed(reader,viewer,owner):true,
    ]);
    if(!allowed||!contact)unavailable();
    return {owner,request};
  }
  async function read(viewer,actor,input) {
    if(!input||Object.keys(input).some(k=>k!=='requestId')||typeof input.requestId!=='string'||!idPattern.test(input.requestId))throw new OtpError('invalid-argument','Demande invalide.');
    await store.charge(actor,'profile',Date.now());
    const {owner}=await context(viewer,input.requestId);
    const [identity,root]=await Promise.all([
      avatars.resolve(viewer,[input.requestId]),
      store.get(`professionalProfiles/${owner}`),
    ]);
    const avatar=identity.avatars[input.requestId]||null;
    let professional=null;
    if(root?.status==='approved') {
      // Reuse the same sanitization and live eligibility as the public directory.
      try {professional=await directory.readProfile(actor,{professionalId:owner});}
      catch(e){if(e.code!=='not-found'&&e.code!=='failed-precondition')throw e;}
    }
    const current=await context(viewer,input.requestId);
    if(current.owner!==owner)unavailable();
    if(professional&&(await store.get(`professionalProfiles/${owner}`))?.status!=='approved')unavailable();
    // Only the name already public on this request; never read users or expose its UID.
    const raw=current.request.authorPublicName;
    const name=typeof raw==='string'&&raw.trim()&&raw.length<=150?raw.trim():'Demandeur Foundi';
    return {name,avatarKey:avatar,professional};
  }
  return {read};
}
function createRequestAuthorStore(db) {
  const store=require('./professional-directory-store').createProfessionalDirectoryStore(db);
  store.legacyOwners=async(id,createdAt)=>{
    const rows=await db.collectionGroup('items').where('createdAt','==',createdAt).limit(51).get();
    if(rows.size>50)return [];
    return rows.docs.filter(d=>d.id===id&&/^userRequests\/[^/]+\/items\/[^/]+$/.test(d.ref.path)).map(d=>d.ref.parent.parent.id);
  };
  return store;
}
module.exports={createRequestAuthorService,createRequestAuthorStore,requestAuthorActor};
