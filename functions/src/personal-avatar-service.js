const {randomBytes,createHash} = require('node:crypto');
const sharp = require('sharp');
const {OtpError, requireUid} = require('./auth-validation');
const {assertActive, contactAllowed} = require('./safety-guard');
const {checkMagic} = require('./attachment-validation');
const {normalize} = require('./request-photo-service');
const fail=(code,message)=>{throw new OtpError(code,message);};
const validKey=k=>typeof k==='string'&&/^[a-f0-9]{32}$/.test(k);
function createPersonalAvatarService({db,auth,bucket,clock=Date.now}) {
  const reader=tx=>({get:async p=>(await (tx?tx.get(db.doc(p)):db.doc(p).get())).data()});
  async function account(uid) {
    const user=await auth.getUser(requireUid(uid));
    if(user.disabled||!user.emailVerified)fail('permission-denied','Un compte actif et vérifié est nécessaire.');
  }
  const garbageRef=path=>db.doc(`personalAvatarGarbage/${createHash('sha256').update(path).digest('hex')}`);
  function queueGarbage(tx,uid,path,dueAt=clock()) {
    if(path)tx.set(garbageRef(path),{uid,objectPath:path,dueAt,createdAt:clock()});
  }
  async function cleanupEntry(ref) {
    const value=(await ref.get()).data();if(!value)return true;
    try {
      if(!value.objectPath?.startsWith(`personalAvatars/${value.uid}/`) || value.objectPath.includes('..'))throw Error('Invalid object ownership');
      const current=(await db.doc(`personalAvatars/${value.uid}`).get()).data();
      if(current?.objectPath!==value.objectPath) {
        const file=bucket.file(value.objectPath);
        let metadata;
        try{[metadata]=await file.getMetadata();}catch(e){if(Number(e.code)!==404)throw e;}
        if(metadata){
          if(metadata.metadata?.owneruid!==value.uid)throw Error('Invalid object ownership');
          await bucket.file(value.objectPath,{generation:String(metadata.generation)}).delete({ifGenerationMatch:String(metadata.generation),ignoreNotFound:true});
        }
      }
      await ref.delete();return true;
    }catch(e){await ref.set({...value,dueAt:clock()+3600000,lastError:'delete-failed'});return false;}
  }
  async function cleanup() {
    let processed=0,failed=0;
    for(let page=0;page<4;page++) {
      const rows=await db.collection('personalAvatarGarbage').where('dueAt','<=',clock()).orderBy('dueAt').limit(50).get();
      for(const row of rows.docs){processed++;if(!await cleanupEntry(row.ref))failed++;}
      if(rows.size<50)break;
    }
    return {processed,failed};
  }
  async function save(uid,input,{onlyIfAbsent=false}={}) {
    await account(uid);
    if(!input || Object.keys(input).some(k=>!['image','contentType','publish'].includes(k)) || typeof input.publish!=='boolean')fail('invalid-argument','Confirme le choix de publication de ta photo.');
    let bytes=null;
    if(input.image!=null) {
      if(typeof input.image!=='string'||input.image.length>7*1024*1024||!['image/jpeg','image/png','image/webp'].includes(input.contentType))fail('invalid-argument','Choisis une photo JPEG, PNG ou WebP de 5 Mio maximum.');
      bytes=Buffer.from(input.image,'base64');
      if(!bytes.length||bytes.length>5*1024*1024)fail('invalid-argument','Photo trop volumineuse.');

    }
    const revision=randomBytes(16).toString('hex'), objectPath=`personalAvatars/${uid}/${revision}.webp`;
    // Reserve budget and a durable orphan record before expensive processing or upload.
    await db.runTransaction(async tx=>{
      await assertActive(reader(tx),uid);
      const ref=db.doc(`personalAvatarLimits/${uid}`),saved=(await tx.get(ref)).data(),day=Math.floor(clock()/86400000);
      const count=saved?.day===day?saved.count:0;if(count>=20)fail('resource-exhausted','Trop de changements de photo aujourd’hui. Réessaie demain.');
      tx.set(ref,{day,count:count+1});if(bytes)queueGarbage(tx,uid,objectPath,clock()+900000);
    });
    if(bytes){
      checkMagic(bytes,input.contentType);
      bytes=await sharp(await normalize(bytes,input.contentType)).resize(256,256,{fit:'cover'}).webp({quality:78}).toBuffer();
      await bucket.file(objectPath).save(bytes,{resumable:false,metadata:{contentType:'image/webp',cacheControl:'private, no-store',metadata:{owneruid:uid}}});
    }
    let prior,skipped=false;
    try {
      await db.runTransaction(async tx=>{
        await assertActive(reader(tx),uid);
        const ref=db.doc(`personalAvatars/${uid}`), old=(await tx.get(ref)).data();
        if(onlyIfAbsent&&old){skipped=true;return;}
        if(input.publish&&!bytes&&!old?.objectPath)fail('failed-precondition','Choisis d’abord une photo personnelle.');
        prior=old;
        const publicId=old?.publicId||randomBytes(16).toString('hex');
        const value={publicId,revision:bytes?revision:old?.revision||revision,objectPath:bytes?objectPath:old?.objectPath||null,published:input.publish,updatedAt:clock()};
        tx.set(ref,value);
        if(bytes){tx.delete(garbageRef(objectPath));if(old?.objectPath&&old.objectPath!==objectPath)queueGarbage(tx,uid,old.objectPath);}
        tx.set(db.doc(`personalAvatarLookup/${publicId}`),{uid});
        if(value.published)tx.set(db.doc(`publicPersonalAvatars/${publicId}`),{version:value.revision});
        else tx.delete(db.doc(`publicPersonalAvatars/${publicId}`));
      });
    }catch(e){if(bytes)await cleanupEntry(garbageRef(objectPath));throw e;}
    if(skipped&&bytes)await cleanupEntry(garbageRef(objectPath));
    if(bytes&&prior?.objectPath&&prior.objectPath!==objectPath)await cleanupEntry(garbageRef(prior.objectPath));
    await syncProfessional(uid);
    return state(uid,{ensure:false});
  }
  const importing=new Map();
  async function ensureIdentity(uid) {
    requireUid(uid);
    if((await db.doc(`personalAvatars/${uid}`).get()).exists)return;
    if(importing.has(uid))return importing.get(uid);
    const operation=(async()=>{
      await account(uid);await assertActive(reader(),uid);
      const profile=(await db.doc(`professionalProfiles/${uid}/showcase/profile`).get()).data();
      const portrait=profile?.portrait;
      if(!portrait?.base64||portrait.base64.length>110000)return;
      const bytes=Buffer.from(portrait.base64,'base64');
      if(createHash('sha256').update(bytes).digest('hex')!==portrait.id)return;
      let format;try{format=(await sharp(bytes).metadata()).format;}catch{return;}
      const type={jpeg:'image/jpeg',png:'image/png',webp:'image/webp'}[format];
      if(type)await save(uid,{image:portrait.base64,contentType:type,publish:true},{onlyIfAbsent:true});
    })();
    importing.set(uid,operation);try{await operation;}finally{importing.delete(uid);}
  }
  async function syncProfessional(uid) {
    requireUid(uid);
    const avatar=(await db.doc(`personalAvatars/${uid}`).get()).data();
    if(!avatar?.objectPath)return;
    const professional=(await db.doc(`professionalProfiles/${uid}`).get()).data();if(!professional)return;
    const [bytes]=await bucket.file(avatar.objectPath).download();
    const portrait={id:createHash('sha256').update(bytes).digest('hex'),base64:bytes.toString('base64')};
    if(bytes.length>81920)fail('failed-precondition','La photo de compte est trop volumineuse pour le profil professionnel.');
    await db.runTransaction(async tx=>{
      await assertActive(reader(tx),uid);
      const [current,root,previous,catalog]=await Promise.all([tx.get(db.doc(`personalAvatars/${uid}`)),tx.get(db.doc(`professionalProfiles/${uid}`)),tx.get(db.doc(`professionalProfiles/${uid}/showcase/profile`)),tx.get(db.doc('referenceData/professionalOnboarding'))]);
      const a=current.data(),p=root.data(),old=previous.data(),reference=catalog.data();
      if(!p||a?.revision!==avatar.revision||a?.objectPath!==avatar.objectPath)return;
      const defaults={name:(p.businessName||'Mon profil professionnel').slice(0,65),trade:(reference?.categories||[]).filter(c=>p.categoryIds?.includes(c.id)).map(c=>c.label).join(' · ').slice(0,85)||'Professionnel',area:(reference?.zones||[]).filter(z=>p.zoneIds?.includes(z.id)).map(z=>z.label).join(' · ').slice(0,100),bio:''};
      const seed=!old||old.identityOnly===true;
      if(old?.portrait?.id===portrait.id&&old.accountAvatarVersion===a.revision&&(!seed||['name','trade','area'].every(k=>old[k]===defaults[k])))return;
      const next={...(!old?{cover:null,gallery:[]}:old),...(seed?defaults:{}),portrait,accountAvatarVersion:a.revision,identityOnly:seed,revision:(old?.revision||0)+1};
      delete next.mutation;tx.set(db.doc(`professionalProfiles/${uid}/showcase/profile`),next);
    });
  }
  async function state(uid,{ensure=true}={}) {
    await account(uid);await assertActive(reader(),uid);
    if(ensure)await ensureIdentity(uid);
    await syncProfessional(uid);
    const value=(await db.doc(`personalAvatars/${uid}`).get()).data();
    let preview=null;
    if(value?.objectPath){try{preview=(await bucket.file(value.objectPath).download())[0].toString('base64');}catch(e){if(Number(e.code)!==404)throw e;}}
    return {hasPhoto:!!value?.objectPath,published:value?.published===true,publicId:value?.publicId||null,version:value?.revision||null,preview};
  }
  async function remove(uid) {
    await account(uid);let old;
    await db.runTransaction(async tx=>{
      await assertActive(reader(tx),uid);const ref=db.doc(`personalAvatars/${uid}`);old=(await tx.get(ref)).data();
      const showcaseRef=db.doc(`professionalProfiles/${uid}/showcase/profile`),showcase=(await tx.get(showcaseRef)).data();
      if(old){tx.delete(db.doc(`publicPersonalAvatars/${old.publicId}`));tx.delete(db.doc(`personalAvatarLookup/${old.publicId}`));queueGarbage(tx,uid,old.objectPath);}
      tx.set(ref,{publicId:old?.publicId||randomBytes(16).toString('hex'),revision:randomBytes(16).toString('hex'),published:false,objectPath:null,removed:true,updatedAt:clock()});
      if(showcase?.portrait){const next={...showcase,portrait:null,revision:(showcase.revision||0)+1};delete next.mutation;delete next.accountAvatarVersion;tx.set(showcaseRef,next);}
    });
    const cleaned=!old?.objectPath||await cleanupEntry(garbageRef(old.objectPath));
    return {hasPhoto:false,published:false,cleanupPending:!cleaned};
  }
  async function resolve(uid,ids) {
    if(!Array.isArray(ids)||ids.length>50||ids.some(id=>typeof id!=='string'||!/^[a-zA-Z0-9_-]{20,80}$/.test(id)))fail('invalid-argument','Demandes invalides.');
    const avatars={}, legacyPages=new Map(), cache=new Map();
    const cached={get:p=>{if(!cache.has(p))cache.set(p,db.doc(p).get().then(d=>d.data()));return cache.get(p);}};
    const unique=[...new Set(ids)];
    if(!unique.length)return {avatars};
    const requests=await db.getAll(...unique.map(id=>db.doc(`requests/${id}`)));
    const owners=await db.getAll(...unique.map(id=>db.doc(`requestOwnership/${id}`)));
    const accounts=new Map();
    // Bounded server-only resolution: never exposes ownership or users documents.
    for(let i=0;i<unique.length;i++) {
      const id=unique[i], request=requests[i].data();if(request?.status!=='published')continue;
      let owner=owners[i].data()?.ownerUid;
      if(!owner && Number.isSafeInteger(request.createdAt)) {
        if(!legacyPages.has(request.createdAt))legacyPages.set(request.createdAt,db.collectionGroup('items').where('createdAt','==',request.createdAt).limit(51).get());
        const rows=await legacyPages.get(request.createdAt);
        if(rows.size<=50){const candidates=rows.docs.filter(d=>d.id===id&&/^userRequests\/[^/]+\/items\/[^/]+$/.test(d.ref.path));if(candidates.length===1)owner=candidates[0].ref.parent.parent.id;}
      }
      if(!owner)continue;
      try{await assertActive(cached,owner);if(!accounts.has(owner))accounts.set(owner,account(owner));await accounts.get(owner);}catch(e){if(['permission-denied','auth/user-not-found'].includes(e.code))continue;throw e;}
      if(uid&&!await contactAllowed(cached,uid,owner))continue;
      await ensureIdentity(owner);
      const value=await cached.get(`personalAvatars/${owner}`);
      if(value?.published)avatars[id]=value.publicId;
    }
    return {avatars};
  }
  async function read(publicId,version) {
    if(!validKey(publicId)||!validKey(version))fail('not-found','Photo indisponible.');
    const uid=(await db.doc(`personalAvatarLookup/${publicId}`).get()).data()?.uid;
    if(!uid)fail('not-found','Photo indisponible.');
    await assertActive(reader(),uid);await account(uid);
    const value=(await db.doc(`personalAvatars/${uid}`).get()).data();
    if(!value?.published||value.publicId!==publicId||value.revision!==version)fail('not-found','Photo indisponible.');
    const [bytes]=await bucket.file(value.objectPath).download();
    // Recheck after download so a concurrent revocation cannot be served as current.
    const current=(await db.doc(`personalAvatars/${uid}`).get()).data();
    if(!current?.published||current.revision!==version)fail('not-found','Photo indisponible.');
    await assertActive(reader(),uid);return bytes;
  }
  return {save,state,remove,resolve,read,cleanup,ensureIdentity,syncProfessional};
}
module.exports={createPersonalAvatarService};
