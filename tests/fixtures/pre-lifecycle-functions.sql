-- Snapshot of existing function definitions for integration regression tests. No application records.
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
 if exists(select 1 from public.laundry_lots l cross join lateral jsonb_array_elements(l.data->'rows') r where r->>'state'<>'Uscito' group by r->>'code' having count(*)>1) then raise exception 'PRODUCT_ALREADY_IN_OPEN_LOT';end if;
 update public.laundry_meta set revision=revision+1 where id;
 insert into public.laundry_audit(actor_email,actor_id,action,details) values(actor_email,actor_id,'save',jsonb_build_object('revision',rev+1,'entities',array(select jsonb_object_keys(changes))));
 return jsonb_build_object('revision',rev+1);
end;$function$
;
CREATE OR REPLACE FUNCTION laundry_private.product_save_core(p_actor jsonb, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare m public.laundry_members; rev bigint; product jsonb; previous jsonb; original_id text; barcode text; internal_id text; previous_barcode text; event_data jsonb;
begin
 if nullif(p_actor->>'id','') is null then raise exception 'IDENTITY_REQUIRED';end if;
 select * into m from public.laundry_members where email=lower(p_actor->>'email') and active;
 if not found or not coalesce((laundry_private.permission_set(m.email)->'permissions'->>'products_manage')::boolean,false) then raise exception 'FORBIDDEN';end if;
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
end;$function$
;
CREATE OR REPLACE FUNCTION laundry_private.wash_sync_product_phases()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare l record; next_rows jsonb; changed boolean:=false;
begin
 for l in select ll.* from public.laundry_lots ll where exists(select 1 from public.laundry_wash_items i where i.lot_id=ll.id) for update loop
  select jsonb_agg(case when b.id is null or r->>'state'='Uscito' then r
   when b.state in ('running','blocked') then r||jsonb_build_object('state','In lavaggio','completed',false,'washBatchId',b.id,'washBatchState',b.state,'requiresFolding',true)
   when b.state='estimated' and nullif(r->>'foldedAt','') is null then r||jsonb_build_object('state','In lavorazione','completed',false,'washBatchId',b.id,'washBatchState',b.state,'requiresFolding',true)
   else r||jsonb_build_object('washBatchId',b.id,'washBatchState',b.state,'requiresFolding',true) end order by n)
  into next_rows from jsonb_array_elements(l.data->'rows') with ordinality x(r,n)
  left join public.laundry_wash_items wi on wi.lot_id=l.id and wi.code=r->>'code'
  left join public.laundry_wash_batches b on b.id=wi.batch_id;
  if next_rows is distinct from l.data->'rows' then update public.laundry_lots set data=jsonb_set(data,'{rows}',next_rows) where id=l.id;changed:=true;end if;
 end loop;
 if changed then update public.laundry_meta set revision=revision+1 where id;end if;
end $function$
;
CREATE OR REPLACE FUNCTION laundry_private.dry_sync_product_phases()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare l record; next_rows jsonb; changed boolean:=false;
begin
 for l in select ll.* from public.laundry_lots ll where exists(select 1 from public.laundry_wash_items i join public.laundry_wash_batches b on b.id=i.batch_id where i.lot_id=ll.id and b.requires_drying) for update loop
  select jsonb_agg(case when b.id is null or not b.requires_drying or r->>'state'='Uscito' then r
   when b.state<>'estimated' then (r-'dryCycleId')||jsonb_build_object('requiresDrying',true,'dryState','waiting_wash')
   when c.id is null then (r-'dryCycleId')||jsonb_build_object('requiresDrying',true,'dryState','pending')
   else r||jsonb_build_object('requiresDrying',true,'dryState',case when c.state='estimated' then 'done' else c.state end,'dryCycleId',c.id) end order by n)
  into next_rows from jsonb_array_elements(l.data->'rows') with ordinality x(r,n)
  left join public.laundry_wash_items wi on wi.lot_id=l.id and wi.code=r->>'code'
  left join public.laundry_wash_batches b on b.id=wi.batch_id
  left join public.laundry_dry_cycles c on c.wash_batch_id=b.id;
  if next_rows is distinct from l.data->'rows' then update public.laundry_lots set data=jsonb_set(data,'{rows}',next_rows) where id=l.id;changed:=true;end if;
 end loop;
 if changed then update public.laundry_meta set revision=revision+1 where id;end if;
end $function$
;
CREATE OR REPLACE FUNCTION laundry_private.wash_batch_tick()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare d jsonb; old_d jsonb; b public.laundry_wash_batches; l jsonb; row_item jsonb; codes text[]; changed boolean:=false; completed_ids text[];
begin
 perform 1 from public.laundry_meta where id for update;
 select data into d from public.laundry_production where id for update; old_d:=d;
 for b in select * from public.laundry_wash_batches where state='running' order by created_at for update loop
  if not exists(select 1 from jsonb_array_elements(d->'machines') m where m->>'id'=b.machine_id and coalesce(m->>'active','true')='true') or exists(select 1 from jsonb_array_elements(d->'tickets') t where t->>'machineId'=b.machine_id and t->>'blocking'='true' and t->>'status'<>'closed') then
   update public.laundry_wash_batches set state='blocked',events=events||jsonb_build_array(jsonb_build_object('at',now(),'action','blocked_by_ticket')) where id=b.id;
   continue;
  end if;
  if b.expected_end>now() then continue;end if;
  update public.laundry_wash_batches set state='estimated' where id=b.id;
  select data into l from public.laundry_lots where id=b.lot_id for update;
  select array_agg(code) into codes from public.laundry_wash_items where batch_id=b.id;
  for row_item in select value from jsonb_array_elements(l->'rows') where value->>'code'=any(codes) loop
   if row_item->>'state'<>'Uscito' and coalesce(row_item->>'washed','false')<>'true' then
    update public.laundry_products set data=jsonb_set(data,'{wash}',to_jsonb(coalesce((data->>'wash')::integer,0)+1)) where id=row_item->>'code';
   end if;
  end loop;
  l:=jsonb_set(l,'{rows}',(select jsonb_agg(case when r->>'code'=any(codes) and r->>'state'<>'Uscito' then r||jsonb_build_object('state','In lavorazione','washed',true,'completed',false,'washBatchState','estimated','requiresFolding',true,'washBatchId',b.id,'washCompletionSource','program_estimate') else r end order by n) from jsonb_array_elements(l->'rows') with ordinality a(r,n)));
  l:=jsonb_set(l,'{events}',coalesce(l->'events','[]')||jsonb_build_array(jsonb_build_object('time',to_char(now() at time zone 'Europe/Rome','DD/MM/YYYY, HH24:MI:SS'),'action','Fine ciclo prevista · '||b.program_name||' · '||b.machine_name,'code','','actor','Sistema · durata programma')));
  update public.laundry_lots set data=l where id=b.lot_id;
  update public.laundry_wash_batches set state='estimated',events=events||jsonb_build_array(jsonb_build_object('at',now(),'action','expected_cycle_end')) where id=b.id;
  changed:=true;
 end loop;
 -- Reconcile only unstarted wash tasks fully covered by these new, elapsed batches.
 select coalesce(array_agg(t->>'id'),array[]::text[]) into completed_ids from jsonb_array_elements(d->'tasks') t
 where t->>'status'='pending' and coalesce(t->'sessions','[]')='[]'::jsonb and jsonb_array_length(coalesce(t->'items','[]'))>0
 and exists(select 1 from jsonb_array_elements(d->'types') typ where typ->>'id'=t->>'typeId' and typ->>'mode'='machine' and typ->>'machineKind' in ('water','decon','dry'))
 and not exists(select 1 from jsonb_array_elements(t->'items') i where not exists(select 1 from public.laundry_wash_items wi join public.laundry_wash_batches wb on wb.id=wi.batch_id where wi.lot_id=(i->>'lotId')::bigint and wi.code=i->>'code' and wb.state='estimated'));
 if cardinality(completed_ids)>0 then
  d:=jsonb_set(d,'{tasks}',(select jsonb_agg(case when t->>'id'=any(completed_ids) then t||jsonb_build_object('status','completed','completedAt',now(),'completionSource','machine_program_estimate','events',coalesce(t->'events','[]')||jsonb_build_array(jsonb_build_object('at',now(),'action','wash_batches_elapsed'))) else t end order by n) from jsonb_array_elements(d->'tasks') with ordinality a(t,n)));
  if jsonb_typeof(d->'plan')='object' then
   d:=jsonb_set(d,'{plan,allocations}',(select coalesce(jsonb_agg(a),'[]') from jsonb_array_elements(d#>'{plan,allocations}') a where not(a->>'taskId'=any(completed_ids))));
   d:=jsonb_set(d,'{plan,issues}',(select coalesce(jsonb_agg(a),'[]') from jsonb_array_elements(d#>'{plan,issues}') a where not(a->>'taskId'=any(completed_ids))));
   d:=jsonb_set(d,'{plan,stale}','true');
  end if;
  update public.laundry_production set data=d,revision=revision+1 where id;
 end if;
 perform laundry_private.wash_sync_product_phases();
 perform laundry_private.dry_sync_product_phases();
 if changed then update public.laundry_meta set revision=revision+1 where id;end if;
end $function$
;
CREATE OR REPLACE FUNCTION laundry_private.sync_repairs()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare r jsonb;k text;
begin
 for r in select value from jsonb_array_elements(new.data->'rows') loop
  foreach k in array array['repair','relabel','verify'] loop
   if coalesce((r->>k)::boolean,false) then
    insert into public.laundry_repairs(lot_id,product_code,kind,status) values(new.id,r->>'code',k,'open')
    on conflict(lot_id,product_code,kind) do update set status='open',completed_at=null;
   else update public.laundry_repairs set status='completed',completed_at=coalesce(completed_at,now()) where lot_id=new.id and product_code=r->>'code' and kind=k and status='open';
   end if;
  end loop;
 end loop;
 return new;
end;$function$
;
CREATE OR REPLACE FUNCTION laundry_private.validate_lot_flow()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
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
end;$function$
;
CREATE OR REPLACE FUNCTION laundry_private.wash_batch_guard_lot()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 if exists(select 1 from public.laundry_wash_items wi join public.laundry_wash_batches b on b.id=wi.batch_id
 cross join lateral jsonb_array_elements(new.data->'rows') r
 where wi.lot_id=new.id and r->>'code'=wi.code and b.state<>'estimated'
 and (r->>'state'='Uscito' or r->>'washed'='true' or r->>'completed'='true')
 and not exists(select 1 from jsonb_array_elements(old.data->'rows') o where o->>'code'=wi.code and o->>'state'=r->>'state' and coalesce(o->>'washed','false')=coalesce(r->>'washed','false') and coalesce(o->>'completed','false')=coalesce(r->>'completed','false'))) then raise exception 'WASH_BATCH_IN_PROGRESS';end if;
 if exists(select 1 from public.laundry_wash_items wi join public.laundry_wash_batches b on b.id=wi.batch_id
 cross join lateral jsonb_array_elements(new.data->'rows') r
 where wi.lot_id=new.id and r->>'code'=wi.code and r->>'state'='Uscito'
 and exists(select 1 from jsonb_array_elements(old.data->'rows') o where o->>'code'=wi.code and o->>'state'<>'Uscito')
 and (not exists(select 1 from jsonb_array_elements(old.data->'rows') o where o->>'code'=wi.code and o->>'completed'='true' and nullif(o->>'foldedAt','') is not null)
 or r->>'repair'='true' or r->>'relabel'='true' or r->>'verify'='true' or r->>'rewashPending'='true')) then raise exception 'PRODUCT_NOT_READY_FOR_EXIT';end if;
 return new;
end $function$

