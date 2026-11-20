const fs=require('fs'),vm=require('vm'),assert=require('node:assert/strict');
const source=fs.readFileSync('wash-batches.js','utf8');
const start=source.indexOf('async function washUpdateSelectedRoute()');
(async()=>{
 let calls=[],messages=[];
 const c={current:{id:1},stage:'Entrata',washChoice:'plain:label',washBusy:false,cloudRevision:4,
 lotMutationAllowed:()=>true,selected:()=>['a','b'],washOptions:()=>[],ensureProcessing:()=>[{id:'label',active:true,wash:false,name:'Etichettare'}],notify:m=>messages.push(m),cloudFlush:async()=>{},washRpc:async(a,p)=>{calls.push([a,p]);return {routeUpdated:2}},cloudAccept:()=>{},detail:()=>{},washRender:()=>{},washMessage:e=>e.message};
 vm.createContext(c);vm.runInContext(source.slice(start),c);
 await c.washUpdateSelectedRoute();assert.equal(calls[0][0],'update_route');assert.deepEqual(Array.from(calls[0][1].codes),['a','b']);assert.equal(calls[0][1].processingId,'label');assert.equal(c.washBusy,false);
 calls=[];c.selected=()=>[];await c.washUpdateSelectedRoute();assert.equal(calls.length,0);
 c.selected=()=>['a'];c.washChoice='w|m';c.washOptions=()=>[{key:'w|m',t:{id:'w',name:'Acqua'},m:{id:'m'}}];await c.washUpdateSelectedRoute();assert.equal(calls[0][1].machineId,'m');assert.equal(calls[0][1].programId,'w');
 calls=[];c.washRpc=async()=>{throw Error('ROUTE_ALREADY_STARTED')};await c.washUpdateSelectedRoute();assert.match(messages.at(-1),/Nessun capo aggiornato/);assert.equal(c.washBusy,false);
 assert.match(source,/onclick="washUpdateSelectedRoute\(\)"/);assert.match(source,/onclick="washRefresh\(\)">Ricarica elenco/);
 console.log('PASS: Aggiorna sends selected codes and route; no selection is blocked; server errors preserve all-or-nothing feedback.');
})().catch(e=>{console.error(e);process.exit(1)});
