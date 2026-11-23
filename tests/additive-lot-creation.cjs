// Run against a read-only export of pg_get_functiondef(laundry_private.laundry_core).
// CORE_FUNCTION_FILE=/path/to/core.sql PGLITE_PATH=/path/to/pglite node tests/additive-lot-creation.cjs
const fs=require('fs'),assert=require('node:assert/strict');
const {PGlite}=require(process.env.PGLITE_PATH);
(async()=>{
 const pg=new PGlite();
 const baseline=fs.readFileSync(process.env.CORE_FUNCTION_FILE,'utf8');
 await pg.exec(`create schema laundry_private;
 create table laundry_members(email text primary key,name text,role text,active boolean,site_user_id text,deleted_at timestamptz);
 create table laundry_meta(id boolean primary key,revision bigint);insert into laundry_meta values(true,10);
 create table laundry_clients(id text primary key,data jsonb);
 create table laundry_lots(id bigint primary key,data jsonb);
 create sequence laundry_lot_sequence start 101;
 create table laundry_audit(actor_email text,actor_id text,action text,details jsonb);
 insert into laundry_members values('operator@example.invalid','Operator','operator',true,null,null),('viewer@example.invalid','Viewer','viewer',true,null,null),('inactive@example.invalid','Inactive','operator',false,null,null);
 insert into laundry_clients values('C1','{"name":"TEST CLIENT","active":true}'),('C2','{"name":"INACTIVE CLIENT","active":false}');`);
 await pg.exec(baseline);
 const payload={revision:9,client:'TEST CLIENT',colli:1,due:'2026-11-26'};
 const call=async(action='lot_create',patch={},email='operator@example.invalid')=>(await pg.query('select laundry_private.laundry_core($1,$2,$3) result',[JSON.stringify({id:'test-operator',email}),action,JSON.stringify({...payload,...patch})])).rows[0].result;
 await assert.rejects(()=>call(),/REVISION_CONFLICT/);
 const migration=fs.readFileSync('supabase/migrations/20261123150000_additive_lot_creation.sql','utf8');
 await pg.exec(migration);
 const definition=async()=>(await pg.query("select pg_get_functiondef('laundry_private.laundry_core(jsonb,text,jsonb)'::regprocedure) d")).rows[0].d;
 const installed=await definition();await pg.exec(migration);assert.equal(await definition(),installed);
 // Both operators opened forms at revision 9; intervening scans move the revision forward.
 const first=await call();assert.equal(first.lot.id,101);assert.equal(first.revision,11);
 await pg.exec('update laundry_meta set revision=revision+1');
 const second=await call();assert.equal(second.lot.id,102);assert.equal(second.revision,13);
 assert.deepEqual(first.lot.rows,[]);assert.equal(first.lot.client,'TEST CLIENT');assert.equal(first.lot.colli,1);assert.equal(first.lot.due,payload.due);
 await assert.rejects(()=>call('save'),/REVISION_CONFLICT/);
 await assert.rejects(()=>call('catalog_delete'),/REVISION_CONFLICT/);
 await assert.rejects(()=>call('lot_create',{client:'UNKNOWN'}),/INVALID_CLIENT/);
 await assert.rejects(()=>call('lot_create',{client:'INACTIVE CLIENT'}),/INVALID_CLIENT/);
 await assert.rejects(()=>call('lot_create',{colli:0}),/INVALID_COLLI/);
 await assert.rejects(()=>call('lot_create',{},'viewer@example.invalid'),/FORBIDDEN/);
 await assert.rejects(()=>call('lot_create',{},'inactive@example.invalid'),/ACCESS_DENIED/);
 assert.equal((await pg.query('select count(*)::int n from laundry_lots')).rows[0].n,2);
 assert.equal((await pg.query("select count(*)::int n from laundry_audit where action='lot_create'")).rows[0].n,2);
 assert.equal((await pg.query('select revision::int r from laundry_meta')).rows[0].r,13);
 await pg.close();console.log('PASS: stale-form lot creation, distinct progressive numbers, revisions/audit, edit conflicts, validation, access guards and idempotent migration');
})().catch(e=>{console.error(e);process.exit(1)});
