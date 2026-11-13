const {OtpError}=require('./auth-validation');
async function indexed(query) {
  try { return await query.get(); }
  catch(error) {
    if([9,'failed-precondition','FAILED_PRECONDITION'].includes(error.code) && /index/i.test(error.message || '')) {
      throw new OtpError('failed-precondition','La modération n’est pas prête : les index nécessaires doivent être activés sur le serveur.');
    }
    throw error;
  }
}
function createSafetyStore(db) {
  return {
    async notices(uid){return (await db.collection(`users/${uid}/safetyNotices`).orderBy('createdAt','desc').limit(10).get()).docs.map(d=>{
      const n=d.data();return {id:d.id,text:n.text,createdAt:n.createdAt,acknowledgedAt:n.acknowledgedAt??null};
    });},
    async expiredEvidence(now){return (await db.collection('safetyReports').where('evidenceExpiresAt','<=',now).orderBy('evidenceExpiresAt').limit(100).get()).docs.map(d=>d.id);},
    async heldAudits(){return (await db.collection('safetyAudit').where('deleteAt','==',null).limit(100).get()).docs.map(d=>({id:d.id,...d.data()}));},
    transaction:operation=>db.runTransaction(t=>operation({get:async path=>(await t.get(db.doc(path))).data(),set:(path,value)=>t.set(db.doc(path),value),delete:path=>t.delete(db.doc(path))})),
    async listBlocks(uid,cursor){
      let q=db.collection(`userBlocks/${uid}/items`).orderBy('__name__');
      if(cursor)q=q.startAfter(cursor);
      const rows=await q.limit(31).get(),page=rows.docs.slice(0,30);
      return {items:page.map(d=>({uid:d.id,...d.data()})),cursor:rows.size>30?page.at(-1).id:null};
    },
    async listReports(input){
      let q=db.collection('safetyReports').where('status','==',input.status);
      if(input.reason)q=q.where('reason','==',input.reason);
      if(input.targetType)q=q.where('targetType','==',input.targetType);
      q=q.orderBy('createdAt').orderBy('__name__');
      if(input.cursor)q=q.startAfter(input.cursor.createdAt,input.cursor.id);
      const rows=await indexed(q.limit(26)),page=rows.docs.slice(0,25);
      // Evidence and reporter identity are fetched only for the authorized detail.
      return {items:page.map(d=>{const r=d.data();return {id:d.id,targetType:r.targetType,reason:r.reason,status:r.status,label:r.label,createdAt:r.createdAt,priority:r.priority,revision:r.revision};}),cursor:rows.size>25?{id:page.at(-1).id,createdAt:page.at(-1).data().createdAt}:null};
    },
    async audit(id){return (await indexed(db.collection('safetyAudit').where('reportId','==',id).orderBy('createdAt').limit(100))).docs.map(d=>({id:d.id,...d.data()}));},
  };
}
module.exports={createSafetyStore};
