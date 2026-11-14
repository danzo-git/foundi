const {test}=require('node:test'),assert=require('node:assert/strict');
test('a deleted request snapshot cannot crash the actual close-notification trigger',async()=>{
 process.env.GCLOUD_PROJECT='demo-foundi';
 process.env.FIREBASE_CONFIG=JSON.stringify({projectId:'demo-foundi',storageBucket:'demo-foundi.appspot.com'});
 const {notifyRequestClosed,notifyRequestPublished,notifyProfessionalDecision,notifyMessageCreated,countNotificationRead}=require('../src/index');
 for(const [before,after] of [[{status:'published'},undefined],[undefined,{status:'deleted'}],[undefined,undefined]])await assert.doesNotReject(()=>Promise.resolve(notifyRequestClosed.run({params:{uid:'test-only',requestId:'test-only'},data:{before:{data:()=>before},after:{data:()=>after}}})));
 for(const handler of [notifyRequestPublished,notifyProfessionalDecision,notifyMessageCreated])await assert.doesNotReject(()=>Promise.resolve(handler.run({params:{uid:'test-only'},data:{data:()=>undefined}})));
 await assert.doesNotReject(()=>Promise.resolve(countNotificationRead.run({params:{uid:'test-only'},data:{before:{data:()=>({readAt:null})},after:{data:()=>undefined}}})));
});
