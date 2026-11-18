const fs=require('fs'),vm=require('vm'),assert=require('node:assert/strict');
const {JSDOM}=require('/tmp/chat-dom-tests/node_modules/jsdom');
const dom=new JSDOM('<dialog id="modal"></dialog>',{url:'https://example.test'}),doc=dom.window.document;
doc.querySelector('dialog').close=function(){this.dispatchEvent(new dom.window.Event('close'))};
const src=fs.readFileSync('lot-workflow.js','utf8');
const ctx={sessionStorage:dom.window.sessionStorage,$:s=>doc.querySelector(s),show:html=>doc.querySelector('dialog').innerHTML=html,esc:x=>x,notify(){},catalogRows:()=>[{id:'T',name:'Tuta',active:true}],cloudUser:{email:'test'},resolveBarcode:x=>x,current:{id:1,rows:[]},stage:'Entrata',db:{garments:[]},cloudAccept(){}};vm.createContext(ctx);
vm.runInContext(src.slice(src.indexOf('function chooseNewLotProductType('),src.indexOf('async function retryPendingLotType(')),ctx);
(async()=>{
for(const [owner,expected] of [['client',false],['rental',true]]){
 const p=ctx.chooseNewLotProductType('NEW');
 const type=ctx.$('#newLotProductType'),ownership=ctx.$('#newLotProductOwnership'),button=ctx.$('#confirmNewLotProduct');
 assert(button.disabled);type.value='T';type.onchange();assert(button.disabled);
 ownership.value=owner;ownership.onchange();assert(!button.disabled);button.click();
 const choice=await p;assert.equal(choice.typeId,'T');assert.equal(choice.rental,expected);
}
const cancel=ctx.chooseNewLotProductType('CANCEL');ctx.$('#cancelNewLotProduct').click();assert.equal(await cancel,null);
let calls=[],fail=true;
ctx.chooseNewLotProductType=async()=>({typeId:'T',rental:false});
ctx.lotAtomicRequest=async(action,payload)=>{
 calls.push([action,payload]);
 if(action==='lot_acquire'){ctx.current.rows.push({code:'NEW'});ctx.db.garments.push({id:'NEW',type:'Da definire',rental:null})}
 else {if(fail){fail=false;throw Error('network')};Object.assign(ctx.db.garments[0],{type:'Tuta',rental:payload.rental})}
 return {};
};ctx.cloudRequest=async()=>({});
await assert.rejects(ctx.acquireLotProductWithType(1,'NEW',{id:'P'}),/proprietà ancora da completare/);
assert.equal(ctx.pendingTypeFor(1,'NEW').rental,false);
await ctx.acquireLotProductWithType(1,'NEW',{id:'P'});
assert.equal(calls.filter(([a])=>a==='lot_acquire').length,1);
assert.equal(ctx.db.garments[0].rental,false);assert(!ctx.pendingTypeFor(1,'NEW'));
console.log('PASS required type + ownership, explicit confirm, cancel, ownership persisted on retry without duplicate entry');
})().catch(e=>{console.error(e);process.exit(1)});
