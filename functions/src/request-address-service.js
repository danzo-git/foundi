const {OtpError,requireUid}=require('./auth-validation');
const {assertActive}=require('./safety-guard');
const {zoneCountry}=require('./catalog-service');
const fail=(code,message)=>{throw new OtpError(code,message);};
// Only an author-confirmed address is saved. Native coordinates are never copied.
function addressMutation(input){
 if(!input||!Object.hasOwn(input,'interventionAddress'))return {provided:false,value:null};
 if(input.interventionAddress===null)return {provided:true,value:null};
 const value=input.interventionAddress;
 if(!value||typeof value!=='object'||Array.isArray(value)||Object.keys(value).some(k=>!['line','countryCode','confirmed'].includes(k))||value.confirmed!==true||typeof value.line!=='string'||value.line.length>500||!['CI','FR'].includes(value.countryCode))fail('invalid-argument','Vérifie et confirme l’adresse qui sera affichée sur ta demande.');
 const line=value.line.normalize('NFC').replace(/[\p{Cc}\p{Cf}]/gu,' ').replace(/\s+/gu,' ').trim();
 if(line.length<5)fail('invalid-argument','Complète l’adresse qui sera affichée sur ta demande avant de la confirmer.');
 return {provided:true,value:{line,countryCode:value.countryCode}};
}
function assertAddressCountry(address,catalog,zoneIds){
 if(address&&!zoneIds.some(id=>{const z=catalog.zones.find(z=>z.id===id);return z&&zoneCountry(z,catalog.zones)===address.countryCode;}))fail('invalid-argument','Choisis au moins une zone de recherche dans le même pays que ton adresse.');
}
function acknowledgement(saved,mutation){
 if(!mutation.provided)return {};
 const address=saved.interventionAddress;
 return {interventionAddressSaved:mutation.value?!!address&&address.line===mutation.value.line&&address.countryCode===mutation.value.countryCode:!address};
}
function createRequestAddressService({store,auth}){
 async function capabilities(uid,input){
  requireUid(uid);
  if(!input||typeof input!=='object'||Array.isArray(input)||Object.keys(input).length)fail('invalid-argument','Paramètres invalides.');
  const user=await auth.getUser(uid);
  if(user.disabled||!user.emailVerified)fail('permission-denied','Compte indisponible.');
  await store.transaction(tx=>assertActive(tx,uid));
  return {version:1,supported:true};
 }
 return {capabilities};
}
module.exports={addressMutation,assertAddressCountry,acknowledgement,createRequestAddressService};
