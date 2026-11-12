// Read-only production diagnostic. Never prints contact details or full user records.
const fs=require('node:fs');
const {initializeApp,deleteApp}=require('firebase-admin/app');
const {getFirestore}=require('firebase-admin/firestore');
const {getAuth}=require('firebase-admin/auth');
const {GoogleAuth}=require('google-auth-library');
const {createHash}=require('node:crypto');
const {accountRequesterName}=require('../src/direct-request-context');
const project='foundi-7c837',region='europe-west1';
async function main(){
  if(process.env.FIRESTORE_EMULATOR_HOST || process.env.FIREBASE_AUTH_EMULATOR_HOST) throw Error('Production audit must not use an emulator');
  const output=process.argv[2],privateRequests=process.argv.includes('--private');
  const collection=privateRequests?'directRequests':'requests',field=privateRequests?'requesterName':'authorPublicName';
  const app=initializeApp({projectId:project}),db=getFirestore(app),auth=getAuth(app);
  const report={project,collection,checkedAt:new Date().toISOString(),recent:[],functions:[]};
  try{
    const docs=await db.collection(collection).orderBy('createdAt','desc').limit(5)
      .select(field,'createdAt','status').get();
    for(const doc of docs.docs){
      const request=doc.data(),ownership=(await db.doc(`requestOwnership/${doc.id}`).get()).data();
      const uid=ownership?.ownerUid;
      const item={id:doc.id,createdAt:request.createdAt,status:request.status,hasStoredName:typeof request[field]==='string'&&!!request[field].trim(),ownerResolved:!!uid};
      if(uid){
        const [profile,own]=await Promise.all([
          db.doc(`users/${uid}`).get(),db.doc(`userRequests/${uid}/items/${doc.id}`).get(),
        ]);
        let account;try{account=await auth.getUser(uid);}catch(error){if(error.code!=='auth/user-not-found')throw error;}
        const name=accountRequesterName(profile.data(),account),ownName=own.data()?.[field];
        Object.assign(item,{ownerHash:createHash('sha256').update(uid).digest('hex').slice(0,12),
          profileExists:profile.exists,profileNamePresent:!!profile.data()?.fullName,
          profileNameUsable:!!accountRequesterName(profile.data()),authNamePresent:!!account?.displayName,
          accountNameUsable:!!name&&!!name.trim(),storedNameMatchesAccount:!!name&&request[field]===name,
          ownNameMatchesAccount:!!name&&ownName===name});
      }
      report.recent.push(item);
    }
    const client=await new GoogleAuth({scopes:['https://www.googleapis.com/auth/cloud-platform']}).getClient();
    for(const name of ['publishRequest','manageRequest','listOpportunities']){
      const {data:f}=await client.request({url:`https://cloudfunctions.googleapis.com/v2/projects/${project}/locations/${region}/functions/${name}`});
      report.functions.push({name,state:f.state,revision:f.serviceConfig?.revision,updatedAt:f.updateTime,source:f.buildConfig?.source?.storageSource});
    }
    if(output)fs.writeFileSync(output,JSON.stringify(report,null,2));
    console.log(JSON.stringify(report));
  }finally{await deleteApp(app);}
}
main().catch(error=>{console.error(error.message);process.exitCode=1;});
