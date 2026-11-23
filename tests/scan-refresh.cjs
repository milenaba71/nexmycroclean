const fs=require('fs'),vm=require('vm'),assert=require('node:assert/strict');
const s=fs.readFileSync('lot-mismatch-alert.js','utf8');
(async()=>{
 let calls=[],writes=0,serverRevision=7;
 const c={current:{id:1,rows:[{code:'A'}]},stage:'Uscita',db:{garments:[{id:'A'}]},cloudRevision:7,resolveBarcode:x=>x,cloudFlush:async()=>{},cloudRequest:async action=>{calls.push(action||'snapshot');return {revision:serverRevision}},cloudAccept:r=>c.cloudRevision=r.revision,lotMismatchInfo:()=>null,checkedProcess:async()=>{writes++;return null}};
 vm.createContext(c);vm.runInContext(s.slice(s.indexOf('const checkedBeforeLotMismatch'),s.indexOf('const lotMismatchStyle')),c);
 await c.checkedProcess('A');assert.deepEqual(calls,['version']);assert.equal(writes,1);
 calls=[];serverRevision=8;await c.checkedProcess('A');assert.deepEqual(calls,['version','snapshot']);assert.equal(c.cloudRevision,8);
 calls=[];c.stage='Entrata';await c.checkedProcess('A');assert.deepEqual(calls,['version']);
 calls=[];c.db.garments=[];await c.checkedProcess('UNKNOWN');assert.deepEqual(calls,['snapshot']);
 c.stage='Uscita';c.cloudRequest=async()=>{throw Error('offline')};const before=writes;assert.equal(await c.checkedProcess('A'),'offline');assert.equal(writes,before);
 console.log('PASS known scans avoid snapshot; concurrent updates refresh; known entry avoids snapshot; unknown entry refreshes; read failure prevents write');
})().catch(e=>{console.error(e);process.exit(1)});
