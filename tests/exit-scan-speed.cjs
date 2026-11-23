const fs=require('fs'),vm=require('vm'),assert=require('node:assert/strict');
(async()=>{
 let calls=[],writes=0,revision=7,custody='active',quality={enabled:true,eligible:['A'],released:['A']};
 const c={current:{id:1,rows:[{code:'A',state:'In lavorazione'}]},stage:'Uscita',db:{garments:[{id:'A'}]},cloudRevision:7,resolveBarcode:x=>x,cloudFlush:async()=>{},cloudRequest:async action=>{calls.push(action||'snapshot');return {revision}},cloudAccept:r=>c.cloudRevision=r.revision,custodyFind:()=>({}),custodyStatus:()=>custody,custodyLabel:x=>x,timedProductAlert:async()=>{},lotMismatchInfo:()=>null,checkedProcess:async()=>{writes++;return null},Q:{rpc:async(a,p)=>{calls.push(['quality',a,p]);return quality}},qualityScanBlocked:async(code,msg)=>msg,err:e=>e.message};
 vm.createContext(c);
 const custodySource=fs.readFileSync('missing-returns.js','utf8');const start=custodySource.indexOf('const checkedProcessBeforeCustody=');vm.runInContext(custodySource.slice(start,custodySource.indexOf('\n',start)),c);
 const mismatch=fs.readFileSync('lot-mismatch-alert.js','utf8');vm.runInContext(mismatch.slice(mismatch.indexOf('const checkedBeforeLotMismatch'),mismatch.indexOf('const lotMismatchStyle')),c);
 const q=fs.readFileSync('lot-quality.js','utf8');vm.runInContext(q.slice(q.indexOf('const beforeQualityScan='),q.indexOf('const beforeRequest=')),c);
 for(let i=0;i<130;i++)assert.equal(await c.checkedProcess('A'),null);
 assert.equal(writes,130);assert.equal(calls.filter(x=>x==='snapshot').length,0);assert.equal(calls.filter(x=>Array.isArray(x)&&x[2].scan_code==='A').length,130);
 calls=[];revision++;await c.checkedProcess('A');assert.equal(calls.filter(x=>x==='snapshot').length,1);
 let before=writes;quality.released=[];assert.match(await c.checkedProcess('A'),/autorizzato/);assert.equal(writes,before);
 quality.eligible=[];assert.match(await c.checkedProcess('A'),/non è pronto/);assert.equal(writes,before);
 quality={enabled:false};custody='returned';assert.match(await c.checkedProcess('A'),/reso dal cliente/);assert.equal(writes,before);
 custody='active';c.cloudRequest=async()=>{throw Error('offline')};assert.equal(await c.checkedProcess('A'),'offline');assert.equal(writes,before);
 console.log('PASS: 130 exit scans use single-code quality checks and zero unconditional snapshots; concurrent changes refresh; quality, custody and offline failures block writes');
})().catch(e=>{console.error(e);process.exit(1)});
