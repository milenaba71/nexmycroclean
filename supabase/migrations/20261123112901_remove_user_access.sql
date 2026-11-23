ALTER TABLE public.laundry_members ADD COLUMN IF NOT EXISTS deleted_at timestamptz;

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
   'garments',laundry_private.snapshot_products(),
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
  return coalesce((select jsonb_agg(jsonb_build_object('email',email,'name',name,'role',role,'active',active,'registered',site_user_id is not null,'isSuperAdmin',exists(select 1 from laundry_private.laundry_super_admin sa where sa.email=laundry_members.email)) order by name) from public.laundry_members where deleted_at is null),'[]'::jsonb);
 end if;
 if p_action='user_save' then
  if m.role<>'admin' then raise exception 'FORBIDDEN';end if;
  if exists(select 1 from laundry_private.laundry_super_admin sa where sa.email=lower(p_payload->>'email')) and (p_payload->>'role'<>'admin' or not (p_payload->>'active')::boolean) then raise exception 'SUPER_ADMIN_PROTECTED';end if;
  if not exists(select 1 from laundry_private.laundry_super_admin sa where sa.email=m.email) and (p_payload->>'role'='admin' or exists(select 1 from public.laundry_members where email=lower(p_payload->>'email') and role='admin')) then raise exception 'FORBIDDEN_ADMIN_ROLE';end if;
  if not (p_payload->>'role'=any(array['admin','operator','viewer'])) or trim(coalesce(p_payload->>'name',''))='' or p_payload->>'email'!~'^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then raise exception 'INVALID_USER';end if;
  if lower(p_payload->>'email')=m.email and (p_payload->>'role'<>'admin' or not (p_payload->>'active')::boolean) then raise exception 'CANNOT_DISABLE_SELF';end if;
  insert into public.laundry_members(email,name,role,active) values(lower(p_payload->>'email'),p_payload->>'name',p_payload->>'role',(p_payload->>'active')::boolean)
  on conflict(email) do update set name=excluded.name,role=excluded.role,active=excluded.active,deleted_at=null;
  update public.laundry_meta set revision=revision+1 where id;
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
  if catalog_kind='client' then perform laundry_private.prepare_client_deletion(catalog_id,before_data,p_actor);end if;
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
   l:=jsonb_set(l,'{rows}',(l->'rows')||jsonb_build_array(jsonb_build_object('code',garment_code,'state','Entrato','repair',false,'relabel',(coalesce(processing_row->>'name','') = 'Etichettare' and processing_row->>'wash' = 'false'),'verify',false,'replacement',false,'rewash',false,'washed',false,'completed',false,'notes','','processingId',processing_row->>'id','processingName',processing_row->>'name','washRequired',coalesce((processing_row->>'wash')::boolean,true))));
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
    if p_payload ? 'rental' then
     product:=laundry_private.entry_product_ownership(product,p_payload->'rental');
    end if;
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
end;$function$;

