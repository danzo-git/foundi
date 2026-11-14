// Read-only release gate. It performs no network calls, publication or deployment.
const fs=require('node:fs'),path=require('node:path');
const root=path.resolve(__dirname,'..'),read=p=>JSON.parse(fs.readFileSync(path.join(root,p),'utf8')),errors=[];
const legal=read('config/legal-documents.sprint-2.draft.json'),runtime=read('public-privacy/assets/runtime.json'),retention=read('config/privacy-policy.draft.json');
if(legal.published!==true||!legal.version||[legal.terms,legal.privacy].some(v=>!v||/PROJET NON PUBLIÉ|à compléter|à valider|reste.{0,20}confirmer/i.test(v)))errors.push('Textes juridiques et identité sociale non validés.');
try{require('../functions/src/privacy-service').policy({...retention,enabled:true});}catch{errors.push('Politique de conservation non approuvée ou incomplète.');}
if(runtime.emulator||runtime.emailEnumerationProtectionVerified!==true||!runtime.projectId||!runtime.apiKey||!runtime.authDomain||!runtime.endpointBase?.startsWith('https://'))errors.push('Runtime public, domaine Auth ou protection anti-énumération non vérifiés.');
const rc=read('.firebaserc'),project=runtime.projectId,targets=rc.targets?.[project]?.hosting;
if(!targets?.publicPrivacy?.length||targets.publicPrivacy.some(id=>targets.admin?.includes(id)))errors.push('Target Hosting publicPrivacy absent ou confondu avec Admin.');
if(errors.length){console.error('Publication refusée par le contrôle local :\n'+errors.map(e=>' - '+e).join('\n'));process.exitCode=1;}else console.log('Préconditions locales satisfaites. Un accord explicite et la recette du domaine restent nécessaires ; rien n’a été publié.');
