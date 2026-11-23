const fs=require('fs'),vm=require('vm'),assert=require('node:assert/strict');
(async()=>{let reads=0;const c={current:{id:42},stage:'Uscita',page:'Lotti',washPollBusy:false,washBusy:false,washLoading:false,dryBusy:false,cloudUser:{},cloudBusy:false,cloudQueue:[],lotBusy:()=>false,$:()=>({open:false}),document:{hidden:false,querySelectorAll:()=>[]},washState:{batches:[]},dryState:{carts:[]},washRpc:async()=>reads++,dryRpc:async()=>reads++,washSyncChoices:()=>{},washMessage:String};vm.createContext(c);
for(const [file,fn,end] of [['wash-batches.js','washPoll','async function washApplyUpdates'],['dryer-phase.js','dryPoll','setInterval']]){const s=fs.readFileSync(file,'utf8'),start=s.indexOf('async function '+fn+'()');vm.runInContext(s.slice(start,s.indexOf(end,start)),c);}
for(let i=0;i<130;i++){await c.washPoll();await c.dryPoll();}assert.equal(reads,0);
c.stage='Lavorazione';for(let i=0;i<130;i++){await c.washPoll();await c.dryPoll();}assert.equal(reads,0);
c.stage='Entrata';await c.washPoll();await c.dryPoll();assert.equal(reads,2);
c.current=null;c.page='Produzione';await c.washPoll();await c.dryPoll();assert.equal(reads,4);
console.log('PASS: 130 exit and 130 folding polling cycles make zero machine requests; entry and production retain polling');})().catch(e=>{console.error(e);process.exit(1)});
