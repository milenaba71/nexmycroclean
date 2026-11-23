const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const s=fs.readFileSync('operator-view.js','utf8');
const alerts=[];let oldCalls=0;
const ctx={F:{active:true,screen:'lot',phase:'fold'},stage:'Lavorazione',current:{id:1,rows:[]},db:{garments:[]},productIsDiscard:g=>g.raw?.SCARTO==='SI',warningCheck:async()=>null,checkedProcess:async()=>{oldCalls++;return null},updatePhaseProgress:()=>{},acknowledge:async(...args)=>alerts.push(args)};
vm.createContext(ctx);
vm.runInContext(s.slice(s.indexOf('const foldDiscardMessage='),s.indexOf('function acknowledge(')),ctx);
vm.runInContext(s.split('\n').find(l=>l.startsWith('const oldWarning=')),ctx);
vm.runInContext(s.split('\n').find(l=>l.startsWith('const oldChecked=')),ctx);
(async()=>{
 ctx.db.garments=[{id:'A',raw:{SCARTO:'SI'}}];ctx.current.rows=[{code:'A',discard:true}];
 assert.equal(await ctx.warningCheck('A'),'DEVI IMBUSTARE CON SACCHETTO BOLLO ROSSO');assert.equal(alerts[0][0],'ATTENZIONE SCARTO');
 ctx.current.rows=[{code:'A',discardReview:true,verify:true}];await ctx.warningCheck('A');assert.equal(alerts.at(-1)[0],'ATTENZIONE SCARTO');
 ctx.current.rows=[{code:'A',discardForReturn:true}];alerts.length=0;
 assert.equal(await ctx.checkedProcess('A'),null);assert.equal(oldCalls,1);assert.equal(alerts.length,1);assert.equal(alerts[0][0],'ATTENZIONE SCARTO');assert.equal(alerts[0][4],true);
 ctx.stage='Uscita';alerts.length=0;await ctx.checkedProcess('A');assert.equal(alerts.length,0);
 ctx.stage='Lavorazione';ctx.current.rows=[{code:'A'}];ctx.db.garments=[{id:'A'}];await ctx.checkedProcess('A');assert.equal(alerts.length,0);assert.equal(ctx.F.feedback,null);
 console.log('PASS: discard warning, customer return confirmation, normal garments and exit unchanged');
})().catch(e=>{console.error(e);process.exitCode=1});
