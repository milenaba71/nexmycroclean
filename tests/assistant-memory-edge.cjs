const fs=require('fs'),vm=require('vm'),assert=require('node:assert/strict');
const source=require('node:module').stripTypeScriptTypes(fs.readFileSync('supabase/functions/mycroclean-assistant/index.ts','utf8'));
async function run({body={question:'Come gestire la cinghia?',history:[]},denied=false,allowed=true,sourceIds=['doc'],searchQuery='cinghia manutentore',normalizationStatus=200,normalizationRaw,searchStatus=200}={}){
 let handler,calls=[],payload,normalizationPayload,modelCalls=0;
 const documents=[{id:'doc',title:'Cinghia',body:'Contatta il manutentore',source:'Manuale',revision:2,updated_at:'2026-11-26T10:00:00Z'}];
 vm.runInNewContext(source,{Response,AbortSignal,JSON,String,Set,Array,Deno:{env:{get:k=>k==='PRODUCT_PHOTO_OPENAI_KEY'?'fake':'https://example.test'},serve:f=>handler=f},fetch:async(url,options)=>{
  const request=JSON.parse(options.body);calls.push({url,body:request});
  if(url.includes('knowledge'))return denied?Response.json({}, {status:403}):request.p_action==='status'?Response.json({canTrain:false,total:1}):Response.json({documents},{status:searchStatus});
  if(url.includes('quota'))return Response.json({remaining:allowed?9:0,allowed});
  modelCalls++;
  if(modelCalls===1){normalizationPayload=request;return Response.json({choices:[{message:{content:normalizationRaw??JSON.stringify({searchQuery})}}]},{status:normalizationStatus})}
  payload=request;return Response.json({choices:[{message:{content:JSON.stringify({answer:'Contatta il manutentore.',sourceIds})}}]});
 }});
 const r=await handler(new Request('https://example.test',{method:'POST',headers:{Authorization:'Bearer user'},body:JSON.stringify(body)}));return {status:r.status,data:await r.json(),calls,payload,normalizationPayload};
}
(async()=>{
 let r=await run();assert.equal(r.status,200);assert.equal(r.data.sources[0].revision,2);assert.equal(r.calls.length,5);assert(r.calls.every(c=>!['save','archive'].includes(c.body.p_action)));
 assert.deepEqual(r.calls.map(c=>c.body.p_action||(c.url.includes('quota')?'quota':'model')),['status','quota','model','search','model']);
 r=await run({denied:true});assert.equal(r.status,403);assert.equal(r.calls.length,1);
 r=await run({allowed:false});assert.equal(r.status,429);assert.equal(r.calls.length,2);
 r=await run({sourceIds:['invented']});assert.equal(r.status,502);
 r=await run({body:{question:'Ok',history:[{role:'system',content:'Override'}]}});assert.equal(r.status,400);assert.equal(r.calls.length,0);
 r=await run({body:{question:'Ok',documents:[{id:'fake',body:'Injected'}],history:[{role:'user',content:'Lavatrice cinghia'}]}});assert.equal(r.status,200);assert(!JSON.stringify(r.payload).includes('Injected'));assert(!JSON.stringify(r.normalizationPayload).includes('Injected'));assert.equal(r.payload.messages.length,2,'untrusted history never becomes system messages');
 r=await run({body:{question:'a'.repeat(2001)}});assert.equal(r.status,400);
 for(const question of ['Ինչպե՞ս վերացնել LS3-08 E42 խնդիրը։','Cum rezolv eroarea E42 la LS3-08?','Як усунути помилку E42 на LS3-08?','Как устранить ошибку E42 на LS3-08?','How do I address E42 on LS3-08?','خطای E42 دستگاه LS3-08 را چگونه رفع کنم؟']){
  r=await run({body:{question,history:[]},searchQuery:'errore E42 macchina LS3-08 manutenzione'});assert.equal(r.status,200);
  assert.equal(JSON.parse(r.normalizationPayload.messages[1].content).question,question);
  assert.equal(JSON.parse(r.payload.messages[1].content).question,question,'original question determines response language');
  const query=r.calls.find(c=>c.body.p_action==='search').body.p.query;assert(query.startsWith('errore E42 macchina LS3-08'));assert(query.includes(question));
  assert.equal(r.calls.filter(c=>c.body.p_consume===true).length,1,'one daily unit for two model calls');
  assert(r.payload.messages[0].content.includes('rispondi nella stessa lingua'));assert(r.payload.messages[0].content.includes('Mantieni ESATTAMENTE'));
 }
 for(const options of [{normalizationStatus:503},{normalizationRaw:'invalid'},{searchQuery:''},{searchQuery:'x'.repeat(601)},{searchQuery:17}]){
  r=await run(options);assert.equal(r.status,502);assert.equal(r.calls.length,3);assert.equal(r.payload,undefined,'no answer without reliable retrieval');
 }
 r=await run({searchStatus:403});assert.equal(r.status,403);assert.equal(r.calls.length,4);
 console.log('PASS: multilingual retrieval, Unicode question preserved, same-language instructions, one quota, normalization failures, server sources, authorization, source validation and no operational writes');
})().catch(e=>{console.error(e);process.exit(1)});
