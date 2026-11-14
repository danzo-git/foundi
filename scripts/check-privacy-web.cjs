const fs=require('node:fs'),path=require('node:path'),{spawnSync}=require('node:child_process');
const result=spawnSync(process.execPath,['--input-type=module','--check'],{input:fs.readFileSync(path.join(__dirname,'../public-privacy/assets/deletion.js'),'utf8'),encoding:'utf8'});
if(result.stdout)process.stdout.write(result.stdout);if(result.stderr)process.stderr.write(result.stderr);process.exitCode=result.status??1;
