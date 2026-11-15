const {OtpError, requireUid} = require('./auth-validation');
const {matchesOpportunity, requestZones, unclassified} = require('./request-matching');
const {contactAllowed, assertActive} = require('./safety-guard');
const fail = (code,message) => {throw new OtpError(code,message);};
const fields = ['title','description','categoryId','categoryLabel','specialtyId','specialtyLabel','zoneId','zoneLabel','zoneIds','zoneLabels','serviceDetail','budget','status','createdAt','interventionAddress'];
function createOpportunityService({store,auth}) {
  return {async list(uid,input={}) {
    requireUid(uid);
    const account = await auth.getUser(uid);
    if(account.disabled || !account.emailVerified) fail('permission-denied','Un compte actif avec une adresse vérifiée est nécessaire.');
    const reader = {get: p => store.get(p)};
    if(store.owners) await assertActive(reader,uid);
    const profile = await store.get(`professionalProfiles/${uid}`);
    if(profile?.status !== 'approved') fail('permission-denied','Un dossier professionnel approuvé est nécessaire.');
    const catalog = await store.get('referenceData/professionalOnboarding');
    function subset(key,allowed) {
      const selected=input[key]??allowed;
      if(!Array.isArray(selected)||selected.some(v=>typeof v!=='string'||!allowed.includes(v)))fail('invalid-argument','Filtres non autorisés.');
      return [...new Set(selected)];
    }
    const categories=subset('categoryIds',profile.categoryIds||[]), specialties=subset('specialtyIds',profile.specialtyIds||[]), zones=subset('zoneIds',profile.zoneIds||[]);
    const units=[];
    const categoryIds=[...categories,...(!input.categoryIds && categories.length ? (catalog?.categories||[]).filter(c=>unclassified(c)&&c.active!==false).map(c=>c.id):[])];
    for(const categoryId of categoryIds) {
      const category=catalog?.categories?.find(c=>c.id===categoryId&&c.active!==false);
      if(!category)continue;
      for(const zoneId of zones) for(const schema of ['legacy','multi']) units.push({categoryId,zoneId,schema});
    }
    const cursor=input.cursor??{unit:0,after:null};
    if(!Number.isInteger(cursor.unit)||cursor.unit<0||cursor.unit>units.length||(cursor.after!=null&&(!Number.isSafeInteger(cursor.after.createdAt)||typeof cursor.after.id!=='string'||!/^[a-zA-Z0-9_-]{1,80}$/.test(cursor.after.id))))fail('invalid-argument','Pagination invalide.');
    let unit=cursor.unit,after=cursor.after,queries=0,scanned=0;const items=[];
    while(unit<units.length&&queries<10&&scanned<60&&items.length<30) {
      const filters=units[unit],size=Math.min(30-items.length,60-scanned);
      const rows=await store.query(filters,after,size);queries++;scanned+=rows.length;
      const own=await store.owned(uid,rows.map(r=>r.id));
      const owners=store.owners?await store.owners(rows.map(r=>r.id)):new Map();
      for(const row of rows) {
        const multi=Array.isArray(row.zoneIds);
        if(multi!==(filters.schema==='multi') || row.status!=='published'||own.has(row.id)||!matchesOpportunity(row,{...profile,specialtyIds:specialties},catalog))continue;
        if(zones.find(z=>requestZones(row).includes(z))!==filters.zoneId)continue;
        const owner=owners.get(row.id);
        if(store.owners && (!owner || !await contactAllowed(reader,uid,owner)))continue;
        items.push({id:row.id,...Object.fromEntries(fields.filter(k=>row[k]!==undefined).map(k=>[k,row[k]])),
          ...(row.authorPublicName?{authorPublicName:row.authorPublicName}:{}),
          ...(row.photosPublic===true&&row.photoIds?.length?{photosPublic:true,photoIds:row.photoIds}:{})});
      }
      if(rows.length<size){unit++;after=null;}else {const last=rows.at(-1);after={createdAt:last.createdAt,id:last.id};}
    }
    if((await store.get(`professionalProfiles/${uid}`))?.status!=='approved')fail('permission-denied','Accès professionnel suspendu.');
    return {items,cursor:unit<units.length?{unit,after}:null};
  }};
}
module.exports={createOpportunityService};
