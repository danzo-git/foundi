// Read-only code audit: downloads immutable deployed source generations, never executes them.
const fs=require('node:fs');
const assert=require('node:assert/strict');
const {createHash}=require('node:crypto');
const {initializeApp,deleteApp}=require('firebase-admin/app');
const {getStorage}=require('firebase-admin/storage');
async function main(){
  const report=JSON.parse(fs.readFileSync('.dart_tool/request-author-audit.json','utf8'));
  assert.equal(report.project,'foundi-7c837');
  const app=initializeApp({projectId:report.project});
  try{
    for(const name of ['publishRequest','listOpportunities']){
      const source=report.functions.find(f=>f.name===name)?.source;
      assert.equal(source?.bucket,'gcf-v2-sources-1080925286687-europe-west1');
      assert.equal(source.object,`${name}/function-source.zip`);
      const [bytes]=await getStorage(app).bucket(source.bucket).file(source.object,{generation:source.generation}).download();
      const output=`.dart_tool/request-author-source-${name}.zip`;
      fs.writeFileSync(output,bytes);
      console.log(JSON.stringify({name,generation:source.generation,bytes:bytes.length,sha256:createHash('sha256').update(bytes).digest('hex'),output}));
    }
  }finally{await deleteApp(app);}
}
main().catch(error=>{console.error(error.message);process.exitCode=1;});
