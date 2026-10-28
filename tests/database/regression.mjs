import { PGlite } from '@electric-sql/pglite';
import { readFileSync, readdirSync } from 'node:fs';
import assert from 'node:assert/strict';
const read = p => readFileSync(new URL('../../'+p,import.meta.url),'utf8');
const legacy=JSON.parse(read('tests/database/fixtures/legacy-sql.json'));
const paths=readdirSync(new URL('../../supabase/migrations/',import.meta.url)).filter(p=>p.endsWith('.sql')).sort();
const release=paths.at(-1);
const fixtures=read('tests/database/fixtures/base.sql');
const versionMap=JSON.parse(read('supabase/legacy-version-map.json'));
let passed=0;
const check=(v,msg)=>{assert.ok(v,msg);passed++;};
async function fails(fn,pattern){await assert.rejects(fn,pattern);passed++;}
const ids={early:'00000000-0000-0000-0000-000000000001',owner:'00000000-0000-0000-0000-000000000002',operator:'00000000-0000-0000-0000-000000000003',viewer:'00000000-0000-0000-0000-000000000004'};
const session='10000000-0000-0000-0000-000000000001';
async function setup(mode){
 const db=new PGlite();await db.exec(fixtures);
 for(const [name,id] of Object.entries(ids)){
  await db.query('insert into auth.users(id,email,email_confirmed_at) values($1,$2,now())',[id,`${name}@example.test`]);
  await db.query('insert into public.laundry_members(email,name,role,created_at) values($1,$2,$3,$4)',[`${name}@example.test`,name,['early','owner'].includes(name)?'admin':name,name==='early'?'2020-01-01':'2021-01-01']);
 }
 await db.query('insert into auth.sessions values($1,$2)',[session,ids.owner]);
 const order=mode==='acquisition-only'?['catalogs.sql','lot_workflow.sql','automatic_acquisition.sql']:mode==='admin-after-barcode'?['catalogs.sql','lot_workflow.sql','automatic_acquisition.sql','product_barcodes.sql','admin_management.sql']:['catalogs.sql','lot_workflow.sql','automatic_acquisition.sql','admin_management.sql','product_barcodes.sql'];
 for(const file of order)await db.exec(legacy[file]);
 if(mode==='current')await db.exec("select setval('public.laundry_barcode_sequence',1000)");
 if(mode==='reverted')await db.exec(legacy['automatic_acquisition.sql']);
 if(mode==='unassigned')await db.exec('delete from laundry_private.laundry_super_admin');
 for(const file of paths.slice(0,-1)){
  // PGlite has no background workers: exclude only pg_cron installation/scheduling.
  // All application SQL, including calendar functions, executes unchanged.
  let sql=read('supabase/migrations/'+file);
  if(file==='20261027065752_recurring_client_calendar.sql')sql=sql.replace('create extension if not exists pg_cron;','').replace("select cron.schedule('mycroclean-recurring-calendar','15 3 * * *',$job$select laundry_private.refresh_client_calendar();$job$);",'');
  await db.exec(sql);
  await db.query('insert into supabase_migrations.schema_migrations(version,name,statements) values($1,$2,$3)',[mode==='deployed-history'?versionMap.find(x=>x.name===file.slice(15,-4)).database_version:file.split('_')[0],file.slice(15,-4),[read('supabase/migrations/'+file)]]);
 }
 return db;
}
async function migrate(db){
 try{await db.exec(read('supabase/migrations/'+release));}catch(e){await db.exec('rollback');throw e;}
}
async function suite(mode){
 const db=await setup(mode);
 try{
 const q=async(sql,args=[]) => (await db.query(sql,args)).rows;
 const scalar=async(sql,args=[])=>Object.values((await q(sql,args))[0])[0];
 if(mode==='current'){
  await db.query("delete from supabase_migrations.schema_migrations where version='20261027072835'");
  await fails(()=>migrate(db),/MIGRATION_ORDER_INVALID/);
  check(await scalar("select to_regclass('laundry_private.core_release') is null"),'failed migration rolls back');
  await db.query('insert into supabase_migrations.schema_migrations values($1,$2,$3)',['20261027072835','client_department_schedules',[read('supabase/migrations/20261027072835_client_department_schedules.sql')]]);
  await db.exec("update supabase_migrations.schema_migrations set statements=array['select 1'] where version='20261027072835'");
  await fails(()=>migrate(db),/CONTENT_MISMATCH/);
  await db.query('update supabase_migrations.schema_migrations set statements=$1 where version=$2',[[read('supabase/migrations/20261027072835_client_department_schedules.sql')],'20261027072835']);
  await db.exec("alter function laundry_private.laundry_core(jsonb,text,jsonb) rename to saved_core; create function laundry_private.laundry_core(jsonb,text,jsonb) returns jsonb language sql as $$select '{}'::jsonb$$");
  await fails(()=>migrate(db),/UNKNOWN_LAUNDRY_CORE/);
  await db.exec('drop function laundry_private.laundry_core(jsonb,text,jsonb);alter function laundry_private.saved_core(jsonb,text,jsonb) rename to laundry_core');
  const authDefinition=await scalar("select pg_get_functiondef('laundry_private.laundry_authenticated(text,jsonb)'::regprocedure)");
  await db.exec(authDefinition.replace('declare u auth.users;', '-- unknown wrapper change\ndeclare u auth.users;'));
  await fails(()=>migrate(db),/UNKNOWN_FUNCTION_REVIEW_REQUIRED/);
  await db.exec(authDefinition);
 }
 await migrate(db);
 await db.query('insert into supabase_migrations.schema_migrations(version,name,statements) values($1,$2,$3)',[release.split('_')[0],'consolidate_laundry_core',[read('supabase/migrations/'+release)]]);
 if(mode==='current')check(await scalar("select last_value>=1000 from public.laundry_barcode_sequence"),'existing barcode sequence never moves backwards');
 const verificationSQL=read('sql/operations/verify_release.sql').replace(/^\\.*$/gm,'');
 async function verify(){try{await db.exec(verificationSQL);}catch(e){await db.exec('rollback');throw e;}}
 await fails(()=>verify(),/EXPLICIT_SUPER_ADMIN_DESIGNATION_REQUIRED/);
 await fails(()=>migrate(db),/CORE_RELEASE_ALREADY_INSTALLED/);
 // The retired files must fail in any order, without changing the core.
 const fingerprint=()=>scalar("select md5(pg_get_functiondef('laundry_private.laundry_core(jsonb,text,jsonb)'::regprocedure))");
 const before=await fingerprint();
 for(const name of Object.keys(legacy).reverse())await fails(()=>db.exec(read('sql/'+name)),/LEGACY_SQL_RETIRED/);
 check(before===await fingerprint(),'retired SQL cannot downgrade functions');
 const rev=()=>scalar('select revision from public.laundry_meta where id');
 async function rpc(user,action,payload={},write=false){
  await db.query('update auth.sessions set user_id=$1 where id=$2',[ids[user],session]);
  await db.query("select set_config('request.jwt.claims',$1,false)",[JSON.stringify({sub:ids[user],session_id:session})]);
  if(write)payload={...payload,revision:await rev()};
  await db.exec('set role authenticated');
  try{return await scalar('select public.laundry_app($1,$2::jsonb)',[action,JSON.stringify(payload)]);}
  finally{await db.exec('reset role');}
 }
 const userPayload={email:'new-admin@example.test',name:'New admin',role:'admin',active:true};
 check(!(await rpc('early','version')).user.isSuperAdmin,'earliest account has no inferred authority');
 await fails(()=>rpc('early','user_save',userPayload),/FORBIDDEN_ADMIN_ROLE/);
 await fails(()=>db.query('select laundry_private.designate_super_admin($1,$2)',[ids.operator,null]),/INVALID_SUPER_ADMIN_ACCOUNT/);
 const previous=['unassigned','acquisition-only'].includes(mode)?null:'early@example.test';
 if(previous)await fails(()=>db.query('select laundry_private.designate_super_admin($1,null)',[ids.owner]),/PREVIOUS_SELECTION_CHANGED/);
 await db.query('select laundry_private.designate_super_admin($1,$2)',[ids.owner,previous]);
 await db.query('select laundry_private.designate_super_admin($1,$2)',[ids.owner,previous]);
 await verify();passed++;
 check((await rpc('owner','version')).user.isSuperAdmin,'explicit second administrator gets authority');
 await fails(()=>db.query('select laundry_private.designate_super_admin($1,$2)',[ids.early,previous]),/ALREADY_CONFIRMED/);
 await rpc('owner','user_save',userPayload);
 await fails(()=>rpc('early','user_save',{...userPayload,role:'operator'}),/FORBIDDEN_ADMIN_ROLE/);
 await fails(()=>rpc('owner','user_save',{email:'owner@example.test',name:'Owner',role:'viewer',active:true}),/SUPER_ADMIN_PROTECTED/);
 await fails(()=>rpc('owner','user_save',{email:'owner@example.test',name:'Owner',role:null,active:true}),/INVALID_USER/);
 await fails(()=>rpc('operator','user_save',userPayload),/FORBIDDEN/);
 await fails(()=>rpc('viewer','lot_create',{client:'Fixture',colli:1},true),/FORBIDDEN/);
 await fails(()=>rpc('operator','catalog_save',{kind:'type',name:'Forbidden'},true),/FORBIDDEN/);
 await fails(()=>rpc('operator','save',{changes:{processing:[{id:'bad'}]}},true),/FORBIDDEN/);
 await db.exec('set role anon');
 await fails(()=>db.query("select public.laundry_app('version','{}')"),/permission denied/);
 await db.exec('reset role;set role authenticated');
 await fails(()=>db.query("select laundry_private.laundry_core('{}','version','{}')"),/permission denied/);
 await fails(()=>db.query('select * from public.laundry_products'),/permission denied/);
 await fails(()=>db.query('select laundry_private.designate_super_admin($1,null)',[ids.owner]),/permission denied/);
 await db.exec('reset role');
 await db.exec("update auth.users set email_confirmed_at=null where email='viewer@example.test'");
 await fails(()=>rpc('viewer','version'),/UNAUTHORIZED/);
 await db.exec("update auth.users set email_confirmed_at=now(),is_anonymous=true where email='viewer@example.test'");
 await fails(()=>rpc('viewer','version'),/UNAUTHORIZED/);
 await db.exec("update auth.users set is_anonymous=false,banned_until=now()+interval '1 day' where email='viewer@example.test'");
 await fails(()=>rpc('viewer','version'),/UNAUTHORIZED/);
 await db.exec("update auth.users set banned_until=null where email='viewer@example.test'");
 await db.exec("update public.laundry_members set active=false where email='viewer@example.test'");
 await fails(()=>rpc('viewer','version'),/ACCESS_DENIED/);
 await db.exec("update public.laundry_members set active=true where email='viewer@example.test'");
 await db.exec('delete from auth.sessions');
 await fails(()=>rpc('owner','version'),/SESSION_REVOKED/);
 await db.query('insert into auth.sessions values($1,$2)',[session,ids.owner]);
 await rpc('owner','save',{changes:{clientRecords:[{id:'C1',name:'Fixture',active:true},{id:'C2',name:'Other',active:true}],processing:[{id:'P1',name:'Wash',active:true,wash:true},{id:'R1',name:'Patch',category:'repairType',unit:'piece',priceMills:1234,active:false,repairActive:true}]}},true);
 const lot=(await rpc('operator','lot_create',{client:'Fixture',colli:1},true)).lot;
 const other=(await rpc('operator','lot_create',{client:'Other',colli:1},true)).lot;
 const acquire=(lot_id,code)=>rpc('operator','lot_acquire',{lot_id,code,processing_id:'P1'},true);
 await acquire(lot.id,'000AbC');
 const product=()=>scalar("select data from public.laundry_products where id='000AbC'");
 const getLot=()=>scalar('select data from public.laundry_lots where id=$1',[lot.id]);
 check((await product()).id==='000AbC','leading zeros and case preserved');
 check((await product()).type==='Da definire','unknown type preserved');
 let count=await rev();
 await fails(()=>acquire(lot.id,'000abc'),/DUPLICATE_SCAN/);
 check(await rev()===count,'rejected duplicate does not increment revision');
 await fails(()=>acquire(other.id,'000AbC'),/PRODUCT_ALREADY_IN_OPEN_LOT/);
 await fails(()=>rpc('operator','lot_acquire',{lot_id:lot.id,code:'bad',processing_id:'missing'},true),/PROCESSING_REQUIRED/);
 await rpc('owner','catalog_save',{kind:'type',id:'T1',name:'Gown'},true);
 await rpc('operator','lot_set_type',{lot_id:lot.id,codes:['000AbC'],type_id:'T1'},true);
 check((await product()).raw.TIPO==='Gown','type assignment updates label');
 const saveLot=(data,garment)=>rpc('operator','save',{changes:{lots:[data],...(garment?{garments:[garment]}:{})}},true);
 let l=await getLot();l.rows[0].state='Uscito';
 await fails(()=>saveLot(l),/WORK_NOT_COMPLETED/);
 l.rows[0].completed=true;l.rows[0].repair=true;
 await fails(()=>saveLot(l),/OPEN_INTERVENTIONS/);
 l.rows[0].repair=false;l.rows[0].rewashPending=true;
 await fails(()=>saveLot(l),/OPEN_INTERVENTIONS/);
 l=await getLot();l.rows[0].state='Lavato';l.rows[0].washed=true;l.rows[0].completed=true;
 let g=await product();g.wash=1;
 await saveLot(l,g);
 l=await getLot();l.rows[0].rewash=true;l.rows[0].rewashPending=true;l.rows[0].completed=false;
 await saveLot(l);
 l.rows[0].rewashPending=false;l.rows[0].washed=true;l.rows[0].completed=true;l.rows[0].washCycles=2;
 g=await product();g.wash=2;await saveLot(l,g);
 // The client stores historical repair prices as integer thousandths, not floats.
 l=await getLot();l.rows[0].repairWork=[{id:'work1',repairTypeId:'R1',name:'Patch',unit:'piece',priceMills:1234,quantity:3,minutesHundredths:125,costMills:3702,completedByEmail:'operator@example.test'}];
 await saveLot(l);
 check((await getLot()).rows[0].repairWork[0].costMills===3702,'three-decimal repair cost survives SQL round trip');
 await rpc('owner','save',{changes:{processing:[{id:'R1',name:'Patch',category:'repairType',unit:'piece',priceMills:9999,active:false,repairActive:true}]}},true);
 check((await getLot()).rows[0].repairWork[0].priceMills===1234,'historical repair price unchanged');
 await fails(()=>rpc('owner','catalog_delete',{kind:'processing',id:'R1'},true),/DELETE_IN_USE/);
 l=await getLot();l.rows[0].state='Uscito';await saveLot(l);
 const stale=await rev();await saveLot(l);
 check((await product()).wash===2,'repeated exit save does not add washes');
 await fails(()=>rpc('operator','save',{revision:stale,changes:{lots:[l]}}),/REVISION_CONFLICT/);
 await fails(()=>saveLot({...l,rows:[]}),/CANNOT_REMOVE_LOT_PRODUCT/);
 await fails(()=>acquire(other.id,'000AbC'),/LOT_PRODUCT_CLIENT_MISMATCH/);
 const next=(await rpc('operator','lot_create',{client:'Fixture',colli:1},true)).lot;
 // Rename barcode through the actual authenticated public RPC.
 await rpc('owner','version');
 const payload={revision:await rev(),original_id:'000AbC',mode:'manual',product:{...await product(),id:'NEW-001'}};
 await db.exec('set role authenticated');
 try{await db.query('select public.laundry_product_save($1::jsonb)',[JSON.stringify(payload)]);}finally{await db.exec('reset role');}
 await acquire(next.id,'new-001');
 await fails(()=>acquire(next.id,'000abc'),/DUPLICATE_SCAN/);
 check(await scalar('select count(*)::int from public.laundry_products')===1,'old and new barcodes resolve to stable product ID');
 check(await scalar("select count(*)::int from public.laundry_audit where action='super_admin_designated'")===1,'designation audited once');
 check(await scalar("select data ? 'stations' from public.laundry_production where id"),'later production migration preserved');
 check(await scalar("select to_regprocedure('public.laundry_client_calendar(text,jsonb)') is not null"),'calendar RPC preserved');
 await verify();passed++;
 if(mode==='current'){
  const definition=await scalar("select pg_get_functiondef('laundry_private.laundry_core(jsonb,text,jsonb)'::regprocedure)");
  await db.exec(definition.replace('declare m public.laundry_members;','-- simulated out-of-band change\ndeclare m public.laundry_members;'));
  await fails(()=>verify(),/FUNCTION_DRIFT/);
  await db.exec(definition);
  await verify();passed++;
 }
 console.log(`PASS database upgrade: ${mode}`);
 }finally{await db.close();}
}
try { for(const mode of ['current','reverted','unassigned','acquisition-only','admin-after-barcode','deployed-history'])await suite(mode); } catch(e) {console.error(e.message, e.where ?? '', e.stack?.split('\n').filter(l=>l.includes('regression.mjs')).join('\n'));process.exit(1);}
console.log(`PASS ${passed} database assertions (isolated PostgreSQL/PGlite, mocked Supabase auth schema)`);
