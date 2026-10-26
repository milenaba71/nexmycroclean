begin;
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


 if p_action='version' then return jsonb_build_object('revision',(select revision from public.laundry_meta where id),'user',jsonb_build_object('email',m.email,'name',m.name,'role',m.role));end if;
 if p_action='snapshot' then
  select revision into rev from public.laundry_meta where id;
  return jsonb_build_object('revision',rev,'user',jsonb_build_object('email',m.email,'name',m.name,'role',m.role),'db',jsonb_build_object(
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
  return coalesce((select jsonb_agg(jsonb_build_object('email',email,'name',name,'role',role,'active',active,'registered',site_user_id is not null) order by name) from public.laundry_members),'[]'::jsonb);
 end if;
 if p_action='user_save' then
  if m.role<>'admin' then raise exception 'FORBIDDEN';end if;
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

 if p_action in ('lot_acquire','lot_set_type') then
  select data into l from public.laundry_lots where id=(p_payload->>'lot_id')::bigint;
  if l is null then raise exception 'INVALID_LOT';end if;
  if p_action='lot_acquire' then
   garment_code:=trim(coalesce(p_payload->>'code',''));
   if length(garment_code) not between 1 and 200 or garment_code~'[[:cntrl:]]' then raise exception 'INVALID_BARCODE';end if;
   if exists(select 1 from jsonb_array_elements(l->'rows') r where lower(r->>'code')=lower(garment_code)) then raise exception 'DUPLICATE_SCAN';end if;
   select data into processing_row from public.laundry_processing where id=p_payload->>'processing_id' and coalesce((data->>'active')::boolean,false);
   if processing_row is null then raise exception 'PROCESSING_REQUIRED';end if;
   select data into product from public.laundry_products where id=garment_code;
   if product is null then
    if (select count(*) from public.laundry_products where lower(id)=lower(garment_code))>1 then raise exception 'AMBIGUOUS_BARCODE';end if;
    select data into product from public.laundry_products where lower(id)=lower(garment_code);
   end if;
   if product is not null then garment_code:=product->>'id';end if;
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
 if p_action not in ('snapshot','version','users','user_save','save','lot_create','catalog_save','client_merge','lot_acquire','lot_set_type') then raise exception 'INVALID_ACTION';end if;
 return laundry_private.laundry_core(jsonb_build_object('id',u.id::text,'email',lower(u.email)),p_action,p_payload);
end;$function$

;
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

update public.laundry_meta set revision=revision+1 where id;
commit;
