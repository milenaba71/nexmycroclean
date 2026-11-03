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


 if p_action='version' then return jsonb_build_object('revision',(select revision from public.laundry_meta where id),'user',jsonb_build_object('email',m.email,'name',m.name,'role',m.role,'isSuperAdmin',exists(select 1 from laundry_private.laundry_super_admin sa where sa.email=m.email)));end if;
 if p_action='snapshot' then
  select revision into rev from public.laundry_meta where id;
  return jsonb_build_object('revision',rev,'user',jsonb_build_object('email',m.email,'name',m.name,'role',m.role,'isSuperAdmin',exists(select 1 from laundry_private.laundry_super_admin sa where sa.email=m.email)),'db',jsonb_build_object(
   'catalogs',jsonb_build_object(
 'type',coalesce((select jsonb_agg(to_jsonb(t) order by name) from public.laundry_types t),'[]'::jsonb),
 'size',coalesce((select jsonb_agg(to_jsonb(t) order by name) from public.laundry_sizes t),'[]'::jsonb),
 'color',coalesce((select jsonb_agg(to_jsonb(t) order by name) from public.laundry_colors t),'[]'::jsonb),
 'dept',coalesce((select jsonb_agg(to_jsonb(t) order by name) from public.laundry_departments t),'[]'::jsonb)),
   'productsPaged',current_setting('laundry.compact_snapshot',true)='on',
   'garments',coalesce((select jsonb_agg(g.data order by g.id) from public.laundry_products g where current_setting('laundry.compact_snapshot',true) is distinct from 'on' or g.id in (select jsonb_array_elements_text(coalesce(nullif(current_setting('laundry.product_ids',true),''),'[]')::jsonb)) or (nullif(current_setting('laundry.product_scope',true),'') is not null and laundry_private.product_matches(g.data,current_setting('laundry.product_scope',true)::jsonb)) or g.id in (select r->>'code' from public.laundry_lots l cross join lateral jsonb_array_elements(l.data->'rows') r)),'[]'::jsonb),
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
  return coalesce((select jsonb_agg(jsonb_build_object('email',email,'name',name,'role',role,'active',active,'registered',site_user_id is not null,'isSuperAdmin',exists(select 1 from laundry_private.laundry_super_admin sa where sa.email=laundry_members.email)) order by name) from public.laundry_members),'[]'::jsonb);
 end if;
 if p_action='user_save' then
  if m.role<>'admin' then raise exception 'FORBIDDEN';end if;
  if exists(select 1 from laundry_private.laundry_super_admin sa where sa.email=lower(p_payload->>'email')) and (p_payload->>'role'<>'admin' or not (p_payload->>'active')::boolean) then raise exception 'SUPER_ADMIN_PROTECTED';end if;
  if not exists(select 1 from laundry_private.laundry_super_admin sa where sa.email=m.email) and (p_payload->>'role'='admin' or exists(select 1 from public.laundry_members where email=lower(p_payload->>'email') and role='admin')) then raise exception 'FORBIDDEN_ADMIN_ROLE';end if;
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
   if exists(select 1 from jsonb_array_elements(l->'rows') r where lower(r->>'code')=lower(garment_code) and r->>'state'<>'Dismesso') then raise exception 'DUPLICATE_SCAN';end if;
   select data into processing_row from public.laundry_processing where id=p_payload->>'processing_id' and coalesce((data->>'active')::boolean,false);
   if processing_row is null then raise exception 'PROCESSING_REQUIRED';end if;
   product:=laundry_private.tag_lookup(garment_code);
   if product is not null then garment_code:=product->>'id';end if;
   if exists(select 1 from jsonb_array_elements(l->'rows') r where lower(r->>'code')=lower(garment_code) and r->>'state'<>'Dismesso') then raise exception 'DUPLICATE_SCAN';end if;
   if exists(select 1 from public.laundry_lots other_lot cross join lateral jsonb_array_elements(other_lot.data->'rows') r where r->>'code'=garment_code and r->>'state' not in ('Uscito','Dismesso')) then raise exception 'PRODUCT_ALREADY_IN_OPEN_LOT';end if;
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
  if not coalesce((laundry_private.permission_set(m.email)->'permissions'->>'masters_manage')::boolean,false) then raise exception 'FORBIDDEN';end if;
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
  if not coalesce((laundry_private.permission_set(m.email)->'permissions'->>'masters_manage')::boolean,false) then raise exception 'FORBIDDEN';end if;
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
  if not coalesce((laundry_private.permission_set(m.email)->'permissions'->>'masters_manage')::boolean,false) and k in ('clientRecords','processing') and jsonb_array_length(changes->k)>0 then raise exception 'FORBIDDEN';end if;
  target:=case k when 'garments' then 'laundry_products' when 'clientRecords' then 'laundry_clients' when 'processing' then 'laundry_processing' else 'laundry_lots' end;
  for item in select value from jsonb_array_elements(changes->k) loop
   if coalesce(item->>'id','')='' then raise exception 'MISSING_ID';end if;
   if not coalesce((laundry_private.permission_set(m.email)->'permissions'->>'products_manage')::boolean,false) and k='garments' then
    select data into before_data from public.laundry_products where id=item->>'id';
    if before_data is null or (item-'wash'-'history'-'raw') is distinct from (before_data-'wash'-'history'-'raw') or (coalesce(item->'raw','{}'::jsonb)-'SCARTO') is distinct from (coalesce(before_data->'raw','{}'::jsonb)-'SCARTO') or ((item->'raw'->>'SCARTO') is distinct from (before_data->'raw'->>'SCARTO') and not ((item->>'wash')::int >= (item->>'max')::int and item->'raw'->>'SCARTO'='SI')) then raise exception 'FORBIDDEN_PRODUCT_EDIT';end if;
   end if;
   if k='clientRecords' and exists(select 1 from public.laundry_clients where id<>item->>'id' and lower(trim(data->>'name'))=lower(trim(item->>'name'))) then raise exception 'DUPLICATE_CLIENT';end if;
   if k='garments' and coalesce((laundry_private.permission_set(m.email)->'permissions'->>'products_manage')::boolean,false) then
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
 if exists(select 1 from public.laundry_lots l cross join lateral jsonb_array_elements(l.data->'rows') r where r->>'state' not in ('Uscito','Dismesso') group by r->>'code' having count(*)>1) then raise exception 'PRODUCT_ALREADY_IN_OPEN_LOT';end if;
 update public.laundry_meta set revision=revision+1 where id;
 insert into public.laundry_audit(actor_email,actor_id,action,details) values(actor_email,actor_id,'save',jsonb_build_object('revision',rev+1,'entities',array(select jsonb_object_keys(changes))));
 return jsonb_build_object('revision',rev+1);
end;$function$

;
-- Opt-in endpoint: old clients continue receiving their unchanged snapshot.
create or replace function public.laundry_screen(p_rpc text, p_args jsonb default '{}', p_ids jsonb default '[]', p_scope jsonb default null) returns jsonb
language plpgsql set search_path='' as $$
declare result jsonb;
begin
 if jsonb_typeof(p_ids)<>'array' or jsonb_array_length(p_ids)>1000 then raise exception 'INVALID_PRODUCT_IDS'; end if;
 perform set_config('laundry.compact_snapshot','on',true);
 perform set_config('laundry.product_ids',p_ids::text,true);
 perform set_config('laundry.product_scope',coalesce(p_scope::text,''),true);
 case p_rpc
 when 'laundry_app' then result:=public.laundry_app(p_args->>'p_action',coalesce(p_args->'p_payload','{}'));
 when 'laundry_product_save' then result:=public.laundry_product_save(p_args->'p_payload');
 when 'laundry_wash_batches' then result:=public.laundry_wash_batches(p_args->>'p_action',coalesce(p_args->'p_payload','{}'));
 when 'laundry_dry_cycles' then result:=public.laundry_dry_cycles(p_args->>'p_action',coalesce(p_args->'p_payload','{}'));
 when 'laundry_assets' then result:=public.laundry_assets(p_args->>'p_action',coalesce(p_args->'p_payload','{}'));
 when 'laundry_airtable_lot_create' then result:=public.laundry_airtable_lot_create(p_args->'p_payload');
 when 'laundry_planning_delete' then result:=public.laundry_planning_delete(p_args->>'p_action',p_args->'p');
 when 'laundry_production_bulk_delete' then result:=public.laundry_production_bulk_delete(p_args->'p');
 when 'laundry_client_calendar' then result:=public.laundry_client_calendar(p_args->>'p_action',coalesce(p_args->'p_payload','{}'));
 else raise exception 'INVALID_RPC';
 end case;
 if result ? 'saved_id' and result ? 'db' then
  result:=jsonb_set(result,'{db,garments}',(result#>'{db,garments}')||((public.laundry_products_query(jsonb_build_object('ids',jsonb_build_array(result->>'saved_id'))))->'rows'));
 end if;
 return result;
end $$;
-- The invoker has no direct product-table access. Saved product inclusion is done
-- in the private authenticated reader below rather than bypassing RLS.
create or replace function laundry_private.product_field(g jsonb,k text) returns text
language plpgsql stable set search_path='' as $$
declare c jsonb; contract jsonb; answer text;
begin
 if k='id' then return coalesce(nullif(g->>'barcode',''),g->>'id'); end if;
 if k='rental' then return case g->>'rental' when 'true' then 'Mycroclean · Noleggio' when 'false' then 'Proprietà cliente' else 'Da definire' end; end if;
 if k in ('washLimit','discard') then return case when coalesce((g->>'wash')::numeric,0)>=coalesce((g->>'max')::numeric,0) or (k='discard' and upper(g#>>'{raw,SCARTO}') in ('SI','SÌ','TRUE','1')) then 'SI' else 'NO' end; end if;
 if k='workState' then select r->>'state' into answer from public.laundry_lots l cross join lateral jsonb_array_elements(l.data->'rows') r where r->>'code'=g->>'id' order by l.id desc limit 1; return coalesce(answer,'Disponibile'); end if;
 if k='rentalContract' then
  if g->>'rental' is distinct from 'true' then return ''; end if;
  if not g ? 'rentalContract' then return 'Associazione automatica preesistente'; end if;
  if g->'rentalContract'='null' then return 'Scorta · senza contratto'; end if;
  select data into c from public.laundry_clients where id=g#>>'{rentalContract,clientId}';
  select v into contract from jsonb_array_elements(coalesce(c->'rentalContracts','[]')) v where v->>'id'=g#>>'{rentalContract,contractId}';
  return coalesce(contract->>'number','Contratto non disponibile');
 end if;
 if starts_with(k,'raw:') then
  answer:=g->'raw'->>substring(k from 5);
  if substring(k from 5) in ('SCARTO','AL LIMITE ACCETTABILITA','ALLERGICO','SMARRITO') then return case when upper(answer) in ('SI','SÌ','TRUE','1') then 'SI' else 'NO' end;end if;
  return coalesce(answer,'');
 end if;
 return coalesce(g->>k,'');
end $$;
create or replace function laundry_private.product_matches(g jsonb,p jsonb) returns boolean
language plpgsql stable set search_path='' as $$
declare k text; v text; r jsonb; a text; b text; search_text text;
begin
 if p ? 'ids' and not (p->'ids' ? (g->>'id')) then return false; end if;
 if p ? 'client' and g->>'client' is distinct from p->>'client' then return false; end if;
 if p->>'prop'='rent' and g->>'rental' is distinct from 'true' then return false; end if;
 if p->>'prop'='client' and g->>'rental' is distinct from 'false' then return false; end if;
 if p->>'prop'='unknown' and coalesce(g->>'rental','')<>'' then return false; end if;
 if coalesce(p->>'query','')<>'' then
  select string_agg(value,' ') into search_text from jsonb_each_text(coalesce(g->'raw','{}'));
  search_text:=concat_ws(' ',search_text,g->>'id',g->>'barcode',g->>'barcodeAliases',g->>'type',g->>'client',g->>'name',g->>'dept',g->>'size',g->>'color');
  if strpos(lower(search_text),lower(p->>'query'))=0 then return false;end if;
 end if;
 for k,v in select * from jsonb_each_text(coalesce(p->'filters','{}')) loop
  if v<>'' and laundry_private.product_field(g,k)<>v then return false;end if;
 end loop;
 for r in select * from jsonb_array_elements(coalesce(p->'rules','[]')) loop
  a:=laundry_private.product_field(g,r->>'key');b:=coalesce(r->>'value','');
  case r->>'op'
   when 'eq' then if lower(a)<>lower(b) then return false;end if;
   when 'neq' then if lower(a)=lower(b) then return false;end if;
   when 'empty' then if trim(a)<>'' and a<>'Da definire' then return false;end if;
   when 'gte','lte' then
    if a!~'^[+-]?([0-9]+([.][0-9]*)?|[.][0-9]+)$' or b!~'^[+-]?([0-9]+([.][0-9]*)?|[.][0-9]+)$' then return false;end if;
    if r->>'op'='gte' and a::numeric<b::numeric or r->>'op'='lte' and a::numeric>b::numeric then return false;end if;
   else if strpos(lower(a),lower(b))=0 then return false;end if;
  end case;
 end loop;
 return true;
end $$;
create or replace function laundry_private.products_query(p jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare identity jsonb; result jsonb; rows jsonb; total bigint; lim int; offst int;
begin
 identity:=laundry_private.laundry_authenticated('version','{}');
 if p ? 'revision' and (p->>'revision')::bigint<>(identity->>'revision')::bigint then raise exception 'REVISION_CONFLICT';end if;
 if p->>'mode'='lookup' then
  result:=laundry_private.tag_lookup(p->>'code');
  return jsonb_build_object('rows',case when result is null then '[]'::jsonb else jsonb_build_array(result) end,'revision',identity->'revision');
 end if;
 if p->>'mode'='meta' then
  return jsonb_build_object('revision',identity->'revision','total',(select count(*) from public.laundry_products),'clients',coalesce((select jsonb_object_agg(name,stats) from (select data->>'client' name,jsonb_build_object('total',count(*),'rent',count(*) filter(where data->>'rental'='true'),'owned',count(*) filter(where data->>'rental'='false'),'unknown',count(*) filter(where data->>'rental' is null)) stats from public.laundry_products where data->>'client' is not null group by data->>'client') q),'{}'),'facets',coalesce((select jsonb_object_agg(k,vals) from (select k,jsonb_agg(v order by v) vals from (select distinct x.key k,x.value v from public.laundry_products g cross join lateral jsonb_each_text(g.data) x where x.key in ('client','type','size','color','dept') and x.value<>'') a group by k) b),'{}'),'rawKeys',coalesce((select jsonb_agg(k order by k) from (select distinct jsonb_object_keys(coalesce(data->'raw','{}')) k from public.laundry_products) q),'[]'));
 end if;
 lim:=greatest(1,least(1000,coalesce((p->>'limit')::int,50)));offst:=greatest(0,coalesce((p->>'offset')::int,0));
 with matched as materialized (select g.id,g.data from public.laundry_products g where laundry_private.product_matches(g.data,p)), paged as (select * from matched order by id offset offst limit lim)
 select (select count(*) from matched),coalesce((select jsonb_agg(case when p->>'mode'='ids' then to_jsonb(id) else data end order by id) from paged),'[]') into total,rows;
 return jsonb_build_object('rows',rows,'total',total,'revision',identity->'revision');
end $$;
create or replace function public.laundry_products_query(p jsonb default '{}') returns jsonb language sql set search_path='' as $$select laundry_private.products_query(p)$$;
revoke all on function public.laundry_screen(text,jsonb,jsonb,jsonb), public.laundry_products_query(jsonb) from public,anon;
grant execute on function public.laundry_screen(text,jsonb,jsonb,jsonb), public.laundry_products_query(jsonb) to authenticated;
revoke all on function laundry_private.product_field(jsonb,text),laundry_private.product_matches(jsonb,jsonb),laundry_private.products_query(jsonb) from public,anon;
grant execute on function laundry_private.products_query(jsonb) to authenticated;
notify pgrst,'reload schema';