CREATE OR REPLACE FUNCTION laundry_private.permissions_control(p_action text, p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare who jsonb; target text; profile_value text; role_value text; caps jsonb; old_row laundry_private.user_permissions; key_name text; ceiling boolean;
begin
 who:=laundry_private.laundry_authenticated('version','{}')->'user';
 perform laundry_private.require_permission('super');
 if p_action='save' then
  target:=lower(trim(p->>'email'));profile_value:=p->>'profile';caps:=p->'permissions';
  if exists(select 1 from laundry_private.laundry_super_admin where email=target) then raise exception 'SUPER_ADMIN_PROTECTED';end if;
  if profile_value not in ('admin','operator','basic','viewer') or profile_value is null or jsonb_typeof(caps) is distinct from 'object' then raise exception 'INVALID_PERMISSIONS';end if;
  role_value:=case profile_value when 'basic' then 'operator' else profile_value end;
  perform 1 from public.laundry_members where email=target and deleted_at is null for update;
  if not found then raise exception 'USER_NOT_FOUND';end if;
  select * into old_row from laundry_private.user_permissions where email=target for update;
  if coalesce(old_row.revision,0) is distinct from (p->>'revision')::bigint then raise exception 'REVISION_CONFLICT';end if;
  for key_name in select jsonb_object_keys(caps) loop
   if key_name not in ('lots_work','lots_create','products_manage','masters_manage','production_execute','production_manage','planning_delete','tickets_manage','airtable_manage','documents_manage','products_delete','production_type_delete','assistant_edit') or jsonb_typeof(caps->key_name)<>'boolean' then raise exception 'INVALID_PERMISSIONS';end if;
   ceiling:=role_value='admin' or (role_value='operator' and key_name not in ('planning_delete','production_type_delete','products_delete'));
   if (caps->>key_name)::boolean and not ceiling then raise exception 'ROLE_PERMISSION_LIMIT';end if;
  end loop;
  if (select count(*) from jsonb_object_keys(caps-'production_type_delete'-'products_delete'-'assistant_edit'))<>10 then raise exception 'INVALID_PERMISSIONS';end if;
  if not (caps ? 'production_type_delete') then caps:=caps||jsonb_build_object('production_type_delete',role_value='admin' and coalesce((old_row.permissions->>'production_type_delete')::boolean,false));end if; if not (caps ? 'products_delete') then caps:=caps||jsonb_build_object('products_delete',role_value='admin' and coalesce((old_row.permissions->>'products_delete')::boolean,false));end if; if not (caps ? 'assistant_edit') then caps:=caps||jsonb_build_object('assistant_edit',role_value in ('admin','operator') and coalesce((old_row.permissions->>'assistant_edit')::boolean,false));end if; update public.laundry_members set role=role_value where email=target;
  insert into laundry_private.user_permissions(email,profile,permissions) values(target,profile_value,caps) on conflict(email) do update set profile=excluded.profile,permissions=excluded.permissions,revision=user_permissions.revision+1,updated_at=now();
  update public.laundry_meta set revision=revision+1 where id;
  insert into public.laundry_audit(actor_email,actor_id,action,details) values(who->>'email',auth.uid()::text,'user_permissions_saved',jsonb_build_object('email',target,'profile',profile_value,'permissions',caps,'previous',to_jsonb(old_row)));
 elsif p_action<>'read' then raise exception 'INVALID_ACTION';end if;
 return (select coalesce(jsonb_agg(jsonb_build_object('email',m.email,'name',m.name,'active',m.active,'role',m.role,'revision',coalesce(u.revision,0))||laundry_private.permission_set(m.email) order by m.name),'[]') from public.laundry_members m left join laundry_private.user_permissions u on u.email=m.email where m.deleted_at is null);
end $function$;

CREATE OR REPLACE FUNCTION public.laundry_user_delete(p_email text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
declare who jsonb; target text:=lower(trim(p_email)); member_before public.laundry_members; permissions_before jsonb; production_before jsonb;
begin
 who:=laundry_private.laundry_authenticated('version','{}')->'user';
 perform laundry_private.require_permission('super');
 if target is null or target='' then raise exception 'USER_NOT_FOUND';end if;
 if target=who->>'email' or exists(select 1 from laundry_private.laundry_super_admin where email=target) then raise exception 'SUPER_ADMIN_PROTECTED';end if;
 -- Same lock order as production/lot writes.
 perform 1 from public.laundry_meta where id for update;
 select * into member_before from public.laundry_members where email=target for update;
 if not found then raise exception 'USER_NOT_FOUND';end if;
 if member_before.deleted_at is not null then return jsonb_build_object('ok',true,'email',target);end if;
 select to_jsonb(u) into permissions_before from laundry_private.user_permissions u where email=target;
 select data into production_before from public.laundry_production where id for update;
 update public.laundry_members set active=false,deleted_at=now() where email=target;
 delete from laundry_private.user_permissions where email=target;
 -- Keep operator identifiers and past activity; exclude from future assignments.
 if exists(select 1 from jsonb_array_elements(coalesce(production_before->'operators','[]')) o where lower(o->>'email')=target) then
  update public.laundry_production set data=jsonb_set(data,'{operators}',
    (select jsonb_agg(case when lower(o->>'email')=target then o||jsonb_build_object('active',false) else o end order by n)
     from jsonb_array_elements(data->'operators') with ordinality a(o,n))),revision=revision+1 where id;
 end if;
 delete from auth.sessions where user_id in(select id from auth.users where lower(email)=target);
 update public.laundry_meta set revision=revision+1 where id;
 insert into public.laundry_audit(actor_email,actor_id,action,details)
 values(who->>'email',auth.uid()::text,'user_deleted',jsonb_build_object('email',target,'previous',to_jsonb(member_before),'permissions',permissions_before));
 return jsonb_build_object('ok',true,'email',target);
end $function$;
REVOKE ALL ON FUNCTION public.laundry_user_delete(text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.laundry_user_delete(text) TO authenticated;

