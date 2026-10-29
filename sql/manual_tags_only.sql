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
 if p_payload->>'mode'='auto' then raise exception 'MANUAL_TAG_REQUIRED';
 elsif p_payload->>'mode'='manual' then barcode:=trim(product->>'id');
 else raise exception 'INVALID_BARCODE_MODE';end if;
 if barcode is null or length(barcode) not between 1 and 200 or barcode~'[[:cntrl:]]' then raise exception 'INVALID_BARCODE';end if;
 if laundry_private.tag_conflict(original_id,barcode) then raise exception 'BARCODE_ALREADY_EXISTS';end if;
 if not exists(select 1 from public.laundry_clients where data->>'name'=product->>'client') then raise exception 'INVALID_CLIENT';end if;
 if coalesce((product->>'wash')::int,-1)<0 or coalesce((product->>'max')::int,0)<1 then raise exception 'INVALID_WASH_LIMIT';end if;
 if previous is not null and product->>'client' is distinct from previous->>'client' and exists(select 1 from public.laundry_lots q cross join lateral jsonb_array_elements(q.data->'rows') lr where lr->>'code'=original_id and lr->>'state' not in ('Uscito','Dismesso')) then raise exception 'PRODUCT_IN_OPEN_LOT_CLIENT_CHANGE';end if;
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
