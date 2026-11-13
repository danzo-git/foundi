const {Timestamp}=require('firebase-admin/firestore');
const {createHash}=require('node:crypto');
const {OtpError}=require('./auth-validation');
const profileFields=['status','businessName','categoryIds','specialtyIds','zoneIds'];
function createProfessionalDirectoryStore(db){
  async function profiles(ids){
    if(!ids.length)return [];
    return (await db.getAll(...ids.map(id=>db.doc(`professionalProfiles/${id}`)),{fieldMask:profileFields}))
      .filter(d=>d.exists).map(d=>({id:d.id,profile:d.data()}));
  }
  return {
    get:async path=>(await db.doc(path).get()).data(),
    profiles,
    async texts(ids){
      if(!ids.length)return new Map();
      const docs=await db.getAll(...ids.map(id=>db.doc(`professionalProfiles/${id}/showcase/profile`)),
        {fieldMask:['name','trade','portrait.id']});
      return new Map(docs.map(d=>[d.ref.parent.parent.id,d.data()||{}]));
    },
    async approvedPage(after,size){
      let query=db.collection('professionalProfiles').where('status','==','approved').orderBy('__name__').select(...profileFields);
      if(after)query=query.startAfter(db.doc(`professionalProfiles/${after}`));
      return (await query.limit(size).get()).docs.map(d=>({id:d.id,profile:d.data()}));
    },
    async charge(actor,kind,now){
      const limits={list:[30,120],profile:[30,180],media:[180,900],check:[30,240]};
      const bucket=Math.floor(now/60000),hash=value=>createHash('sha256').update(value).digest('hex');
      const refs=[db.doc(`professionalDirectoryLimits/${hash(actor+':'+kind)}`),db.doc(`professionalDirectoryLimits/${hash('global:'+kind)}`)];
      await db.runTransaction(async tx=>{
        const docs=await tx.getAll(...refs);
        const counts=docs.map(d=>d.data()?.bucket===bucket?d.data().count:0);
        if(counts.some((n,i)=>!Number.isSafeInteger(n)||n<0||n>=limits[kind][i]))throw new OtpError('resource-exhausted','La recherche est très sollicitée. Réessaie dans une minute.');
        refs.forEach((ref,i)=>tx.set(ref,{bucket,count:counts[i]+1,expiresAt:Timestamp.fromMillis(now+86400000)}));
      });
    },
    putCursor:async(token,value)=>db.doc(`professionalDirectoryCursors/${token}`).create({...value,expiresAt:Timestamp.fromMillis(value.expiresAt)}),
    async cursor(token){
      const value=(await db.doc(`professionalDirectoryCursors/${token}`).get()).data();
      return value?{...value,expiresAt:value.expiresAt.toMillis()}:null;
    },
  };
}
module.exports={createProfessionalDirectoryStore};
