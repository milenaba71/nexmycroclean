const fs=require('fs'),vm=require('vm'),assert=require('node:assert/strict');
const source=fs.readFileSync(require('path').join(__dirname,'../operator-view.js'),'utf8');
const loads=fs.readFileSync(require('path').join(__dirname,'../wash-loads.js'),'utf8');
const batches=[
 {id:'partial-dry',lot_id:45,machine_kind:'dry',state:'gathering',quantity:20},
 {id:'water-a',machine_kind:'water',state:'ready',quantity:10,load_group_id:'mixed'},
 {id:'water-b',machine_kind:'water',state:'ready',quantity:15,load_group_id:'mixed'},
 {id:'decon',machine_kind:'decon',state:'blocked',quantity:30},
 {id:'running',machine_kind:'water',state:'running',quantity:20},
 {id:'empty',machine_kind:'dry',state:'gathering',quantity:0},
 {id:'finished',machine_kind:'water',state:'done',quantity:20}
];
const ctx={washState:{batches}};vm.createContext(ctx);
vm.runInContext(loads.match(/^function washDistinctLoads[^\n]+/m)[0],ctx);
vm.runInContext(source.match(/^function activeWashCarts[^\n]+/m)[0],ctx);
assert.equal(ctx.activeWashCarts().length,4);
assert.equal(ctx.activeWashCarts().filter(b=>b.state!=='running').length,3);
assert.equal(ctx.activeWashCarts('water').length,2);
assert(ctx.activeWashCarts().some(b=>b.lot_id===45));
let html='';
Object.assign(ctx,{prod:{machines:[]},dryState:{carts:[]},shell:value=>html=value,washCard:b=>'<article>'+b.id+'</article>',dryActive:()=>false,dryCard:()=>'',F:{error:'',machineDepartment:'dry'},button:()=>'',userCan:()=>true,document:{querySelectorAll:()=>[]}});
vm.runInContext(source.slice(source.indexOf('function drawMachines(){'),source.indexOf('const oldWashRefresh=')),ctx);ctx.drawMachines();
assert(html.includes('<article>partial-dry</article>'));
assert(!html.includes('<article>empty</article>'));
assert(!html.includes('<article>finished</article>'));
assert(source.includes("['wash','2','Lavaggio','carrelli in attesa','floor.machines()']"));
console.log('PASS: partial carts visible, finished and empty excluded, mixed loads counted once, Lavaggio opens all kinds');

assert(!html.includes('<article>water-a</article>'));
assert(!html.includes('<article>decon</article>'));
ctx.F.machineDepartment='water';ctx.drawMachines();
assert(html.includes('<article>water-a</article>'));
assert(!html.includes('<article>partial-dry</article>'));
assert(!html.includes('<article>water-b</article>'));
ctx.F.machineDepartment='decon';ctx.drawMachines();
assert(html.includes('<article>decon</article>'));
assert(!html.includes('<article>partial-dry</article>'));
ctx.F.machineDepartment=null;ctx.drawMachines();
assert.equal((html.match(/data-wash-department=/g)||[]).length,3);
for(const title of ['Rep Acqua','Rep Dec','Rep Secco'])assert(html.includes(title));
assert(!html.includes('<article>'));
console.log('PASS: three department tiles; dry, water and decontamination carts separated by assigned kind');
