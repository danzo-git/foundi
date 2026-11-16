// Read-only anonymous baseline of public endpoints. Never persist response
// bodies, resource identifiers, names, photos, tokens or addresses.
const fs = require('node:fs');
const {performance} = require('node:perf_hooks');
const project = 'foundi-7c837';
const origin = `https://europe-west1-${project}.cloudfunctions.net/`;
const metrics = [];
async function post(url, body) {
  const start = performance.now();
  const response = await fetch(url, {method:'POST', headers:{'content-type':'application/json'},
    body:JSON.stringify(body), signal:AbortSignal.timeout(30000)});
  const headersAt = performance.now();
  const bytes = new Uint8Array(await response.arrayBuffer());
  const done = performance.now();
  let data; try {data = JSON.parse(new TextDecoder().decode(bytes));} catch {data = null;}
  return {data, metric:{httpStatus:response.status, headersMs:headersAt-start,
    totalMs:done-start, decodedResponseBytes:bytes.length,
    contentLengthHeader:response.headers.has('content-length')?Number(response.headers.get('content-length')):null}};
}
async function sample(name, input) {
  let last;
  const samples = [];
  for (let i=0;i<3;i++) {
    const response = await post(origin+name, {data:input});
    samples.push({...response.metric, errorStatus:response.data?.error?.status??null});
    if (response.metric.httpStatus!==200 || !response.data?.result) break;
    last = response.data.result;
  }
  const successful = samples.filter(s=>s.httpStatus===200).map(s=>s.totalMs).sort((a,b)=>a-b);
  metrics.push({endpoint:name, samples, medianMs:successful.length===3?successful[1]:null,
    p95Ms:null, serverMs:null, actualFirestoreReads:null});
  return last;
}
async function main() {
  const directory = await sample('listPublicProfessionals', {});
  if (directory?.items?.[0]?.professionalId) {
    await sample('readPublicProfessionalProfile', {professionalId:directory.items[0].professionalId});
  }
  const selection = await post(`https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/documents:runQuery`, {
    structuredQuery:{from:[{collectionId:'requests'}],
      select:{fields:[{fieldPath:'proposalCount'}]},
      where:{fieldFilter:{field:{fieldPath:'status'},op:'EQUAL',value:{stringValue:'published'}}},
      orderBy:[{field:{fieldPath:'createdAt'},direction:'DESCENDING'}],limit:5},
  });
  const candidates = Array.isArray(selection.data)?selection.data.filter(r=>r.document):[];
  candidates.sort((a,b)=>Number(b.document.fields?.proposalCount?.integerValue??0)-Number(a.document.fields?.proposalCount?.integerValue??0));
  const requestId = candidates[0]?.document?.name?.split('/').pop();
  if (requestId) {
    await sample('listRequestRespondents', {requestId,offset:0});
    await sample('readRequestAuthorProfile', {requestId});
  }
  const result = {kind:'anonymous_public_production_http_baseline', measuredAtUtc:new Date().toISOString(),
    note:'PC HTTP; before new profile/respondent deployment. No private conversation or logged-in data. Three samples, no p95. Bytes are decoded payload sizes, not wire traffic.',
    publicRequestSelectionStatus:selection.metric.httpStatus, endpoints:metrics};
  fs.writeFileSync('docs/sprint-2-6/public-read-baseline.json',JSON.stringify(result,null,2)+'\n');
  console.log(JSON.stringify(result));
}
main().catch(error=>{console.error(JSON.stringify({probeFailed:true,errorType:error.name}));process.exitCode=1;});
