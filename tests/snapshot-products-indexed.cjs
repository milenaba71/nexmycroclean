const fs=require('fs'),assert=require('node:assert/strict'),{PGlite}=require(process.env.PGLITE_PATH);
(async()=>{const pg=new PGlite();const sql=fs.readFileSync('sql/snapshot-products-indexed.sql','utf8');const original=sql.split('$old$')[1];
await pg.exec(`create role anon;create role authenticated;create schema laundry_private;create table laundry_products(id text primary key,data jsonb);create table laundry_lots(id int,data jsonb);
create function laundry_private.product_matches(g jsonb,p jsonb) returns boolean language plpgsql as $$begin return not(p?'client') or g->>'client'=p->>'client';end$$;
insert into laundry_products select i::text,jsonb_build_object('id',i::text,'client',case when i%2=0 then 'A' else 'B' end) from generate_series(1,20000)i;
insert into laundry_lots values(1,'{"rows":[{"code":"1"},{"code":"2"},{"code":"1"}]}');`);
await pg.exec(`create function laundry_private.laundry_core(jsonb,text,jsonb) returns jsonb language plpgsql as $$begin return ${original};end$$;`);
await pg.exec(sql);
for(const compact of ['on','off'])for(const scope of ['', '{}','{"client":"A"}'])for(const ids of ['[]','["2","3","missing","3"]']){
 await pg.query("select set_config('laundry.compact_snapshot',$1,false),set_config('laundry.product_scope',$2,false),set_config('laundry.product_ids',$3,false)",[compact,scope,ids]);
 const row=(await pg.query(`select ${original} old,laundry_private.snapshot_products() new`)).rows[0];assert.deepEqual(row.new,row.old);
}
console.log('PASS indexed snapshot preserves products for full, compact, scoped, duplicate and unknown ids');await pg.close();})().catch(e=>{console.error(e);process.exit(1)});
