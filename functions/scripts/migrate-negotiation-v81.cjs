// Dry-run by default. Plans include private backups: store outside version control.
const fs=require('node:fs');
const assert=require('node:assert/strict');
const {isDeepStrictEqual}=require('node:util');
const {GoogleAuth}=require('google-auth-library');
const {planNegotiationMigration}=require('../src/negotiation-migration');
const args=process.argv.slice(2), option=k=>args[args.indexOf(k)+1];
const project=args.includes('--project')?option('--project'):null;
if(!project || !/^[a-z][a-z0-9-]+$/.test(project))throw Error('--project is required');
const emulator=process.env.FIRESTORE_EMULATOR_HOST;
if(emulator&&!project.startsWith('demo-'))throw Error('Emulator migration requires a demo- project');
const base=`${emulator?'http://'+emulator:'https://firestore.googleapis.com'}/v1/projects/${project}/databases/(default)`;
function decode(v){
 if('nullValue'in v)return null;if('stringValue'in v)return v.stringValue;if('booleanValue'in v)return v.booleanValue;
 if('integerValue'in v && Number.isSafeInteger(Number(v.integerValue)))return Number(v.integerValue);
 if('doubleValue'in v && typeof v.doubleValue==='number')return v.doubleValue;
 if('mapValue'in v)return decodeFields(v.mapValue.fields||{});
 if('arrayValue'in v)return (v.arrayValue.values||[]).map(decode);
 return {$firestoreValue:v};
}
const decodeFields=f=>Object.fromEntries(Object.entries(f).map(([k,v])=>[k,decode(v)]));
function encode(v){
 if(v===null)return {nullValue:null};if(v?.$firestoreValue)return v.$firestoreValue;
 if(typeof v==='string')return {stringValue:v};if(typeof v==='boolean')return {booleanValue:v};
 if(typeof v==='number')return Number.isInteger(v)?{integerValue:String(v)}:{doubleValue:v};
 if(Array.isArray(v))return {arrayValue:{values:v.map(encode)}};
 return {mapValue:{fields:encodeFields(v)}};
}
const encodeFields=f=>Object.fromEntries(Object.entries(f).map(([k,v])=>[k,encode(v)]));
async function main(){
 const client=emulator?{request:async({url,method='GET',data,params})=>{
   const u=new URL(url);for(const [k,v] of Object.entries(params||{}))u.searchParams.set(k,v);
   if(args.includes('--verbose'))console.error(JSON.stringify({step:'request',method,endpoint:u.pathname.split('/').at(-1)}));
   const response=await fetch(u,{method,signal:AbortSignal.timeout(15000),headers:{'content-type':'application/json','authorization':'Bearer owner'},...(data?{body:JSON.stringify(data)}:{})});
   const body=await response.json();if(!response.ok)throw Error(body.error?.message||response.status);return {data:body};
 }}:await new GoogleAuth({scopes:['https://www.googleapis.com/auth/cloud-platform']}).getClient();
 const apply=args.includes('--apply'),rollback=args.includes('--rollback');assert.ok(!(apply&&rollback));
 if(apply||rollback){
  assert.ok(args.includes('--plan'),'--plan backup required');const plan=JSON.parse(fs.readFileSync(option('--plan'),'utf8'));assert.equal(plan.project,project);
  let changed=0,skipped=0;
  for(const group of plan.groups){
   const {data:begun}=await client.request({method:'POST',url:`${base}/documents:beginTransaction`,data:{options:{readWrite:{}}}});const transaction=begun.transaction;
   try{
    const {data:read}=await client.request({method:'POST',url:`${base}/documents:batchGet`,data:{transaction,documents:group.changes.map(c=>`projects/${project}/databases/(default)/documents/${c.path}`)}});
    const documents=new Map(read.filter(r=>r.found).map(r=>[r.found.name.split('/documents/')[1],r.found]));
    const rows=group.changes.map(change=>{const d=documents.get(change.path);assert.ok(d,`Missing document at ${change.path}`);return {change,current:decodeFields(d.fields||{})};});
    const source=rollback?'after':'before',target=rollback?'before':'after';
    if(rows.every(r=>isDeepStrictEqual(r.current,r.change[target]))){skipped++;await client.request({method:'POST',url:`${base}/documents:rollback`,data:{transaction}});continue;}
    for(const row of rows)assert.ok(isDeepStrictEqual(row.current,row.change[source]),`Conflict at ${row.change.path}; no writes for this request`);
    await client.request({method:'POST',url:`${base}/documents:commit`,data:{transaction,writes:rows.map(({change})=>({update:{name:`projects/${project}/databases/(default)/documents/${change.path}`,fields:encodeFields(change[target])}}))}});changed++;
   }catch(e){await client.request({method:'POST',url:`${base}/documents:rollback`,data:{transaction}}).catch(()=>{});throw e;}
  }
  console.log(JSON.stringify({project,mode:rollback?'rollback':'apply',changed,alreadyApplied:skipped}));return;
 }
 const records=[];const counts={};
 for(const collectionId of ['requests','items','proposals','conversations']){
  let last;
  do{
   const structuredQuery={from:[{collectionId,allDescendants:collectionId==='items'}],orderBy:[{field:{fieldPath:'__name__'},direction:'ASCENDING'}],limit:250};
   if(last)structuredQuery.startAt={values:[{referenceValue:last}],before:false};
   const {data}=await client.request({method:'POST',url:`${base}/documents:runQuery`,data:{structuredQuery}});const docs=data.filter(r=>r.document).map(r=>r.document);
   for(const d of docs){const path=d.name.split('/documents/')[1];if(collectionId==='items'&&!/^userRequests\/[^/]+\/items\/[^/]+$/.test(path))continue;records.push({path,data:decodeFields(d.fields||{})});}
   last=docs.length===250?docs.at(-1).name:null;
  }while(last);
  counts[collectionId]=records.filter(r=>collectionId==='items'?r.path.startsWith('userRequests/'):r.path.startsWith(collectionId+'/')).reduce((c,r)=>{const s=r.data.status||'unknown';c[s]=(c[s]||0)+1;return c;},{});
 }
 const result=planNegotiationMigration(records),plan={version:81,project,createdAt:new Date().toISOString(),inventory:counts,...result};
 if(args.includes('--output'))fs.writeFileSync(option('--output'),JSON.stringify(plan,null,2),{flag:'wx',mode:0o600});
 console.log(JSON.stringify({project,mode:'dry-run',inventory:counts,counts:result.counts,anomalies:result.anomalies.length,writes:0,backup:args.includes('--output')?option('--output'):null}));
}
main().catch(e=>{console.error(JSON.stringify({error:e.message,http:e.response?.status}));process.exitCode=1;});
