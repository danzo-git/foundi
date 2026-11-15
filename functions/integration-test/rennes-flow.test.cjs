const {test}=require('node:test'),assert=require('node:assert/strict');
const {initializeApp,deleteApp}=require('firebase-admin/app');
const {getFirestore}=require('firebase-admin/firestore');
const {guardedTransaction}=require('../src/privacy-guard');
const {createCatalogService}=require('../src/catalog-service');
const {createRequestService}=require('../src/request-service');
const {createNotificationService}=require('../src/notification-service');
const {key}=require('../src/notification-policy');
test('RENNES one French commune, real publication, exact zone fanout and no duplicate for multi-country pros',{skip:!process.env.FIRESTORE_EMULATOR_HOST,timeout:180000},async()=>{
 const app=initializeApp({projectId:'demo-foundi-rennes'},'rennes-'+Date.now()),db=getFirestore(app);
 const auth={getUser:async()=>({disabled:false,emailVerified:true,customClaims:{admin:true}})};
 let now=Date.now();
 const store={transaction:fn=>guardedTransaction(db,fn)};
 const initial={enabled:true,version:'before',categories:[{id:'services',label:'Services',specialties:[{id:'plomberie',label:'Plomberie'}],requirements:{independent:[],company:[]}}],zones:[{id:'ci-cocody',label:'Cocody',type:'commune',countryCode:'CI',active:true}],documentTypes:[{id:'identity',label:'Identité',active:true}]};
 const catalog=createCatalogService({store,auth}),requests=createRequestService({store,auth,clock:()=>now});
 const notification=createNotificationService({db,auth,clock:()=>now,messaging:{send:async()=>{throw Error('Real push forbidden');}}});
 const requestId='RennesPublication000001',rennes='fr_commune_35238';
 try {
  await db.doc('referenceData/professionalOnboarding').set(initial);
  await catalog.update('admin',{admin:true},{operation:'enableRennes',expectedVersion:'before'});
  const saved=(await db.doc('referenceData/professionalOnboarding').get()).data();
  assert.equal(saved.zones.length,2);assert.deepEqual(saved.zones[0],initial.zones[0]);assert.equal(saved.zones[1].countryCode,'FR');
  await db.doc('users/client').set({fullName:'Client de recette'});
  const payload={budget:null,title:'Réparer une fuite à Rennes',description:'Une fuite dans la cuisine nécessite une intervention.',categoryId:'services',specialtyId:'plomberie',zoneId:rennes,zoneIds:[rennes]};
  const published=await requests.publish('client',requestId,payload);assert.equal(published.zoneLabel,'Rennes');
  const base={status:'approved',categoryIds:['services'],specialtyIds:['plomberie']};
  await db.doc('professionalProfiles/rennes-only').set({...base,zoneIds:[rennes]});
  await db.doc('professionalProfiles/cocody-only').set({...base,zoneIds:['ci-cocody']});
  await db.doc('professionalProfiles/both').set({...base,zoneIds:[rennes,'ci-cocody']});
  async function dispatch(id,request,version) {
    await notification.enqueueRequest('matched','client',id,request,version);
    const job=key('matched','client',id,String(version));
    await notification.processJob(job);await notification.processJob(job);
  }
  await dispatch(requestId,published,1);
  const count=async(uid,id)=>(await db.collection(`users/${uid}/notifications`).where('requestId','==',id).get()).size;
  assert.equal(await count('rennes-only',requestId),1);assert.equal(await count('both',requestId),1);assert.equal(await count('cocody-only',requestId),0);
  now+=61001;
  const other='CocodyPublication000001',ci=await requests.publish('client',other,{...payload,zoneId:'ci-cocody',zoneIds:['ci-cocody']});
  await dispatch(other,ci,1);assert.equal(await count('rennes-only',other),0);assert.equal(await count('cocody-only',other),1);
  now+=61001;
  const combined='CombinedPublication0001',multi=await requests.publish('client',combined,{...payload,zoneIds:[rennes,'ci-cocody']});
  await dispatch(combined,multi,1);assert.equal(await count('both',combined),1);
  // Historical country metadata remains unchanged, and no other French city is inserted.
  assert.deepEqual((await db.doc('referenceData/professionalOnboarding').get()).data().zones.map(z=>z.id),['ci-cocody',rennes]);
 } finally {await deleteApp(app);}
});
