// Test-only ClamD protocol fixture. Unknown content NEVER receives a clean verdict.
const net=require('node:net'),fs=require('node:fs'),path=require('node:path'),{createHash}=require('node:crypto');
const digest=b=>createHash('sha256').update(b).digest('hex');
async function startFixture(){
 const folder=path.join(__dirname,'../fixtures'),allowed=new Set(['photo.png','photo.jpeg','photo.webp','document.pdf'].map(n=>digest(fs.readFileSync(path.join(folder,n)))));
 const infected=digest(Buffer.concat([fs.readFileSync(path.join(folder,'photo.png')),Buffer.from('FOUNDI_INFECTED_TEST_FIXTURE')]));
 const sockets=new Set(),server=net.createServer(socket=>{
  sockets.add(socket);socket.on('close',()=>sockets.delete(socket));let buffer=Buffer.alloc(0),command=false,total=0;const chunks=[];
  socket.setTimeout(15000,()=>socket.destroy());socket.on('error',()=>{});
  socket.on('data',data=>{
   buffer=Buffer.concat([buffer,data]);
   if(!command){if(buffer.length<10)return;if(buffer.subarray(0,10).toString()!=='zINSTREAM\0'){socket.destroy();return;}buffer=buffer.subarray(10);command=true;}
   while(buffer.length>=4){const size=buffer.readUInt32BE();if(size>65536||total+size>15*1048576){socket.end('stream: Size limit ERROR\0');return;}if(buffer.length<4+size)return;
    buffer=buffer.subarray(4);if(!size){const hash=digest(Buffer.concat(chunks));socket.end(hash===infected?'stream: Fixture.Test FOUND\0':allowed.has(hash)?'stream: OK\0':'stream: Unknown fixture ERROR\0');return;}
    chunks.push(Buffer.from(buffer.subarray(0,size)));total+=size;buffer=buffer.subarray(size);
   }
  });
 });
 await new Promise((resolve,reject)=>{server.once('error',reject);server.listen(0,'127.0.0.1',resolve);});
 return {port:server.address().port,close:async()=>{for(const s of sockets)s.destroy();await new Promise(r=>server.close(r));}};
}
module.exports={startFixture};
