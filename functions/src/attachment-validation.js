const sharp = require('sharp');
const {PDFDocument} = require('pdf-lib');
const {OtpError} = require('./auth-validation');
const TYPES = {'image/jpeg':['jpg','jpeg'],'image/png':['png'],'image/webp':['webp'],'application/pdf':['pdf']};
const fail = () => { throw new OtpError('invalid-argument','Fichier illisible, trop complexe ou format non pris en charge.'); };
function metadata(input) {
  if (!input || !['image','pdf'].includes(input.type) || typeof input.originalName !== 'string' ||
      !Number.isSafeInteger(input.sizeBytes) || input.sizeBytes < 1 || input.sizeBytes > (input.type === 'image' ? 10 : 15)*1048576 ||
      typeof input.sha256 !== 'string' || !/^[a-f0-9]{64}$/.test(input.sha256)) fail();
  const originalName = input.originalName.replace(/\\/g,'/').split('/').at(-1).replace(/[\x00-\x1f\x7f"<>:|?*]/g,'_').slice(-120);
  const extension = originalName.split('.').at(-1).toLowerCase();
  if (!TYPES[input.contentType]?.includes(extension) || (input.type === 'pdf') !== (input.contentType === 'application/pdf')) fail();
  return {type:input.type,originalName,contentType:input.contentType,sizeBytes:input.sizeBytes,sha256:input.sha256};
}
function checkMagic(bytes, mime) {
  let found;
  if (bytes.length >= 3 && bytes[0] === 255 && bytes[1] === 216 && bytes[2] === 255) found='image/jpeg';
  if (bytes.subarray(0,8).equals(Buffer.from([137,80,78,71,13,10,26,10]))) found='image/png';
  if (bytes.length >= 12 && bytes.toString('ascii',0,4)==='RIFF' && bytes.toString('ascii',8,12)==='WEBP') found='image/webp';
  if (/^%PDF-(1\.[0-7]|2\.0)[\r\n]/.test(bytes.toString('ascii',0,10))) found='application/pdf';
  if (found !== mime) fail();
}
async function canonicalize(bytes, item) {
  checkMagic(bytes,item.contentType);
  try {
    if (item.type === 'pdf') {
      if (!/%%EOF\s*$/.test(bytes.subarray(-1024).toString('latin1')) || /\/(Encrypt|JavaScript|JS|Launch|RichMedia|EmbeddedFile|OpenAction|AA)\b/.test(bytes.toString('latin1'))) fail();
      const pdf=await PDFDocument.load(bytes,{ignoreEncryption:false,throwOnInvalidObject:true,updateMetadata:false});
      if (pdf.isEncrypted || pdf.getPageCount() < 1 || pdf.getPageCount() > 500) fail();
      return bytes; // Structural checks do not provide antivirus assurance.
    }
    const pipeline=sharp(bytes,{limitInputPixels:20000000,failOn:'warning',animated:false});
    const info=await pipeline.metadata();
    if (!info.width || !info.height || (info.pages || 1) > 1) fail();
    const image=pipeline.rotate().resize({width:2560,height:2560,fit:'inside',withoutEnlargement:true});
    const result=item.contentType==='image/jpeg' ? await image.jpeg({quality:85}).toBuffer()
      : item.contentType==='image/webp' ? await image.webp({quality:85}).toBuffer() : await image.png({compressionLevel:9}).toBuffer();
    if (result.length > 10*1048576) fail();
    return result;
  } catch (e) { if (e instanceof OtpError) throw e; fail(); }
}
module.exports={metadata,checkMagic,canonicalize};
