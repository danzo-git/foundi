const {AsyncLocalStorage}=require('node:async_hooks');
const {OtpError}=require('./auth-validation');
const context=new AsyncLocalStorage();
async function assertOpen(tx,uid){
  if(uid && await tx.get(`accountLifecycle/${uid}`))throw new OtpError('permission-denied','La suppression de ce compte est en cours ou terminée.');
}
function guardedTransaction(db,operation){
  return db.runTransaction(async t=>{
    const adapter={get:async path=>(await t.get(db.doc(path))).data(),set:(path,value)=>t.set(db.doc(path),value),delete:path=>t.delete(db.doc(path)),conversationsForRequest:async id=>(await t.get(db.collection('conversations').where('requestId','==',id))).docs.map(d=>({id:d.id,...d.data()}))};
    await assertOpen(adapter,context.getStore()?.uid);
    return operation(adapter);
  });
}
module.exports={context,assertOpen,guardedTransaction};
