// The sync key is supplied only to the private Airtable automation, never in the public app.
const cfg=input.config();
const endpoint='https://ofvbgaweemjkzugdseua.supabase.co/functions/v1/mycroclean-ddt';
const call=async(action,p={})=>{const r=await fetch(endpoint,{method:'POST',headers:{'Content-Type':'application/json','X-Mycroclean-Sync':cfg.syncKey},body:JSON.stringify({action,p})});if(!r.ok)throw Error('Sincronizzazione DDT non completata: '+r.status);return r.json()};
const run=await call('begin');
if(run.busy){output.set('result','Un aggiornamento è già in corso');return;}
const rowsTable=base.getTable('tblstbnacxeJi4Qv2'),headsTable=base.getTable('tblmFIb5aTD0T6wS5');
const marker='fld8m7Hjzqm8XdqdS',sentField='fldUVOnsnflDUNZSg',returnedField='fldajPNUHTjclaCOB';
for(const job of run.jobs){
 const r=await rowsTable.selectRecordAsync(job.line_id);
 const before=Number(r?.getCellValue(returnedField)||0),sent=Number(r?.getCellValue(sentField)||0);
 let conflict='';
 if(!r)conflict='Riga eliminata in Airtable';
 else if(r.getCellValueAsString(marker)===job.id){if(before!==Number(job.after_qty))conflict='Quantità modificata dopo il rientro: verificare manualmente';}
 else if(before!==Number(job.before_qty)||Number(job.after_qty)>sent)conflict='Quantità Airtable cambiate: rientro non applicato, ricontrollare il residuo';
 else await rowsTable.updateRecordAsync(r.id,{[returnedField]:Number(job.after_qty),[marker]:job.id});
 await call('ack',{lease:run.lease,id:job.id,status:conflict?'conflict':'applied',error:conflict||null});
}
const heads=await headsTable.selectRecordsAsync({fields:['fldgUBDxX6mWjaEaf','fldV9dUf6dh1JVugv','fldcMAWKedobKCZHT','fldHVtrfFlRjU07Ci']});
const hmap=new Map(heads.records.map(r=>[r.id,r]));
const rows=await rowsTable.selectRecordsAsync({fields:['fld9aMUrfNEx91ksV',sentField,returnedField,'fldRfJ3RBNK3HA3Fj','fld8puXt5jZv8eGpZ','fldRd1hIg6bsMgiDh','fldTXN7Z7oxz1YNLZ','fldYgnaNwNTrJvUVZ','fldqBEHEFuumn0RvE']});
const records=[];
for(const r of rows.records){
 const links=r.getCellValue('fld9aMUrfNEx91ksV')||[];
 if(links.length!==1)continue; // An ambiguous document must not receive quantities.
 const h=hmap.get(links[0].id);if(!h)continue;
 const suppliers=h.getCellValue('fldV9dUf6dh1JVugv')||[];
 const sent=Number(r.getCellValue(sentField)||0),returned=Number(r.getCellValue(returnedField)||0);
 if(!Number.isFinite(sent)||!Number.isFinite(returned)||sent<0||returned<0)throw Error('Quantità DDT non valide: '+r.id);
 records.push({id:r.id,sent,returned,data:{ddtId:h.id,number:h.getCellValueAsString('fldgUBDxX6mWjaEaf'),date:h.getCellValue('fldcMAWKedobKCZHT'),supplierId:suppliers.length===1?suppliers[0].id:'',supplierName:suppliers.map(s=>s.name).join(' · '),description:r.getCellValueAsString('fld8puXt5jZv8eGpZ')||r.getCellValueAsString('fldRfJ3RBNK3HA3Fj')||r.getCellValueAsString('fldTXN7Z7oxz1YNLZ')||r.getCellValueAsString('fldRd1hIg6bsMgiDh')||r.name,unit:r.getCellValueAsString('fldqBEHEFuumn0RvE'),notes:r.getCellValueAsString('fldYgnaNwNTrJvUVZ')}});
}
const result=await call('finish',{lease:run.lease,records});output.set('result',String(result.synced)+' righe DDT aggiornate');
