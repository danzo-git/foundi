const fs=require('node:fs');
const {initializeApp,deleteApp}=require('firebase-admin/app'),{getFirestore}=require('firebase-admin/firestore');
async function main(){
 const app=initializeApp({projectId:'foundi-7c837'}),db=getFirestore(app);
 try{
  const [general,messages]=await Promise.all([db.collectionGroup('notificationState').get(),db.collectionGroup('messageState').get()]);
  const uids=new Set([...general.docs,...messages.docs].filter(d=>d.id==='inbox').map(d=>d.ref.parent.parent.id));
  const accounts=[];
  for(const uid of uids)accounts.push(await db.runTransaction(async tx=>{
   const [gc,mc,gr,mr]=await Promise.all([
    tx.get(db.doc(`users/${uid}/notificationState/inbox`)),tx.get(db.doc(`users/${uid}/messageState/inbox`)),
    tx.get(db.collection(`users/${uid}/notifications`).where('schemaVersion','==',9).where('isGeneral','==',true).where('readAt','==',null)),
    tx.get(db.collection(`users/${uid}/messageInbox`).where('unread','==',true))]);
   return {uid,generalStored:gc.data()?.unreadCount || 0,generalExpected:gr.size,messagesStored:mc.data()?.unreadCount || 0,messagesExpected:mr.size};
  }));
  const mismatches=accounts.filter(a=>a.generalStored!==a.generalExpected||a.messagesStored!==a.messagesExpected);
  const report={project:'foundi-7c837',at:new Date().toISOString(),accounts,mismatches:mismatches.length};
  const args=process.argv.slice(2);if(args.includes('--output'))fs.writeFileSync(args[args.indexOf('--output')+1],JSON.stringify(report,null,2));
  console.log(JSON.stringify({project:report.project,accounts:accounts.length,mismatches:mismatches.length,generalUnread:accounts.reduce((s,a)=>s+a.generalStored,0),privateUnread:accounts.reduce((s,a)=>s+a.messagesStored,0)}));
  if(mismatches.length)process.exitCode=1;
 }finally{await deleteApp(app);}
}
main().catch(e=>{console.error(e.message);process.exitCode=1;});
