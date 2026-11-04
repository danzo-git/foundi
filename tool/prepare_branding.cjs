// Deterministic asset packaging: preserve the supplied artwork and its colours.
// Run from the repository root after npm --prefix functions ci.
const fs=require('node:fs'),path=require('node:path');
const sharp=require('../functions/node_modules/sharp');
const root=path.resolve(__dirname,'..');
const source=path.join(root,'assets/branding/foundi-logo-source.png');
async function png(input,file,size){
 fs.mkdirSync(path.dirname(file),{recursive:true});
 await sharp(input).resize(size,size,{fit:'contain',background:'#ffffff'}).removeAlpha().png().toFile(file);
}
async function main(){
 // Trim only the white presentation margin; keep a square canvas without
 // stretching the artwork. The unmodified supplied source remains in assets.
 const trimmed=await sharp(source).trim({background:'#ffffff',threshold:25}).toBuffer();
 const mark=trimmed;
 // Small in-app asset; native icon exports still use the full-resolution art.
 await png(mark,path.join(root,'assets/branding/foundi-mark.png'),384);
 for(const [density,scale]of Object.entries({mdpi:1,hdpi:1.5,xhdpi:2,xxhdpi:3,xxxhdpi:4})){
  const dir=path.join(root,`android/app/src/main/res/mipmap-${density}`);
  await png(mark,path.join(dir,'ic_launcher.png'),48*scale);
  await png(mark,path.join(dir,'ic_launcher_round.png'),48*scale);
  // The original margin provides the adaptive icon's safe foreground inset.
  await png(source,path.join(dir,'ic_launcher_foreground.png'),108*scale);
 }
 const adaptive=path.join(root,'android/app/src/main/res/mipmap-anydpi-v26');fs.mkdirSync(adaptive,{recursive:true});
 const xml='<?xml version="1.0" encoding="utf-8"?>\n<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n    <background android:drawable="@color/ic_launcher_background" />\n    <foreground android:drawable="@mipmap/ic_launcher_foreground" />\n</adaptive-icon>\n';
 for(const name of ['ic_launcher','ic_launcher_round'])fs.writeFileSync(path.join(adaptive,name+'.xml'),xml);
 fs.writeFileSync(path.join(root,'android/app/src/main/res/values/launcher_colors.xml'),'<?xml version="1.0" encoding="utf-8"?>\n<resources>\n    <color name="ic_launcher_background">#003B2D</color>\n</resources>\n');
 for(const platform of ['ios','macos']){
  const dir=path.join(root,`${platform}/Runner/Assets.xcassets/AppIcon.appiconset`);
  const contents=JSON.parse(fs.readFileSync(path.join(dir,'Contents.json'),'utf8'));
  for(const entry of contents.images){
   if(!entry.filename)continue;
   await png(mark,path.join(dir,entry.filename),Math.round(parseFloat(entry.size)*parseFloat(entry.scale)));
  }
 }
 for(const size of [192,512]){
  await png(mark,path.join(root,`web/icons/Icon-${size}.png`),size);
  await png(source,path.join(root,`web/icons/Icon-maskable-${size}.png`),size);
 }
 await png(mark,path.join(root,'web/favicon.png'),32);
 const sizes=[16,24,32,48,64,128,256],images=[];
 for(const size of sizes)images.push(await sharp(mark).resize(size,size).ensureAlpha().png().toBuffer());
 const header=Buffer.alloc(6+16*sizes.length);header.writeUInt16LE(1,2);header.writeUInt16LE(sizes.length,4);
 let offset=header.length;
 sizes.forEach((size,i)=>{const at=6+16*i;header[at]=size===256?0:size;header[at+1]=header[at];header.writeUInt16LE(1,at+4);header.writeUInt16LE(32,at+6);header.writeUInt32LE(images[i].length,at+8);header.writeUInt32LE(offset,at+12);offset+=images[i].length;});
 fs.writeFileSync(path.join(root,'windows/runner/resources/app_icon.ico'),Buffer.concat([header,...images]));
 console.log('Foundi logo packaged for Flutter, Android, iOS, macOS, Windows and web.');
}
main().catch(e=>{console.error(e.message);process.exitCode=1;});
