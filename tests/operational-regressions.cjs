const fs=require('fs'),vm=require('vm'),assert=require('assert');
const source=fs.readFileSync(require('path').join(__dirname,'../operator-view.js'),'utf8');
function between(text,start,end){const a=text.indexOf(start),b=text.indexOf(end,a);assert(a>=0&&b>a);return text.slice(a,b)}
// Execute actual operational filtering with completed rewash history.
let ctx={productIsDiscard:()=>false};vm.createContext(ctx);
vm.runInContext(between(source,'function asideFor(', 'function acknowledge('),ctx);
assert.equal(ctx.asideFor({rewash:true,rewashPending:false},{}),null);
assert.equal(ctx.asideFor({rewash:true,rewashPending:true},{})[0],'RILAVAGGIO');
assert.equal(ctx.asideFor({repair:true}, {})[0],'RIPARAZIONI');
// The new colleague sees a manually transferred pending task before replanning.
let rendered=[];
Object.assign(ctx,{prod:{tasks:[{id:'t',status:'pending',assignee:'new'}],plan:{allocations:[{taskId:'t',email:'old'}]}},cloudUser:{email:'new'},pTaskPriorityOrder:()=>0,pTaskCard:t=>{rendered.push(t.id);return ''},shell:()=>{},document:{querySelectorAll:()=>[]}});
vm.runInContext(between(source,'function drawWork(){','F.repairLot='),ctx);
ctx.drawWork();assert.deepEqual(rendered,['t']);
rendered=[];ctx.cloudUser.email='old';ctx.drawWork();assert.deepEqual(rendered,[]);
// A missing submitter must neither block submission nor leave the global lock set.
const prodSource=fs.readFileSync(require('path').join(__dirname,'../production.js'),'utf8');
let submit,closed=0,drawn=0,messages=[],fail=false;
const form={id:'productionForm',dataset:{kind:'handoff',id:'t'},querySelector:()=>null};
ctx={document:{addEventListener:(_,f)=>submit=f},prodBusy:false,prod:{},prodRevision:1,clone:x=>x,FormData:class {get(){return 'x'}},pNumber:()=>5,pRpc:async()=>{if(fail)throw Error('save rejected')},pDraw:()=>drawn++,notify:x=>messages.push(x),pError:e=>e.message,$:sel=>sel==='#modal'?{close:()=>closed++}:null};
vm.createContext(ctx);
vm.runInContext(between(prodSource,"document.addEventListener('submit',","async function pAction("),ctx);
(async()=>{
 await submit({target:form,submitter:null,preventDefault(){}});
 assert.equal(ctx.prodBusy,false);assert.equal(closed,1);assert.equal(drawn,1);assert.match(messages[0],/Passaggio salvato/);
 fail=true;await submit({target:form,submitter:null,preventDefault(){}});
 assert.equal(ctx.prodBusy,false);assert.equal(closed,1);assert.equal(messages.at(-1),'save rejected');
 console.log('PASS: retained rewash history, transferred task visibility, submit without button, failed-save recovery');
})().catch(e=>{console.error(e);process.exitCode=1});
// Detail links must retain the operational destination and correct phase.
let calls=[];
const nav={F:{active:true,repairLot:id=>calls.push(['repair',id]),machines:()=>calls.push(['machines']),openLot:(id,phase)=>calls.push([phase,id])},pAction:async()=>{},$:()=>({close(){}}),prod:{tasks:[{id:'dry',typeId:'dryer'},{id:'exit',typeId:'out'},{id:'entry',typeId:'entry'}]},pType:id=>({station:id,mode:id==='dryer'?'machine':'piece'}),pStationKind:x=>x};
vm.createContext(nav);vm.runInContext(between(source,'const floorProductionAction=pAction;','const floorOldPDraw=pDraw;'),nav);
(async()=>{
 await nav.pAction('taskDetail','dry');await nav.pAction('lot','1');
 await nav.pAction('taskDetail','exit');await nav.pAction('lot','2');
 await nav.pAction('taskDetail','entry');await nav.pAction('lot','3');
 await nav.pAction('repairLot','4');
 assert.deepEqual(calls,[['machines'],['out',2],['entry',3],['repair',4]]);
 console.log('PASS: operational detail links for machines, exit, entry and repairs');
})().catch(e=>{console.error(e);process.exitCode=1});
