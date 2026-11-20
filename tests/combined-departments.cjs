const fs=require('fs'),assert=require('node:assert/strict');
const {PGlite}=require(process.env.PGLITE_PATH||'@electric-sql/pglite');
(async()=>{
 const db=new PGlite();
 await db.exec(`create schema laundry_private;create schema auth;
 create function auth.uid() returns uuid language sql as $$select '00000000-0000-0000-0000-000000000001'::uuid$$;
 create table laundry_meta(id boolean primary key);insert into laundry_meta values(true);
 create table laundry_production(id boolean primary key,data jsonb);
 create table laundry_lots(id bigint,data jsonb);
 create table laundry_wash_batches(id uuid primary key,program_id text,machine_kind text,state text,started_at timestamptz,load_group_id uuid,lot_id bigint,machine_id text,created_at timestamptz,events jsonb default '[]');
 create table laundry_wash_items(batch_id uuid);
 create table laundry_audit(actor_email text,actor_id text,action text,details jsonb);
 create function laundry_private.laundry_authenticated(text,jsonb) returns jsonb language sql as $$select '{"user":{"role":"admin","email":"test"}}'::jsonb$$;
 create function laundry_private.require_permission(text) returns void language sql as $$select null::void$$;
 create function laundry_private.require_water_batch_skill(uuid) returns void language sql as $$select null::void$$;
 create function laundry_private.wash_batch_control_single(action text,p jsonb) returns jsonb language plpgsql as $$begin if action='start' then update public.laundry_wash_batches set state='running',machine_id=p->>'machineId' where id=(p->>'batchId')::uuid;end if;return '{}'::jsonb;end$$;`);
 const original=fs.readFileSync('sql/combined-water-loads.sql','utf8');
 let def=original.slice(original.indexOf('CREATE OR REPLACE FUNCTION laundry_private.wash_batch_control(p_action'));

 await db.exec(def);
 await db.exec(fs.readFileSync('supabase/migrations/20261120170850_unified_department_loads.sql','utf8'));
 const ids=['00000000-0000-0000-0000-000000000011','00000000-0000-0000-0000-000000000012'];
 async function seed(kind,capacity=2,second=kind){await db.exec('truncate laundry_wash_batches,laundry_wash_items,laundry_production');await db.query('insert into laundry_production values(true,$1)',[JSON.stringify({machines:[{id:'m',kind,capacity}]})]);for(let i=0;i<2;i++){await db.query("insert into laundry_wash_batches(id,program_id,machine_kind,state,lot_id,machine_id) values($1,'p',$2,'ready',1,'m')",[ids[i],i?second:kind]);await db.query('insert into laundry_wash_items values($1)',[ids[i]])}}
 const p={batchIds:ids,programId:'p',machineId:'m',expectedQuantities:Object.fromEntries(ids.map(id=>[id,1]))};
 for(const kind of ['water','decon','dry']){await seed(kind);await db.query("select laundry_private.wash_batch_control('merge_start',$1)",[JSON.stringify(p)]);const {rows}=await db.query('select count(distinct load_group_id)::int groups,count(*)::int total from laundry_wash_batches where state=\'running\'');assert.deepEqual(rows[0],{groups:1,total:2})}
 await seed('dry',1);await assert.rejects(db.query("select laundry_private.wash_batch_control('merge_start',$1)",[JSON.stringify(p)]),/COMBINED_CAPACITY_EXCEEDED/);
 await seed('water',2,'dry');await assert.rejects(db.query("select laundry_private.wash_batch_control('merge_start',$1)",[JSON.stringify(p)]),/CART_PROGRAMS_DIFFERENT/);
 await db.close();console.log('PASS: water/decon/dry grouped atomically; overcapacity and mixed departments rejected');
})().catch(e=>{console.error(e);process.exit(1)});
