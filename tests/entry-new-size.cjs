const fs=require('fs'),assert=require('node:assert/strict');const {PGlite}=require(process.env.PGLITE_PATH);
(async()=>{const pg=new PGlite();await pg.exec(`create role anon;create role authenticated;create schema laundry_private;create schema auth;
create function auth.uid() returns uuid language sql set search_path=public as $$select '00000000-0000-0000-0000-000000000001'::uuid$$;
create table laundry_meta(id boolean primary key,revision bigint);insert into laundry_meta values(true,1);
create table laundry_lots(id bigint primary key,data jsonb);insert into laundry_lots values(1,'{"rows":[],"departmentName":"Reparto test"}');
create table laundry_products(id text primary key,data jsonb);create table laundry_types(id text primary key,active boolean);insert into laundry_types values('T',true);
create table laundry_processing(id text primary key,data jsonb);insert into laundry_processing values('P','{"active":true,"wash":false}');
create table laundry_audit(id bigint generated always as identity,actor_email text,actor_id text,action text,details jsonb);
create table laundry_sizes(id text primary key,name text,active boolean);insert into laundry_sizes values('M','M',true),('OLD','Old',false);
create sequence codes;
create function laundry_private.next_available_barcode() returns text language sql set search_path=public as $$select nextval('codes')::text$$;
create function laundry_private.require_permission(p text) returns void language plpgsql set search_path=public as $$begin if current_setting('test.denied',true)='yes' or (p='products_manage' and current_setting('test.no_labels',true)='yes') then raise exception 'PERMISSION_DENIED';end if;end $$;
create function laundry_private.laundry_authenticated(a text,p jsonb) returns jsonb language plpgsql set search_path=public as $$begin
 if a='version' then return '{"user":{"email":"test"}}';end if;
 if a='lot_acquire' then
 insert into laundry_products values(p->>'code','{"rental":null,"raw":{}}');
 update laundry_lots set data=jsonb_set(data,'{rows}',data->'rows'||jsonb_build_array(jsonb_build_object('code',p->>'code','state','Entrato'))) where id=(p->>'lot_id')::bigint;
 elsif a='lot_set_type' and p ? 'rental' then update laundry_products set data=data||jsonb_build_object('rental',p->'rental') where id=p->'codes'->>0;
 end if;
 return jsonb_build_object('revision',(select revision from laundry_meta where id));end $$;
create function laundry_private.wash_batch_control(a text,p jsonb) returns jsonb language sql set search_path=public as $$select laundry_private.laundry_authenticated('lot_acquire',jsonb_build_object('code',p->>'code','lot_id',p->'lotId'))$$;`);
await pg.exec(fs.readFileSync('sql/entry-new-product-size.sql','utf8'));
const call=async p=>(await pg.query('select public.laundry_entry_new_product($1) result',[JSON.stringify(p)])).rows[0].result;
for(const rental of [false,true]){const p={lot_id:1,type_id:'T',processing_id:'P',rental,request_id:require('crypto').randomUUID()};const r=await call(p);const saved=(await pg.query('select data from laundry_products where id=$1',[r.saved_id])).rows[0].data;assert.equal(saved.rental,rental);const row=(await pg.query("select r from laundry_lots cross join lateral jsonb_array_elements(data->'rows') r where r->>'code'=$1",[r.saved_id])).rows[0].r;assert.equal(row.relabel,true);assert.equal(row.relabelRequested,true);assert.equal((await call(p)).already_saved,true);await assert.rejects(()=>call({...p,rental:!rental}),/REQUEST_MISMATCH/)}
const legacy={lot_id:1,type_id:'T',processing_id:'P',request_id:require('crypto').randomUUID()};await call(legacy);assert.equal((await call(legacy)).already_saved,true);
await assert.rejects(()=>call({...legacy,request_id:require('crypto').randomUUID(),rental:'false'}),/INVALID_OWNERSHIP/);
assert.equal((await pg.query('select count(*)::int n from laundry_products')).rows[0].n,3);
const sized={...legacy,request_id:require('crypto').randomUUID(),size_id:'M'};
const created=await call(sized);const product=(await pg.query('select data from laundry_products where id=$1',[created.saved_id])).rows[0].data;
assert.equal(product.size,'M');assert.equal(product.raw.TAGLIA,'M');assert.equal((await call(sized)).already_saved,true);
await assert.rejects(()=>call({...sized,size_id:'OLD'}),/REQUEST_MISMATCH/);
for(const size_id of ['OLD','missing',''])await assert.rejects(()=>call({...sized,request_id:require('crypto').randomUUID(),size_id}),/INVALID_PRODUCT_SIZE/);
await pg.exec("set test.no_labels='yes'");
await assert.rejects(()=>call({...sized,request_id:require('crypto').randomUUID()}),/PERMISSION_DENIED/);
await call({...legacy,request_id:require('crypto').randomUUID()});
assert.equal((await pg.query('select count(*)::int n from laundry_products')).rows[0].n,5);
console.log('PASS: size saved in product/raw; invalid sizes rejected; size permission enforced; legacy users still create; size retry/mismatch;  both ownership choices, automatic labels, idempotent retry, ownership mismatch and legacy jobs');await pg.close();})().catch(e=>{console.error(e);process.exit(1)});
