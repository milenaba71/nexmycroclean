const fs=require('fs'),vm=require('vm'),assert=require('node:assert/strict');
const source=fs.readFileSync('operator-view.js','utf8');
let moves=0,focusCalls=0,frames=[],scrolls=[];
const body={},input={value:'NEXT-PARTIAL',disabled:false,readOnly:false,focus(options){assert.equal(options.preventScroll,true);ctx.document.activeElement=this;focusCalls++}};
const route={classList:{add(){}},querySelector(){return {}},after(node){moves++;this.nextElementSibling=node;ctx.document.activeElement=body}};
const summary={after(node){moves++;this.nextElementSibling=node;ctx.document.activeElement=body}};
const section={querySelector(){return {textContent:''}},querySelectorAll(){return []},closest(){return panel}};
const panel={firstElementChild:route,prepend(node){moves++;this.firstElementChild=node;ctx.document.activeElement=body}};
route.nextElementSibling=summary;summary.nextElementSibling=section;input.closest=()=>section;
const modal={open:false};
const ctx={F:{active:true,screen:'lot',phase:'entry',stopped:false,entryReady:()=>true},current:{id:56},window:{scrollTo:p=>scrolls.push(p)},document:{body,activeElement:input},requestAnimationFrame:f=>frames.push(f),userCan:()=>true,$:id=>({'#scan':input,'#modal':modal,'#floorLotSummary':summary,'#entryProcessing':{closest:()=>route}}[id]),scanWasFocused:true,scanLot:56,scanPhase:'entry',scanX:0,scanY:620};
vm.createContext(ctx);
vm.runInContext(source.slice(source.indexOf('F.entryOrder=function()'),source.indexOf('\nfunction entryTypeCounts')),ctx);
// Refreshing an already arranged entry must never detach the active scanner.
for(let n=0;n<130;n++)ctx.F.entryOrder();
assert.equal(moves,0);assert.equal(ctx.document.activeElement,input);assert.equal(input.value,'NEXT-PARTIAL');
const start=source.indexOf(' if(scanWasFocused){',source.indexOf('F.decorate=function()'));
const restoration=source.slice(start,source.indexOf('\n};',start));
// A first layout can detach the scanner; restore focus and scrolling immediately and after layout.
ctx.document.activeElement=body;vm.runInContext(restoration,ctx);
assert.equal(ctx.document.activeElement,input);assert.equal(scrolls.at(-1).top,620);frames.shift()();assert.equal(input.value,'NEXT-PARTIAL');
function deferred(change){frames=[];ctx.document.activeElement=input;vm.runInContext(restoration,ctx);const before=focusCalls,scrollBefore=scrolls.length;change();frames.shift()();assert.equal(focusCalls,before);assert.equal(scrolls.length,scrollBefore)}
// Never pull focus from a dialog, an intentional edit, another lot or another phase.
deferred(()=>modal.open=true);modal.open=false;
deferred(()=>ctx.document.activeElement={id:'notes'});
deferred(()=>ctx.current={id:57});ctx.current={id:56};
deferred(()=>ctx.F.phase='out');ctx.F.phase='entry';
deferred(()=>ctx.F.stopped=true);ctx.F.stopped=false;
deferred(()=>input.disabled=true);input.disabled=false;
console.log('PASS: 130 stable entry layouts, scanner focus/partial barcode and viewport retained; dialogs, edits, navigation and disabled scanning respected');
