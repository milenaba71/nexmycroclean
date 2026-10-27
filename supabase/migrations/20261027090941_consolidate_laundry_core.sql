-- Consolidated upgrade of the legacy laundry database, NOT a fresh-project baseline.
-- Apply only through the ordered migration history; see docs/database-migrations.md.
begin;
set local lock_timeout = '10s';
select pg_advisory_xact_lock(7102701);
do $preflight$
declare current_hash text; required text; expected record; actual_source text;
begin
 if to_regclass('laundry_private.core_release') is not null then
  raise exception 'CORE_RELEASE_ALREADY_INSTALLED: never replay an older release';
 end if;
 foreach required in array array['public.laundry_members','public.laundry_meta','public.laundry_products','public.laundry_clients','public.laundry_processing','public.laundry_lots','public.laundry_repairs','public.laundry_audit','public.laundry_production','laundry_private.client_schedules'] loop
  if to_regclass(required) is null then raise exception 'BASELINE_OR_MIGRATIONS_MISSING: %',required;end if;
 end loop;
 if to_regclass('supabase_migrations.schema_migrations') is null then raise exception 'MIGRATION_HISTORY_RECONCILIATION_REQUIRED';end if;
 -- Both histories are accepted only when the recorded SQL is byte-equivalent
 -- after trimming outer whitespace. Never insert fictitious history entries.
 if exists(select 1 from (values
 ('20261026204528','20261026204930','airtable_customer_orders','011057fffaa01e46c890c70e9a4b24bcd1778abc70e4d9f4f6a24ffc30c47146'),
 ('20261026220115','20261026220326','airtable_lot_orders','29fa4af3b52057ffc61e1e7341509fbe5c3271febd01f57c76e0946b4976e76a'),
 ('20261026222534','20261026224210','production_planning','4b892b07a00ba2d599d0eaa665e4e3f82131d2386f00d5fc4c30baf3902f06b0'),
 ('20261027060819','20261027061157','production_stations','c7eaf51735c14d0952fcbe4af96fcd546bcd1afbe74d79a8c3830c9453730037'),
 ('20261027061557','20261027061714','production_machine_programs','9478f47fce13887e04a191513882f585b857f2798843f46c55d3d121b29b8d90'),
 ('20261027065752','20261027070414','recurring_client_calendar','c91321753d223ccadece47a88b9d0f964d3484bac488822d0bc8a6853c977876'),
 ('20261027072835','20261027073308','client_department_schedules','28d6617c4e90e6528194b4e4365bd39fd8ba207118aafd21bc9ff6923955d2b7')
 ) required(repo_version,db_version,migration_name,sql_hash)
 where not exists(select 1 from supabase_migrations.schema_migrations h
  where h.version in (required.repo_version,required.db_version)
   and h.name=required.migration_name
   and encode(sha256(convert_to(btrim(array_to_string(h.statements,E'\n'),E' \n\r\t'),'UTF8')),'hex')=required.sql_hash
 )) then raise exception 'MIGRATION_ORDER_INVALID_OR_CONTENT_MISMATCH';end if;
 select encode(sha256(convert_to(prosrc,'UTF8')),'hex') into current_hash from pg_proc where oid=to_regprocedure('laundry_private.laundry_core(jsonb,text,jsonb)');
 if current_hash is null or current_hash not in ('0476b4050a0b37761a4a9981cf0848e418a91f7371132a8de2a9b1d1793c1821','0e8f3240c255c31d60ca93463f26f521425e1e2284d0a06b921e35a37d4dd60d','701d3e0ae6f2ad47169781e6d15a4cd0fd7131ce098b59937f8d1706be367700','f4f0f0371ecefd9ba6c5b5490cc3a75e67dc400cdc7ddf4a587a1514dab65549','bbb92a8cbdf2161468b0a15603f8ab424ac59b9e98771d876ac34729a50c1c47') then raise exception 'UNKNOWN_LAUNDRY_CORE_REVIEW_REQUIRED';end if;

 -- Also reject untracked changes in wrappers/triggers: the core alone is not enough.
 for expected in select * from (values ('laundry_private.laundry_authenticated(text,jsonb)',array['136e56b60595af66c5f82dcee6ec92ec3056d0d5fa98498e055ae2e5c4811d6b','efac94ba3a6170cf44114ee9e88cbe07119c018aa91bb990f418a55bbc224cbc','6d04fa09edb5b324102dcc0b61d00dd5da1df509109665a9d6701cc5e228de66']::text[]),
 ('laundry_private.validate_lot_flow()',array['fd380ea10afd2b5bfa73fadcd1d8d0285afb6f847fe251cecf6cea875c686a64','8a55f4d3ff18e6599ca4e3dbff29d5c9b3f9351bca46a7770f8f4176e8c3fda5']::text[]),
 ('laundry_private.guard_product_barcode()',array['20869839a6a4a13898fdfcc4a4191775f0491aa68798db4d03a68c057e21c5ca']::text[]),
 ('laundry_private.product_save_core(jsonb,jsonb)',array['848569d2c4a0e5d1514816adebe65c7ccae1d5854d0caf12424169de395f10c5']::text[]),
 ('laundry_private.product_save_authenticated(jsonb)',array['9222035d9e0a17b02300bd4c67a70c6cecded283ac0055edd177af99e51b641c']::text[]),
 ('public.laundry_product_save(jsonb)',array['2b588da4249e4f954d6b345946ac5444e4503c7df1214366f69132f4de1352c3']::text[])) known(signature,hashes) loop
  select prosrc into actual_source from pg_proc where oid=to_regprocedure(expected.signature);
  if actual_source is not null and not (encode(sha256(convert_to(actual_source,'UTF8')),'hex')=any(expected.hashes)) then
   raise exception 'UNKNOWN_FUNCTION_REVIEW_REQUIRED: %',expected.signature;
  end if;
 end loop;
end;$preflight$;
-- Product master tables. Existing values are preserved, including inactive historic values.
create table if not exists public.laundry_types (
 id text primary key default gen_random_uuid()::text,
 name text not null check(length(trim(name)) between 1 and 150),
 active boolean not null default true);
