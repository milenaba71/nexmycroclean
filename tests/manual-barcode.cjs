const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict'),path=require('node:path');
const source=fs.readFileSync(path.join(__dirname,'../lot-workflow.js'),'utf8');
const start=source.indexOf('function bindAutoScanner('),end=source.indexOf('\nfunction ',start+1);
const calls=[],timers=[];const c={current:{id:1},stage:'Entrata',scanTimer:null,clearTimeout(){},setTimeout(fn){timers.push(fn)},enqueueBarcode:x=>calls.push(x)};vm.createContext(c);vm.runInContext(source.slice(start,end),c);
function input(){const listeners={};return {value:'',disabled:false,isConnected:true,addEventListener(k,fn){listeners[k]=fn},fire(k,e={}){listeners[k]?.({preventDefault(){},stopPropagation(){},...e})}}}
const i=input();c.bindAutoScanner(i);
for(const text of ['2','20','2026','2026ABC']){i.value=text;i.fire('input');for(const fn of timers.splice(0))fn();assert.equal(calls.length,0);assert.equal(i.value,text)}
i.fire('keydown',{key:'Enter',isComposing:true});assert.equal(calls.length,0);
i.fire('keydown',{key:'Enter'});assert.deepEqual(calls,['2026ABC']);assert.equal(i.value,'');
i.fire('keydown',{key:'Enter'});assert.equal(calls.length,1);
i.value='TAG2';i.fire('keydown',{key:'Tab'});assert.deepEqual(calls,['2026ABC','TAG2']);
i.value='TAG3';c.current={id:2};i.fire('keydown',{key:'Enter'});assert.equal(calls.length,2);assert.equal(i.value,'TAG3');
c.current={id:1};c.stage='Uscita';i.fire('keydown',{key:'Enter'});assert.equal(calls.length,2);
c.stage='Entrata';i.disabled=true;i.fire('keydown',{key:'Enter'});assert.equal(calls.length,2);
console.log('PASS: pauses never submit partial codes, Enter/Tab submit once, IME/empty/disabled/stale lot and phase guarded');
