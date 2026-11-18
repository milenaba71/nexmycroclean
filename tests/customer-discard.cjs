const fs=require('fs'),vm=require('vm'),assert=require('node:assert/strict');
const source=fs.readFileSync('discard.js','utf8'),ctx={arg:JSON.stringify};vm.createContext(ctx);
vm.runInContext(source.slice(source.indexOf('const customerDiscardNote=')),ctx);
const row={code:'A',state:'Entrato',notes:'Tasca danneggiata',washBatchId:'W',washed:true};
for(const rental of [true,null,undefined]){
 assert.throws(()=>ctx.setCustomerDiscardReturn(row,{rental},true),/proprietà/);
 assert(ctx.customerDiscardOption(row,{rental},true).includes('disabled'));
}
ctx.setCustomerDiscardReturn(row,{rental:false},true);
assert.equal(row.notes,'Tasca danneggiata\nSCARTO · Da restituire al cliente');
assert.equal(row.state,'Entrato');assert.equal(row.discard,undefined);assert.equal(row.verify,undefined);
ctx.setCustomerDiscardReturn(row,{rental:false},true);assert.equal(row.notes.split('SCARTO').length,2);
assert(!ctx.customerDiscardOption(row,{rental:false},true).includes('disabled'));
assert(ctx.customerDiscardOption(row,{rental:false},false).includes('disabled'));
const flow=fs.readFileSync('lot-workflow.js','utf8');vm.runInContext(flow.match(/^function lotReady\(r\).*$/m)[0],ctx);
assert.equal(!!ctx.lotReady(row),false);row.completed=true;row.foldedAt='2026-11-18T20:00:00Z';assert.equal(!!ctx.lotReady(row),true);
row.repair=true;assert.equal(!!ctx.lotReady(row),false);row.repair=false;
ctx.setCustomerDiscardReturn(row,{rental:false},false);assert.equal(row.notes,'Tasca danneggiata');
row.notes='x'.repeat(2000);assert.throws(()=>ctx.setCustomerDiscardReturn(row,{rental:false},true),/lunghe/);assert.equal(row.discardForReturn,false);
console.log('PASS customer-only discard, notes retained/idempotent, no retirement, folding readiness, other interventions preserved');
