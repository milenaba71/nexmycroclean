

do $patch$ declare definition text; before_check text:=' if exists(select 1 from public.laundry_products g where g.id is distinct from original_id and (lower(g.id)=lower(barcode) or lower(coalesce(nullif(g.data->>''barcode'',''''),g.id))=lower(barcode) or exists(select 1 from jsonb_array_elements_text(coalesce(g.data->''barcodeAliases'',''[]''::jsonb)) a where lower(a)=lower(barcode)))) then raise exception ''BARCODE_ALREADY_EXISTS'';end if;';begin
 definition:=pg_get_functiondef('laundry_private.product_save_core(jsonb,jsonb)'::regprocedure);
 if position(before_check in definition)=0 then raise exception 'ASSET_PRODUCT_SAVE_SOURCE_CHANGED';end if;
 definition:=replace(definition,before_check,' if laundry_private.tag_conflict(original_id,barcode) then raise exception ''BARCODE_ALREADY_EXISTS'';end if;');
 definition:=replace(definition,'lr->>''state''<>''Uscito''','lr->>''state'' not in (''Uscito'',''Dismesso'')');execute definition;
end $patch$;

-- Strict integration with the current scanning and editable-barcode implementation.
do $patch$ declare definition text; before_lookup text:='   if (select count(*) from public.laundry_products g where lower(g.id)=lower(garment_code) or lower(coalesce(nullif(g.data->>''barcode'',''''),g.id))=lower(garment_code) or exists(select 1 from jsonb_array_elements_text(coalesce(g.data->''barcodeAliases'',''[]''::jsonb)) a where lower(a)=lower(garment_code)))>1 then raise exception ''AMBIGUOUS_BARCODE'';end if;
   select data into product from public.laundry_products g where lower(g.id)=lower(garment_code) or lower(coalesce(nullif(g.data->>''barcode'',''''),g.id))=lower(garment_code) or exists(select 1 from jsonb_array_elements_text(coalesce(g.data->''barcodeAliases'',''[]''::jsonb)) a where lower(a)=lower(garment_code));
   if product is not null then garment_code:=product->>''id'';end if;';begin
 definition:=pg_get_functiondef('laundry_private.laundry_core(jsonb,text,jsonb)'::regprocedure);
 if position(before_lookup in definition)=0 then raise exception 'ASSET_LOOKUP_SOURCE_CHANGED';end if;
 definition:=replace(definition,before_lookup,'   product:=laundry_private.tag_lookup(garment_code);
   if product is not null then garment_code:=product->>''id'';end if;');
 definition:=replace(definition,'if exists(select 1 from jsonb_array_elements(l->''rows'') r where lower(r->>''code'')=lower(garment_code))','if exists(select 1 from jsonb_array_elements(l->''rows'') r where lower(r->>''code'')=lower(garment_code) and r->>''state''<>''Dismesso'')');
 definition:=replace(definition,'r->>''state''<>''Uscito''','r->>''state'' not in (''Uscito'',''Dismesso'')');execute definition;
end $patch$;
do $patch$ declare definition text; f regprocedure;begin
 foreach f in array array['laundry_private.wash_sync_product_phases()'::regprocedure,'laundry_private.dry_sync_product_phases()'::regprocedure,'laundry_private.wash_batch_tick()'::regprocedure] loop
 definition:=pg_get_functiondef(f);
 definition:=replace(definition,'r->>''state''=''Uscito''','r->>''state'' in (''Uscito'',''Dismesso'')');
 definition:=replace(definition,'r->>''state''<>''Uscito''','r->>''state'' not in (''Uscito'',''Dismesso'')');
 definition:=replace(definition,'row_item->>''state''<>''Uscito''','row_item->>''state'' not in (''Uscito'',''Dismesso'')');execute definition;
 end loop;
end $patch$;

-- Cancel outstanding repair requests without recording work that never happened.
alter table public.laundry_repairs add column if not exists cancelled_at timestamptz;
alter table public.laundry_repairs add column if not exists cancellation_reason text;
do $$declare c record;begin
 for c in select conname from pg_constraint where conrelid='public.laundry_repairs'::regclass and contype='c' and pg_get_constraintdef(oid) like '%status%' loop execute format('alter table public.laundry_repairs drop constraint %I',c.conname);end loop;
end $$;
alter table public.laundry_repairs add constraint laundry_repairs_lifecycle_status check(status in ('open','completed','cancelled'));
do $patch$ declare definition text;begin
 definition:=pg_get_functiondef('laundry_private.sync_repairs()'::regprocedure);
 if position('  foreach k in array' in definition)=0 then raise exception 'ASSET_REPAIR_SOURCE_CHANGED';end if;
 definition:=replace(definition,'  foreach k in array',E'  if r->>''state''=''Dismesso'' then\n   update public.laundry_repairs set status=''cancelled'',cancelled_at=now(),cancellation_reason=''Capo dismesso'',completed_at=null where lot_id=new.id and product_code=r->>''code'' and status=''open'';\n   continue;\n  end if;\n  foreach k in array');execute definition;
end $patch$;
-- Do not allow legacy planning endpoints to restart work on a dismissed garment.
create function laundry_private.asset_production_guard() returns trigger language plpgsql security definer set search_path='' as $$
declare t jsonb;
begin
 for t in select value from jsonb_array_elements(new.data->'tasks') where value->>'status' not in ('completed','cancelled') loop
  if exists(select 1 from jsonb_array_elements(t->'items') i join laundry_private.assets a on a.product_id=i->>'code' where a.state in ('retired','bought_out')) then raise exception 'ASSET_RETIRED';end if;
 end loop;
 return new;
end $$;
revoke all on function laundry_private.asset_production_guard() from public,anon,authenticated;
create trigger asset_production_guard before update on public.laundry_production for each row execute function laundry_private.asset_production_guard();