alter table public.laundry_types enable row level security;
revoke all on public.laundry_types from public,anon,authenticated;
drop policy if exists deny_direct_access on public.laundry_types;
create policy deny_direct_access on public.laundry_types for all to anon,authenticated using(false) with check(false);
create unique index if not exists laundry_types_name_unique on public.laundry_types (lower(trim(name)));
create table if not exists public.laundry_sizes (
 id text primary key default gen_random_uuid()::text,
 name text not null check(length(trim(name)) between 1 and 150),
 active boolean not null default true);
alter table public.laundry_sizes enable row level security;
revoke all on public.laundry_sizes from public,anon,authenticated;
drop policy if exists deny_direct_access on public.laundry_sizes;
create policy deny_direct_access on public.laundry_sizes for all to anon,authenticated using(false) with check(false);
create unique index if not exists laundry_sizes_name_unique on public.laundry_sizes (lower(trim(name)));
create table if not exists public.laundry_colors (
 id text primary key default gen_random_uuid()::text,
 name text not null check(length(trim(name)) between 1 and 150),
 active boolean not null default true);
alter table public.laundry_colors enable row level security;
revoke all on public.laundry_colors from public,anon,authenticated;
drop policy if exists deny_direct_access on public.laundry_colors;
create policy deny_direct_access on public.laundry_colors for all to anon,authenticated using(false) with check(false);
create unique index if not exists laundry_colors_name_unique on public.laundry_colors (lower(trim(name)));
create table if not exists public.laundry_departments (
 id text primary key default gen_random_uuid()::text,
 name text not null check(length(trim(name)) between 1 and 150),
 active boolean not null default true,
 client_id text not null references public.laundry_clients(id));
alter table public.laundry_departments enable row level security;
revoke all on public.laundry_departments from public,anon,authenticated;
drop policy if exists deny_direct_access on public.laundry_departments;
create policy deny_direct_access on public.laundry_departments for all to anon,authenticated using(false) with check(false);
create unique index if not exists laundry_departments_name_unique on public.laundry_departments (client_id,lower(trim(name)));
insert into public.laundry_types(name) select distinct trim(data->>'type') from public.laundry_products where coalesce(trim(data->>'type'),'') not in ('','Da definire') on conflict do nothing;
insert into public.laundry_sizes(name) select distinct trim(data->>'size') from public.laundry_products where coalesce(trim(data->>'size'),'') not in ('','Da definire') on conflict do nothing;
insert into public.laundry_colors(name) select distinct trim(data->>'color') from public.laundry_products where coalesce(trim(data->>'color'),'') not in ('','Da definire') on conflict do nothing;
insert into public.laundry_departments(name,client_id) select distinct trim(p.data->>'dept'),c.id from public.laundry_products p join public.laundry_clients c on c.data->>'name'=p.data->>'client' where coalesce(trim(p.data->>'dept'),'')<>'' on conflict do nothing;

create table if not exists laundry_private.laundry_super_admin (
 singleton boolean primary key default true check(singleton),
 email text not null unique references public.laundry_members(email)
);
-- A legacy, automatically chosen account is retained for review, but not trusted.
alter table laundry_private.laundry_super_admin add column confirmed_at timestamptz;
alter table laundry_private.laundry_super_admin add column confirmed_user_id uuid references auth.users(id);
alter table laundry_private.laundry_super_admin enable row level security;
revoke all on laundry_private.laundry_super_admin from public,anon,authenticated;
create function laundry_private.designate_super_admin(p_user_id uuid, p_expected_previous_email text default null)
returns void language plpgsql security invoker set search_path='' as $fn$
declare candidate auth.users; previous laundry_private.laundry_super_admin;
begin
 lock table public.laundry_members in share row exclusive mode;
 lock table laundry_private.laundry_super_admin in exclusive mode;
 select * into candidate from auth.users where id=p_user_id;
 if not found or candidate.email_confirmed_at is null or coalesce(candidate.is_anonymous,false) or (candidate.banned_until is not null and candidate.banned_until>now())
  or not exists(select 1 from public.laundry_members where email=lower(candidate.email) and role='admin' and active) then raise exception 'INVALID_SUPER_ADMIN_ACCOUNT';end if;
 select * into previous from laundry_private.laundry_super_admin where singleton;
 if previous.confirmed_at is not null then
  if previous.confirmed_user_id=p_user_id and previous.email=lower(candidate.email) then return;end if;
  raise exception 'SUPER_ADMIN_ALREADY_CONFIRMED';
 end if;
 if previous.email is distinct from p_expected_previous_email then raise exception 'SUPER_ADMIN_PREVIOUS_SELECTION_CHANGED';end if;
 insert into laundry_private.laundry_super_admin(singleton,email,confirmed_at,confirmed_user_id)
 values(true,lower(candidate.email),now(),p_user_id)
 on conflict(singleton) do update set email=excluded.email,confirmed_at=excluded.confirmed_at,confirmed_user_id=excluded.confirmed_user_id;
 insert into public.laundry_audit(actor_email,actor_id,action,details)
 values(lower(candidate.email),session_user,'super_admin_designated',jsonb_build_object('user_id',p_user_id,'previous_email',previous.email,'database_actor',session_user));
