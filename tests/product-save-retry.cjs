const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const s=fs.readFileSync('product-barcodes.js','utf8');let calls=[],responses=[],fresh;
const ctx={appSupabase:{rpc:async(name,arg)=>{calls.push(arg.p_payload);return responses.shift()}},cloudRequest:async()=>fresh};vm.createContext(ctx);vm.runInContext(s.slice(s.indexOf('function productSaveFingerprint'),s.indexOf('saveProduct=async')),ctx);
const original={id:'A',name:'Olga',wash:1,raw:{NOTE:'prima'},history:[]},payload={revision:1,original_id:'A',product:{...original,name:'Nuovo'}};
const conflict={error:{message:'REVISION_CONFLICT'}};
(async()=>{
 fresh={revision:2,db:{garments:[{history:[],raw:{NOTE:'prima'},wash:1,name:'Olga',id:'A'}]}};responses=[conflict,{data:{saved_id:'A'}}];
 assert.equal((await ctx.saveProductWithRevisionRetry(payload,original)).saved_id,'A');assert.equal(calls.length,2);assert.equal(calls[1].revision,2);assert.equal(calls[1].product.name,'Nuovo');
 calls=[];fresh.db.garments[0].wash=2;responses=[conflict];await assert.rejects(()=>ctx.saveProductWithRevisionRetry(payload,original),/PRODUCT_CHANGED_DURING_EDIT/);assert.equal(calls.length,1);
 calls=[];responses=[conflict,{data:{saved_id:'NEW'}}];assert.equal((await ctx.saveProductWithRevisionRetry({revision:1,original_id:null,product:{}},null)).saved_id,'NEW');
 calls=[];responses=[{error:{message:'BARCODE_ALREADY_EXISTS'}}];await assert.rejects(()=>ctx.saveProductWithRevisionRetry(payload,original),/BARCODE_ALREADY_EXISTS/);assert.equal(calls.length,1);
 fresh.db.garments=[original];calls=[];responses=[conflict,conflict,conflict];await assert.rejects(()=>ctx.saveProductWithRevisionRetry(payload,original),/PRODUCT_SAVE_BUSY/);assert.equal(calls.length,3);
 assert(s.includes('form.productSaveRevision=cloudRevision'));assert(s.includes('revision:form.productSaveRevision??cloudRevision'));
 console.log('PASS unrelated revision retry, stable comparison, changed garment blocked, new product, barcode errors, bounded retries, original form revision');
})().catch(e=>{console.error(e);process.exitCode=1});
