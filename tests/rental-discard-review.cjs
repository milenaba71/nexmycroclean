const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const source=fs.readFileSync('operator-view.js','utf8');
async function check(initialRental,refreshedRental,value=true){
 const row={code:'A',state:'Entrato'},g={id:'A',rental:initialRental},events=[],messages=[];
 let flushes=0;
 const c={current:{id:1,rows:[row]},db:{garments:[g]},F:{flags(){}},flagLabels:{discardReview:'Scarto da verificare'},userCan:()=>true,busy:()=>false,$:()=>({querySelectorAll:()=>[],textContent:''}),cloudFlush:async()=>{flushes++},cloudRequest:async()=>({}),cloudAccept:()=>{g.rental=refreshedRental},log:(...args)=>events.push(args),detail(){},notify:x=>messages.push(x),cloudStopped:false};
 vm.createContext(c);vm.runInContext(source.slice(source.indexOf('F.flag=async'),source.indexOf('const examples=')),c);
 await c.F.flag('A','discardReview',value);
 assert.equal(c.F.flagSaving,false);
 if(refreshedRental===true||!value){assert.equal(row.discardReview,value);assert.equal(row.verify,value?true:undefined);assert.equal(events.length,1);assert.equal(flushes,2)}
 else{assert.equal(row.discardReview,undefined);assert.equal(row.verify,undefined);assert.equal(events.length,0);assert.equal(flushes,1);assert(messages.some(x=>x.includes('solo per i capi a noleggio')))}
}
(async()=>{
 for(const rental of [true,false,null,undefined])await check(rental,rental);
 await check(true,false); // Ownership can change while the signals dialog is open.
 await check(false,true);
 await check(false,false,false); // Existing reviews may still be removed, never silently cleared.
 console.log('PASS: floor review writes enforce refreshed rental ownership without changing other signals');
})().catch(e=>{console.error(e);process.exitCode=1});
