const fs=require('fs'),assert=require('node:assert/strict');const {PGlite}=require(process.env.PGLITE_PATH);
(async()=>{const pg=new PGlite();await pg.exec(`create role anon;create role authenticated;create schema laundry_private;create schema auth;
create function auth.uid() returns uuid language sql as $$select '00000000-0000-0000-0000-000000000001'::uuid$$;
create table laundry_lots(id bigint primary key,data jsonb);create table laundry_products(id text primary key,data jsonb);create table laundry_meta(id boolean primary key,revision bigint);insert into laundry_meta values(true,1);
create function laundry_private.laundry_authenticated(a text,p jsonb) returns jsonb language sql as $$select '{"user":{"name":"Test","email":"test@example.invalid"}}'::jsonb$$;
create function laundry_private.require_permission(cap text) returns void language plpgsql as $$begin if current_setting('test.denied',true)='yes' then raise exception 'PERMISSION_DENIED';end if;end $$;`);
for(const f of ['lot_quality.sql','quality_product_identity.sql'])await pg.exec(fs.readFileSync('sql/'+f,'utf8'));
const rows=Array.from({length:4},(_,i)=>({code:String(i+1),state:'In lavorazione',completed:true,washed:true,processingId:'water',foldedAt:'today'}));
const call=async(a,p={})=>(await pg.query('select public.laundry_quality($1,$2) q',[a,JSON.stringify({lot_id:1,...p})])).rows[0].q;
const update=async(r)=>pg.query("update laundry_lots set data=jsonb_set(data,'{rows}',$1) where id=1",[JSON.stringify(r)]);
await pg.query('insert into laundry_lots values(1,$1)',[JSON.stringify({rows})]);
const checks={clean:'ok',dry:'ok',integrity:'ok',identity:'ok',packing:'ok'};
// Existing release remains valid when later passes cover fewer rows after exit.
await call('record',{revision:0,rows,outcome:'pass',checks,sample_count:1});
let changed=structuredClone(rows);changed[0].state='Uscito';await update(changed);
await call('record',{revision:1,rows:changed,outcome:'pass',checks,sample_count:1});
await pg.exec(fs.readFileSync('sql/quality_sampling_three.sql','utf8'));
let q=await call('read');assert.equal(q.released.length,3);
changed[1].state='Uscito';await update(changed); // no repeat control
await update(rows);
const record=async(code,outcome='pass',extra={})=>{const q=await call('read');return call('record',{revision:q.revision,rows:q.rows,sample_code:code,outcome,checks:outcome==='pass'?checks:{...checks,clean:'ko'},notes:outcome==='fail'?'Macchia da trattare':'',sample_count:1,...extra})};
await assert.rejects(()=>record('99'),/QUALITY_SAMPLE_NOT_READY/);
q=await record('1');assert.equal(q.samples.length,1);assert.equal(q.released.length,4);
await assert.rejects(()=>record('2'),/QUALITY_SAMPLE_LIMIT/);
changed=structuredClone(rows);changed[0].state='Uscito';await update(changed);changed[1].state='Uscito';await update(changed);assert.equal((await call('read')).released.length,2);
await update(rows);
q=await record('1','fail');assert.equal(q.expanded,true);assert.equal(q.sample_target,3);assert.equal(q.released.length,0);
q=await record('2');assert.equal(q.released.length,0);
q=await record('3');assert.equal(q.released.length,0); // failing first sample still must be corrected
await assert.rejects(()=>record('4'),/QUALITY_SAMPLE_LIMIT/);
q=await record('1');assert.equal(q.samples.length,3);assert.equal(q.released.length,4);
await assert.rejects(()=>record('1','pass',{revision:0}),/REVISION_CONFLICT/);
await pg.exec("set test.denied='yes'");await assert.rejects(()=>record('1'),/PERMISSION_DENIED/);await pg.exec("set test.denied='no'");
changed=structuredClone(rows);changed[0].notes='Nota amministrativa';await update(changed);assert.equal((await call('read')).released.length,4);
changed[0].repair=true;await update(changed);assert.equal((await call('read')).released.includes('1'),false);
changed[0].repair=false;changed[0].rewashCycles=1;await update(changed);assert.equal((await call('read')).released.includes('1'),false);
await assert.rejects(()=>update([{...changed[0],state:'Uscito'},...changed.slice(1)]),/QUALITY_RELEASE_REQUIRED/);
await update(rows);
await pg.query('insert into laundry_products values($1,$2)',['1',JSON.stringify({size:'L'})]);assert.equal((await call('read')).released.includes('1'),false);
// Small lots never require nonexistent samples.
await pg.query('insert into laundry_lots values(2,$1)',[JSON.stringify({rows:rows.slice(0,1)})]);
q=await call('record',{lot_id:2,revision:0,rows:rows.slice(0,1),sample_code:'1',outcome:'fail',checks:{...checks,clean:'ko'},notes:'Macchia'});assert.equal(q.sample_target,1);
await pg.exec(fs.readFileSync('sql/quality_lot45_customer_return.sql','utf8'));
await pg.exec(`update laundry_products set data=data||'{"rental":false}' where id='1'`);
const scopedReady=async(lid,r)=>(await pg.query('select laundry_private.quality_row_ready_for_lot($1,$2) ok',[lid,JSON.stringify(r)])).rows[0].ok;
assert.equal(await scopedReady(45,{...rows[0],discard:true,discardForReturn:true}),true);
assert.equal(await scopedReady(44,{...rows[0],discard:true,discardForReturn:true}),false);
assert.equal(await scopedReady(45,{...rows[0],discard:true,discardForReturn:true,repair:true}),false);
assert.equal(await scopedReady(45,{...rows[1],discard:true,discardForReturn:true}),false);
await pg.exec(fs.readFileSync('sql/quality-scan-read.sql','utf8'));
const fullRead=await call('read');
for(const code of ['1','2','3','4','unknown']){
 const compact=await call('read',{scan_code:code});
 assert.equal(compact.enabled,fullRead.enabled);
 assert.deepEqual(compact.eligible,fullRead.eligible.filter(x=>x===code));
 assert.deepEqual(compact.released,fullRead.released.filter(x=>x===code));
 assert.equal(compact.rows,undefined);assert.equal(compact.checks,undefined);
}
await assert.rejects(()=>call('read',{scan_code:''}),/INVALID_BARCODE/);
await assert.rejects(()=>call('read',{lot_id:999,scan_code:'1'}),/LOT_NOT_FOUND/);
await assert.rejects(()=>update([{...rows[0],state:'Uscito'},...rows.slice(1)]),/QUALITY_RELEASE_REQUIRED/);
// Wash-limit returns: real quality RPC and exit trigger, without resetting wear or discard.
await pg.exec(fs.readFileSync('supabase/migrations/20261127111631_wash_limit_return_flow.sql','utf8'));
let lid=100;
for(const wash of [80,81,150])for(const rental of [false,true,null]){
 lid++;const code='return-'+lid,entry={code,state:'Entrato',completed:false,discard:true,washed:true,washBatchId:'batch',processingId:'water'};
 await pg.query('insert into laundry_products values($1,$2)',[code,JSON.stringify({wash,max:80,rental,raw:{SCARTO:'SI'}})]);
 await pg.query('insert into laundry_lots values($1,$2)',[lid,JSON.stringify({rows:[entry]})]);
 assert.equal(await scopedReady(lid,entry),false);
 const folded={...entry,state:'In lavorazione',completed:true,foldedAt:'today'};
 const setRows=async(row)=>pg.query("update laundry_lots set data=jsonb_set(data,'{rows}',$2) where id=$1",[lid,JSON.stringify([row])]);
 await setRows(folded);assert.equal(await scopedReady(lid,folded),true);
 for(const flag of ['repair','relabel','verify','rewashPending','discardReview'])assert.equal(await scopedReady(lid,{...folded,[flag]:true}),false,flag);
 assert.equal(await scopedReady(lid,{...folded,foldedAt:null}),false);
 assert.equal(await scopedReady(lid,{...folded,requiresDrying:true,dryState:'waiting'}),false);
 await assert.rejects(()=>setRows({...folded,state:'Uscito'}),/QUALITY_RELEASE_REQUIRED/);
 const before=await call('read',{lot_id:lid});assert(before.eligible.includes(code));
 await call('record',{lot_id:lid,revision:before.revision,rows:before.rows,sample_code:code,outcome:'pass',checks,sample_count:1});
 await setRows({...folded,state:'Uscito'});
 const saved=(await pg.query('select data from laundry_lots where id=$1',[lid])).rows[0].data.rows[0];
 assert.equal(saved.state,'Uscito');assert.equal(saved.discard,true);
 assert.equal((await pg.query('select data from laundry_products where id=$1',[code])).rows[0].data.wash,wash);
}
assert.equal(await scopedReady(44,{...rows[0],discard:true,discardForReturn:true}),false,'unrelated discard remains blocked');
await pg.query('insert into laundry_products values($1,$2)',['custom',JSON.stringify({wash:81,max:100})]);
assert.equal(await scopedReady(200,{...rows[0],code:'custom',discard:true}),false);
await pg.exec("update laundry_products set data=data||'{\"wash\":101}' where id='custom'");
assert.equal(await scopedReady(200,{...rows[0],code:'custom',discard:true}),true);
for(const role of ['anon','authenticated'])assert.equal((await pg.query("select has_function_privilege($1,'laundry_private.quality_row_ready_for_lot(bigint,jsonb)','EXECUTE') ok",[role])).rows[0].ok,false);
console.log('PASS wash-limit returns: entry, folding, quality, exit; discard/count preserved; independent holds and private permissions retained');
console.log('PASS compact scan matches full quality status; unknown rejected; final exit guard remains active');
console.log('PASS: bounded distinct samples, first failure expansion, corrections, repeat exits, legacy releases, readiness, rewash/identity invalidation, concurrent writes and permissions');await pg.close();})().catch(e=>{console.error(e);process.exit(1)});
