const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict'),path=require('node:path');
const src=fs.readFileSync(path.join(__dirname,'../lot-workflow.js'),'utf8');
const row={code:'P1',state:'Entrato'},events=[];const ctx={current:{rows:[row]},db:{garments:[{id:'P1'}]},lotMutationAllowed:()=>true,renderLotRows(){},productIsDiscard:g=>!!g?.discard,notify(){},log:(a,c)=>events.push([a,c]),detail(){}};vm.createContext(ctx);
vm.runInContext(src.slice(src.indexOf('function setRegisteredFlag('),src.indexOf('const lotFlagBeforeWorkflow')),ctx);
ctx.setRegisteredFlag('P1','discardReview',true);assert.equal(row.verify,true);assert.equal(row.discardReview,true);assert.equal(row.discard,undefined);assert(events[0][0].includes('Scarto da verificare'));
ctx.setRegisteredFlag('P1','discardReview',false);assert.equal(row.discardReview,false);assert.equal(row.verify,true); // Do not silently cancel a separate verification.
ctx.setRegisteredFlag('P1','replacement',true);assert.equal(row.replacement,true);
row.state='Dismesso';ctx.setRegisteredFlag('P1','discardReview',true);assert.equal(row.discardReview,false);
row.state='Uscito';ctx.setRegisteredFlag('P1','discardReview',true);assert.equal(row.discardReview,false);
row.state='Entrato';row.discardReview=true;ctx.db.garments[0].discard=true;ctx.setRegisteredFlag('P1','discardReview',false);assert.equal(row.discardReview,true);
const rendering=src.slice(src.indexOf('function renderLotRows('),src.indexOf('\n',src.indexOf('function renderLotRows(')));
assert(rendering.includes("['discardReview','Scarto da verificare']"));assert(rendering.includes('repairDiscardPending(r)'));
const asset=fs.readFileSync(path.join(__dirname,'../garment-lifecycle.js'),'utf8');assert(asset.includes("r.state!=='Uscito'&&userCan('products_manage')"));assert(asset.includes("b.textContent='Valuta scarto / sostituzione'"));
console.log('PASS: review flag requests verification without disposal, removal preserves verification, completed rows protected, product discard enforced, office action permission-gated');
