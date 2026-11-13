const assert=require('node:assert/strict');
const {createSafetyService}=require('../../src/safety-service');
const {createConversationService}=require('../../src/conversation-service');
const {createProposalService,proposalId}=require('../../src/proposal-service');
const {createRequestService}=require('../../src/request-service');
const rid='SafetyRequestIdentifier001',pid=proposalId(rid,'pro');
function seed(){
  const request={title:'Réparer une fuite',description:'Une fuite dans la cuisine à réparer.',categoryId:'c',categoryLabel:'Services',specialtyId:'s',specialtyLabel:'Plomberie',zoneId:'z',zoneLabel:'Zone test',budget:15000,status:'published',createdAt:1};
  return new Map([
    [`requests/${rid}`,request],[`userRequests/client/items/${rid}`,{...request,proposalCount:1}],[`requestOwnership/${rid}`,{ownerUid:'client'}],
    ['users/client',{fullName:'Client Test'}],['professionalProfiles/pro',{status:'approved',businessName:'Atelier Test',categoryIds:['c'],specialtyIds:['s'],zoneIds:['z']}],
    [`proposals/${pid}`,{requestId:rid,clientUid:'client',professionalUid:'pro',professionalName:'Atelier Test',description:'Une proposition de test.',amount:15000,delay:'Demain',status:'sent',createdAt:2}],
    ['referenceData/professionalOnboarding',{enabled:true,categories:[{id:'c',label:'Services',specialties:[{id:'s',label:'Plomberie'}]}],zones:[{id:'z',label:'Zone test'}]}],
  ]);
}
function setup(){
  const data=seed(),accounts=new Map();let pending=Promise.resolve(),now=100000;
  const store={get:async p=>data.get(p),transaction(operation){
    const task=pending.then(async()=>{const next=structuredClone(data);let writing=false;
      const result=await operation({get:async p=>{assert.equal(writing,false,'Firestore reads must precede writes');return next.get(p);},set:(p,v)=>{writing=true;next.set(p,v);},delete:p=>{writing=true;next.delete(p);},conversationsForRequest:async id=>[...next].filter(([p,v])=>/^conversations\/[^/]+$/.test(p)&&v.requestId===id).map(([p,v])=>({id:p.split('/')[1],...v}))});
      data.clear();for(const row of next)data.set(...row);return result;});pending=task.catch(()=>{});return task;
  },notices:async uid=>[...data].filter(([p])=>p.startsWith(`users/${uid}/safetyNotices/`)).map(([p,n])=>({id:p.split('/').at(-1),text:n.text,createdAt:n.createdAt,acknowledgedAt:n.acknowledgedAt??null})),audit:async id=>[...data].filter(([p,r])=>p.startsWith('safetyAudit/')&&r.reportId===id).map(([,r])=>r),expiredEvidence:async time=>[...data].filter(([p,r])=>p.startsWith('safetyReports/')&&r.evidenceExpiresAt<=time).map(([p])=>p.split('/')[1])};
  const auth={getUser:async uid=>accounts.get(uid)||{uid,disabled:false,emailVerified:true,customClaims:{admin:uid==='admin'||uid==='admin2'}},getUsers:async refs=>({users:await Promise.all(refs.map(r=>auth.getUser(r.uid)))})};
  const deps={store,auth,clock:()=>now};const safety=createSafetyService(deps),chat=createConversationService(deps),proposals=createProposalService(deps),requests=createRequestService(deps);
  return {data,store,auth,accounts,safety,chat,proposals,requests,deps,setTime:t=>{now=t;}};
}
module.exports={setup,seed,rid,pid};