end;$fn$;
revoke all on function laundry_private.designate_super_admin(uuid,text) from public,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION laundry_private.laundry_core(p_actor jsonb, p_action text, p_payload jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare m public.laundry_members; rev bigint; item jsonb; target text; k text; changes jsonb; new_id bigint; l jsonb; num integer; actor_email text; actor_id text; before_data jsonb; res jsonb; role_before text; catalog_kind text; catalog_name text; catalog_client text; catalog_id text; old_name text; old_client text; catalog_active boolean; product jsonb; processing_row jsonb; garment_code text; event_data jsonb;
begin

 actor_email:=lower(p_actor->>'email');actor_id:=p_actor->>'id';
 if actor_id is null or actor_id='' or actor_email is null then raise exception 'IDENTITY_REQUIRED';end if;
 select * into m from public.laundry_members where email=actor_email and active;
 if not found then raise exception 'ACCESS_DENIED';end if;


 if p_action='version' then return jsonb_build_object('revision',(select revision from public.laundry_meta where id),'user',jsonb_build_object('email',m.email,'name',m.name,'role',m.role,'isSuperAdmin',exists(select 1 from laundry_private.laundry_super_admin sa where sa.confirmed_at is not null and sa.confirmed_user_id::text=actor_id and sa.email=m.email)));end if;
 if p_action='snapshot' then
  select revision into rev from public.laundry_meta where id;
  return jsonb_build_object('revision',rev,'user',jsonb_build_object('email',m.email,'name',m.name,'role',m.role,'isSuperAdmin',exists(select 1 from laundry_private.laundry_super_admin sa where sa.confirmed_at is not null and sa.confirmed_user_id::text=actor_id and sa.email=m.email)),'db',jsonb_build_object(
   'catalogs',jsonb_build_object(
 'type',coalesce((select jsonb_agg(to_jsonb(t) order by name) from public.laundry_types t),'[]'::jsonb),
 'size',coalesce((select jsonb_agg(to_jsonb(t) order by name) from public.laundry_sizes t),'[]'::jsonb),
 'color',coalesce((select jsonb_agg(to_jsonb(t) order by name) from public.laundry_colors t),'[]'::jsonb),
 'dept',coalesce((select jsonb_agg(to_jsonb(t) order by name) from public.laundry_departments t),'[]'::jsonb)),
   'garments',coalesce((select jsonb_agg(data order by id) from public.laundry_products),'[]'::jsonb),
   'clientRecords',coalesce((select jsonb_agg(data order by id) from public.laundry_clients),'[]'::jsonb),
   'processing',coalesce((select jsonb_agg(data order by id) from public.laundry_processing),'[]'::jsonb),
   'lots',coalesce((select jsonb_agg(data order by id) from public.laundry_lots),'[]'::jsonb),
   'repairs',coalesce((select jsonb_agg(to_jsonb(r) order by created_at desc) from public.laundry_repairs r),'[]'::jsonb),
   'next',coalesce((select max(id)+1 from public.laundry_lots),1),
   'nextClient',coalesce((select max(substring(id from 2)::int)+1 from public.laundry_clients where id~'^C[0-9]+$'),1),
   'processingNext',coalesce((select max(substring(id from 2)::int)+1 from public.laundry_processing where id~'^P[0-9]+$'),1)));
 end if;
 if p_action='users' then
  if m.role<>'admin' then raise exception 'FORBIDDEN';end if;
  return coalesce((select jsonb_agg(jsonb_build_object('email',email,'name',name,'role',role,'active',active,'registered',site_user_id is not null,'isSuperAdmin',exists(select 1 from laundry_private.laundry_super_admin sa where sa.confirmed_at is not null and sa.email=laundry_members.email)) order by name) from public.laundry_members),'[]'::jsonb);
 end if;
 if p_action='user_save' then
  if m.role<>'admin' then raise exception 'FORBIDDEN';end if;
  if coalesce(p_payload->>'role','') not in ('admin','operator','viewer') or jsonb_typeof(p_payload->'active') is distinct from 'boolean' then raise exception 'INVALID_USER';end if;
  if exists(select 1 from laundry_private.laundry_super_admin sa where sa.email=lower(p_payload->>'email')) and (p_payload->>'role'<>'admin' or not (p_payload->>'active')::boolean) then raise exception 'SUPER_ADMIN_PROTECTED';end if;
  if not exists(select 1 from laundry_private.laundry_super_admin sa where sa.confirmed_at is not null and sa.confirmed_user_id::text=actor_id and sa.email=m.email) and (p_payload->>'role'='admin' or exists(select 1 from public.laundry_members where email=lower(p_payload->>'email') and role='admin')) then raise exception 'FORBIDDEN_ADMIN_ROLE';end if;
  if not (p_payload->>'role'=any(array['admin','operator','viewer'])) or trim(coalesce(p_payload->>'name',''))='' or p_payload->>'email'!~'^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then raise exception 'INVALID_USER';end if;
  if lower(p_payload->>'email')=m.email and (p_payload->>'role'<>'admin' or not (p_payload->>'active')::boolean) then raise exception 'CANNOT_DISABLE_SELF';end if;
  insert into public.laundry_members(email,name,role,active) values(lower(p_payload->>'email'),p_payload->>'name',p_payload->>'role',(p_payload->>'active')::boolean)
  on conflict(email) do update set name=excluded.name,role=excluded.role,active=excluded.active;
  insert into public.laundry_audit(actor_email,actor_id,action,details) values(actor_email,actor_id,'user_save',p_payload);
  return jsonb_build_object('ok',true);
 end if;
 if m.role='viewer' then raise exception 'FORBIDDEN';end if;
 select revision into rev from public.laundry_meta where id for update;
 if (p_payload->>'revision')::bigint is distinct from rev then raise exception 'REVISION_CONFLICT';end if;

 if p_action='catalog_delete' then
  if m.role<>'admin' then raise exception 'FORBIDDEN';end if;
  catalog_kind:=p_payload->>'kind';catalog_id:=p_payload->>'id';
  target:=case catalog_kind when 'type' then 'laundry_types' when 'size' then 'laundry_sizes' when 'color' then 'laundry_colors' when 'dept' then 'laundry_departments' when 'client' then 'laundry_clients' when 'processing' then 'laundry_processing' end;
  if target is null then raise exception 'INVALID_CATALOG';end if;
  if catalog_kind in ('client','processing') then execute format('select data from public.%I where id=$1',target) into before_data using catalog_id;
  else execute format('select to_jsonb(t) from public.%I t where id=$1',target) into before_data using catalog_id;end if;
  if before_data is null then raise exception 'UNKNOWN_CATALOG';end if;
  catalog_name:=before_data->>'name';
  if catalog_kind in ('type','size','color') and exists(select 1 from public.laundry_products where data->>catalog_kind=catalog_name) then raise exception 'DELETE_IN_USE';end if;
  if catalog_kind='dept' and exists(select 1 from public.laundry_products where data->>'dept'=catalog_name and data->>'client'=(select data->>'name' from public.laundry_clients where id=before_data->>'client_id')) then raise exception 'DELETE_IN_USE';end if;
  if catalog_kind='client' and (exists(select 1 from public.laundry_products where data->>'client'=catalog_name) or exists(select 1 from public.laundry_lots where data->>'client'=catalog_name) or exists(select 1 from public.laundry_departments where client_id=catalog_id)) then raise exception 'DELETE_IN_USE';end if;
  if catalog_kind='processing' and exists(select 1 from public.laundry_lots q cross join lateral jsonb_array_elements(q.data->'rows') r where r->>'processingId'=catalog_id or exists(select 1 from jsonb_array_elements(coalesce(r->'repairWork','[]'::jsonb)) rw where rw->>'repairTypeId'=catalog_id)) then raise exception 'DELETE_IN_USE';end if;
  execute format('delete from public.%I where id=$1',target) using catalog_id;
  update public.laundry_meta set revision=revision+1 where id;
  insert into public.laundry_audit(actor_email,actor_id,action,details) values(actor_email,actor_id,'catalog_delete',jsonb_build_object('kind',catalog_kind,'deleted',before_data));
  return laundry_private.laundry_core(p_actor,'snapshot','{}'::jsonb);
 end if;

 if p_action in ('lot_acquire','lot_set_type') then
  select data into l from public.laundry_lots where id=(p_payload->>'lot_id')::bigint;
  if l is null then raise exception 'INVALID_LOT';end if;
  if p_action='lot_acquire' then
   garment_code:=trim(coalesce(p_payload->>'code',''));
   if length(garment_code) not between 1 and 200 or garment_code~'[[:cntrl:]]' then raise exception 'INVALID_BARCODE';end if;
   if exists(select 1 from jsonb_array_elements(l->'rows') r where lower(r->>'code')=lower(garment_code)) then raise exception 'DUPLICATE_SCAN';end if;
   select data into processing_row from public.laundry_processing where id=p_payload->>'processing_id' and coalesce((data->>'active')::boolean,false);
   if processing_row is null then raise exception 'PROCESSING_REQUIRED';end if;
   if (select count(*) from public.laundry_products g where lower(g.id)=lower(garment_code) or lower(coalesce(nullif(g.data->>'barcode',''),g.id))=lower(garment_code) or exists(select 1 from jsonb_array_elements_text(coalesce(g.data->'barcodeAliases','[]'::jsonb)) a where lower(a)=lower(garment_code)))>1 then raise exception 'AMBIGUOUS_BARCODE';end if;
   select data into product from public.laundry_products g where lower(g.id)=lower(garment_code) or lower(coalesce(nullif(g.data->>'barcode',''),g.id))=lower(garment_code) or exists(select 1 from jsonb_array_elements_text(coalesce(g.data->'barcodeAliases','[]'::jsonb)) a where lower(a)=lower(garment_code));
   if product is not null then garment_code:=product->>'id';end if;
   if exists(select 1 from jsonb_array_elements(l->'rows') r where lower(r->>'code')=lower(garment_code)) then raise exception 'DUPLICATE_SCAN';end if;
   if exists(select 1 from public.laundry_lots other_lot cross join lateral jsonb_array_elements(other_lot.data->'rows') r where r->>'code'=garment_code and r->>'state'<>'Uscito') then raise exception 'PRODUCT_ALREADY_IN_OPEN_LOT';end if;
   if product is null then
    product:=jsonb_build_object('id',garment_code,'name','','client',l->>'client','dept','','type','Da definire','size','Da definire','color','Da definire','wash',0,'max',80,'rental',null,'history','[]'::jsonb,'raw',jsonb_build_object('CODICE',garment_code,'AZIENDA',l->>'client','TIPO','Da definire','SCARTO','NO','DATA DI CREAZIONE',to_char(now() at time zone 'Europe/Rome','DD/MM/YYYY')));
   elsif product->>'client' is distinct from l->>'client' then raise exception 'LOT_PRODUCT_CLIENT_MISMATCH';end if;
   event_data:=jsonb_build_object('action','Entrata · '||(processing_row->>'name'),'code',garment_code,'time',to_char(now() at time zone 'Europe/Rome','DD/MM/YYYY, HH24:MI:SS'),'actor',m.name,'actorEmail',m.email);
   product:=jsonb_set(product,'{history}',coalesce(product->'history','[]'::jsonb)||jsonb_build_array(event_data||jsonb_build_object('lot','L.'||lpad(l->>'id',6,'0')||'-2026')));
   insert into public.laundry_products(id,data) values(garment_code,product) on conflict(id) do update set data=excluded.data;
   l:=jsonb_set(l,'{rows}',(l->'rows')||jsonb_build_array(jsonb_build_object('code',garment_code,'state','Entrato','repair',false,'relabel',false,'verify',false,'replacement',false,'rewash',false,'washed',false,'completed',false,'notes','','processingId',processing_row->>'id','processingName',processing_row->>'name','washRequired',coalesce((processing_row->>'wash')::boolean,true))));
   l:=jsonb_set(l,'{events}',coalesce(l->'events','[]'::jsonb)||jsonb_build_array(event_data));
   l:=jsonb_set(l,'{entryProcessingId}',to_jsonb(processing_row->>'id'));
  else
   select name into catalog_name from public.laundry_types where id=p_payload->>'type_id' and active;
   if catalog_name is null then raise exception 'INVALID_PRODUCT_TYPE';end if;
   if jsonb_typeof(p_payload->'codes') is distinct from 'array' or jsonb_array_length(p_payload->'codes')<1 then raise exception 'SELECT_PRODUCTS';end if;
   for garment_code in select distinct value#>>'{}' from jsonb_array_elements(p_payload->'codes') loop
    if not exists(select 1 from jsonb_array_elements(l->'rows') r where r->>'code'=garment_code) then raise exception 'PRODUCT_NOT_IN_LOT';end if;
    select data into product from public.laundry_products where id=garment_code;
    if product is null then raise exception 'UNKNOWN_PRODUCT';end if;
    event_data:=jsonb_build_object('action','Tipo prodotto assegnato · '||catalog_name||' (prima: '||coalesce(product->>'type','Da definire')||')','code',garment_code,'time',to_char(now() at time zone 'Europe/Rome','DD/MM/YYYY, HH24:MI:SS'),'actor',m.name,'actorEmail',m.email);
    product:=jsonb_set(jsonb_set(product,'{type}',to_jsonb(catalog_name)),'{raw}',coalesce(product->'raw','{}'::jsonb)||jsonb_build_object('TIPO',catalog_name));
    product:=jsonb_set(product,'{history}',coalesce(product->'history','[]'::jsonb)||jsonb_build_array(event_data||jsonb_build_object('lot','L.'||lpad(l->>'id',6,'0')||'-2026')));
    update public.laundry_products set data=product where id=garment_code;
    l:=jsonb_set(l,'{events}',coalesce(l->'events','[]'::jsonb)||jsonb_build_array(event_data));
   end loop;
  end if;
  update public.laundry_lots set data=l where id=(l->>'id')::bigint;
  update public.laundry_meta set revision=revision+1 where id;
  insert into public.laundry_audit(actor_email,actor_id,action,details) values(actor_email,actor_id,p_action,p_payload);
  return laundry_private.laundry_core(p_actor,'snapshot','{}'::jsonb);
 end if;

 if p_action='catalog_save' then
  if m.role<>'admin' then raise exception 'FORBIDDEN';end if;
  catalog_kind:=p_payload->>'kind';catalog_name:=trim(p_payload->>'name');catalog_id:=coalesce(nullif(p_payload->>'id',''),gen_random_uuid()::text);catalog_client:=p_payload->>'client_id';catalog_active:=coalesce((p_payload->>'active')::boolean,true);
  target:=case catalog_kind when 'type' then 'laundry_types' when 'size' then 'laundry_sizes' when 'color' then 'laundry_colors' when 'dept' then 'laundry_departments' end;
  if target is null or catalog_name is null or length(catalog_name) not between 1 and 150 then raise exception 'INVALID_CATALOG';end if;
  execute format('select name from public.%I where id=$1',target) into old_name using catalog_id;
  if catalog_kind='dept' then
   if not exists(select 1 from public.laundry_clients where id=catalog_client) then raise exception 'INVALID_CLIENT';end if;
   execute 'select client_id from public.laundry_departments where id=$1' into old_client using catalog_id;
   if old_client is not null and old_client<>catalog_client then raise exception 'DEPARTMENT_CLIENT_IMMUTABLE';end if;
   insert into public.laundry_departments(id,name,active,client_id) values(catalog_id,catalog_name,catalog_active,catalog_client) on conflict(id) do update set name=excluded.name,active=excluded.active;
  else
   execute format('insert into public.%I(id,name,active) values($1,$2,$3) on conflict(id) do update set name=excluded.name,active=excluded.active',target) using catalog_id,catalog_name,catalog_active;
  end if;
  if old_name is not null and old_name<>catalog_name then
   update public.laundry_products set data=jsonb_set(jsonb_set(data,array[catalog_kind],to_jsonb(catalog_name)),array['raw',case catalog_kind when 'type' then 'TIPO' when 'size' then 'TAGLIA' when 'color' then 'COLORE' else 'REPARTO' end],to_jsonb(catalog_name)) where data->>catalog_kind=old_name and (catalog_kind<>'dept' or data->>'client'=(select data->>'name' from public.laundry_clients where id=catalog_client));
  end if;
  update public.laundry_meta set revision=revision+1 where id;
  insert into public.laundry_audit(actor_email,actor_id,action,details) values(actor_email,actor_id,'catalog_save',p_payload);
  return jsonb_build_object('revision',rev+1);
 end if;
 if p_action='client_merge' then
  if m.role<>'admin' then raise exception 'FORBIDDEN';end if;
  select data->>'name' into old_name from public.laundry_clients where id=p_payload->>'source';
  select data->>'name' into catalog_name from public.laundry_clients where id=p_payload->>'destination' and coalesce((data->>'active')::boolean,true);
  if old_name is null or catalog_name is null or old_name=catalog_name then raise exception 'INVALID_CLIENT';end if;
  catalog_client:=p_payload->>'destination';catalog_kind:=trim(coalesce(p_payload->>'department',''));
  if catalog_kind<>'' then
   insert into public.laundry_departments(name,client_id) values(catalog_kind,catalog_client) on conflict do nothing;
  end if;
  insert into public.laundry_departments(name,client_id,active) select name,catalog_client,active from public.laundry_departments where client_id=p_payload->>'source' on conflict do nothing;
  select coalesce(jsonb_agg(id),'[]'::jsonb) into res from public.laundry_products where data->>'client'=old_name;
  update public.laundry_products set data=jsonb_set(jsonb_set(data,'{client}',to_jsonb(catalog_name)),'{raw,AZIENDA}',to_jsonb(catalog_name)) where data->>'client'=old_name;
  if catalog_kind<>'' then
   update public.laundry_products set data=jsonb_set(jsonb_set(data,'{dept}',to_jsonb(catalog_kind)),'{raw,REPARTO}',to_jsonb(catalog_kind)) where data->>'client'=catalog_name and data->>'id' in (select value#>>'{}' from jsonb_array_elements(res));
  end if;
  update public.laundry_lots set data=jsonb_set(data,'{client}',to_jsonb(catalog_name)) where data->>'client'=old_name;
  update public.laundry_clients set data=data||jsonb_build_object('active',false,'mergedInto',catalog_client) where id=p_payload->>'source';
  update public.laundry_meta set revision=revision+1 where id;
  insert into public.laundry_audit(actor_email,actor_id,action,details) values(actor_email,actor_id,'client_merge',p_payload);
  return jsonb_build_object('revision',rev+1);
 end if;

 if p_action='lot_create' then
  if not exists(select 1 from public.laundry_clients where data->>'name'=p_payload->>'client' and coalesce((data->>'active')::boolean,true)) then raise exception 'INVALID_CLIENT';end if;
  if coalesce((p_payload->>'colli')::int,0)<1 then raise exception 'INVALID_COLLI';end if;
  new_id:=nextval('public.laundry_lot_sequence');
  l:=jsonb_build_object('id',new_id,'client',p_payload->>'client','date',to_char(now() at time zone 'Europe/Rome','YYYY-MM-DD'),'due',p_payload->>'due','colli',(p_payload->>'colli')::int,'rows','[]'::jsonb,'events','[]'::jsonb);
  insert into public.laundry_lots(id,data) values(new_id,l);
  update public.laundry_meta set revision=revision+1 where id;
  insert into public.laundry_audit(actor_email,actor_id,action,details) values(actor_email,actor_id,'lot_create',l);
  return jsonb_build_object('lot',l,'revision',rev+1);
 end if;
 if p_action<>'save' then raise exception 'INVALID_ACTION';end if;
 changes:=p_payload->'changes';
 if changes is null or jsonb_typeof(changes)<>'object' then raise exception 'INVALID_CHANGES';end if;
 for k in select jsonb_object_keys(changes) loop
  if k not in ('garments','clientRecords','processing','lots') then raise exception 'INVALID_ENTITY';end if;
  if m.role='operator' and k in ('clientRecords','processing') and jsonb_array_length(changes->k)>0 then raise exception 'FORBIDDEN';end if;
  target:=case k when 'garments' then 'laundry_products' when 'clientRecords' then 'laundry_clients' when 'processing' then 'laundry_processing' else 'laundry_lots' end;
  for item in select value from jsonb_array_elements(changes->k) loop
   if coalesce(item->>'id','')='' then raise exception 'MISSING_ID';end if;
   if m.role='operator' and k='garments' then
    select data into before_data from public.laundry_products where id=item->>'id';
    if before_data is null or (item-'wash'-'history'-'raw') is distinct from (before_data-'wash'-'history'-'raw') or (coalesce(item->'raw','{}'::jsonb)-'SCARTO') is distinct from (coalesce(before_data->'raw','{}'::jsonb)-'SCARTO') or ((item->'raw'->>'SCARTO') is distinct from (before_data->'raw'->>'SCARTO') and not ((item->>'wash')::int >= (item->>'max')::int and item->'raw'->>'SCARTO'='SI')) then raise exception 'FORBIDDEN_PRODUCT_EDIT';end if;
   end if;
   if k='clientRecords' and exists(select 1 from public.laundry_clients where id<>item->>'id' and lower(trim(data->>'name'))=lower(trim(item->>'name'))) then raise exception 'DUPLICATE_CLIENT';end if;
   if k='garments' and m.role='admin' then
    for catalog_kind in select unnest(array['type','size','color','dept']) loop
     catalog_name:=trim(item->>catalog_kind);
     if coalesce(catalog_name,'') not in ('','Da definire') then
      if catalog_kind='dept' then
       select id into catalog_client from public.laundry_clients where data->>'name'=item->>'client';
       if catalog_client is not null then insert into public.laundry_departments(name,client_id) values(catalog_name,catalog_client) on conflict do nothing;end if;
      else
       target:=case catalog_kind when 'type' then 'laundry_types' when 'size' then 'laundry_sizes' else 'laundry_colors' end;
       execute format('insert into public.%I(name) values($1) on conflict do nothing',target) using catalog_name;
      end if;
     end if;
    end loop;
    target:='laundry_products';
   end if;
   if k='lots' then
    if not exists(select 1 from public.laundry_lots where id=(item->>'id')::bigint) then raise exception 'USE_LOT_CREATE';end if;
    if jsonb_typeof(item->'rows')<>'array' or jsonb_typeof(item->'events')<>'array' then raise exception 'INVALID_LOT';end if;
    if exists(select 1 from jsonb_array_elements(item->'rows') r group by r->>'code' having count(*)>1) then raise exception 'DUPLICATE_SCAN';end if;
    if exists(select 1 from jsonb_array_elements(item->'rows') r where not exists(select 1 from public.laundry_products g where g.id=r->>'code')) then raise exception 'UNKNOWN_PRODUCT';end if;
    execute format('update public.%I set data=$1 where id=$2',target) using item,(item->>'id')::bigint;
   else
    execute format('insert into public.%I(id,data) values($1,$2) on conflict(id) do update set data=excluded.data',target) using item->>'id',item;
   end if;
  end loop;
 end loop;
 if m.role='admin' then
  insert into public.laundry_departments(name,client_id) select distinct trim(p.data->>'dept'),c.id from public.laundry_products p join public.laundry_clients c on c.data->>'name'=p.data->>'client' where coalesce(trim(p.data->>'dept'),'')<>'' on conflict do nothing;
 end if;
 if exists(select 1 from public.laundry_lots l cross join lateral jsonb_array_elements(l.data->'rows') r where r->>'state'<>'Uscito' group by r->>'code' having count(*)>1) then raise exception 'PRODUCT_ALREADY_IN_OPEN_LOT';end if;
 update public.laundry_meta set revision=revision+1 where id;
 insert into public.laundry_audit(actor_email,actor_id,action,details) values(actor_email,actor_id,'save',jsonb_build_object('revision',rev+1,'entities',array(select jsonb_object_keys(changes))));
 return jsonb_build_object('revision',rev+1);
end;$function$

;
CREATE OR REPLACE FUNCTION laundry_private.laundry_authenticated(p_action text, p_payload jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare u auth.users; sid text;
begin
 if auth.uid() is null then raise exception 'UNAUTHORIZED';end if;
 select * into u from auth.users where id=auth.uid();
 if not found or u.email_confirmed_at is null or coalesce(u.is_anonymous,false) or (u.banned_until is not null and u.banned_until>now()) then raise exception 'UNAUTHORIZED';end if;
 sid:=auth.jwt()->>'session_id';
 if sid is null or not exists(select 1 from auth.sessions where id::text=sid and user_id=u.id) then raise exception 'SESSION_REVOKED';end if;
 if p_action not in ('snapshot','version','users','user_save','save','lot_create','catalog_save','client_merge','lot_acquire','lot_set_type','catalog_delete') then raise exception 'INVALID_ACTION';end if;
 return laundry_private.laundry_core(jsonb_build_object('id',u.id::text,'email',lower(u.email)),p_action,p_payload);
end;$function$

;
-- Internal IDs remain stable. Only the barcode used for scanning/labels is editable.
create sequence if not exists public.laundry_barcode_sequence;
-- ALTER SEQUENCE RESTART is transactional; unlike setval it rolls back on failure.
do $sequence$
declare next_code bigint;
begin
 select greatest(
  (select last_value + case when is_called then 1 else 0 end from public.laundry_barcode_sequence),
  coalesce((select max(code::bigint) from (
   select id as code from public.laundry_products
   union all select data->>'barcode' from public.laundry_products
   union all select value from public.laundry_products cross join lateral jsonb_array_elements_text(coalesce(data->'barcodeAliases','[]'::jsonb))
  ) codes where code~'^[0-9]+$' and length(code)<=18),0)+1
 ) into next_code;
 execute format('alter sequence public.laundry_barcode_sequence restart with %s',next_code);
end;$sequence$;
revoke all on sequence public.laundry_barcode_sequence from public,anon,authenticated;
create unique index if not exists laundry_effective_barcode_unique on public.laundry_products(lower(coalesce(nullif(data->>'barcode',''),id)));

-- All aliases remain reserved for the same product, even during CSV imports.
create or replace function laundry_private.guard_product_barcode()
returns trigger language plpgsql security definer set search_path='' as $guard$
declare candidate text;
begin
 perform 1 from public.laundry_meta where id for update;
 if new.data->>'id' is distinct from new.id then raise exception 'PRODUCT_ID_IMMUTABLE';end if;
 if jsonb_typeof(coalesce(new.data->'barcodeAliases','[]'::jsonb))<>'array' then raise exception 'INVALID_BARCODE';end if;
 if tg_op='UPDATE' then
  if coalesce(new.data->'barcodeAliases','[]'::jsonb) @> coalesce(old.data->'barcodeAliases','[]'::jsonb) is not true then raise exception 'BARCODE_HISTORY_IMMUTABLE';end if;
  if coalesce(nullif(new.data->>'barcode',''),new.id)<>coalesce(nullif(old.data->>'barcode',''),old.id) and not coalesce(new.data->'barcodeAliases','[]'::jsonb) @> jsonb_build_array(coalesce(nullif(old.data->>'barcode',''),old.id)) then raise exception 'BARCODE_HISTORY_REQUIRED';end if;
 end if;
 for candidate in select distinct lower(code) from (select new.id as code union all select nullif(new.data->>'barcode','') union all select value from jsonb_array_elements_text(coalesce(new.data->'barcodeAliases','[]'::jsonb))) codes where code is not null loop
  if length(candidate) not between 1 and 200 or candidate~'[[:cntrl:]]' then raise exception 'INVALID_BARCODE';end if;
  if exists(select 1 from public.laundry_products other where other.id<>new.id and (lower(other.id)=candidate or lower(coalesce(nullif(other.data->>'barcode',''),other.id))=candidate or exists(select 1 from jsonb_array_elements_text(coalesce(other.data->'barcodeAliases','[]'::jsonb)) a where lower(a)=candidate))) then raise exception 'BARCODE_ALREADY_EXISTS';end if;
 end loop;
 return new;
end;$guard$;
revoke all on function laundry_private.guard_product_barcode() from public,anon,authenticated;
drop trigger if exists guard_product_barcode on public.laundry_products;
create trigger guard_product_barcode before insert or update on public.laundry_products for each row execute function laundry_private.guard_product_barcode();



create or replace function laundry_private.product_save_core(p_actor jsonb,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path='' as $function$
declare m public.laundry_members; rev bigint; product jsonb; previous jsonb; original_id text; barcode text; internal_id text; previous_barcode text; event_data jsonb;
begin
 if nullif(p_actor->>'id','') is null then raise exception 'IDENTITY_REQUIRED';end if;
 select * into m from public.laundry_members where email=lower(p_actor->>'email') and active;
 if not found or m.role<>'admin' then raise exception 'FORBIDDEN';end if;
 select revision into rev from public.laundry_meta where id for update;
 if (p_payload->>'revision')::bigint is distinct from rev then raise exception 'REVISION_CONFLICT';end if;
 original_id:=nullif(p_payload->>'original_id','');product:=p_payload->'product';
 if product is null or jsonb_typeof(product)<>'object' then raise exception 'INVALID_PRODUCT';end if;
 if original_id is not null then select data into previous from public.laundry_products where id=original_id;if previous is null then raise exception 'UNKNOWN_PRODUCT';end if;end if;
 if p_payload->>'mode'='auto' then
  loop
   barcode:=nextval('public.laundry_barcode_sequence')::text;
   exit when not exists(select 1 from public.laundry_products g where lower(g.id)=lower(barcode) or lower(coalesce(nullif(g.data->>'barcode',''),g.id))=lower(barcode) or exists(select 1 from jsonb_array_elements_text(coalesce(g.data->'barcodeAliases','[]'::jsonb)) a where lower(a)=lower(barcode)));
  end loop;
 elsif p_payload->>'mode'='manual' then barcode:=trim(product->>'id');
 else raise exception 'INVALID_BARCODE_MODE';end if;
 if barcode is null or length(barcode) not between 1 and 200 or barcode~'[[:cntrl:]]' then raise exception 'INVALID_BARCODE';end if;
 if exists(select 1 from public.laundry_products g where g.id is distinct from original_id and (lower(g.id)=lower(barcode) or lower(coalesce(nullif(g.data->>'barcode',''),g.id))=lower(barcode) or exists(select 1 from jsonb_array_elements_text(coalesce(g.data->'barcodeAliases','[]'::jsonb)) a where lower(a)=lower(barcode)))) then raise exception 'BARCODE_ALREADY_EXISTS';end if;
 if not exists(select 1 from public.laundry_clients where data->>'name'=product->>'client') then raise exception 'INVALID_CLIENT';end if;
 if coalesce((product->>'wash')::int,-1)<0 or coalesce((product->>'max')::int,0)<1 then raise exception 'INVALID_WASH_LIMIT';end if;
 if previous is not null and product->>'client' is distinct from previous->>'client' and exists(select 1 from public.laundry_lots q cross join lateral jsonb_array_elements(q.data->'rows') lr where lr->>'code'=original_id and lr->>'state'<>'Uscito') then raise exception 'PRODUCT_IN_OPEN_LOT_CLIENT_CHANGE';end if;
 internal_id:=coalesce(original_id,barcode);previous_barcode:=coalesce(nullif(previous->>'barcode',''),original_id);
 product:=product||jsonb_build_object('id',internal_id,'barcode',barcode,'history',coalesce(previous->'history','[]'::jsonb),'barcodeAliases',coalesce(previous->'barcodeAliases','[]'::jsonb));
 product:=jsonb_set(product,'{raw}',coalesce(product->'raw','{}'::jsonb)||jsonb_build_object('CODICE',barcode));
 if previous_barcode is not null and previous_barcode<>barcode then
  product:=jsonb_set(product,'{barcodeAliases}',(select coalesce(jsonb_agg(distinct value),'[]'::jsonb) from jsonb_array_elements((product->'barcodeAliases')||jsonb_build_array(previous_barcode))));
  event_data:=jsonb_build_object('action','Barcode modificato · '||previous_barcode||' → '||barcode,'code',barcode,'time',to_char(now() at time zone 'Europe/Rome','DD/MM/YYYY, HH24:MI:SS'),'actor',m.name,'actorEmail',m.email);
  product:=jsonb_set(product,'{history}',(product->'history')||jsonb_build_array(event_data));
 end if;
 insert into public.laundry_products(id,data) values(internal_id,product) on conflict(id) do update set data=excluded.data;
 update public.laundry_meta set revision=revision+1 where id;
 insert into public.laundry_audit(actor_email,actor_id,action,details) values(m.email,p_actor->>'id','product_barcode_save',jsonb_build_object('id',internal_id,'previous',previous_barcode,'barcode',barcode,'mode',p_payload->>'mode'));
 return laundry_private.laundry_core(p_actor,'snapshot','{}'::jsonb)||jsonb_build_object('saved_code',barcode,'saved_id',internal_id);
end;$function$;
revoke all on function laundry_private.product_save_core(jsonb,jsonb) from public,anon,authenticated;
create or replace function laundry_private.product_save_authenticated(p_payload jsonb)
returns jsonb language plpgsql security definer set search_path='' as $function$
declare identity_result jsonb;
begin
 identity_result:=laundry_private.laundry_authenticated('version','{}'::jsonb);
 return laundry_private.product_save_core(jsonb_build_object('id',auth.uid()::text,'email',identity_result->'user'->>'email'),p_payload);
end;$function$;
revoke all on function laundry_private.product_save_authenticated(jsonb) from public,anon,authenticated;
grant execute on function laundry_private.product_save_authenticated(jsonb) to authenticated;
create or replace function public.laundry_product_save(p_payload jsonb)
returns jsonb language sql security invoker set search_path='' as $function$select laundry_private.product_save_authenticated(p_payload);$function$;
revoke all on function public.laundry_product_save(jsonb) from public,anon,authenticated;
grant execute on function public.laundry_product_save(jsonb) to authenticated;
create or replace function laundry_private.validate_lot_flow()
returns trigger language plpgsql set search_path='' as $function$
declare r jsonb; previous jsonb;
begin
 if exists(select 1 from jsonb_array_elements(new.data->'rows') as duplicate_row(value) group by lower(duplicate_row.value->>'code') having count(*)>1) then raise exception 'DUPLICATE_SCAN';end if;
 if tg_op='UPDATE' and exists(select 1 from jsonb_array_elements(old.data->'rows') prior where not exists(select 1 from jsonb_array_elements(new.data->'rows') newer where newer->>'code'=prior->>'code')) then
  raise exception 'CANNOT_REMOVE_LOT_PRODUCT';
 end if;
 for r in select value from jsonb_array_elements(new.data->'rows') loop
  previous:=null;
  if tg_op='UPDATE' then select value into previous from jsonb_array_elements(old.data->'rows') where value->>'code'=r->>'code';end if;
  if length(coalesce(r->>'notes',''))>2000 then raise exception 'LOT_NOTE_TOO_LONG';end if;
  if previous is null and not exists(select 1 from public.laundry_products where id=r->>'code' and data->>'client'=new.data->>'client') then raise exception 'LOT_PRODUCT_CLIENT_MISMATCH';end if;
  if r->>'state'='Uscito' and coalesce(previous->>'state','')<>'Uscito' then
   if not (coalesce((r->>'completed')::boolean,false) or coalesce((r->>'washed')::boolean,false)) then raise exception 'WORK_NOT_COMPLETED';end if;
   if coalesce((r->>'repair')::boolean,false) or coalesce((r->>'relabel')::boolean,false) or coalesce((r->>'verify')::boolean,false) or coalesce((r->>'rewashPending')::boolean,false) then raise exception 'OPEN_INTERVENTIONS';end if;
  end if;
 end loop;
 return new;
end;$function$;
revoke all on function laundry_private.validate_lot_flow() from public,anon,authenticated;

drop trigger if exists validate_lot_flow on public.laundry_lots;
create trigger validate_lot_flow before insert or update on public.laundry_lots for each row execute function laundry_private.validate_lot_flow();

-- Internal actor-taking code must never be callable by API roles.
revoke all on function laundry_private.laundry_core(jsonb,text,jsonb) from public,anon,authenticated,service_role;
revoke all on function laundry_private.laundry_authenticated(text,jsonb) from public,anon,authenticated;
grant usage on schema laundry_private to authenticated;
grant execute on function laundry_private.laundry_authenticated(text,jsonb) to authenticated;
create table laundry_private.core_release (
 singleton boolean primary key default true check(singleton),
 version text not null,
 installed_at timestamptz not null default now(),
 function_hashes jsonb not null
);
alter table laundry_private.core_release enable row level security;
revoke all on laundry_private.core_release from public,anon,authenticated,service_role;
insert into laundry_private.core_release(singleton,version,function_hashes)
select true,'20261027090941',jsonb_object_agg(oid::regprocedure::text,encode(sha256(convert_to(pg_get_functiondef(oid),'UTF8')),'hex'))
from pg_proc where oid in (
 'laundry_private.laundry_core(jsonb,text,jsonb)'::regprocedure,
 'laundry_private.laundry_authenticated(text,jsonb)'::regprocedure,
 'laundry_private.validate_lot_flow()'::regprocedure,
 'laundry_private.guard_product_barcode()'::regprocedure,
 'laundry_private.product_save_core(jsonb,jsonb)'::regprocedure
);
update public.laundry_meta set revision=revision+1 where id;
commit;
