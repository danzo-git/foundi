const {randomUUID,createHash}=require('node:crypto');
const {OtpError,requireUid}=require('./auth-validation');
const {readConversation,idOK}=require('./conversation-service');
const {metadata,checkMagic,canonicalize}=require('./attachment-validation');
const fail=(code,message)=>{throw new OtpError(code,message);};
const hash=b=>createHash('sha256').update(b).digest('hex');
const recordPath=(c,m)=>`conversations/${c}/attachments/${m}`;
const messagePath=(c,m)=>`conversations/${c}/messages/${m}`;
const terminal=state=>['cancelled','expired','rejected'].includes(state);
function createAttachmentService({store,auth,files,scan=async()=> 'unavailable',requireScan=true,clock=()=>Date.now()}) {
  async function account(uid){requireUid(uid);const a=await auth.getUser(uid);if(a.disabled||!a.emailVerified)fail('permission-denied','Un compte actif et vérifié est nécessaire.');}
  function ids(c,m){if(!idOK(c)||!idOK(m))fail('invalid-argument','Pièce jointe invalide.');}
  const outcome=item=>({state:item.state,attachmentId:item.attachmentId});
  async function prepare(uid,data){
    await account(uid);ids(data?.conversationId,data?.messageId);
    if(Object.keys(data).some(k=>!['conversationId','messageId','type','originalName','contentType','sizeBytes','sha256'].includes(k)))fail('invalid-argument','Champ de pièce jointe invalide.');
    const meta=metadata(data),{conversationId:c,messageId:m}=data,attachmentId=randomUUID();
    return store.transaction(async tx=>{
      const {writable}=await readConversation(tx,uid,c),existing=await tx.get(recordPath(c,m)),message=await tx.get(messagePath(c,m));
      if(existing){if(existing.senderUid!==uid||Object.entries(meta).some(([k,v])=>existing[k]!==v))fail('already-exists','Cet identifiant correspond à un autre envoi.');return outcome(existing);}
      if(!writable)fail('failed-precondition','Cette discussion est en lecture seule.');
      if(message)fail('already-exists','Cet identifiant correspond à un message existant.');
      const now=clock(),ratePath=`conversationAttachmentRates/${uid}`,rate=await tx.get(ratePath);
      const minute=Math.floor(now/60000),day=Math.floor(now/86400000),minuteCount=rate?.minute===minute?rate.minuteCount:0,dayCount=rate?.day===day?rate.dayCount:0,dayBytes=rate?.day===day?rate.dayBytes:0;
      if(minuteCount>=5||dayCount>=50||dayBytes+meta.sizeBytes>100*1048576)fail('resource-exhausted','Limite de fichiers atteinte. Réessaie plus tard.');
      const item={...meta,conversationId:c,messageId:m,attachmentId,senderUid:uid,state:'reserved',createdAt:now,expiresAt:now+86400000,
        storagePath:`conversations/${c}/attachments/${m}/${attachmentId}`,quarantinePath:`conversations/${c}/quarantine/${attachmentId}`};
      tx.set(ratePath,{minute,minuteCount:minuteCount+1,day,dayCount:dayCount+1,dayBytes:dayBytes+meta.sizeBytes});tx.set(recordPath(c,m),item);return outcome(item);
    });
  }
  async function upload(uid,c,m,bytes){
    await account(uid);ids(c,m);
    if(!Buffer.isBuffer(bytes)||!bytes.length||bytes.length>15*1048576)fail('invalid-argument','Fichier trop volumineux ou vide.');
    const lease=randomUUID(),digest=hash(bytes);
    const item=await store.transaction(async tx=>{
      const {writable}=await readConversation(tx,uid,c),saved=await tx.get(recordPath(c,m));
      if(!saved||saved.senderUid!==uid)fail('permission-denied','Envoi non autorisé.');
      if(saved.sha256!==digest||saved.sizeBytes!==bytes.length)fail('invalid-argument','Le contenu ne correspond pas au fichier confirmé.');
      if(saved.state==='ready')return saved;
      if(!writable||terminal(saved.state)||saved.expiresAt<=clock())fail('failed-precondition','Cet envoi est annulé, expiré ou la discussion est en lecture seule.');
      if(saved.state==='processing'&&saved.leaseUntil>clock())return saved;
      const attemptMinute=Math.floor(clock()/60000),attemptCount=saved.attemptMinute===attemptMinute?(saved.attemptCount||0):0;
      if((saved.attempts||0)>=20||attemptCount>=5)fail('resource-exhausted','Trop de tentatives. Réessaie plus tard ou choisis à nouveau le fichier.');
      const next={...saved,state:'processing',lease,leaseUntil:clock()+120000,attempts:(saved.attempts||0)+1,attemptMinute,attemptCount:attemptCount+1};tx.set(recordPath(c,m),next);return next;
    });
    if(item.state==='ready'||item.lease!==lease)return outcome(item);
    try{
      checkMagic(bytes,item.contentType);
      await files.save(item.quarantinePath,bytes,'application/octet-stream',{messageid:m,sha256:digest});
      // Only server configuration can skip antivirus. Never label that path as scanned/clean.
      const mandatory=typeof requireScan==='function'?requireScan():requireScan;
      const verdict=mandatory===false?'skipped':await scan(bytes);
      if(verdict==='infected')fail('invalid-argument','Fichier refusé par la vérification de sécurité.');
      if(verdict!=='clean'&&mandatory!==false){
        return store.transaction(async tx=>{
          const current=await tx.get(recordPath(c,m));
          if(current.state==='ready'||current.lease!==lease||terminal(current.state))return outcome(current);
          const next={...current,state:'awaiting_scan',leaseUntil:0};tx.set(recordPath(c,m),next);return outcome(next);
        });
      }
      const validationMode=verdict==='skipped'?'structural-v1':'clean-v1';
      const validated=await canonicalize(bytes,item),generation=await files.save(item.storagePath,validated,item.contentType,{messageid:m,sha256:hash(validated),validation:validationMode});
      const result=await store.transaction(async tx=>{
        const {chat,writable}=await readConversation(tx,uid,c),current=await tx.get(recordPath(c,m)),existing=await tx.get(messagePath(c,m));
        if(current.state==='ready')return outcome(current);
        if(!writable||current.lease!==lease||current.state!=='processing'||current.expiresAt<=clock())fail('failed-precondition','Envoi non confirmé : annulation, expiration ou discussion en lecture seule.');
        if(existing)fail('already-exists','Cet identifiant correspond à un autre message.');
        const now=Math.max(clock(),(chat.lastMessageAt||chat.createdAt)+1);
        // Reservation size/hash stay immutable when image recompression changes the delivered bytes.
        const ready={...current,state:'ready',generation:String(generation),validatedAt:now,validatedSizeBytes:validated.length,validationMode,antivirusStatus:verdict};delete ready.expiresAt;
        tx.set(recordPath(c,m),ready);
        tx.set(messagePath(c,m),{type:item.type,senderUid:uid,createdAt:now,storagePath:item.storagePath,attachmentId:item.attachmentId,
          originalName:item.originalName,sizeBytes:validated.length,contentType:item.contentType,generation:String(generation),antivirusStatus:verdict});
        tx.set(`conversations/${c}`,{...chat,updatedAt:now,lastMessageAt:now,lastMessagePreview:item.type==='image'?'Photo partagée':'Document PDF partagé'});
        return outcome(ready);
      });
      await files.remove(item.quarantinePath).catch(()=>{});return result;
    }catch(error){
      await store.transaction(async tx=>{
        const current=await tx.get(recordPath(c,m));
        if(current?.lease===lease&&current.state==='processing')tx.set(recordPath(c,m),{...current,state:error.code==='invalid-argument'?'rejected':'awaiting_scan',leaseUntil:0});
      });
      const current=await store.get(recordPath(c,m));
      if(terminal(current?.state))await removeFiles(item);
      if(current?.state==='ready')return outcome(current);
      throw error;
    }
  }
  async function removeFiles(item){await Promise.all([files.remove(item.quarantinePath),files.remove(item.storagePath)]);}
  async function cancel(uid,c,m){
    await account(uid);ids(c,m);
    const item=await store.transaction(async tx=>{
      await readConversation(tx,uid,c);const saved=await tx.get(recordPath(c,m));
      if(!saved||saved.senderUid!==uid)fail('permission-denied','Envoi non autorisé.');
      if(saved.state==='ready')return saved;
      const next={...saved,state:'cancelled',leaseUntil:0};tx.set(recordPath(c,m),next);return next;
    });
    if(item.state!=='ready')await removeFiles(item);return outcome(item);
  }
  async function read(uid,c,m){
    await account(uid);ids(c,m);
    const item=await store.transaction(async tx=>{
      await readConversation(tx,uid,c);const saved=await tx.get(recordPath(c,m)),message=await tx.get(messagePath(c,m));
      if(saved?.state!=='ready'||!message||message.storagePath!==saved.storagePath||message.senderUid!==saved.senderUid||!['image','pdf'].includes(message.type))fail('not-found','Fichier indisponible ou non vérifié.');
      return saved;
    });
    const bytes=await files.read(item.storagePath,item.generation);
    if(bytes.length!==item.validatedSizeBytes)fail('failed-precondition','Fichier indisponible.');
    return {bytes,contentType:item.contentType,originalName:item.originalName};
  }
  async function cleanup(){
    let count=0;
    for(let page=0;page<10;page++){
      const rows=await store.expiredAttachments(clock(),100);if(!rows.length)break;
      for(const {path} of rows){
        if(!/^conversations\/[a-zA-Z0-9_-]{20,80}\/attachments\/[a-zA-Z0-9_-]{20,80}$/.test(path))continue;
        const item=await store.transaction(async tx=>{const current=await tx.get(path);if(!current||current.state==='ready'||!current.expiresAt||current.expiresAt>clock())return null;
          const next={...current,state:'expired',leaseUntil:0};delete next.expiresAt;tx.set(path,next);return next;});
        if(item){try{await removeFiles(item);count++;}catch(e){
          await store.transaction(async tx=>{const current=await tx.get(path);if(current?.state==='expired')tx.set(path,{...current,expiresAt:clock()+3600000});});
          throw e;
        }}
      }
      if(rows.length<100)break;
    }
    return {expired:count};
  }
  return {prepare,upload,cancel,read,cleanup};
}
module.exports={createAttachmentService};
