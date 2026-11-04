const fs=require('fs'),vm=require('vm'),assert=require('node:assert/strict'),path=require('path');
const root=path.resolve(__dirname,'..');
const read=n=>fs.readFileSync(path.join(root,n),'utf8');
const ctx={console,document:{head:{insertAdjacentHTML(){}}},detail(){},esc:v=>String(v??'').replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;').replaceAll('"','&quot;'),db:{garments:[{id:'P1',type:'TUTA',name:'Operatore',size:'L',dept:'Reparto'}],repairs:[]},lotno:l=>'L.'+l.id,repairDate:v=>v,repairCall:(id,code)=>id+',"'+code+'"',lotReady:()=>true};ctx.window=ctx;vm.createContext(ctx);
vm.runInContext(fs.readFileSync(path.join(root,'lot-summary.js'),'utf8'),ctx);
const costs=fs.readFileSync(path.join(root,'repair-costs.js'),'utf8');vm.runInContext(costs.slice(costs.indexOf('function euro3'),costs.indexOf('function repairTypesView')),ctx);
vm.runInContext('const baseSummary=lotTypeSummary;lotTypeSummary=lot=>baseSummary(lot)+repairTotalsPanel(lot)',ctx);
vm.runInContext(read('sewing-details.js'),ctx);vm.runInContext(read('lot-summary-print.js'),ctx);
const lot={id:7,client:'Cliente',date:'04/11/2026',events:[],rows:[{code:'P1',state:'Uscito',notes:'NOTA LOTTO <test>',repairWork:[{name:'Toppa',kind:'repair',unit:'piece',quantity:2,minutesHundredths:500,priceMills:1250,costMills:2500,completedBy:'Anna',notes:'NOTA INTERVENTO <test>'}]}]};
const before=JSON.stringify(lot),yes=ctx.lotSummaryPrintHtml(lot,true),no=ctx.lotSummaryPrintHtml(lot,false);
assert(yes.includes('NOTA LOTTO &lt;test&gt;'));assert(yes.includes('NOTA INTERVENTO &lt;test&gt;'));
assert(!no.includes('NOTA LOTTO'));assert(!no.includes('NOTA INTERVENTO'));assert(!no.includes('<th class="report-note">'));
for(const html of [yes,no]){for(const text of ['Toppa','Anna','2,500 €','lot-summary-products','lot-summary-sewing','sewing-products','sewing-details'])assert(html.includes(text),text);}
assert.equal(JSON.stringify(lot),before);assert(ctx.lotTypeSummary(lot).includes('printLotSummary(7,false)'));assert(ctx.lotTypeSummary(lot).includes('printLotSummary(7,true)'));
assert(ctx.lotSummaryPrintHtml({...lot,rows:[]},false).includes('Registra i primi prodotti'));
console.log('PASS: notes omitted from HTML, totals and operators retained, four section colors, escaped text, no data mutation, empty lot');
