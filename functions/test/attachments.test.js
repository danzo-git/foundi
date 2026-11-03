const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),{createHash}=require('node:crypto');
const {setup,rid,p1}=require('./helpers/conversation-fixture');
const {createAttachmentService}=require('../src/attachment-service');
const {metadata,canonicalize}=require('../src/attachment-validation');
const {createClamScanner,privateAddress}=require('../src/attachment-scanner');
const fixture=name=>fs.readFileSync(path.join(__dirname,'fixtures',name));
const png=fixture('photo.png'),pdf=fixture('document.pdf');
const digest=b=>createHash('sha256').update(b).digest('hex');
const mid=n=>'AttachmentMessage'+String(n).padStart(6,'0');
const input=(n=1,bytes=png,type='image',originalName='photo.png',contentType='image/png')=>({conversationId:p1,messageId:mid(n),type,originalName,contentType,sizeBytes:bytes.length,sha256:digest(bytes)});
const code=c=>e=>e.code===c;
async function rich(scan,requireScan=true){
 const c=setup();await c.select('client',{requestId:rid,proposalId:p1});
 const objects=new Map();let now=100,verdict='clean',generation=0;
 const files={save:async(p,bytes,contentType,meta)=>{const old=objects.get(p);if(old){assert.equal(old.metadata.sha256,meta.sha256);return old.generation;}const object={bytes:Buffer.from(bytes),contentType,metadata:meta,generation:String(++generation)};objects.set(p,object);return object.generation;},
  remove:async p=>{objects.delete(p);},read:async(p,g)=>{const o=objects.get(p);if(!o||o.generation!==g)throw Error('Object missing');return o.bytes;}};
 const store={...c.deps.store,expiredAttachments:async(time,size)=>[...c.data].filter(([p,d])=>/^conversations\/[^/]+\/attachments\//.test(p)&&d.expiresAt<=time).slice(0,size).map(([path,data])=>({path,...data}))};
 const svc=createAttachmentService({...c.deps,store,files,clock:()=>now,requireScan,scan:scan||(async()=>verdict)});
 return {...c,...svc,objects,files,setTime:v=>now=v,setVerdict:v=>verdict=v,record:n=>c.data.get(`conversations/${p1}/attachments/${mid(n)}`),message:n=>c.data.get(`conversations/${p1}/messages/${mid(n)}`)};
}
test('contact requires explicit consent, preserves own profile and public data, retries without leaking phone into previews',async()=>{
 const c=setup();await c.select('client',{requestId:rid,proposalId:p1});c.data.get('users/client').phone='+2250100000000';
 const message={conversationId:p1,messageId:mid(1),type:'contact',phoneNumber:'+2250700000000',consent:true};
 await assert.rejects(c.send('client',{...message,consent:false}),code('invalid-argument'));
 for(const phoneNumber of ['0700000000','+0001234','tel:+2250700000000','+225 07'])await assert.rejects(c.send('client',{...message,phoneNumber}),code('invalid-argument'));
 await assert.rejects(c.send('client',{...message,senderUid:'pro'}),code('invalid-argument'));
 const a=await c.send('client',message),b=await c.send('client',message);assert.deepEqual(a,b);
 assert.equal(c.data.get('users/client').phone,'+2250100000000');assert.equal(c.data.get(`requests/${rid}`).status,'published');
 assert.equal(c.data.get(`conversations/${p1}`).lastMessagePreview,'Contact partagé');assert.equal(c.data.get(`conversations/${p1}/messages/${mid(1)}`).senderUid,'client');
 await assert.rejects(c.send('other-pro',message),code('permission-denied'));await assert.rejects(c.send('client',{...message,phoneNumber:'+2250500000000'}),code('already-exists'));
});
test('clean image creates one final message after validation, strips metadata, remains private and idempotent',async()=>{
 const c=await rich(),data=input();const first=await c.prepare('client',data),again=await c.prepare('client',data);assert.deepEqual(first,again);assert.equal(c.message(1),undefined);
 assert.equal((await c.upload('client',p1,mid(1),png)).state,'ready');assert.equal(c.message(1).type,'image');assert.equal(c.message(1).senderUid,'client');
 assert.equal(c.message(1).storagePath,c.record(1).storagePath);assert.equal('downloadURL'in c.message(1),false);assert.equal('expiresAt'in c.record(1),false);
 assert.equal(c.objects.has(c.record(1).quarantinePath),false);assert.ok((await c.read('pro',p1,mid(1))).bytes.length>0);
 const size=c.objects.size;assert.equal((await c.prepare('client',data)).state,'ready');assert.equal((await c.upload('client',p1,mid(1),png)).state,'ready');assert.equal(c.objects.size,size);
 await assert.rejects(c.upload('client',p1,mid(1),Buffer.from('other')),code('invalid-argument'));assert.equal(c.data.get(`requests/${rid}`).status,'published');
});
test('PDF and all target image formats receive structural validation in addition to scanner approval',async()=>{
 const c=await rich();await c.prepare('pro',input(1,pdf,'pdf','devis.pdf','application/pdf'));await c.upload('pro',p1,mid(1),pdf);
 assert.deepEqual((await c.read('client',p1,mid(1))).bytes,pdf);
 for(const [i,mime,ext]of [[2,'image/jpeg','jpeg'],[3,'image/webp','webp']]){const b=fixture('photo.'+ext);await c.prepare('client',input(i,b,'image','photo.'+ext,mime));await c.upload('client',p1,mid(i),b);assert.equal(c.message(i).contentType,mime);}
});
test('no scanner means quarantine, no final message and no participant download; explicit retry can finish safely',async()=>{
 const c=await rich();c.setVerdict('unavailable');await c.prepare('client',input());assert.equal((await c.upload('client',p1,mid(1),png)).state,'awaiting_scan');
 assert.equal(c.message(1),undefined);assert.equal(c.objects.has(c.record(1).quarantinePath),true);assert.equal(c.objects.has(c.record(1).storagePath),false);
 await assert.rejects(c.read('client',p1,mid(1)),code('not-found'));await assert.rejects(c.read('pro',p1,mid(1)),code('not-found'));
 c.setVerdict('clean');await c.upload('client',p1,mid(1),png);assert.equal(c.message(1).type,'image');assert.equal(c.objects.size,1);
 assert.equal(await createClamScanner()(png),'unavailable');assert.equal(await createClamScanner({host:'disabled'})(png),'unavailable');for(const host of ['8.8.8.8','1.1.1.1','172.40.1.1'])assert.equal(privateAddress(host),false);
});

test('server opt-out delivers structurally validated images/PDF privately without invoking or claiming antivirus',async()=>{
 let scans=0;const c=await rich(async()=>{scans++;throw Error('Scanner must not be called');},false);
 for(const [n,bytes,type,name,mime]of [[1,png,'image','photo.png','image/png'],[2,pdf,'pdf','fiche.pdf','application/pdf'],[3,fixture('photo.jpeg'),'image','photo.jpeg','image/jpeg'],[4,fixture('photo.webp'),'image','photo.webp','image/webp']]){
  await c.prepare('client',input(n,bytes,type,name,mime));assert.equal((await c.upload('client',p1,mid(n),bytes)).state,'ready');
  assert.equal(c.record(n).antivirusStatus,'skipped');assert.equal(c.record(n).validationMode,'structural-v1');assert.equal(c.message(n).antivirusStatus,'skipped');
  assert.equal(c.objects.get(c.record(n).storagePath).metadata.validation,'structural-v1');assert.equal(c.objects.has(c.record(n).quarantinePath),false);
  assert.ok((await c.read('pro',p1,mid(n))).bytes.length);await assert.rejects(c.read('other-pro',p1,mid(n)),code('permission-denied'));
  assert.equal((await c.upload('client',p1,mid(n),bytes)).state,'ready');
 }
 assert.equal(scans,0);assert.equal(c.data.get(`requests/${rid}`).status,'published');
});

test('opting out of antivirus retains MIME, size, signature, parsing and server-only policy checks',async()=>{
 const c=await rich(undefined,false);await assert.rejects(c.prepare('client',{...input(),requireScan:false}),code('invalid-argument'));
 await assert.rejects(c.prepare('client',{...input(),sizeBytes:10*1048576+1}),code('invalid-argument'));
 await assert.rejects(c.prepare('client',{...input(),contentType:'application/zip'}),code('invalid-argument'));
 for(const [n,bytes,type,name,mime]of [[1,Buffer.from('PK\x03\x04fake'),'image','fake.png','image/png'],[2,Buffer.concat([png.subarray(0,8),Buffer.from('broken')]),'image','broken.png','image/png'],[3,Buffer.from('%PDF-1.7\n/JavaScript test\n%%EOF'),'pdf','active.pdf','application/pdf']]){
  await c.prepare('client',input(n,bytes,type,name,mime));await assert.rejects(c.upload('client',p1,mid(n),bytes),code('invalid-argument'));assert.equal(c.message(n),undefined);assert.equal(c.record(n).state,'rejected');
 }
});

test('server policy can retry a pending file without antivirus, then restore mandatory scanning for new uploads',async()=>{
 let required=true,verdict='unavailable';const c=await rich(async()=>verdict,()=>required);await c.prepare('client',input());
 assert.equal((await c.upload('client',p1,mid(1),png)).state,'awaiting_scan');required=false;
 assert.equal((await c.upload('client',p1,mid(1),png)).state,'ready');assert.equal(c.record(1).antivirusStatus,'skipped');
 required=true;await c.prepare('client',input(2));assert.equal((await c.upload('client',p1,mid(2),png)).state,'awaiting_scan');assert.equal(c.message(2),undefined);
 verdict='skipped';await c.prepare('client',input(3));assert.equal((await c.upload('client',p1,mid(3),png)).state,'awaiting_scan');assert.equal(c.message(3),undefined);
 // Turning antivirus back on does not claim to rescan an already shared file.
 assert.ok((await c.read('pro',p1,mid(1))).bytes.length);assert.equal(c.record(1).antivirusStatus,'skipped');
});
test('size, extension, MIME, unexpected fields, false type and binary signature are independently enforced',async()=>{
 for(const data of [{...input(),sizeBytes:10*1048576+1},{...input(1,pdf,'pdf','a.pdf','application/pdf'),sizeBytes:15*1048576+1},{...input(),originalName:'a.svg'},{...input(),contentType:'application/zip'},{...input(),type:'pdf'}])assert.throws(()=>metadata(data),code('invalid-argument'));
 const c=await rich();await assert.rejects(c.prepare('client',{...input(),senderUid:'pro'}),code('invalid-argument'));
 const fake=Buffer.from('PK\x03\x04not-a-png');await c.prepare('client',input(1,fake));await assert.rejects(c.upload('client',p1,mid(1),fake),code('invalid-argument'));assert.equal(c.record(1).state,'rejected');assert.equal(c.objects.size,0);assert.equal(c.message(1),undefined);
 await assert.rejects(c.upload('client',p1,mid(1),Buffer.alloc(15*1048576+1)),code('invalid-argument'));
});
test('corrupt images, active/encrypted/unparseable PDFs and scanner infection cannot publish a message',async()=>{
 const corrupt=Buffer.concat([png.subarray(0,8),Buffer.from('broken')]);await assert.rejects(canonicalize(corrupt,{type:'image',contentType:'image/png'}),code('invalid-argument'));
 for(const bytes of [Buffer.from('%PDF-1.7\n/JavaScript test\n%%EOF'),Buffer.from('%PDF-1.7\n/Encrypt test\n%%EOF'),Buffer.from('%PDF-1.7\ninvalid\n%%EOF')])await assert.rejects(canonicalize(bytes,{type:'pdf',contentType:'application/pdf'}),code('invalid-argument'));
 const c=await rich();c.setVerdict('infected');await c.prepare('client',input());await assert.rejects(c.upload('client',p1,mid(1),png),code('invalid-argument'));assert.equal(c.record(1).state,'rejected');assert.equal(c.message(1),undefined);assert.equal(c.objects.size,0);
});
test('third party, wrong conversation, uploader spoof and overwriting a reservation are refused',async()=>{
 const c=await rich();await assert.rejects(c.prepare(null,input()),code('unauthenticated'));await assert.rejects(c.prepare('other-pro',input()),code('permission-denied'));await assert.rejects(c.prepare('client',{...input(),conversationId:'UnknownConversation00001'}),code('permission-denied'));
 await c.prepare('client',input());await assert.rejects(c.prepare('pro',input()),code('already-exists'));await assert.rejects(c.prepare('client',{...input(),originalName:'other.png'}),code('already-exists'));
 await assert.rejects(c.upload('pro',p1,mid(1),png),code('permission-denied'));await assert.rejects(c.cancel('pro',p1,mid(1)),code('permission-denied'));await assert.rejects(c.read('other-pro',p1,mid(1)),code('permission-denied'));
});
test('cancel during validation wins atomically, cleans objects and never creates a broken final message',async()=>{
 let entered,finish;const scanning=new Promise(r=>entered=r),gate=new Promise(r=>finish=r);const c=await rich(async()=>{entered();return gate;});
 await c.prepare('client',input());const upload=c.upload('client',p1,mid(1),png);await scanning;assert.equal((await c.cancel('client',p1,mid(1))).state,'cancelled');finish('clean');await assert.rejects(upload,code('failed-precondition'));assert.equal(c.objects.size,0);assert.equal(c.message(1),undefined);
});
test('close during upload preserves V8.1 messaging; deletion stops new attachments but preserves validated history',async()=>{
 let entered,finish;const scanning=new Promise(r=>entered=r),gate=new Promise(r=>finish=r);const c=await rich(async()=>{entered();return gate;});await c.prepare('client',input());const upload=c.upload('client',p1,mid(1),png);await scanning;await c.manage('client',rid,'close');finish('clean');assert.equal((await upload).state,'ready');
 await c.manage('client',rid,'delete');assert.ok((await c.read('pro',p1,mid(1))).bytes.length);await assert.rejects(c.prepare('client',input(2)),code('failed-precondition'));assert.equal((await c.cancel('client',p1,mid(1))).state,'ready');
});
test('refusal during validation prevents publication and expiry removes unreferenced files',async()=>{
 let entered,finish;const scanning=new Promise(r=>entered=r),gate=new Promise(r=>finish=r);const c=await rich(async()=>{entered();return gate;});await c.prepare('client',input());const upload=c.upload('client',p1,mid(1),png);await scanning;
 await c.decide('client',{requestId:rid,proposalId:p1,action:'reject',decisionId:'RejectDecision000000001'});finish('clean');await assert.rejects(upload,code('failed-precondition'));assert.equal(c.message(1),undefined);
 c.setTime(86400001+100);assert.equal((await c.cleanup()).expired,1);assert.equal(c.objects.size,0);assert.equal(c.record(1).state,'expired');
});
test('quota is per sender; preparing retries is free but new IDs and repeated upload attempts are bounded',async()=>{
 const c=await rich();for(let i=1;i<=5;i++)await c.prepare('client',input(i));await c.prepare('client',input(1));await assert.rejects(c.prepare('client',input(6)),code('resource-exhausted'));await c.prepare('pro',input(6));
 c.setVerdict('unavailable');for(let i=0;i<5;i++)await c.upload('client',p1,mid(1),png);await assert.rejects(c.upload('client',p1,mid(1),png),code('resource-exhausted'));
 c.setTime(60100);assert.equal((await c.upload('client',p1,mid(1),png)).state,'awaiting_scan');
});
test('expiry retries a failed object deletion rather than forgetting an orphan',async()=>{
 const c=await rich();c.setVerdict('unavailable');await c.prepare('client',input());await c.upload('client',p1,mid(1),png);c.setTime(86400200);
 const remove=c.files.remove;c.files.remove=async()=>{throw Error('Storage offline');};await assert.rejects(c.cleanup());assert.ok(c.record(1).expiresAt>86400200);c.files.remove=remove;c.setTime(86400200+3600001);await c.cleanup();assert.equal(c.objects.size,0);
});
