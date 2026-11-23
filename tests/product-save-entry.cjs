const fs=require('fs'),vm=require('vm'),assert=require('node:assert/strict');
const s=fs.readFileSync('product-barcodes.js','utf8');
let saves=0,entries=0,printed=0,focused=0,closed=0,messages=[],entryError=false;
const values={id:'NEW001',name:'Test',dept:'',size:'L',color:'Blu',type:'TUTA',client:'CLIENT',wash:'0',max:'80',rental:'no',creation:'2026-11-23'};
const form={productEntryContext:{lotId:56,processingId:'P',washChoice:'W|M'},querySelectorAll:()=>[]};
const ctx={current:{id:56,client:'CLIENT',rows:[]},stage:'Entrata',chosenProcessing:'P',washChoice:'W|M',cloudRevision:1,
 db:{garments:[]},userCan:()=>true,clone:x=>JSON.parse(JSON.stringify(x)),lotBusy:()=>false,selectedProcessing:()=>({id:'P'}),dateLabel:x=>x||'',ownership:()=>'',notify:m=>messages.push(m),restoreEntryScanFocus:()=>focused++,
 FormData:class{get(k){return values[k]??''}has(k){return k in values}getAll(){return []}},$:()=>({close(){closed++}}),cloudFlush:async()=>{},
 saveProductWithRevisionRetry:async payload=>{saves++;return {saved_id:'NEW001',saved_code:'NEW001',db:{garments:[payload.product]}}},
 cloudAccept:data=>{ctx.db=data.db},prepareLabel:()=>{assert.equal(entries,1);assert.equal(ctx.current.rows.length,1);printed++},
 enqueueBarcode:async code=>{entries++;assert.equal(code,'NEW001');await Promise.resolve();if(!entryError)ctx.current.rows.push({code,state:'Entrato'});else messages.push('Errore scansione');}
};
vm.createContext(ctx);vm.runInContext(s.slice(s.indexOf('async function registerSavedProductInEntry'),s.indexOf('const garmentTableBeforeEditableBarcode')),ctx);
const event=print=>({target:form,submitter:{name:print?'print':''},preventDefault(){}});
(async()=>{
 await ctx.saveProduct(event(true),null);
 assert.equal(saves,1);assert.equal(entries,1);assert.equal(printed,1);assert.equal(closed,1);assert.equal(ctx.current.rows.length,1);assert.equal(focused,1);
 // Editing a garment already in the lot does not register it again.
 await ctx.saveProduct(event(false),'NEW001');assert.equal(saves,2);assert.equal(entries,1);
 // Office saves and a changed lot/phase are never silently assigned to an entry.
 ctx.current.rows=[];form.productEntryContext=null;await ctx.saveProduct(event(false),null);assert.equal(entries,1);
 form.productEntryContext={lotId:55,processingId:'P',washChoice:'W|M'};await ctx.saveProduct(event(false),null);assert.equal(entries,1);
 form.productEntryContext.lotId=56;ctx.stage='Uscita';await ctx.saveProduct(event(false),null);assert.equal(entries,1);ctx.stage='Entrata';
 // A failure in entry leaves the product saved, without a second product write.
 entryError=true;const before=saves;await ctx.saveProduct(event(false),null);assert.equal(saves,before+1);assert.equal(entries,2);assert.equal(ctx.current.rows.length,0);assert(messages.some(m=>m.includes('Scheda prodotto salvata. Entrata non registrata')));
 entryError=false;ctx.washChoice='OTHER';await ctx.saveProduct(event(false),null);assert.equal(entries,2);ctx.washChoice='W|M';
 ctx.userCan=cap=>cap!=='lots_work';await ctx.saveProduct(event(false),null);assert.equal(entries,2);ctx.userCan=()=>true;
 values.client='OTHER CLIENT';await ctx.saveProduct(event(false),null);assert.equal(entries,2);
 console.log('PASS: one save registers entry, print waits for entry, existing row not duplicated, office/navigation/route/client/permission guards, failure never resaves product');
 // Preserve the existing bounded conflict retry through the machine RPC adapter.
 const wash=fs.readFileSync('wash-batches.js','utf8'),flow=fs.readFileSync('lot-workflow.js','utf8');let calls=0,refreshed=0;
 const retry={appSupabase:{rpc:async()=>++calls===1?{error:{message:'REVISION_CONFLICT'}}:{data:{ok:true}}},washMessage:e=>e.message,cloudRevision:1,cloudAccept:r=>{retry.cloudRevision=r.revision;refreshed++},washSyncChoices(){}};
 vm.createContext(retry);vm.runInContext(wash.slice(wash.indexOf('async function washRpc('),wash.indexOf('\nasync function washRefresh(')),retry);
 retry.cloudRequest=(action,payload)=>action?retry.washRpc('acquire',payload):Promise.resolve({revision:2});
 vm.runInContext(flow.slice(flow.indexOf('async function lotAtomicRequest('),flow.indexOf('\nasync function assignLotProductType(')),retry);
 assert.equal((await retry.lotAtomicRequest('lot_acquire',{})).ok,true);assert.equal(calls,2);assert.equal(refreshed,1);
 console.log('PASS: concurrent machine-entry conflict refreshes and retries automatically');
})().catch(e=>{console.error(e);process.exit(1)});
