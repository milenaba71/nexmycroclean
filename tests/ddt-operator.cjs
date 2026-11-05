const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict'),path=require('node:path');
const source=fs.readFileSync(path.join(__dirname,'../operator-view.js'),'utf8');
let opened=0,blocked=false;
const ctx={F:{},window:{DdtReturns:{}},DdtReturns:{view:()=>opened++},busy:()=>blocked,notify:()=>{},setMode:on=>ctx.F.active=on,current:{},page:''};vm.createContext(ctx);
vm.runInContext(source.match(/F.ddt=function\(\)\{[^\n]+/)[0],ctx);ctx.F.ddt();assert.equal(opened,1);assert.equal(ctx.page,'DDT fornitori · Airtable');assert.equal(ctx.current,null);assert.equal(ctx.F.screen,'ddt');blocked=true;ctx.F.ddt();assert.equal(opened,1);
const ddt=fs.readFileSync(path.join(__dirname,'../ddt-returns.js'),'utf8');let nodes=[{textContent:'Lotti'},{textContent:'Utenti'}];
const nav={children:nodes,insertBefore:(b,u)=>nodes.splice(u?nodes.indexOf(u):nodes.length,0,b)};
const c={window:{floor:{active:false}},render:()=>{},cloudUser:{},page:'Lotti',current:null,esc:String,$:s=>s==='#nav'?nav:s==='#ddtNav'?nodes.find(n=>n.id==='ddtNav'):null,document:{createElement:()=>({classList:{toggle(){}}})}};vm.createContext(c);vm.runInContext(ddt,c);c.render();assert.equal(nodes.at(-1).textContent,'Utenti');assert.equal(nodes.at(-2).id,'ddtNav');c.render();assert.equal(nodes.length,3);console.log('PASS: operator DDT route, busy guard, office Users last, no duplicate menu');
