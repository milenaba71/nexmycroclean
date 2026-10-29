const fs=require('fs'),assert=require('assert'),crypto=require('crypto'),{PGlite}=require(process.env.PGLITE_PATH||'@electric-sql/pglite');
(async()=>{const pg=new PGlite();await pg.exec(`create role anon;create role authenticated;create schema auth;create schema laundry_private;
create function auth.uid() returns uuid language sql as $$select '00000000-0000-0000-0000-000000000001'::uuid$$;
create table public.laundry_meta(id boolean primary key,revision bigint);insert into laundry_meta values(true,1);
create table public.laundry_products(id text primary key,data jsonb not null);create unique index laundry_effective_barcode_unique on laundry_products(lower(coalesce(nullif(data->>'barcode',''),id)));
create table public.laundry_clients(id text primary key,data jsonb);create table public.laundry_lots(id bigint primary key,data jsonb);
create table public.laundry_audit(actor_email text not null,actor_id text,action text,details jsonb);
create table public.laundry_production(id boolean primary key,data jsonb,revision bigint);insert into laundry_production values(true,'{"tasks":[],"plan":null}',1);
create table public.laundry_wash_batches(id uuid primary key,state text,requires_drying boolean default false);create table public.laundry_wash_items(batch_id uuid,code text,lot_id bigint);
create table public.laundry_dry_cycles(wash_batch_id uuid,state text);
create function laundry_private.laundry_authenticated(a text,p jsonb) returns jsonb language sql as $$select '{"user":{"email":"admin@example.invalid","role":"admin"}}'::jsonb$$;
create function laundry_private.require_permission(cap text) returns void language plpgsql as $$begin if current_setting('test.role',true)='viewer' then raise exception 'PERMISSION_DENIED';end if;end $$;
insert into laundry_clients values('C1','{"name":"Cliente","rentalContracts":[{"id":"K1","status":"active"}]}');
`);
const product=(id)=>({id,barcode:id,barcodeAliases:[],wash:0,max:80,client:'Cliente',type:'Camice',size:'M',color:'Bianco',name:'Persona',dept:'Reparto',rental:true,rentalContract:{clientId:'C1',contractId:'K1'},raw:{SCARTO:'NO'},history:[]});
for(const id of ['TAG1','TAG2','TAG3','TAG4','TAG5','TAG6'])await pg.query('insert into laundry_products values($1,$2)',[id,product(id)]);
await pg.exec(fs.readFileSync('sql/garment_lifecycle.sql','utf8'));
await pg.exec("create table public.laundry_sizes(id text,name text,active boolean); insert into laundry_sizes values('L','L',true),('XL','XL',false)");
await pg.exec(fs.readFileSync('sql/garment_returns_size_change.sql','utf8'));
await pg.exec('create trigger guard_product_barcode before insert or update on laundry_products for each row execute function laundry_private.guard_product_barcode()');
const read=async()=> (await pg.query("select public.laundry_assets('read','{}') x")).rows[0].x;
const call=async(action,p={})=>(await pg.query('select public.laundry_assets($1,$2) x',[action,{revision:(await read()).revision,requestId:crypto.randomUUID(),...p}])).rows[0].x;
const get=async(id)=>(await pg.query('select data from laundry_products where id=$1',[id])).rows[0].data;
// New return and size-change flows use the same transactional guards.
for(const id of ['LEFT','RESIZE','STOCK-L','BADSIZE'])await pg.query('insert into laundry_products values($1,$2)',[id,{...product(id),...(id==='STOCK-L'?{size:'L',rentalContract:null}:{} )}]);
await call('configure',{productId:'STOCK-L',state:'stock',washBaseline:0});
await assert.rejects(()=>call('employee_return',{productId:'LEFT',reason:'employee_left'}),/RETURN_CONFIRMATION_REQUIRED/);
await assert.rejects(()=>call('return',{productId:'LEFT',reason:'employee_left',checked:true}),/INVALID_RETURN_ACTION/);
await call('employee_return',{productId:'LEFT',reason:'employee_left',checked:true});
assert.equal((await get('LEFT')).lifecycleState,'reconditioning');assert.equal((await get('LEFT')).rentalContract,null);assert.equal((await get('LEFT')).name,'');
assert.equal((await read()).charges.filter(c=>c.product_id==='LEFT').length,0);
assert.equal((await read()).assets.find(a=>a.product_id==='LEFT').events[0].wearer,'Persona');
await call('recondition',{productId:'LEFT',checked:true});assert.equal((await get('LEFT')).lifecycleState,'stock');
await assert.rejects(()=>call('replace',{productId:'BADSIZE',reason:'size_change',newSize:'XL',returned:true,tagMode:'new',tag:'BAD'}),/INVALID_REPLACEMENT_SIZE/);
await assert.rejects(()=>call('replace',{productId:'BADSIZE',reason:'size_change',newSize:'L',tagMode:'new',tag:'BAD'}),/RETURN_CONFIRMATION_REQUIRED/);
await assert.rejects(()=>call('replace',{productId:'RESIZE',reason:'wear',replacementId:'STOCK-L',tagMode:'new',tag:'BAD'}),/STOCK_MISMATCH/);
await call('replace',{productId:'RESIZE',reason:'size_change',newSize:'L',returned:true,replacementId:'STOCK-L',tagMode:'new',tag:'SIZE-L-NEW'});
assert.equal((await get('RESIZE')).lifecycleState,'reconditioning');assert.equal((await get('RESIZE')).size,'M');assert.equal((await get('RESIZE')).raw.SCARTO,'NO');assert.equal((await get('RESIZE')).rentalContract,null);
assert.equal((await get('STOCK-L')).size,'L');assert.equal((await get('STOCK-L')).name,'Persona');assert.equal((await get('STOCK-L')).rentalContract.contractId,'K1');assert.equal((await read()).charges.filter(c=>c.product_id==='RESIZE').length,0);
const policy=await call('policy',{name:'Test only',base:'months',bands:[{from:0,to:6,percent:100},{from:6,to:12,percent:75},{from:12,to:null,percent:0}]});const policyId=policy.policies[0].id;
await assert.rejects(()=>call('policy',{name:'Overlap',base:'months',bands:[{from:0,to:6,percent:100},{from:5,to:null,percent:50}]}),/INVALID_POLICY_BANDS/);
await call('configure',{productId:'TAG1',state:'in_service',priceCents:10000,serviceDate:'2026-01-01',washBaseline:0,policyId});
await pg.exec("insert into laundry_lots values(1,'{\"client\":\"Cliente\",\"rows\":[{\"code\":\"TAG1\",\"state\":\"In lavorazione\",\"washed\":true}],\"events\":[]}')");
const req=crypto.randomUUID();const replacement=await call('replace',{requestId:req,productId:'TAG1',reason:'improper_damage',tagMode:'reuse',checked:true,attachment:'heatsealed_sewn',priceCents:15000,policyId});const next=replacement.replacementId;
assert(next);assert.equal((await get('TAG1')).lifecycleState,'retired');assert.equal((await get(next)).barcode,'TAG1');assert.equal((await get(next)).replaces,'TAG1');assert.equal((await get('TAG1')).replacedBy,next);assert.equal((await get(next)).name,'Persona');assert.equal((await get(next)).wash,0);assert.deepEqual((await get(next)).rentalContract,{clientId:'C1',contractId:'K1'});
assert.equal((await pg.query("select laundry_private.tag_lookup('TAG1') p")).rows[0].p.id,next);
assert.equal((await pg.query("select data#>>'{rows,0,state}' s from laundry_lots where id=1")).rows[0].s,'Dismesso');
const replay=await call('replace',{requestId:req,productId:'TAG1',reason:'improper_damage'});assert.equal(replay.replacementId,next);
assert.equal((await read()).assignments.filter(a=>a.tag_code==='tag1'&&!a.released_at).length,1);
await assert.rejects(()=>call('replace',{productId:'TAG1',reason:'wear',tagMode:'new',tag:'X'}),/ASSET_ALREADY_CLOSED/);
await assert.rejects(()=>pg.query("update laundry_products set data=jsonb_set(data,'{lifecycleState}','\"in_service\"') where id='TAG1'"),/USE_ASSET_WORKFLOW/);
await assert.rejects(()=>pg.query("update laundry_lots set data=jsonb_set(data,'{rows,0,state}','\"Entrato\"') where id=1"),/ASSET_RETIRED/);
await assert.rejects(()=>call('configure',{productId:next,state:'in_service',priceCents:1,serviceDate:'2026-01-01'}),/SERVICE_VALUES_FROZEN/);
await call('retire',{productId:'TAG2',reason:'wear'});assert.equal((await read()).charges.filter(c=>c.product_id==='TAG2').length,0);
await call('verify_tag',{tag:'TAG2',outcome:'free',checked:true,attachment:'heatsealed_sewn'});
await call('retire',{productId:'TAG3',reason:'lost'});let charge=(await read()).charges.find(c=>c.product_id==='TAG3');assert.equal(charge.state,'incomplete');
await assert.rejects(()=>call('charge_decide',{chargeId:charge.id,decision:'approved',note:'ok test'}),/CHARGE_NOT_PENDING/);
await call('charge_complete',{chargeId:charge.id,priceCents:10000,serviceDate:'2026-01-01',policyId});charge=(await read()).charges.find(c=>c.id===charge.id);assert.equal(charge.state,'pending');
await call('charge_decide',{chargeId:charge.id,decision:'approved',note:'Verified test'});assert.equal((await read()).charges.find(c=>c.id===charge.id).state,'approved');
await assert.rejects(()=>call('replace',{productId:'TAG4',reason:'lost',tagMode:'reuse',checked:true,attachment:'heatsealed_sewn'}),/TAG_INSPECTION_REQUIRED/);
await pg.exec("insert into laundry_wash_batches(id,state) values('10000000-0000-0000-0000-000000000001','running');insert into laundry_wash_items values('10000000-0000-0000-0000-000000000001','TAG4',1)");
await assert.rejects(()=>call('retire',{productId:'TAG4',reason:'wear'}),/ASSET_MACHINE_BUSY/);
await pg.exec("update laundry_wash_batches set state='estimated'");
await call('replace',{productId:'TAG4',reason:'wash_limit',tagMode:'free',tag:'TAG2',priceCents:null,policyId:null});
await assert.rejects(()=>call('replace',{productId:'TAG5',reason:'wear',tagMode:'free',tag:'TAG2'}),/TAG_NOT_VERIFIED_FREE/);
assert.equal((await get('TAG5')).lifecycleState,undefined); // entire failed transaction rolled back
await pg.exec("select set_config('test.role','viewer',false)");await assert.rejects(()=>call('retire',{productId:'TAG5',reason:'wear'}),/PERMISSION_DENIED/);await pg.exec("select set_config('test.role','admin',false)");
const boundary=await pg.query("select laundry_private.asset_calculation(a,0,'lost','2026-07-01') x from laundry_private.assets a where product_id='TAG1'");assert.equal(boundary.rows[0].x.percent,75);assert.equal(boundary.rows[0].x.amountCents,7500);
assert.equal((await pg.query("select has_function_privilege('anon','public.laundry_assets(text,jsonb)','execute') x")).rows[0].x,false);
assert.equal((await pg.query("select has_function_privilege('authenticated','laundry_private.tag_attach(text,text,text,boolean)','execute') x")).rows[0].x,false);

// Retire first, replace later without changing the original charge or retirement time.
await call('retire',{productId:'TAG5',reason:'wear'});
const retirement=(await read()).assets.find(a=>a.product_id==='TAG5').retired_at;
const late=await call('replace',{productId:'TAG5',reason:'wear',tagMode:'new',tag:'LATE-NEW'});
assert(late.replacementId);assert.equal(late.assets.find(a=>a.product_id==='TAG5').retired_at,retirement);
// A closed-contract return keeps wash history and only becomes usable after inspection.
await call('configure',{productId:'TAG6',state:'in_service',serviceDate:'2026-02-01',priceCents:5000,policyId});
await assert.rejects(()=>call('return',{productId:'TAG6'}),/CLOSE_CONTRACT_FIRST/);
await pg.exec("update laundry_clients set data=jsonb_set(data,'{rentalContracts,0,status}','\"closed\"')");
await call('return',{productId:'TAG6'});assert.equal((await get('TAG6')).lifecycleState,'reconditioning');
await call('recondition',{productId:'TAG6',checked:true});assert.equal((await get('TAG6')).lifecycleState,'stock');assert.equal((await get('TAG6')).rentalContract,null);
// The stock garment is reused without resetting its physical wash count.
await pg.exec("update laundry_products set data=jsonb_set(data,'{wash}','7') where id='TAG6'");
await pg.query('insert into laundry_products values($1,$2)',['TAG7',product('TAG7')]);
let stocked=await call('replace',{productId:'TAG7',reason:'wear',replacementId:'TAG6',tagMode:'new',tag:'STOCK-TAG',priceCents:4000,policyId});assert.equal(stocked.replacementId,'TAG6');assert.equal((await get('TAG6')).wash,7);assert.equal(stocked.assets.find(a=>a.product_id==='TAG6').wash_baseline,7);
// Shared pending work retains its other items and invalidates only affected allocations.
await pg.query('insert into laundry_products values($1,$2)',['TAG8',product('TAG8')]);
await pg.exec(`update laundry_production set data='{"tasks":[{"id":"shared","status":"pending","quantity":2,"items":[{"code":"TAG8","lotId":1},{"code":"KEEP","lotId":1}],"events":[]}],"plan":{"allocations":[{"taskId":"shared"}],"issues":[]},"planHistory":[]}'`);
await call('retire',{productId:'TAG8',reason:'wear'});
const plan=(await pg.query('select data from laundry_production')).rows[0].data;assert.equal(plan.tasks[0].status,'pending');assert.equal(plan.tasks[0].quantity,1);assert.equal(plan.tasks[0].items[0].code,'KEEP');assert.equal(plan.plan.allocations.length,0);
const washesPolicy=await call('policy',{name:'Wash test only',base:'washes',bands:[{from:0,to:10,percent:90},{from:10,to:null,percent:20}]});
const washPid=washesPolicy.policies.find(p=>p.base==='washes').id;
await pg.query('insert into laundry_products values($1,$2)',['WASH',product('WASH')]);
await call('configure',{productId:'WASH',state:'in_service',serviceDate:'2026-01-01',priceCents:10001,washBaseline:0,policyId:washPid});
const washBoundary=await pg.query("select laundry_private.asset_calculation(a,10,'lost','2026-07-01') x from laundry_private.assets a where product_id='WASH'");assert.equal(washBoundary.rows[0].x.amountCents,2000);



// Purchase at contract end creates an approval proposal and leaves the physical tag on the garment.
await pg.query('insert into laundry_products values($1,$2)',['BUYOUT',product('BUYOUT')]);
await call('configure',{productId:'BUYOUT',state:'in_service',serviceDate:'2026-01-31',priceCents:9999,policyId});
const anniversary=await pg.query("select laundry_private.asset_calculation(a,0,'buyout','2026-02-28') x from laundry_private.assets a where product_id='BUYOUT'");assert.equal(anniversary.rows[0].x.age,1);
await call('buyout',{productId:'BUYOUT'});let bought=await read();assert.equal(bought.assets.find(a=>a.product_id==='BUYOUT').state,'bought_out');assert.equal(bought.charges.find(c=>c.product_id==='BUYOUT').state,'pending');assert(bought.assignments.some(a=>a.product_id==='BUYOUT'&&!a.released_at));
await assert.rejects(()=>pg.query("select laundry_private.tag_lookup('BUYOUT')"),/ASSET_NOT_IN_SERVICE/);

// Apply the integration patch to the real pre-change function definitions.
await pg.exec(`create table laundry_members(email text primary key,name text,role text,active boolean,site_user_id text);
insert into laundry_members values('admin@example.invalid','Admin','admin',true,null);
create function laundry_private.permission_set(email text) returns jsonb language sql as $$select '{"permissions":{"products_manage":true}}'::jsonb$$;create table laundry_private.laundry_super_admin(email text);create table laundry_processing(id text primary key,data jsonb);
insert into laundry_processing values('P1','{"id":"P1","name":"Acqua","active":true,"wash":true}');
create table laundry_types(id text,name text,active boolean);create table laundry_colors(id text,name text);create table laundry_departments(id text,name text,client_id text);
create table laundry_repairs(lot_id bigint,product_code text,kind text,status text check(status in ('open','completed')),created_at timestamptz default now(),completed_at timestamptz,primary key(lot_id,product_code,kind));
alter table laundry_wash_batches add lot_id bigint,add machine_id text,add program_name text,add machine_name text,add expected_end timestamptz,add created_at timestamptz default now(),add events jsonb default '[]';
alter table laundry_dry_cycles add id uuid default gen_random_uuid(),add expected_end timestamptz;
`);
await pg.exec(fs.readFileSync('tests/fixtures/pre-lifecycle-functions.sql','utf8'));
await pg.exec(fs.readFileSync('sql/garment_lifecycle_integration.sql','utf8'));
await pg.exec(`create trigger validate_lot_flow before insert or update on laundry_lots for each row execute function laundry_private.validate_lot_flow();
create trigger wash_batch_guard_lot before update on laundry_lots for each row execute function laundry_private.wash_batch_guard_lot();
create trigger sync_repairs after insert or update on laundry_lots for each row execute function laundry_private.sync_repairs();
insert into laundry_lots values(2,'{"id":2,"client":"Cliente","rows":[],"events":[]}');`);
const actor={id:'00000000-0000-0000-0000-000000000001',email:'admin@example.invalid'};
const acquired=(await pg.query('select laundry_private.laundry_core($1,$2,$3) x',[actor,'lot_acquire',{lot_id:2,code:'TAG1',processing_id:'P1',revision:(await read()).revision}])).rows[0].x;
assert.equal(acquired.db.lots.find(l=>l.id===2).rows[0].code,next);
assert.equal((await pg.query("select data#>>'{rows,0,code}' x from laundry_lots where id=1")).rows[0].x,'TAG1');
let changed={...(await get(next)),id:'TAG1',name:'Updated wearer'};
await pg.query('select laundry_private.product_save_core($1,$2)',[actor,{revision:(await read()).revision,mode:'manual',original_id:next,product:changed}]);
assert.equal((await get(next)).name,'Updated wearer');assert.equal((await get(next)).id,next);
await pg.query('insert into laundry_products values($1,$2)',['REPAIR',product('REPAIR')]);
await pg.exec(`insert into laundry_lots values(3,'{"id":3,"client":"Cliente","rows":[{"code":"REPAIR","state":"Entrato","repair":true}],"events":[]}')`);
assert.equal((await pg.query("select status from laundry_repairs where product_code='REPAIR'")).rows[0].status,'open');
await call('retire',{productId:'REPAIR',reason:'breakage'});
assert.equal((await pg.query("select status from laundry_repairs where product_code='REPAIR'")).rows[0].status,'cancelled');
assert.equal((await pg.query("select completed_at from laundry_repairs where product_code='REPAIR'")).rows[0].completed_at,null);
await assert.rejects(()=>pg.exec(`update laundry_production set data=jsonb_set(data,'{tasks}','[{"id":"bad","status":"pending","items":[{"code":"REPAIR"}]}]')`),/ASSET_RETIRED/);
await pg.exec('select laundry_private.wash_batch_tick();select laundry_private.dry_sync_product_phases();');
assert.equal((await pg.query("select data#>>'{rows,0,state}' x from laundry_lots where id=3")).rows[0].x,'Dismesso');
console.log('PASS integration: existing scan endpoint resolves reused tag to new garment; historical lot IDs stay stable; editable product save still works; repairs are cancelled, not completed; schedulers preserve dismissed rows');

console.log('PASS lifecycle: immutable identity/history, atomic replacement, tag reuse/inspection, stock checks, idempotency, live-machine lock, configurable depreciation boundaries, charge approval, role and helper isolation');await pg.close();})().catch(e=>{console.error(e);process.exit(1)});
