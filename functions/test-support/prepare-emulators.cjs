const fs=require('fs');const net=require('net');const path=require('path');
// Local test configuration only. No credentials and no remote operations.
(async()=>{
 const free=()=>new Promise((resolve,reject)=>{const s=net.createServer();s.on('error',reject);s.listen(0,'127.0.0.1',()=>{const port=s.address().port;s.close(()=>resolve(port));});});
 const root=path.resolve(__dirname,'../..');const c=JSON.parse(fs.readFileSync(path.join(root,'firebase.emulators.json')));
 for(const key of ['auth','firestore','storage','functions','hub','logging'])c.emulators[key].port=await free();
 c.emulators.firestore.websocketPort=await free();
 fs.writeFileSync(path.join(root,'.firebase-integration.json'),JSON.stringify(c,null,2));
 const env=path.join(root,'functions/.env.demo-foundi');if(!fs.existsSync(env))fs.copyFileSync(path.join(root,'config/emulator-functions.env'),env);
 console.log('Local emulator ports:',JSON.stringify(c.emulators));
})().catch(e=>{console.error(e.message);process.exitCode=1;});
