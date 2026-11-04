const fs=require('node:fs'),path=require('node:path'),{spawn}=require('node:child_process');
const {startFixture}=require('../test/helpers/clamd-fixture.cjs');
const root=path.resolve(__dirname,'../..'),envPath=path.join(root,'functions/.env.local'),backupPath=path.join(root,'.dart_tool/v82-local-env-backup.bin');
async function main(){
 if(fs.existsSync(backupPath))throw Error('Previous local environment backup exists: restore it before rerunning.');
 const existed=fs.existsSync(envPath),original=existed?fs.readFileSync(envPath):Buffer.alloc(0);fs.mkdirSync(path.dirname(backupPath),{recursive:true});fs.writeFileSync(backupPath,original,{flag:'wx',mode:0o600});
 let fixture,child;
 const secretPath=path.join(root,'functions/.secret.local'),createdTestSecrets=!fs.existsSync(secretPath);
 const stop=()=>child?.kill('SIGINT');process.once('SIGINT',stop);process.once('SIGTERM',stop);
 try{
  if(createdTestSecrets)fs.writeFileSync(secretPath,'SMTP_PASSWORD=emulator-only\nSMTP_USER=emulator-only\nOTP_HMAC_KEY=emulator-only-not-a-production-secret-32\n',{flag:'wx',mode:0o600});
  fixture=await startFixture();
  const required=!process.argv.includes('--without-antivirus');
  const preserved=original.toString('utf8').replace(/^ATTACHMENT_SCAN_(HOST|PORT)=.*\r?\n?/gm,'').replace(/^ATTACHMENT_REQUIRE_SCAN=.*\r?\n?/gm,'');
  fs.writeFileSync(envPath,preserved+`\nATTACHMENT_SCAN_HOST=127.0.0.1\nATTACHMENT_SCAN_PORT=${fixture.port}\nATTACHMENT_REQUIRE_SCAN=${required}\n`);
  const cli=process.env.FIREBASE_CLI_JS||path.join(process.env.APPDATA,'npm/node_modules/firebase-tools/lib/bin/firebase.js');
  const onlyRules=process.argv.includes('--rules-only');
  const v91Only=process.argv.includes('--v91-only'),v9Only=process.argv.includes('--v9-only'),config=v91Only?'firebase.v91.emulators.json':v9Only?'firebase.v9.emulators.json':'firebase.v82.emulators.json';
  const testCommand=onlyRules?'npm.cmd --prefix functions run test:rules':process.argv.includes('--v9-only')?'npm.cmd --prefix functions run test:v9:emulated':'npm.cmd --prefix functions run test:emulated';
  child=spawn(process.execPath,[cli,'emulators:exec',...(onlyRules?[]:[v91Only?'--inspect-functions=14999':v9Only?'--inspect-functions=13999':'--inspect-functions=12999']),'--config',config,'--project','demo-foundi','--only',onlyRules?'firestore,storage':'auth,firestore,storage,functions',testCommand],
   {cwd:root,stdio:'inherit',env:{...process.env,JAVA_TOOL_OPTIONS:'-Xmx512m',NODE_OPTIONS:'--max-old-space-size=384',FUNCTIONS_DISCOVERY_TIMEOUT:'120',FUNCTIONS_EMULATOR_HOST:v91Only?'127.0.0.1:1423':v9Only?'127.0.0.1:1323':'127.0.0.1:1223',V82_TEST_REQUIRE_SCAN:String(required),NO_PROXY:'127.0.0.1,localhost,::1'}});
  process.exitCode=await new Promise((resolve,reject)=>{child.once('error',reject);child.once('exit',code=>resolve(code??1));});
 }finally{
  if(fixture)await fixture.close();if(existed)fs.writeFileSync(envPath,original);else if(fs.existsSync(envPath))fs.unlinkSync(envPath);fs.unlinkSync(backupPath);
  if(createdTestSecrets&&fs.existsSync(secretPath))fs.unlinkSync(secretPath);
  process.removeListener('SIGINT',stop);process.removeListener('SIGTERM',stop);
 }
}
main().catch(e=>{console.error(e.message);process.exitCode=1;});
