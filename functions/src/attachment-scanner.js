const net=require('node:net'),dns=require('node:dns/promises'),{once}=require('node:events');
function privateAddress(ip) {
  return /^(10\.|127\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.)/.test(ip) || ip==='::1' || /^(fc|fd)[a-f0-9:]+$/i.test(ip);
}
// ClamD INSTREAM. No public TCP endpoint, no permissive fallback and no paid service provisioned.
function createClamScanner({host='',port=3310,timeout=30000}={}) {
  return async bytes => {
    if (!host || host==='disabled' || !Number.isInteger(port) || port<1 || port>65535) return 'unavailable';
    let address;
    try { address=(await dns.lookup(host)).address; } catch { return 'unavailable'; }
    if (!privateAddress(address)) return 'unavailable';
    return new Promise(resolve=>{
      const socket=net.createConnection({host:address,port});let answer='',done=false;
      const finish=result=>{if(done)return;done=true;socket.destroy();resolve(result);};
      socket.setTimeout(timeout,()=>finish('unavailable'));
      socket.on('error',()=>finish('unavailable'));
      socket.on('end',()=>finish('unavailable'));
      socket.on('data',chunk=>{
        answer+=chunk.toString('utf8');if(answer.length>4096)return finish('unavailable');
        if(answer.includes('\0')||answer.includes('\n'))finish(/^stream: OK[\0\r\n]*$/.test(answer)?'clean':answer.includes(' FOUND')?'infected':'unavailable');
      });
      socket.on('connect',async()=>{
        try {
          socket.write(Buffer.from('zINSTREAM\0'));
          for(let offset=0;offset<bytes.length&&!done;offset+=65536){const chunk=bytes.subarray(offset,offset+65536),size=Buffer.alloc(4);size.writeUInt32BE(chunk.length);socket.write(size);if(!socket.write(chunk))await once(socket,'drain');}
          if(!done)socket.write(Buffer.alloc(4));
        }catch{finish('unavailable');}
      });
    });
  };
}
module.exports={createClamScanner,privateAddress};
