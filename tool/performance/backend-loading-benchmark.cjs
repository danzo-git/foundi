// Actual service code with synthetic I/O. No Firebase, real people or network.
const fs=require('node:fs');
const path=require('node:path');
const {createHash}=require('node:crypto');
const {execFileSync}=require('node:child_process');
const {createRequire}=require('node:module');
const {performance}=require('node:perf_hooks');
const fixtures=require('../../functions/test-support/backend-loading-fixtures');
const root=path.resolve(__dirname,'../..');
const baselineRef='b8546e888d1f2ff7c057a03db0895d78ce461d50';
function services(relative) {
  const filename=path.join(root,relative), source=execFileSync('git',['show',`${baselineRef}:${relative}`],{cwd:root,encoding:'utf8'});
  const reference={exports:{}};
  new Function('require','module','exports',source)(createRequire(filename),reference,reference.exports);
  return {before:reference.exports,after:require(filename),afterSha256:createHash('sha256').update(fs.readFileSync(filename)).digest('hex')};
}
const variants={
  respondents:services('functions/src/request-respondents-service.js'),
  directoryProfile:services('functions/src/professional-directory-service.js'),
  authorProfile:services('functions/src/request-author-service.js'),
};
const cases={
  respondents:{fixture:fixtures.respondentsFixture,create:'createRequestRespondentsService',
    invoke:f=>f.service.list('viewer',f.requestId,0)},
  directoryProfile:{fixture:fixtures.directoryFixture,create:'createProfessionalDirectoryService',
    invoke:f=>f.service.readProfile('actor',{professionalId:f.id})},
  authorProfile:{fixture:fixtures.authorFixture,create:'createRequestAuthorService',
    invoke:f=>f.service.read('viewer','actor',{requestId:f.requestId})},
};
async function main() {
  const samples=21,delayMs=3,result={kind:'node_profile_and_respondents_synthetic_io',baselineRef,
    samplesPerVersion:samples,warmSamples:20,fixtureReadDelayMs:delayMs,
    note:'In-memory stores and timers; counters/JSON bytes are synthetic, not billed Firestore or network measurements. JSON bytes count document values returned by the fake store, not the HTTP response to the app. One synthetic 1 KiB non-public field demonstrates the profile fieldMask. The author fixture delegates avatar resolution and directory projection to one simulated I/O each, so its counters exclude their internal operations.',
    actualFirestoreReads:null,actualNetworkBytes:null,cases:{}};
  for(const [name,scenario] of Object.entries(cases)) {
    const records={before:[],after:[]};
    for(let sample=0;sample<samples;sample++) {
      // Interleave the versions, alternating the order to limit timing bias.
      for(const version of sample%2?['after','before']:['before','after']) {
        const f=scenario.fixture(variants[name][version][scenario.create],{delayMs});
        const start=performance.now();
        const response=await scenario.invoke(f);
        records[version].push({elapsedMs:performance.now()-start,...f.metrics});
        if(name==='respondents'&&response.items.length!==20)throw Error('Incomplete fixture page');
      }
    }
    result.cases[name]={afterSourceSha256:variants[name].afterSha256};
    for(const version of ['before','after']) {
      const values=records[version].slice(1).map(row=>row.elapsedMs).sort((a,b)=>a-b);
      result.cases[name][version]={medianMs:(values[9]+values[10])/2,p95Ms:values[18],records:records[version]};
    }
    const current=result.cases[name];
    current.medianReductionPercent=(1-current.after.medianMs/current.before.medianMs)*100;
  }
  const destination=path.join(root,'docs/sprint-2-6/backend-loading-comparison.json');
  fs.mkdirSync(path.dirname(destination),{recursive:true});
  fs.writeFileSync(destination,JSON.stringify(result,null,2)+'\n');
  console.log(JSON.stringify(Object.fromEntries(Object.entries(result.cases).map(([name,value])=>[name,{
    beforeMedianMs:value.before.medianMs,afterMedianMs:value.after.medianMs,
    beforeP95Ms:value.before.p95Ms,afterP95Ms:value.after.p95Ms,
    beforeReads:value.before.records[0].documentReads,afterReads:value.after.records[0].documentReads,
    beforeFakeBytes:value.before.records[0].returnedBytes,afterFakeBytes:value.after.records[0].returnedBytes,
  }]))));
}
main().catch(error=>{console.error(error);process.exitCode=1;});
