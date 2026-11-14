const {FieldPath}=require('firebase-admin/firestore');
const {publicStatus}=require('./privacy-service');
function createPrivacyStore(db){return {
  transaction:operation=>db.runTransaction(t=>operation({get:async path=>(await t.get(db.doc(path))).data(),set:(path,v)=>t.set(db.doc(path),v),delete:path=>t.delete(db.doc(path))})),
  pending:async now=>(await db.collection('accountDeletionJobs').where('runnable','==',true).where('dueAt','<=',now).orderBy('dueAt').limit(2).get()).docs.map(d=>d.id),
  list:async cursor=>{let q=db.collection('accountDeletionJobs').orderBy(FieldPath.documentId());if(cursor)q=q.startAfter(cursor);const rows=await q.limit(26).get();return {items:rows.docs.slice(0,25).map(d=>({...publicStatus(d.data()),lastErrorCode:d.data().lastErrorCode||null})),cursor:rows.size>25?rows.docs[24].id:null};},
  audit:async value=>{const config=(await db.doc('privacyConfiguration/current').get()).data();if(!Number.isSafeInteger(config?.auditSeconds) || config.auditSeconds<3600 || config.auditSeconds>31536000)throw new (require('./auth-validation').OtpError)('failed-precondition','Valide la durée du journal privé avant de consulter les dossiers.');await db.collection('accountDeletionAudit').add({...value,deleteAt:new Date(value.createdAt+config.auditSeconds*1000)});},
};}
module.exports={createPrivacyStore};
