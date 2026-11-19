const fs=require('fs'),vm=require('vm'),assert=require('node:assert/strict');
const s=fs.readFileSync('lot-workflow.js','utf8');
let frame,focused,scrolls=[];const input={value:'NEXT',focus:o=>focused=o};
const c={window:{scrollX:0,scrollY:640,scrollTo:o=>scrolls.push(o)},current:{id:1},stage:'Uscita',scanTimer:null,clearTimeout,requestAnimationFrame:f=>frame=f,detail:()=>{input.value=''},$:id=>id==='#scan'?input:{open:false},Event:class{},};input.dispatchEvent=()=>{};
vm.createContext(c);vm.runInContext(s.slice(s.indexOf('function redrawLotKeepingScan()'),s.indexOf('function redrawLotKeepingScan()')+s.slice(s.indexOf('function redrawLotKeepingScan()')).indexOf('\nasync function')),c);
c.redrawLotKeepingScan();assert.equal(input.value,'NEXT');assert.equal(focused.preventScroll,true);assert.equal(scrolls[0].top,640);frame();assert.equal(scrolls.length,2);
c.redrawLotKeepingScan();c.current={id:2};const n=scrolls.length;frame();assert.equal(scrolls.length,n);
console.log('PASS scanner viewport preserved; partial next code retained; navigation not pulled back');
