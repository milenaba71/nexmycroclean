/* Synthetic example only: no accounts, RPC calls or persisted business records. */
(function(root){
function example(date='2026-11-02',absent=false){const P=root.ProductionCore,s=P.initial();
function op(id,name,station,end){return {id,email:id,name,station,skills:[station],active:true,days:[1,2,3,4,5],start:'08:00',end,breaks:[{start:'10:00',minutes:15},{start:'12:00',minutes:station==='entry'?30:60},...(station==='entry'?[]:[{start:'15:00',minutes:15}])]}}
s.operators=[op('in','Operatore entrata','entry','14:00'),op('fold1','Piegatura 1','clean','16:00'),op('fold2','Piegatura 2','clean','16:00'),...[1,2,3,4].map(n=>op('repair'+n,'Riparazioni '+n,'repair','17:00')),op('out','Operatore uscita','out','17:00')];
if(absent)s.overrides=[{id:'absence',email:'fold2',date,absent:true}];
s.machines=s.machines.filter(m=>m.kind==='decon'||m.id==='dryer-1').map(m=>({...m,capacity:50,start:'08:00',end:'17:00'}));
s.types.push({id:'wash-demo',name:'Lavaggio',station:'entry',mode:'machine',value:30,operatorMinutes:5,setup:0,machineKind:'decon',active:true},{id:'dry-demo',name:'Asciugatura',station:'entry',mode:'machine',value:20,operatorMinutes:3,setup:0,machineKind:'dryer',active:true},{id:'repair-demo',name:'Riparazione',station:'repair',mode:'piece',value:6,setup:0,active:true});
for(let [i,deadline] of ['14:00','15:00','16:00'].entries()){let lot='DEMO-'+(i+1),due=date+'T'+deadline;function add(suffix,typeId,quantity,dependsOn=[]){let id=lot+'-'+suffix;s.tasks.push({id,title:lot+' · '+s.types.find(t=>t.id===typeId).name,typeId,quantity,dependsOn,due,releaseDate:date,status:'pending',items:[],sessions:[]});return id}
let incoming=add('entry','entry',50),wash=add('wash','wash-demo',50,[incoming]),dry=add('dry','dry-demo',50,[wash]),repairs=[1,2,3,4].map(n=>add('repair'+n,'repair-demo',1,[dry])),normal=add('fold','fold',46,[dry]),repaired=add('fold-repaired','fold',4,repairs);add('exit','exit',50,[normal,repaired]);}
s.plan=P.plan(s,date,1);return s}
root.productionExample=example;if(typeof module!=='undefined')module.exports=example;
if(typeof document==='undefined')return;
const esc=s=>String(s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
function render(){let s=example('2026-11-02',document.querySelector('#absence').checked),P=root.ProductionCore;document.querySelector('#summary').textContent=`150 prodotti · 3 lotti · ${s.plan.allocations.length}/${s.tasks.length} attività assegnate · ${s.plan.allocations.filter(a=>a.late).length} attività oltre consegna`;
document.querySelector('#loads').innerHTML=P.loadRows(s,'2026-11-02',1).map(r=>`<article><h3>${esc(s.operators.find(o=>o.email===r.email).name)}</h3><strong>${r.assigned} min</strong> / ${r.available} disponibili<progress max="${r.available||1}" value="${r.assigned}"></progress><small>${Math.max(0,r.available-r.assigned)} minuti liberi</small></article>`).join('');
document.querySelector('#tasks').innerHTML=s.plan.allocations.slice().sort((a,b)=>a.segments[0].start-b.segments[0].start).map(a=>{let t=s.tasks.find(t=>t.id===a.taskId);return `<tr><td>${esc(t.title)}<small>${t.quantity} prodotti · consegna ${t.due.slice(11)}</small></td><td>${esc(s.operators.find(o=>o.email===a.email).name)}</td><td>${a.segments.map(x=>P.clock(x.start)+'–'+P.clock(x.end)).join('<br>')}</td><td>${a.machineId?esc(s.machines.find(m=>m.id===a.machineId).name)+'<small>'+a.machineSpans.map(x=>P.clock(x.start)+'–'+P.clock(x.end)).join(', ')+'</small>':'—'}</td></tr>`}).join('');document.querySelector('#issues').textContent=s.plan.issues.map(i=>i.reason).join(' · ')}
document.querySelector('#absence').addEventListener('change',render);render();
})(typeof window!=='undefined'?window:globalThis);
