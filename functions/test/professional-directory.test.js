const {test}=require('node:test');
const assert=require('node:assert/strict');
const {createHash}=require('node:crypto');
const sharp=require('sharp');
const {createProfessionalDirectoryService,directoryActor}=require('../src/professional-directory-service');
function fixture(count=1){
  let now=1000,seq=0;
  const catalog={enabled:true,categories:[{id:'auto',label:'Automobile',specialties:[{id:'import',label:'Importation'}]},{id:'home',label:'Maison',specialties:[{id:'wood',label:'Menuiserie'}]}],zones:[{id:'abidjan',label:'Abidjan'},{id:'cocody',label:'Cocody'}]};
  const profiles=new Map(),showcases=new Map(),users=new Map(),cursors=new Map(),charges=[],scans=[];
  for(let i=0;i<count;i++){
    const id='professional'+String(i).padStart(4,'0');
    profiles.set(id,{status:'approved',businessName:'Équipe '+i,categoryIds:['auto'],specialtyIds:['import'],zoneIds:['abidjan'],email:'private@example.test',documents:['secret']});
    users.set(id,{uid:id,emailVerified:true,disabled:false});
  }
  const store={get:async p=>p==='referenceData/professionalOnboarding'?catalog:p.endsWith('/showcase/profile')?showcases.get(p.split('/')[1]):profiles.get(p.split('/')[1]),
    profiles:async ids=>ids.filter(id=>profiles.has(id)).map(id=>({id,profile:profiles.get(id)})),
    texts:async ids=>new Map(ids.map(id=>[id,showcases.get(id)||{}])),
    approvedPage:async(after,size)=>{scans.push([after,size]);return [...profiles].filter(([id,p])=>p.status==='approved'&&(!after||id>after)).slice(0,size).map(([id,profile])=>({id,profile}));},
    charge:async(...args)=>charges.push(args),putCursor:async(t,v)=>cursors.set(t,v),cursor:async t=>cursors.get(t)};
  const auth={getUsers:async ids=>({users:ids.map(({uid})=>users.get(uid)).filter(Boolean)}),getUser:async id=>{if(!users.has(id)){const e=Error();e.code='auth/user-not-found';throw e;}return users.get(id);}};
  const service=createProfessionalDirectoryService({store,auth,clock:()=>now,newCursor:()=>String(++seq).padStart(64,'a')});
  return {service,profiles,showcases,users,catalog,cursors,charges,scans,store,advance:()=>{now+=600001;}};
}
test('directory traverses the complete set, normalizes accents and combines all declared filters',async()=>{
  const f=fixture(175);
  f.profiles.get('professional0168').businessName='  Atelier Ébène  ';
  f.profiles.get('professional0168').categoryIds=['home'];f.profiles.get('professional0168').specialtyIds=['wood'];f.profiles.get('professional0168').zoneIds=['cocody'];
  const criteria={query:'  ATELIER   ebene ',categoryId:'home',specialtyId:'wood',zoneId:'cocody'};
  const first=await f.service.search('guest',criteria);
  assert.equal(first.items.length,0);assert.match(first.cursor,/^[a-f0-9]{64}$/);assert.equal(f.scans.length,3);
  const next=await f.service.search('guest',{...criteria,cursor:first.cursor});
  assert.deepEqual(next.items.map(p=>p.professionalId),['professional0168']);assert.equal(next.cursor,null);
  assert.deepEqual(Object.keys(next.items[0]).sort(),['categories','name','portraitId','professionalId','specialties','trade','zones'].sort());
  assert.ok(!JSON.stringify(next).includes('private@example'));assert.ok(!JSON.stringify(next).includes('secret'));
});
test('pagination does not drop rows when a page ends inside a fetched chunk',async()=>{
  const f=fixture(85),ids=[];let cursor;
  do{const page=await f.service.search('actor',{cursor});ids.push(...page.items.map(p=>p.professionalId));cursor=page.cursor;}while(cursor);
  assert.equal(ids.length,85);assert.equal(new Set(ids).size,85);
});
test('opaque cursors are bound to actor, criteria and expiry',async()=>{
  const f=fixture(25),page=await f.service.search('actor',{});
  for(const [actor,args] of [['other',{cursor:page.cursor}],['actor',{cursor:page.cursor,query:'different'}],['actor',{cursor:'0'.repeat(64)}]])await assert.rejects(f.service.search(actor,args),e=>e.code==='invalid-argument');
  f.advance();await assert.rejects(f.service.search('actor',{cursor:page.cursor}),e=>e.code==='invalid-argument');
});
test('pending, suspended, disabled, unverified and inactive references never appear',async()=>{
  const f=fixture(7);
  f.profiles.get('professional0000').status='pending';f.profiles.get('professional0001').status='suspended';
  f.users.get('professional0002').disabled=true;f.users.get('professional0003').emailVerified=false;
  f.profiles.get('professional0004').specialtyIds=['retired'];f.profiles.get('professional0005').categoryIds=['removed'];
  assert.deepEqual((await f.service.search('guest',{})).items.map(p=>p.professionalId),['professional0006']);
  assert.deepEqual((await f.service.check('guest',{professionalIds:[...f.profiles.keys()]})).professionalIds,['professional0006']);
  for(let i=0;i<6;i++)await assert.rejects(f.service.readProfile('guest',{professionalId:'professional000'+i}),e=>e.code==='not-found');
});
test('approval is rechecked after scanning and before disclosing profile or media',async()=>{
  const f=fixture(1),id='professional0000';
  const original=f.store.profiles;f.store.profiles=async ids=>{f.profiles.get(id).status='suspended';return original(ids);};
  assert.equal((await f.service.search('actor',{})).items.length,0);
  f.profiles.get(id).status='approved';const get=f.store.get;
  f.store.get=async path=>{if(path.endsWith('/showcase/profile'))f.users.get(id).disabled=true;return get(path);};
  await assert.rejects(f.service.readProfile('actor',{professionalId:id}),e=>e.code==='not-found');
});
test('independent public profile whitelists fields and returns canonical direct activity',async()=>{
  const f=fixture(),id='professional0000';f.showcases.set(id,{revision:1,name:'Garage Ébène',trade:'Importateur',area:'Abidjan',bio:'Des véhicules pour votre activité.',gallery:[],email:'secret@example.test',phone:'0700000000',proposals:['private'],documents:['secret']});
  const value=await f.service.readProfile('guest',{professionalId:id});
  assert.equal(value.name,'Garage Ébène');assert.equal(value.requestActivity.categoryId,'auto');assert.equal(value.professionalId,id);
  for(const secret of ['email','phone','proposals','documents','ownerId'])assert.equal(value[secret],undefined);
  f.showcases.get(id).gallery={private:'corrupt'};f.showcases.get(id).bio='contact secret@example.test';
  assert.equal((await f.service.readProfile('guest',{professionalId:id})).bio,'');
});
test('media is lazy, bounded to three real thumbnails and sanitized',async()=>{
  const f=fixture(),id='professional0000',photos=[];
  for(let i=0;i<4;i++){
    const b=await sharp({create:{width:400,height:250,channels:3,background:{r:i*30,g:100,b:100}}}).png().toBuffer();
    photos.push({id:createHash('sha256').update(b).digest('hex'),base64:b.toString('base64')});
  }
  f.showcases.set(id,{gallery:photos,portrait:photos[0]});
  const manifest=await f.service.readMedia('guest',{professionalId:id});assert.equal(manifest.galleryIds.length,3);assert.equal(manifest.base64,undefined);
  const result=await f.service.readMedia('guest',{professionalId:id,photoId:photos[1].id});
  const bytes=Buffer.from(result.base64,'base64'),meta=await sharp(bytes).metadata();
  assert.ok(bytes.length<=16384);assert.equal(meta.format,'jpeg');assert.ok(meta.width<=224);assert.equal(meta.exif,undefined);
  await assert.rejects(f.service.readMedia('guest',{professionalId:id,photoId:photos[3].id}),e=>e.code==='not-found');
  f.profiles.get(id).status='suspended';await assert.rejects(f.service.readMedia('guest',{professionalId:id}),e=>e.code==='not-found');
});
test('strict input rejects forged filters, excessive lists and malformed ids',async()=>{
  const f=fixture();
  for(const args of [{query:'a'.repeat(81)},{specialtyId:'import'},{categoryId:'retired'},{zoneId:'retired'},{status:'pending'},{cursor:'professional0000'}])await assert.rejects(f.service.search('actor',args),e=>e.code==='invalid-argument');
  await assert.rejects(f.service.check('actor',{professionalIds:Array(25).fill('professional0000')}),e=>e.code==='invalid-argument');
  await assert.rejects(f.service.readProfile('actor',{professionalId:'../secret'}),e=>e.code==='invalid-argument');
  f.catalog.enabled=false;await assert.rejects(f.service.search('actor',{}),e=>e.code==='failed-precondition');
});
test('actor uses trusted transport and auth context, never client supplied identity',()=>{
  assert.equal(directoryActor({rawRequest:{ip:'127.0.0.1'},data:{uid:'forged'}}),directoryActor({rawRequest:{ip:'127.0.0.1'}}));
  assert.notEqual(directoryActor({rawRequest:{ip:'127.0.0.1'}}),directoryActor({rawRequest:{ip:'127.0.0.1'},auth:{uid:'real'}}));
  assert.throws(()=>directoryActor({data:{ip:'fake'}}),e=>e.code==='resource-exhausted');
});
