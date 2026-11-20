const fs=require('fs'),vm=require('vm'),assert=require('node:assert/strict');
const {JSDOM}=require(process.env.JSDOM_PATH||'jsdom');
const doc=new JSDOM('<main id="app"></main>').window.document;
const s=fs.readFileSync('operator-view.js','utf8');
const ctx={F:{},document:doc,prod:{machines:[]},dryState:{carts:[]},dryActive:()=>true,cartDeliveryOrder:()=>0,esc:String,attr:String,lotSearchText:v=>String(v).toLowerCase(),waterCartSearch:ids=>ids.join(' '),WashLoads:{card:b=>'<article>'+b.id+'</article>',toolbar:()=>'<div>Seleziona</div>'},washLoadMembers:b=>[b],activeWashCarts:kind=>[{id:kind,lot_id:56,state:'ready'}],button:()=>'',userCan:()=>true,shell:html=>doc.getElementById('app').innerHTML=html};vm.createContext(ctx);
vm.runInContext(s.slice(s.indexOf('F.filterWater=function'),s.indexOf('function drawWater(){')),ctx);
vm.runInContext(s.slice(s.indexOf('function drawMachines(){'),s.indexOf('const oldWashRefresh=')),ctx);
ctx.drawMachines();assert(!doc.querySelector('#waterLotSearch'));
for(const kind of ['water','decon','dry']){ctx.F.machineDepartment=kind;ctx.drawMachines();assert(doc.querySelector('#waterLotSearch'));assert(doc.querySelector('.water-queue article').textContent===kind);ctx.F.filterWater('999');assert(doc.querySelector('[data-water-search]').hidden);ctx.F.filterWater('56');assert(!doc.querySelector('[data-water-search]').hidden)}
console.log('PASS: overview and all three departments render compact searchable queues');
