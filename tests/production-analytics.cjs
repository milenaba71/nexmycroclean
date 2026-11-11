const assert=require('node:assert/strict'),A=require('../production-analytics-core.js');
const type={id:'labels',name:'Etichettatura',mode:'piece',value:1.5,setup:0};
const task={id:'t',typeId:'labels',quantity:20,status:'completed',completedAt:'2026-11-02T12:00:00Z',standardSnapshot:{type,quantity:20},sessions:[{seconds:2160,date:'2026-11-02'}],items:[{lotId:1}]};
const state={types:[{...type,value:99}],tasks:[task],tickets:[],machines:[{id:'m',name:'M1'}]};
let r=A.report(state,[{id:1,client:'Client'}],'2026-11');assert.equal(r.standard,30);assert.equal(r.actual,36);assert.equal(r.delta,6);assert.equal(r.percent,20);
assert.equal(A.report(state,[{id:1,client:'Client'}],'2026-11',{client:'Other'}).rows.length,0);
const legacy={...task,id:'legacy',standardSnapshot:undefined};r=A.report({...state,tasks:[legacy]},[],'2026-11');assert.equal(r.missing,1);assert.equal(r.compared,0);
const unknownActual={...task,sessions:[]};assert.equal(A.report({...state,tasks:[unknownActual]},[],'2026-11').missing,1);
// Month grouping uses Rome rather than UTC, full completed task vs partial month sessions.
const cross={...task,completedAt:'2026-10-31T23:30:00Z',sessions:[{seconds:600,date:'2026-10-31'},{seconds:1200,date:'2026-11-01'}]};r=A.report({...state,tasks:[cross]},[],'2026-11');assert.equal(r.actual,30);assert.equal(r.monthActual,20);
assert.equal((A.bounds('2026-03').end-A.bounds('2026-03').start)/3600000,31*24-1);assert.equal((A.bounds('2026-10').end-A.bounds('2026-10').start)/3600000,31*24+1);
const h=(at,blocking,status='open')=>({at,blocking,status});
const t1={id:'a',machineId:'m',createdAt:'2026-10-31T22:00:00Z',status:'closed',history:[h('2026-10-31T22:00:00Z',true),h('2026-11-01T02:00:00Z',false,'closed')]};
const t2={id:'b',machineId:'m',createdAt:'2026-11-01T00:00:00Z',status:'closed',history:[h('2026-11-01T00:00:00Z',true),h('2026-11-01T03:00:00Z',false)]};
r=A.report({...state,tickets:[t1,t2]},[],'2026-11',{},Date.parse('2026-11-10T12:00Z'));assert.equal(r.faults,1);assert.equal(r.stops,0);assert.equal(r.machineRows[0].carried,1);assert.equal(r.downtimeMinutes,240); // UTC 23:00 to 03:00; overlapping ticket is not a second stop.
const reopened={id:'c',machineId:'m',createdAt:'2026-11-02T08:00Z',status:'open',history:[h('2026-11-02T08:00Z',false),h('2026-11-02T09:00Z',true),h('2026-11-02T10:00Z',false,'resolved'),h('2026-11-03T08:00Z',true)]};
r=A.report({...state,tickets:[reopened]},[],'2026-11',{},Date.parse('2026-11-03T09:00Z'));assert.equal(r.stops,2);assert.equal(r.downtimeMinutes,120);
r=A.report({...state,tickets:[{...reopened,history:[{at:'2026-11-02T08:00Z',status:'open'}]}]},[],'2026-11');assert.equal(r.unknown,1);assert.equal(r.downtimeMinutes,0);
const machine={id:'m',capacity:30};r=A.report({...state,tasks:[{...task,quantity:60,standardSnapshot:{quantity:60,machine,type:{id:'wash',mode:'machine',value:45,operatorMinutes:5,setup:2}},sessions:[{seconds:720,date:'2026-11-02'}]}]},[],'2026-11');assert.equal(r.standard,12);assert.equal(r.delta,0);
console.log('PASS: standard snapshots, missing data, client filters, month boundaries, DST, overlap union, reopenings, partial history, machine/operator separation');
