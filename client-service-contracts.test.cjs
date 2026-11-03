const fs=require('fs'),vm=require('vm'),assert=require('node:assert/strict');
let permitted=true,saves=0,closed=0,fail=false;
const c={id:'C1',name:'Cliente senza noleggio',notes:'Note originali',rentalContracts:[{number:'R1'}]};
const box={},form={dataset:{},querySelectorAll:()=>[],querySelector:()=>box};
const ctx={document:{addEventListener(){}},userCan:()=>permitted,ensureClients:()=>[c],esc:s=>String(s??'').replace(/</g,'&lt;').replace(/>/g,'&gt;'),lotDate:s=>s||'—',cloudFlush:async()=>{if(fail)throw Error('offline')},save:()=>saves++,$:()=>({close:()=>closed++}),drawClientProfile:async()=>{},notify:()=>{}};
vm.createContext(ctx);vm.runInContext(fs.readFileSync(__dirname+'/client-service-contracts.js','utf8'),ctx);
(async()=>{
assert(ctx.clientServiceSections(c).includes('Nuovo contratto di servizio'));
assert.throws(()=>ctx.validateServiceContract({title:'',status:'active'},[]));
assert.throws(()=>ctx.validateServiceContract({title:'Lavaggio',status:'active',start:'2026-12-01',end:'2026-01-01'},[]));
assert.throws(()=>ctx.validateServiceContract({title:'Lavaggio',status:'active',number:'abc'},[{id:'k1',number:'ABC'}]));
await ctx.saveClientService(form,'C1','serviceContracts','[]',()=>[{id:'k1',title:'Lavaggio',status:'active',notes:'<script>test</script>'}]);
assert.equal(saves,1);assert.equal(closed,1);assert.equal(c.rentalContracts[0].number,'R1');assert.equal(c.notes,'Note originali');assert(!ctx.serviceContractRows(c).includes('<script>'));
await ctx.saveClientService(form,'C1','serviceNeeds','""',()=> 'Consegne separate');assert.equal(c.serviceNeeds,'Consegne separate');
permitted=false;await ctx.saveClientService(form,'C1','serviceNeeds',JSON.stringify(c.serviceNeeds),()=> 'vietato');assert.equal(c.serviceNeeds,'Consegne separate');assert(!ctx.clientServiceSections(c).includes('data-service-new'));
permitted=true;await ctx.saveClientService(form,'C1','serviceNeeds','"stale"',()=> 'conflitto');assert.equal(c.serviceNeeds,'Consegne separate');
fail=true;await ctx.saveClientService(form,'C1','serviceNeeds',JSON.stringify(c.serviceNeeds),()=> 'offline');assert.equal(c.serviceNeeds,'Consegne separate');assert.equal(closed,2);
console.log('PASS: non-rental client, creation, existing fields preserved, notes, validation, permission, concurrency and save errors');
})();
