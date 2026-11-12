const {test}=require('node:test');
const assert=require('node:assert/strict');
const {directRequestActivity,accountRequesterName}=require('../src/direct-request-context');

test('direct activity respects professional order, active categories and matching specialties',()=>{
  const catalog={enabled:true,categories:[
    {id:'retired',label:'Inactive',active:false},
    {id:'home',label:'Maison',specialties:[{id:'old',label:'Ancienne',active:false},{id:'wood',label:'Menuiserie'},{id:'paint',label:'Peinture'}]},
    {id:'auto',label:'Automobile'},
  ]};
  const profile={categoryIds:['retired','home','auto'],specialtyIds:['old','paint','wood']};
  assert.deepEqual(directRequestActivity(profile,catalog),{categoryId:'home',categoryLabel:'Maison',specialtyId:'paint',specialtyLabel:'Peinture'});
  assert.deepEqual(directRequestActivity({...profile,specialtyIds:[]},catalog),{categoryId:'auto',categoryLabel:'Automobile',specialtyId:'',specialtyLabel:''});
  assert.equal(directRequestActivity({categoryIds:['home'],specialtyIds:['old']},catalog),null);
  assert.equal(directRequestActivity(profile,{...catalog,enabled:false}),null);
});

test('request identity uses safe account fields and excludes contact details',()=>{
  assert.equal(accountRequesterName({fullName:'  Awa   Kouassi  '},{displayName:'Autre nom'}),'Awa Kouassi');
  assert.equal(accountRequesterName({fullName:'private@example.test'},{displayName:'Élodie N’Guessan'}),'Élodie N’Guessan');
  for(const fullName of ['Contact +2250700000000','private@example.test','Nom\u0000invalide','']) {
    assert.equal(accountRequesterName({fullName}),null);
  }
});
