const fs=require('fs'),vm=require('vm'),assert=require('node:assert/strict');
const PC=require('../production-core.js');
const source=fs.readFileSync('production.js','utf8');
const fn=source.slice(source.indexOf('function pLotPlanWork('),source.indexOf('function pAssignedSheet('));
const context={db:{garments:[]},lotReady:r=>!!r.washed,productProcessingDepartment:()=> 'clean'};vm.createContext(context);vm.runInContext(fn,context);
const fold={id:'fold',name:'Piegatura',mode:'rate',value:75,setup:0,station:'clean',active:true};
function state(){return {types:[fold,{id:'exit',name:'Uscita',active:true,station:'out'},{id:'repair-unknown',name:'Cucito',active:true,station:'repair'}],stations:[],tasks:[],calendars:[]}}
const lot={id:42,rows:Array.from({length:121},(_,i)=>({code:'T'+i,state:'In lavorazione',washed:true,completed:false}))};
let result=context.pLotPlanWork(state(),[lot]);assert.equal(result.tasks[0].quantity,121);assert.equal(result.tasks[0].items.length,121);assert.equal(PC.estimate(fold,121).labor,97);
lot.rows.slice(0,111).forEach(r=>Object.assign(r,{completed:true,foldedAt:'2026-11-18'}));result=context.pLotPlanWork(state(),[lot]);assert.equal(result.tasks[0].quantity,10);assert.equal(result.blocked[0].quantity,111);assert.equal(PC.estimate(fold,10).labor,8);
const memc={id:48,rows:Array.from({length:163},(_,i)=>({code:'M'+i,state:'In lavorazione',washed:i<70,completed:i<62,foldedAt:i<62?'2026-11-18':null}))};
const done={id:41,rows:Array.from({length:167},(_,i)=>({code:'F'+i,state:'Uscito',washed:true,completed:true}))};
result=context.pLotPlanWork(state(),[lot,memc,done]);assert.equal(result.tasks.find(t=>t.items[0].lotId===48).quantity,8);assert.equal(result.blocked.filter(b=>b.lotId===48).reduce((n,b)=>n+b.quantity,0),155);assert(!result.tasks.some(t=>t.items[0].lotId===41));
for(const l of [lot,memc])assert.equal(result.tasks.filter(t=>t.items[0].lotId===l.id).reduce((n,t)=>n+t.quantity,0)+result.blocked.filter(b=>b.lotId===l.id).reduce((n,b)=>n+b.quantity,0),l.rows.length);
console.log('PASS: all 121/163 rows counted across lots, completed folding excluded, blocked items reconciled, dispatched lot excluded, 121=97 min and remaining 10=8 min at configured 75/hour');
