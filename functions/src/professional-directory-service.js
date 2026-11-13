const {createHash,randomBytes}=require('node:crypto');
const sharp=require('sharp');
const {OtpError}=require('./auth-validation');
const {internalId}=require('./notification-policy');
const {activeZones}=require('./catalog-service');
const {directoryEntry}=require('./request-interaction-service');
const {showcaseProjection}=require('./professional-showcase-service');
const {directRequestActivity}=require('./direct-request-context');
const {publicProfileAllowed}=require('./safety-guard');
const pageSize=12,chunkSize=40,scanLimit=120,leaseMs=30000;
const fail=(code,message)=>{throw new OtpError(code,message);};
const unavailable=()=>fail('not-found','Ce professionnel n’est plus disponible.');
const normalize=value=>value.normalize('NFD').replace(/\p{M}/gu,'').toLowerCase().replace(/\s+/gu,' ').trim();
const hash=value=>createHash('sha256').update(JSON.stringify(value)).digest('hex');
const safeText=(value,max,fallback='')=>typeof value==='string'&&value.trim().length<=max&&!/[@\p{C}]|(?<!\p{Nd})(?:\p{Nd}[\s().+-]*){7}\p{Nd}/u.test(value)?value.trim():fallback;
const photoId=value=>typeof value==='string'&&/^[a-f0-9]{64}$/.test(value);
function object(input,keys){
  if(!input||typeof input!=='object'||Array.isArray(input)||Object.keys(input).some(k=>!keys.includes(k)))fail('invalid-argument','Paramètres de recherche invalides.');
}
function filters(input,catalog){
  object(input,['query','categoryId','specialtyId','zoneId','cursor']);
  if(input.query!==undefined&&(typeof input.query!=='string'||input.query.length>80))fail('invalid-argument','Recherche trop longue.');
  const result={query:normalize(input.query||''),categoryId:input.categoryId??null,specialtyId:input.specialtyId??null,zoneId:input.zoneId??null};
  for(const key of ['categoryId','specialtyId','zoneId'])if(result[key]!==null&&(typeof result[key]!=='string'||!/^[a-zA-Z0-9_-]{1,80}$/.test(result[key])))fail('invalid-argument','Choisis des références actives.');
  const category=catalog.categories?.find(c=>c.id===result.categoryId&&c.active!==false);
  if((result.categoryId&&!category)||(result.specialtyId&&(!category||!category.specialties?.some(s=>s.id===result.specialtyId&&s.active!==false)))||
    (result.zoneId&&!activeZones(catalog.zones).some(z=>z.id===result.zoneId)))fail('invalid-argument','Choisis des références actives.');
  if(input.cursor!=null&&(typeof input.cursor!=='string'||!/^[a-f0-9]{64}$/.test(input.cursor)))fail('invalid-argument','Pagination invalide.');
  return result;
}
function publicPhoto(value){
  if(!value||!photoId(value.id)||typeof value.base64!=='string'||value.base64.length>110000)return null;
  const bytes=Buffer.from(value.base64,'base64');
  if(!bytes.length||bytes.length>81920||bytes.toString('base64')!==value.base64||createHash('sha256').update(bytes).digest('hex')!==value.id)return null;
  return {id:value.id,base64:value.base64};
}
function publicProfile(id,profile,catalog,showcase){
  const entry=directoryEntry(id,profile,catalog),activity=directRequestActivity(profile,catalog);
  if(!entry||!activity||!safeText(entry.name,150))unavailable();
  const raw=showcase||{},projection=showcaseProjection({...raw,gallery:Array.isArray(raw.gallery)?raw.gallery.slice(0,6):[]});
  return {...projection,revision:Number.isSafeInteger(raw.revision)?raw.revision:0,
    name:safeText(raw.name,65,entry.name)||entry.name,
    trade:safeText(raw.trade,85,[...entry.categories,...entry.specialties].join(' · ')),
    area:safeText(raw.area,100,entry.zones.join(' · ')),bio:safeText(raw.bio,500),
    portrait:publicPhoto(raw.portrait),cover:publicPhoto(raw.cover),gallery:(Array.isArray(raw.gallery)?raw.gallery:[]).slice(0,6).map(publicPhoto).filter(Boolean),
    professionalId:id,requestActivity:activity};
}
function createProfessionalDirectoryService({store,auth,clock=Date.now,newCursor=()=>randomBytes(32).toString('hex')}){
  async function catalog(){const value=await store.get('referenceData/professionalOnboarding');if(value?.enabled!==true)fail('failed-precondition','L’annuaire est temporairement indisponible.');return value;}
  async function accounts(ids){
    if(!ids.length)return new Set();
    const result=await auth.getUsers(ids.map(uid=>({uid})));
    const enabled=await Promise.all(result.users.filter(u=>u.emailVerified&&!u.disabled).map(async u=>await publicProfileAllowed(store,u.uid)?u.uid:null));
    return new Set(enabled.filter(Boolean));
  }
  function summary(id,profile,texts,c){
    const entry=directoryEntry(id,profile,c),activity=directRequestActivity(profile,c);
    if(!entry||!activity||!safeText(entry.name,150))return null;
    return {professionalId:id,name:safeText(texts?.name,65,entry.name)||entry.name,
      trade:safeText(texts?.trade,85,entry.specialties.join(' · ')||entry.categories.join(' · ')),
      categories:entry.categories,specialties:entry.specialties,zones:entry.zones,
      portraitId:photoId(texts?.portrait?.id)?texts.portrait.id:null};
  }
  function matches(item,profile,f,c){
    if(!item)return false;
    if(f.categoryId&&!profile.categoryIds?.includes(f.categoryId))return false;
    if(f.specialtyId&&!profile.specialtyIds?.includes(f.specialtyId))return false;
    if(f.zoneId&&!profile.zoneIds?.includes(f.zoneId))return false;
    const text=normalize([safeText(profile.businessName,150),item.name,item.trade,...item.categories,...item.specialties,...item.zones].join(' '));
    return f.query.split(' ').filter(Boolean).every(word=>text.includes(word));
  }
  async function live(ids,c){
    const [rows,texts,active]=await Promise.all([store.profiles(ids),store.texts(ids),accounts(ids)]);
    return rows.filter(r=>active.has(r.id)).map(r=>({id:r.id,profile:r.profile,item:summary(r.id,r.profile,texts.get(r.id),c)})).filter(r=>r.item);
  }
  async function context(id){
    if(!internalId(id))fail('invalid-argument','Profil professionnel invalide.');
    const [c,profile]=await Promise.all([catalog(),store.get(`professionalProfiles/${id}`)]);
    if(!profile||!directoryEntry(id,profile,c)||!directRequestActivity(profile,c))unavailable();
    let user;try{user=await auth.getUser(id);}catch(error){if(error.code==='auth/user-not-found')unavailable();throw error;}
    if(!user.emailVerified||user.disabled)unavailable();
    if(!await publicProfileAllowed(store,id))unavailable();
    return {c,profile};
  }
  async function search(actor,input={}){
    await store.charge(actor,'list',clock());
    const c=await catalog(),f=filters(input,c),criteria=hash([f,c.version??null,c.updatedAt?.toMillis?.()??c.updatedAt??null]);
    let after=null;
    if(input.cursor){
      const saved=await store.cursor(input.cursor);
      if(!saved||saved.actor!==actor||saved.criteria!==criteria||saved.expiresAt<=clock()||!internalId(saved.after))fail('invalid-argument','La recherche a changé ou a expiré. Relance-la.');
      after=saved.after;
    }
    const candidates=[];let scanned=0,more=false;
    while(scanned<scanLimit&&candidates.length<pageSize){
      const rows=await store.approvedPage(after,Math.min(chunkSize,scanLimit-scanned));
      if(!rows.length){more=false;break;}
      const ids=rows.map(r=>r.id).filter(internalId);
      const [texts,active]=await Promise.all([store.texts(ids),accounts(ids)]);
      let consumed=0;
      for(const row of rows){
        consumed++;scanned++;after=row.id;
        if(active.has(row.id)){
          const item=summary(row.id,row.profile,texts.get(row.id),c);
          if(matches(item,row.profile,f,c))candidates.push(row.id);
        }
        if(candidates.length===pageSize)break;
      }
      more=consumed<rows.length||rows.length===chunkSize;
      if(!more)break;
    }
    // Approval, account state and matching criteria are checked again before disclosure.
    const currentCatalog=await catalog();
    const fresh=await live(candidates,currentCatalog),byId=new Map(fresh.filter(r=>matches(r.item,r.profile,f,currentCatalog)).map(r=>[r.id,r.item]));
    const items=candidates.filter(id=>byId.has(id)).map(id=>byId.get(id));
    let cursor=null;
    if(more&&after){cursor=newCursor();await store.putCursor(cursor,{actor,criteria,after,expiresAt:clock()+600000});}
    return {items,cursor,validForSeconds:leaseMs/1000};
  }
  async function readProfile(actor,input){
    object(input,['professionalId']);await store.charge(actor,'profile',clock());
    await context(input.professionalId);
    const raw=await store.get(`professionalProfiles/${input.professionalId}/showcase/profile`);
    const latest=await context(input.professionalId);
    return publicProfile(input.professionalId,latest.profile,latest.c,raw);
  }
  async function check(actor,input){
    object(input,['professionalIds']);
    const ids=input.professionalIds;
    if(!Array.isArray(ids)||ids.length>24||ids.some(id=>!internalId(id))||new Set(ids).size!==ids.length)fail('invalid-argument','Profils invalides.');
    await store.charge(actor,'check',clock());
    const c=await catalog(),current=await live(ids,c);
    return {professionalIds:current.map(r=>r.id),validForSeconds:leaseMs/1000};
  }
  async function readMedia(actor,input){
    object(input,['professionalId','photoId']);
    if(input.photoId!=null&&!photoId(input.photoId))fail('invalid-argument','Photo invalide.');
    await store.charge(actor,'media',clock());await context(input.professionalId);
    const raw=await store.get(`professionalProfiles/${input.professionalId}/showcase/profile`);
    const portrait=publicPhoto(raw?.portrait),gallery=(Array.isArray(raw?.gallery)?raw.gallery:[]).slice(0,3).map(publicPhoto).filter(Boolean);
    let result;
    if(input.photoId==null)result={portraitId:portrait?.id??null,galleryIds:gallery.map(p=>p.id)};
    else {
      const photo=[portrait,...gallery].find(p=>p?.id===input.photoId);if(!photo)unavailable();
      let bytes;
      try{
        for(const quality of [72,58,44]){
          bytes=await sharp(Buffer.from(photo.base64,'base64'),{limitInputPixels:2000000}).rotate()
            .resize({width:portrait?.id===photo.id?96:224,height:portrait?.id===photo.id?96:148,fit:'cover',withoutEnlargement:true})
            .flatten({background:'#ffffff'}).jpeg({quality}).toBuffer();
          if(bytes.length<=16384)break;
        }
      }catch(_){unavailable();}
      if(bytes.length>16384)unavailable();
      result={id:photo.id,base64:bytes.toString('base64')};
    }
    await context(input.professionalId);
    return result;
  }
  return {search,readProfile,readMedia,check};
}
function directoryActor(request){
  const ip=request.rawRequest?.ip||request.rawRequest?.socket?.remoteAddress;
  if(typeof ip!=='string'||!ip||ip.length>100)fail('resource-exhausted','La recherche est temporairement indisponible.');
  return hash(['foundi-directory',ip,request.auth?.uid??null]);
}
module.exports={createProfessionalDirectoryService,directoryActor,normalize};
