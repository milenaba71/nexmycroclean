const fs=require('fs'),vm=require('vm'),assert=require('node:assert/strict');
const source=fs.readFileSync('operator-view.js','utf8'),alerts=[],ctx={db:{garments:[]},current:{id:10,rows:[]},stage:'Entrata',F:{active:true,screen:'lot',phase:'entry'},productIsDiscard:g=>g?.raw?.SCARTO==='SI',productCodeLink:x=>x,esc:x=>String(x),lotRowStatus:()=> 'In lavorazione',repairDiscardPending:r=>!!r?.discard,warningCheck:async function(code){const g=ctx.db.garments.find(x=>x.id===code);return await ctx.timedProductAlert('Attenzione prodotto',['Prodotto segnato come SCARTO.',`Limite lavaggi RAGGIUNTO O SUPERATO: ${g?.wash} lavaggi eseguiti, massimo ${g?.max}.`,...(g?.allergic?['ALLERGICO']:[])],5,code)?null:'Operazione annullata.'},checkedProcess:async function(code){return ctx.warningCheck(code)},timedProductAlert:async()=>false,updatePhaseProgress(){},acknowledge:async(...args)=>alerts.push(args)};
vm.createContext(ctx);const discard=fs.readFileSync('discard.js','utf8');vm.runInContext(discard.slice(discard.indexOf('function productAtWashLimit'),discard.indexOf('function productIsDiscard')),ctx);
vm.runInContext(source.slice(source.indexOf('const foldDiscardMessage='),source.indexOf('function acknowledge(')),ctx);
vm.runInContext(source.slice(source.indexOf('const oldAlert='),source.indexOf('// Existing mismatch checks')),ctx);
for(const prefix of ['const oldWarning=','const oldChecked='])vm.runInContext(source.split('\n').find(l=>l.startsWith(prefix)),ctx);
vm.runInContext(source.slice(source.indexOf('const previousDiscardPending='),source.indexOf('function pendingFlags(')),ctx);
vm.runInContext(source.split('\n').find(l=>l.startsWith('function garmentLine(')),ctx);
(async()=>{
 for(const wash of [80,81,150])for(const rental of [false,true,null]){
  const g={id:'A',wash,max:80,rental,raw:{SCARTO:'SI'}},row={code:'A',discard:true,completed:false,state:'Entrato'};ctx.db.garments=[g];ctx.current.rows=[row];ctx.stage='Entrata';ctx.F.phase='entry';alerts.length=0;
  assert.equal(await ctx.checkedProcess('A'),null);assert.equal(alerts.length,0,'entry warning must not reject registration');
  assert.equal(ctx.repairDiscardPending(row),false);assert(ctx.lotRowStatus(row).includes('SCARTO'));assert(ctx.garmentLine(row).includes('Da restituire al cliente'));
  ctx.stage='Lavorazione';ctx.F.phase='fold';assert.equal(await ctx.checkedProcess('A'),null);assert.equal(alerts.length,1);assert.equal(alerts[0][0],'ATTENZIONE SCARTO');assert.equal(alerts[0][4],true,'red bag notice confirms registered folding');
  ctx.stage='Uscita';alerts.length=0;assert.equal(await ctx.checkedProcess('A'),null);assert.equal(alerts.length,0);
  for(const field of ['repair','relabel','verify','rewashPending','replacement'])assert.notEqual(ctx.asideFor({...row,[field]:true},g),null,field+' preserved');
  assert.equal(ctx.repairDiscardPending({...row,discardReview:true,verify:true}),true);
 }
 ctx.db.garments=[{id:'A',wash:79,max:80,raw:{SCARTO:'SI'}}];assert.notEqual(ctx.asideFor({code:'A',discard:true},ctx.db.garments[0]),null,'below-limit unrelated discard unchanged');
 ctx.db.garments[0]={id:'A',wash:81,max:80,allergic:true};ctx.stage='Entrata';assert.equal(await ctx.checkedProcess('A'),'Operazione annullata.');
 assert.equal(ctx.productAtWashLimit({wash:81,max:100}),false);assert.equal(ctx.productAtWashLimit({wash:101,max:100}),true);assert.equal(ctx.productAtWashLimit({wash:0,max:0}),false);
 console.log('PASS wash-limit UI: entry, registered folding/red bag, exit, ownership modes, independent holds, custom limits, persistent discard label');
})().catch(e=>{console.error(e);process.exit(1)});
