const {test}=require('node:test'),assert=require('node:assert/strict');
const {planNegotiationMigration}=require('../src/negotiation-migration');
function legacy(status='in_discussion'){
 const own={status,createdAt:10,updatedAt:20,selectedProposalId:'p',selectedProfessionalUid:'pro',conversationId:'r',proposalCount:2};
 return [{path:'requests/r',data:{status,createdAt:10,updatedAt:20,title:'Demande'}},
  {path:'userRequests/client/items/r',data:own},
  {path:'proposals/p',data:{requestId:'r',clientUid:'client',professionalUid:'pro',status:'selected',conversationId:'r',createdAt:11,selectedAt:20}},
  {path:'conversations/r',data:{requestId:'r',selectedProposalId:'p',clientUid:'client',professionalUid:'pro',status:status==='closed'?'read_only':'active',createdAt:20,updatedAt:21,lastMessageAt:21,lastMessagePreview:'Historique',requestSnapshot:{status,title:'Demande'}}}];
}
test('A11: pure legacy migration reopens only automatic discussion, preserves IDs/times and is rerunnable',()=>{
 const rows=legacy(),before=structuredClone(rows),plan=planNegotiationMigration(rows);assert.deepEqual(rows,before);assert.equal(plan.counts.reopen,1);assert.equal(plan.anomalies.length,0);
 const map=new Map(rows.map(r=>[r.path,r.data]));for(const c of plan.groups[0].changes){assert.equal(c.before,map.get(c.path));map.set(c.path,c.after);}
 assert.equal(map.get('requests/r').status,'published');assert.equal(map.get('requests/r').updatedAt,20);
 assert.equal(map.get('proposals/p').conversationId,'r');assert.equal(map.get('conversations/r').createdAt,20);assert.equal(map.get('conversations/r').lastMessagePreview,'Historique');assert.equal(map.get('userRequests/client/items/r').selectedProposalId,undefined);
 assert.equal(planNegotiationMigration([...map].map(([path,data])=>({path,data}))).groups.length,0);
});
test('closed/deleted requests never reopen; closed chats become active, deleted remain archived',()=>{
 for(const status of ['closed','deleted']){const plan=planNegotiationMigration(legacy(status));assert.equal(plan.counts.reopen,0);assert.equal(plan.groups[0].changes.some(c=>c.path==='requests/r'),false);assert.equal(plan.groups[0].changes.find(c=>c.path==='conversations/r').after.status,status==='closed'?'active':'read_only');}
});
test('inconsistent/missing ownership, publication, selection or conversation is reported without unsafe writes',()=>{
 for(const mutate of [r=>r.pop(),r=>r[1].data.createdAt=99,r=>r[1].data.status='closed',r=>r[2].data.professionalUid='intruder',r=>r[1].data.selectedProposalId='other']){const rows=legacy();mutate(rows);const plan=planNegotiationMigration(rows);assert.equal(plan.groups.length,0);assert.ok(plan.anomalies.length>0);}
});
