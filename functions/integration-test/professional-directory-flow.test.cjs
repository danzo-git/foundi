const {test}=require('node:test');
const assert=require('node:assert/strict');
const {initializeApp,deleteApp}=require('firebase-admin/app');
const {getFirestore}=require('firebase-admin/firestore');
const {createProfessionalDirectoryStore}=require('../src/professional-directory-store');
const {createProfessionalDirectoryService}=require('../src/professional-directory-service');
test('real Firestore adapter: filtered pagination, thin projections, revocation, TTL and enforced rate budget',
 {skip:!process.env.FIRESTORE_EMULATOR_HOST,timeout:90000},async()=>{
  assert.match(process.env.FIRESTORE_EMULATOR_HOST,/^(127\.0\.0\.1|localhost):/);
  const stamp=Date.now(),app=initializeApp({projectId:'demo-foundi'},'directory-'+stamp),db=getFirestore(app),store=createProfessionalDirectoryStore(db);
  const prefix='directory'+stamp,ids=Array.from({length:45},(_,i)=>prefix+String(i).padStart(3,'0'));
  const auth={getUser:async uid=>({uid,emailVerified:true,disabled:false}),getUsers:async refs=>({users:refs.map(r=>({uid:r.uid,emailVerified:true,disabled:false}))})};
  const service=createProfessionalDirectoryService({store,auth});
  try{
    await db.doc('referenceData/professionalOnboarding').set({enabled:true,categories:[{id:'wood',label:'Menuiserie'}],zones:[{id:'zone',label:'Zone de test'}]});
    const batch=db.batch();
    for(const [i,id] of ids.entries()){
      batch.set(db.doc(`professionalProfiles/${id}`),{status:'approved',businessName:i===44?'Atelier Ébène':'Entreprise '+i,categoryIds:['wood'],specialtyIds:[],zoneIds:['zone'],email:'secret@example.test',documents:['private']});
      batch.set(db.doc(`professionalProfiles/${id}/showcase/profile`),{revision:1,name:i===44?'Atelier Ébène':'Entreprise '+i,trade:'Menuiserie',area:'Zone de test',bio:'Rangements sur mesure.',gallery:[],private:'secret'});
    }
    await batch.commit();
    const thin=await store.texts([ids[44]]);assert.deepEqual(Object.keys(thin.get(ids[44])).sort(),['name','trade']);
    const rows=await store.approvedPage(null,40);assert.ok(rows.length<=40);assert.equal(rows[0].profile.email,undefined);
    let cursor,found=[];
    do{const page=await service.search(prefix,{query:'ebene',categoryId:'wood',zoneId:'zone',cursor});found.push(...page.items);cursor=page.cursor;}while(cursor);
    assert.deepEqual(found.map(p=>p.professionalId),[ids[44]]);
    const page=await service.search(prefix,{});assert.ok(page.cursor);
    const saved=await db.doc(`professionalDirectoryCursors/${page.cursor}`).get();assert.equal(typeof saved.data().expiresAt.toMillis(),'number');
    assert.ok(!JSON.stringify(page).includes('secret'));
    const profile=await service.readProfile(prefix,{professionalId:ids[44]});assert.equal(profile.requestActivity.categoryId,'wood');assert.equal(profile.private,undefined);
    await db.doc(`professionalProfiles/${ids[44]}`).update({status:'suspended'});
    assert.deepEqual((await service.check(prefix,{professionalIds:[ids[44]]})).professionalIds,[]);
    await assert.rejects(service.readProfile(prefix,{professionalId:ids[44]}),e=>e.code==='not-found');
    for(let i=0;i<30;i++)await store.charge(prefix,'profile',1);
    await assert.rejects(store.charge(prefix,'profile',1),e=>e.code==='resource-exhausted');
  }finally{await deleteApp(app);}
});
