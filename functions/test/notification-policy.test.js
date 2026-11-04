const {test}=require('node:test'),assert=require('node:assert/strict');
const {key,catalog,matchesOpportunity,professionalType,decisionType}=require('../src/notification-policy');
const {cleanPreview,messagePushContent,isPrivateMessage}=require('../src/notification-policy');
const reference={categories:[{id:'c',specialties:[{id:'s'},{id:'s2'}]},{id:'flat',specialties:[]}]};
const profile={status:'approved',categoryIds:['c','flat','c'],specialtyIds:['s','s2','s'],zoneIds:['z','z2','z']};
const request={status:'published',categoryId:'c',specialtyId:'s',zoneId:'z'};
test('V9 matches exactly FOUN-52 combinations including multiple specialties/zones',()=>{
 for(const specialtyId of ['s','s2'])for(const zoneId of ['z','z2'])assert.equal(matchesOpportunity({...request,specialtyId,zoneId},profile,reference),true);
 for(const p of [{...profile,status:'pending'},{...profile,zoneIds:['parent-of-z']},{...profile,specialtyIds:[]},{...profile,categoryIds:[]}])assert.equal(matchesOpportunity(request,p,reference),false);
 for(const r of [{...request,status:'closed'},{...request,status:'deleted'},{...request,specialtyId:''},{...request,zoneId:'child-of-z'}])assert.equal(matchesOpportunity(r,profile,reference),false);
 assert.equal(matchesOpportunity({...request,categoryId:'flat',specialtyId:''},profile,reference),true);
 assert.equal(matchesOpportunity(request,profile,{}),false);
});
test('V9 only recognizes real admin transitions and actual changed decisions',()=>{
 assert.equal(professionalType({from:'pending',to:'approved'}),'professional.approved');
 assert.equal(professionalType({from:'pending',to:'rejected'}),'professional.rejected');
 assert.equal(professionalType({from:'pending',to:'needs_changes'}),'professional.more_info_requested');
 for(const from of ['draft','approved','rejected'])assert.equal(professionalType({from,to:'approved'}),undefined);
 assert.equal(decisionType({action:'retain',status:'retained',proposalId:'p',previousRetainedProposalId:'p'}),undefined);
 assert.equal(decisionType({action:'retain',status:'retained',proposalId:'p',previousRetainedProposalId:null}),'proposal.retained');
 assert.equal(decisionType({action:'reject',status:'rejected'}),'proposal.rejected');
 assert.equal(decisionType({action:'archive',status:'read_only'}),undefined);
 assert.equal(catalog['conversation.ended'],undefined);
});
test('V9 stable recipient IDs are distinct and the entire push catalogue is neutral',()=>{
 assert.equal(key('event','uid'),key('event','uid'));assert.notEqual(key('event','a'),key('event','b'));
 assert.notEqual(key('a\0b','c'),key('a','bc'));
 for(const value of Object.values(catalog))assert.ok(!/https?:|\+225|secret|\.pdf/i.test(value.join(' ')));
});

test('V9.1 preview normalizes controls, whitespace, apostrophes and truncates complete emoji graphemes',()=>{
 assert.equal(cleanPreview(" Bonjour,\n\tvous êtes disponible demain ?\u0000\u202e "),'Bonjour, vous êtes disponible demain ?');
 assert.equal(cleanPreview("C'est prêt 👨‍👩‍👧‍👦"),"C'est prêt 👨‍👩‍👧‍👦");
 const long=cleanPreview('👨‍👩‍👧‍👦'.repeat(101));
 assert.equal([...new Intl.Segmenter('fr',{granularity:'grapheme'}).segment(long)].length,100);
 assert.ok(long.endsWith('…'));assert.ok(!long.includes('\ufffd'));
});
test('V9.1 previews obey privacy for every message type without disclosing shared contacts or filenames',()=>{
 for(const [type,body]of Object.entries({text:'Texte privé',image:'📷 Photo',pdf:'📄 Document PDF',contact:'📞 Contact partagé'})){
  const message={type,text:'Texte privé',phoneNumber:'+2250700000000',originalName:'private-name.pdf'};
  assert.deepEqual(messagePushContent(message,'AutoLink CI',true),{title:'AutoLink CI',body});
  assert.deepEqual(messagePushContent(message,'AutoLink CI',false),{title:'AutoLink CI',body:'Nouveau message'});
 }
 assert.equal(messagePushContent({type:'text'},' \u0000 ',true).title,'Un utilisateur Foundi');
 assert.equal(isPrivateMessage({type:'chat_message'}),true);assert.equal(isPrivateMessage({type:'message.created'}),true);
 assert.equal(isPrivateMessage({type:'conversation.opened'}),false);
});
