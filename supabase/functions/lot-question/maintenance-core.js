/* Shared, read-only calculations. No model-generated figures enter this report. */
(function(root){
'use strict';
const norm=v=>String(v||'').normalize('NFD').replace(/[\u0300-\u036f]/g,'').trim().toLowerCase().replace(/\s+/g,' ');
const time=v=>typeof v==='string'?Date.parse(v):NaN;
const list=v=>Array.isArray(v)?v:[];
function union(spans){const out=[];for(const s of spans.filter(s=>s.end>s.start).sort((a,b)=>a.start-b.start)){const last=out.at(-1);if(last&&s.start<=last.end)last.end=Math.max(last.end,s.end);else out.push({...s})}return out}
function downtime(t,now){
 const all=list(t.history),hs=all.filter(h=>h&&Number.isFinite(time(h.at))&&time(h.at)<=now).slice().sort((a,b)=>time(a.at)-time(b.at));
 let start=null,unknown=hs.length!==all.length||!hs.length||time(hs[0]?.at)>time(t.createdAt),spans=[];
 for(const h of hs){const at=time(h.at);if(typeof h.blocking!=='boolean'){unknown=true;if(start!==null)spans.push({start,end:at});start=null;continue}
  const blocked=h.blocking&&h.status!=='closed';if(blocked&&start===null)start=at;if(!blocked&&start!==null){spans.push({start,end:at});start=null}
 }
 if(start!==null)spans.push({start,end:now});
 return {spans,unknown};
}
function isTest(t){const kind=t.maintenance?.kind;if(kind)return kind==='test';return /\b(test|prova)\b/i.test([t.description,...list(t.history).map(h=>h?.note)].join(' '))}
function report(state,{days=90,machineId=''}={}){
 if(![30,90,365,0].includes(days))throw Error('INVALID_PERIOD');
 const now=time(state.asOf);if(!Number.isFinite(now))throw Error('INVALID_SNAPSHOT');
 const machines=list(state.machines);if(machineId&&!machines.some(m=>m.id===machineId))throw Error('INVALID_MACHINE');
 const start=days?now-days*86400000:0,all=list(state.tickets).filter(t=>!machineId||t.machineId===machineId);
 const inPeriod=t=>{const d=downtime(t,now);return time(t.createdAt)>=start&&time(t.createdAt)<=now||list(t.history).some(h=>time(h?.at)>=start&&time(h?.at)<=now)||d.spans.some(s=>s.start<now&&s.end>start)||t.status!=='closed'};
 const excluded=all.filter(t=>isTest(t)&&inPeriod(t)),tickets=all.filter(t=>!isTest(t)&&inPeriod(t));
 const rows=tickets.map(t=>{
  const d=downtime(t,now),history=list(t.history).filter(h=>h&&typeof h==='object'&&Number.isFinite(time(h.at))&&time(h.at)<=now).slice().sort((a,b)=>time(a.at)-time(b.at));
  let prior='',reopens=0;for(const h of history){if(h.status==='open'&&['resolved','closed'].includes(prior)&&time(h.at)>=start)reopens++;prior=h.status}
  return {...t,history,unknown:d.unknown,reopens,newInPeriod:time(t.createdAt)>=start&&time(t.createdAt)<=now,spans:d.spans.map(s=>({start:Math.max(start,s.start),end:Math.min(now,s.end)})).filter(s=>s.end>s.start)};
 });
 const ids=[...new Set([...machines.filter(m=>!machineId||m.id===machineId).map(m=>m.id),...rows.map(t=>t.machineId)])];
 const machineRows=ids.map(id=>{const ts=rows.filter(t=>t.machineId===id);return {id,name:machines.find(m=>m.id===id)?.name||id,tickets:ts.length,newFaults:ts.filter(t=>t.newInPeriod&&t.maintenance?.kind!=='planned').length,planned:ts.filter(t=>t.newInPeriod&&t.maintenance?.kind==='planned').length,reopens:ts.reduce((s,t)=>s+t.reopens,0),minutes:union(ts.flatMap(t=>t.spans)).reduce((s,t)=>s+(t.end-t.start)/60000,0),unknown:ts.filter(t=>t.unknown).length,open:ts.filter(t=>t.status!=='closed').length,blocking:ts.some(t=>t.blocking===true&&t.status!=='closed')}});
 const groups=new Map();
 for(const t of rows){if(t.maintenance?.kind==='planned')continue;const m=t.maintenance||{},component=norm(m.component),code=norm(m.errorCode);if(!component&&!code)continue;
  const key=JSON.stringify([t.machineId,component,code]),g=groups.get(key)||{machineId:t.machineId,component:m.component||'',errorCode:m.errorCode||'',occurrences:0,ticketIds:[]};
  const count=Number(t.newInPeriod)+t.reopens;if(count){g.occurrences+=count;g.ticketIds.push(t.id);groups.set(key,g)}
 }
 return {asOf:state.asOf,days,machineId,from:days?new Date(start).toISOString():null,machines:machineRows,tickets:rows,excludedTests:excluded.map(t=>({id:t.id,description:t.description,machineId:t.machineId})),recurrences:[...groups.values()].filter(g=>g.occurrences>1),minutes:machineRows.reduce((s,m)=>s+m.minutes,0),unknown:rows.filter(t=>t.unknown).length};
}
function evidence(r){
 const selected=r.tickets.slice().sort((a,b)=>Number(b.status!=='closed')-Number(a.status!=='closed')||time(b.updatedAt||b.createdAt)-time(a.updatedAt||a.createdAt)).slice(0,40);
 const text=v=>String(v||'').slice(0,500);
 return {asOf:r.asOf,from:r.from,days:r.days,minutes:r.minutes,unknown:r.unknown,machines:r.machines,recurrences:r.recurrences,excludedTests:r.excludedTests.length,totalTickets:r.tickets.length,includedTickets:selected.length,
  tickets:selected.map(t=>({id:t.id,machineId:t.machineId,status:t.status,blocking:t.blocking,description:text(t.description),createdAt:t.createdAt,unknown:t.unknown,reopens:t.reopens,maintenance:Object.fromEntries(['kind','component','errorCode','cause','work','parts','nextDate'].map(k=>[k,text(t.maintenance?.[k])])),historyTruncated:t.history.length>8,history:t.history.slice(-8).map(h=>({at:h.at,status:h.status,blocking:h.blocking,note:text(h.note)}))}))};
}
root.MaintenanceCore={report,evidence,downtime,union,isTest};
if(typeof module!=='undefined')module.exports=root.MaintenanceCore;
})(globalThis);
