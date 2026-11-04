const fs=require('node:fs');
const {FieldPath}=require('firebase-admin/firestore');
const {isPrivateMessage,key}=require('../src/notification-policy');

async function* pages(query){
  let cursor;
  while(true){
    const page=await (cursor?query.startAfter(cursor):query).limit(200).get();
    for(const row of page.docs)yield row;
    if(page.size<200)return;
    cursor=page.docs.at(-1);
  }
}

async function migrate({db,service,apply=false,cutoff=Date.now()}){
  const report={schemaVersion:91,apply,cutoff,notifications:0,privateNotifications:0,generalNotifications:0,messages:0,missingParents:0,upgradedOutboxes:0,metadataBefore:[],countersBefore:{}};
  const legacy=new Map();
  for await(const row of pages(db.collectionGroup('notifications').orderBy(FieldPath.documentId()))){
    if(!/^users\/[^/]+\/notifications\/[^/]+$/.test(row.ref.path))continue;
    const n=row.data(),uid=row.ref.parent.parent.id;
    report.notifications++;
    if(!Object.hasOwn(report.countersBefore,uid))report.countersBefore[uid]=(await db.doc(`users/${uid}/notificationState/inbox`).get()).data()?.unreadCount ?? 0;
    report.metadataBefore.push({path:row.ref.path,isGeneral:n.isGeneral ?? null});
    if(isPrivateMessage(n)){
      report.privateNotifications++;
      const match=/^messages\/([^/]+)\/([^/]+)$/.exec(n.eventId || '');
      const conversationId=match?.[1] || n.conversationId || n.resourceId,messageId=match?.[2] || n.messageId;
      if(conversationId&&messageId)legacy.set(key(`messages/${conversationId}/${messageId}`,uid),n.readAt!=null);
      if(apply)await service.excludeLegacyMessage(uid,row.id);
      const outbox=db.doc(`notificationOutbox/${row.id}`),queued=await outbox.get();
      if(queued.exists && queued.data().state==='pending'){
        report.upgradedOutboxes++;
        if(apply)await db.runTransaction(async tx=>{
          const current=(await tx.get(outbox)).data();
          if(current?.state!=='pending')return;
          tx.update(outbox,conversationId&&messageId
            ?{kind:'chat_message',conversationId,messageId}
            :{state:'skipped',reason:'legacy-message-without-target'});
        });
      }
    }else if(n.schemaVersion===9){
      report.generalNotifications++;
      if(apply && n.isGeneral!==true)await row.ref.update({isGeneral:true});
    }
  }
  for await(const row of pages(db.collectionGroup('messages').orderBy(FieldPath.documentId()))){
    const path=/^conversations\/([^/]+)\/messages\/([^/]+)$/.exec(row.ref.path),m=row.data();
    if(!path||!Number.isSafeInteger(m.createdAt)||m.createdAt>cutoff)continue;
    const chat=(await db.doc(`conversations/${path[1]}`).get()).data();
    if(!chat || ![chat.clientUid,chat.professionalUid].includes(m.senderUid)){report.missingParents++;continue;}
    const uid=m.senderUid===chat.clientUid?chat.professionalUid:chat.clientUid;
    report.messages++;
    if(apply)await service.message(path[1],path[2],m,{push:false,legacyRead:legacy.get(key(`messages/${path[1]}/${path[2]}`,uid))===true});
  }
  return report;
}

async function main(){
  const args=process.argv.slice(2),value=name=>args[args.indexOf(name)+1];
  const projectId=args.includes('--project')?value('--project'):null;
  if(!projectId || (!projectId.startsWith('demo-')&&projectId!=='foundi-7c837'))throw Error('Explicit supported --project required.');
  const apply=args.includes('--apply');
  const {initializeApp,deleteApp}=require('firebase-admin/app'),{getFirestore}=require('firebase-admin/firestore'),{getAuth}=require('firebase-admin/auth');
  const {createNotificationService}=require('../src/notification-service');
  const app=initializeApp({projectId}),db=getFirestore(app);
  try{
    const service=createNotificationService({db,auth:getAuth(app),messaging:{send:()=>{throw Error('Migration never sends push.');}}});
    const report=await migrate({db,service,apply});
    if(args.includes('--output'))fs.writeFileSync(value('--output'),JSON.stringify(report,null,2));
    const {metadataBefore,countersBefore,...summary}=report;
    console.log(JSON.stringify({projectId,...summary,accounts:Object.keys(countersBefore).length}));
  }finally{await deleteApp(app);}
}
if(require.main===module)main().catch(e=>{console.error(e.message);process.exitCode=1;});
module.exports={migrate};
