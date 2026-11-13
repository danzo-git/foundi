const sharp = require('sharp');
const {createHash}=require('node:crypto');
const {OtpError}=require('./auth-validation');
const safeId=value=>typeof value==='string' && /^[a-zA-Z0-9_-]{1,128}$/.test(value);
async function thumbnail(bytes) {
  if(!Buffer.isBuffer(bytes) || bytes.length>15*1048576)throw Error('invalid image');
  for(const size of [384,256,160]){
    const value=await sharp(bytes,{limitInputPixels:20000000}).rotate().resize({width:size,height:size,fit:'inside',withoutEnlargement:true}).flatten({background:'#ffffff'}).jpeg({quality:65}).toBuffer();
    if(value.length<=32768)return value.toString('base64');
  }
  throw Error('image too complex');
}
function createSafetyEvidence({files}) {
  async function capture(tx, target, resolved) {
    const images=[];let unavailable=0;
    const add=async(id,read)=>{try{images.push({id,base64:await thumbnail(await read())});}catch(_){unavailable++;}};
    if(target.targetType==='professional'){
      const profile=await tx.get(`professionalProfiles/${target.targetId}/showcase/profile`);
      for(const p of [profile?.portrait,profile?.cover,...(profile?.gallery || []).slice(0,6)].filter(Boolean))await add(p.id,async()=>{
        if(typeof p.base64!=='string' || p.base64.length>110000)throw Error('invalid photo');const bytes=Buffer.from(p.base64,'base64');
        if(createHash('sha256').update(bytes).digest('hex')!==p.id)throw Error('invalid hash');return bytes;
      });
    }else if(target.targetType==='request'){
      for(const id of resolved.evidence.photoIds.slice(0,3)){
        const p=await tx.get(`requestPhotoFiles/${target.targetId}_${id}`);
        await add(id,async()=>{
          if(p?.state!=='linked' || p.uid!==resolved.reportedUid || p.requestId!==target.targetId || p.photoId!==id || !safeId(p.objectId) || !p.generation)throw Error('invalid link');
          return files.read(`requestPhotos/${p.uid}/${p.requestId}/${id}/${p.objectId}.webp`,p.generation);
        });
      }
    }else if(target.targetType==='message' && resolved.evidence.message?.type==='image'){
      const m=resolved.evidence.message;
      await add(target.targetId,async()=>{
        const saved=await tx.get(`conversations/${target.conversationId}/attachments/${target.targetId}`);
        if(saved?.state!=='ready' || saved.senderUid!==resolved.reportedUid || saved.storagePath!==m.storagePath || !safeId(m.attachmentId) || m.storagePath!==`conversations/${target.conversationId}/attachments/${target.targetId}/${m.attachmentId}`)throw Error('invalid link');
        return files.read(m.storagePath,m.generation);
      });
    }
    return {...resolved.evidence,images,...(unavailable?{mediaUnavailable:unavailable}:{})};
  }
  async function attachment(report){
    const m=report.evidence?.message,c=report.evidence?.conversationId;
    if(report.targetType!=='message' || !safeId(c) || !safeId(report.targetId) || !m || !['image','pdf'].includes(m.type) || !safeId(m.attachmentId) || !m.generation || m.senderUid!==report.reportedUid || m.storagePath!==`conversations/${c}/attachments/${report.targetId}/${m.attachmentId}`)throw new OtpError('not-found','Pièce jointe de preuve indisponible.');
    const bytes=await files.read(m.storagePath,m.generation);
    return {bytes,contentType:m.contentType,originalName:m.originalName || 'piece-jointe'};
  }
  return {capture,attachment};
}
module.exports={createSafetyEvidence};
