const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const custody=fs.readFileSync('missing-returns.js','utf8').split('\n').find(l=>l.startsWith('const checkedProcessBeforeCustody='));
const mismatch=fs.readFileSync('lot-mismatch-alert.js','utf8');
(async()=>{
 let revision=1,reads=0,processed=0,status='active';
 const ctx={stage:'Entrata',cloudRevision:1,current:{id:56,rows:[]},db:{garments:[{id:'A'}]},cloudFlush:async()=>{},cloudRequest:async action=>{if(action==='version')return {revision};reads++;return {revision}},cloudAccept:r=>{ctx.cloudRevision=r.revision},resolveBarcode:x=>x,custodyFind:()=>({}),custodyStatus:()=>status,custodyLabel:()=>status,timedProductAlert:async()=>{},checkedProcess:async()=>{processed++;return null},lotMismatchInfo:()=>null,showLotMismatch:async()=>{}};
 vm.createContext(ctx);vm.runInContext(custody,ctx);
 vm.runInContext(mismatch.slice(mismatch.indexOf('const checkedBeforeLotMismatch='),mismatch.indexOf('const lotMismatchStyle=')),ctx);
 for(let i=0;i<120;i++)assert.equal(await ctx.checkedProcess('A'),null);
 assert.equal(reads,0);assert.equal(processed,120);
 revision=2;await ctx.checkedProcess('A');assert.equal(reads,1);assert.equal(ctx.cloudRevision,2);
 status='returned';assert.match(await ctx.checkedProcess('A'),/reso dal cliente/);assert.equal(processed,121);
 status='active';ctx.lotMismatchInfo=()=>({reason:'Altro cliente'});assert.equal(await ctx.checkedProcess('A'),'Altro cliente');assert.equal(processed,121);
 ctx.lotMismatchInfo=()=>null;ctx.db.garments=[];await ctx.checkedProcess('NEW');assert.equal(reads,2);
 ctx.stage='Lavorazione';ctx.current.rows=[{code:'A'}];ctx.db.garments=[{id:'A'}];const beforeFold=reads;for(let i=0;i<130;i++)assert.equal(await ctx.checkedProcess('A'),null);assert.equal(reads,beforeFold);revision++;await ctx.checkedProcess('A');assert.equal(reads,beforeFold+1);status='returned';assert.match(await ctx.checkedProcess('A'),/reso dal cliente/);
 console.log('PASS folding: 130 scans without full reload, remote changes refreshed and returned products blocked;  120 scans without full pre-scan reload, changed revision refreshed, returned/wrong-client blocked, unknown code refreshed');
})().catch(e=>{console.error(e);process.exitCode=1});
