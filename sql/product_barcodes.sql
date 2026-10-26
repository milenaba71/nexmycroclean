begin;
-- Internal IDs remain stable. Only the barcode used for scanning/labels is editable.
create sequence public.laundry_barcode_sequence;
select setval('public.laundry_barcode_sequence',coalesce((select max(code::bigint) from (select id as code from public.laundry_products union all select data->>'barcode' from public.laundry_products union all select value from public.laundry_products cross join lateral jsonb_array_elements_text(coalesce(data->'barcodeAliases','[]'::jsonb))) codes where code~'^[0-9]+$' and length(code)<=18),0)+1,false);
revoke all on sequence public.laundry_barcode_sequence from public,anon,authenticated;
create unique index laundry_effective_barcode_unique on public.laundry_products(lower(coalesce(nullif(data->>'barcode',''),id)));

-- All aliases remain reserved for the same product, even during CSV imports.
create function laundry_private.guard_product_barcode()
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
create trigger guard_product_barcode before insert or update on public.laundry_products for each row execute function laundry_private.guard_product_barcode();

-- Only replace the product lookup in acquisition. Identity and role checks remain unchanged.
do $patch$
declare definition text; original_lookup text; replacement_lookup text;
begin
 definition:=pg_get_functiondef('laundry_private.laundry_core(jsonb,text,jsonb)'::regprocedure);
 original_lookup:=$old$   select data into product from public.laundry_products where id=garment_code;
   if product is null then
    if (select count(*) from public.laundry_products where lower(id)=lower(garment_code))>1 then raise exception 'AMBIGUOUS_BARCODE';end if;
    select data into product from public.laundry_products where lower(id)=lower(garment_code);
   end if;
   if product is not null then garment_code:=product->>'id';end if;$old$;
 replacement_lookup:=$new$   if (select count(*) from public.laundry_products g where lower(g.id)=lower(garment_code) or lower(coalesce(nullif(g.data->>'barcode',''),g.id))=lower(garment_code) or exists(select 1 from jsonb_array_elements_text(coalesce(g.data->'barcodeAliases','[]'::jsonb)) a where lower(a)=lower(garment_code)))>1 then raise exception 'AMBIGUOUS_BARCODE';end if;
   select data into product from public.laundry_products g where lower(g.id)=lower(garment_code) or lower(coalesce(nullif(g.data->>'barcode',''),g.id))=lower(garment_code) or exists(select 1 from jsonb_array_elements_text(coalesce(g.data->'barcodeAliases','[]'::jsonb)) a where lower(a)=lower(garment_code));
   if product is not null then garment_code:=product->>'id';end if;
   if exists(select 1 from jsonb_array_elements(l->'rows') r where lower(r->>'code')=lower(garment_code)) then raise exception 'DUPLICATE_SCAN';end if;$new$;
 if position(original_lookup in definition)=0 then raise exception 'ACQUISITION_LOOKUP_CHANGED_REVIEW_MIGRATION';end if;
 execute replace(definition,original_lookup,replacement_lookup);
end;$patch$;

create function laundry_private.product_save_core(p_actor jsonb,p_payload jsonb)
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
create function laundry_private.product_save_authenticated(p_payload jsonb)
returns jsonb language plpgsql security definer set search_path='' as $function$
declare identity_result jsonb;
begin
 identity_result:=laundry_private.laundry_authenticated('version','{}'::jsonb);
 return laundry_private.product_save_core(jsonb_build_object('id',auth.uid()::text,'email',identity_result->'user'->>'email'),p_payload);
end;$function$;
revoke all on function laundry_private.product_save_authenticated(jsonb) from public,anon,authenticated;
grant execute on function laundry_private.product_save_authenticated(jsonb) to authenticated;
create function public.laundry_product_save(p_payload jsonb)
returns jsonb language sql security invoker set search_path='' as $function$select laundry_private.product_save_authenticated(p_payload);$function$;
revoke all on function public.laundry_product_save(jsonb) from public,anon,authenticated;
grant execute on function public.laundry_product_save(jsonb) to authenticated;
update public.laundry_meta set revision=revision+1 where id;
commit;
