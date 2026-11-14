const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const root=path.resolve(__dirname,'../..');
test('public privacy resources are accessible without auth, safely served and match the unpublished app payload',async()=>{
 const {server}=require('../../scripts/preview-privacy.cjs');await new Promise(r=>server.listen(0,'127.0.0.1',r));
 try{const base='http://127.0.0.1:'+server.address().port;for(const route of ['/','/assistance','/confidentialite','/conditions-utilisation','/suppression-compte']){const r=await fetch(base+route);assert.equal(r.status,200);assert.equal(r.headers.get('referrer-policy'),'no-referrer');assert.ok(r.headers.get('content-security-policy').includes("object-src 'none'"));const html=await r.text();assert.ok(html.includes('lang="fr"'));assert.ok(html.includes('kouamedenzel09@gmail.com'));}
 const draft=JSON.parse(fs.readFileSync(path.join(root,'config/legal-documents.sprint-2.draft.json')));assert.equal(draft.published,false);assert.equal(draft.terms,fs.readFileSync(path.join(root,'docs/legal/sprint-2/cgu-v1-projet.md'),'utf8'));assert.equal(draft.privacy,fs.readFileSync(path.join(root,'docs/legal/sprint-2/confidentialite-v1-projet.md'),'utf8'));
 const runtime=await(await fetch(base+'/assets/runtime.json')).json();assert.equal(runtime.enabled,false);assert.equal((await fetch(base+'/suppression-compte',{method:'POST'})).status,405);assert.equal((await fetch(base+'/does-not-exist')).status,404);
 }finally{await new Promise(r=>server.close(r));}
});
