const fs=require('node:fs'),assert=require('node:assert/strict');
const code=fs.readFileSync(require('node:path').join(__dirname,'../automation/ddt-worker.js'),'utf8');
const AsyncFunction=Object.getPrototypeOf(async function(){}).constructor;
async function scenario(current,marker,expectedWrites,conflict){
 let writes=0;const calls=[];
 const fields={fldUVOnsnflDUNZSg:100,fldajPNUHTjclaCOB:current,fld8m7Hjzqm8XdqdS:marker,fld9aMUrfNEx91ksV:[{id:'header'}]};
 const row={id:'line',name:'Articolo',getCellValue:k=>fields[k],getCellValueAsString:k=>String(fields[k]||'')};
 const head={id:'header',getCellValue:k=>k==='fldV9dUf6dh1JVugv'?[{id:'supplier',name:'Fornitore'}]:'2026-11-04',getCellValueAsString:()=> '109'};
 const table={selectRecordAsync:async()=>row,updateRecordAsync:async(id,f)=>{writes++;Object.assign(fields,f)},selectRecordsAsync:async()=>({records:[row]})};
 await new AsyncFunction('input','base','fetch','output',code)({config:()=>({syncKey:'test'})},{getTable:id=>id==='tblstbnacxeJi4Qv2'?table:{selectRecordsAsync:async()=>({records:[head]})}},async(url,o)=>{const p=JSON.parse(o.body);calls.push(p);return {ok:true,json:async()=>p.action==='begin'?{lease:'test',jobs:[{id:'job',line_id:'line',before_qty:30,after_qty:50}]}:{synced:1}}},{set:()=>{}});
 assert.equal(writes,expectedWrites);assert.equal(calls[1].p.status,conflict?'conflict':'applied');assert.equal(calls[2].p.records[0].data.supplierName,'Fornitore');assert.equal(calls[2].p.records[0].returned,conflict?current:50);
}
(async()=>{await scenario(30,'',1,false);await scenario(50,'job',0,false);await scenario(40,'',0,true);await scenario(60,'job',0,true);console.log('PASS: manual increment, retry without duplicate, external edit conflict, mirrored supplier and quantities')})().catch(e=>{console.error(e);process.exit(1)});
