create or replace function laundry_private.edit_selected_products(p_ids text[],p_patch jsonb,p_revision bigint)
returns jsonb language plpgsql security definer set search_path='' as $$
declare who jsonb; rev bigint; pid text; g jsonb; next_product jsonb; field_key text; field_value text; raw_key text; effective_client text; reason text; updated text[]:='{}'; unchanged text[]:='{}'; skipped jsonb:='[]';
begin
 who:=laundry_private.laundry_authenticated('version','{}')->'user';
 perform laundry_private.require_permission('products_manage');
 if coalesce(cardinality(p_ids),0) not between 1 and 500 or array_position(p_ids,null) is not null then raise exception 'INVALID_SELECTION';end if;
 if jsonb_typeof(p_patch) is distinct from 'object' or p_patch='{}'::jsonb or octet_length(p_patch::text)>20000 then raise exception 'INVALID_PRODUCT_PATCH';end if;
 select revision into rev from public.laundry_meta where id for update;
 if p_revision is distinct from rev then raise exception 'REVISION_CONFLICT';end if;
 for field_key,field_value in select key,value#>>'{}' from jsonb_each(p_patch) loop
  if field_key not in ('type','size','color','client','dept','name','ARMADIO','POSIZIONE','ESTERNA','NOTE','estimatedBirthDate') or jsonb_typeof(p_patch->field_key)<>'string' or length(field_value)>(case when field_key='NOTE' then 5000 else 150 end) then raise exception 'INVALID_PRODUCT_PATCH';end if;
  if field_key in ('type','size','color','client') and btrim(field_value)='' then raise exception 'INVALID_CATALOG_VALUE';end if;
  if field_key='estimatedBirthDate' and field_value<>'' then
   if field_value !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then raise exception 'INVALID_BIRTH_DATE';end if;
   perform field_value::date;
  end if;
  if field_key='type' and not exists(select 1 from public.laundry_types where name=field_value and active) then raise exception 'INVALID_CATALOG_VALUE';end if;
  if field_key='size' and not exists(select 1 from public.laundry_sizes where name=field_value and active) then raise exception 'INVALID_CATALOG_VALUE';end if;
  if field_key='color' and not exists(select 1 from public.laundry_colors where name=field_value and active) then raise exception 'INVALID_CATALOG_VALUE';end if;
  if field_key='client' and not exists(select 1 from public.laundry_clients where data->>'name'=field_value and coalesce((data->>'active')::boolean,true)) then raise exception 'INVALID_CLIENT';end if;
 end loop;
 for pid in select distinct unnest(p_ids) loop
  select data into g from public.laundry_products where id=pid for update;
  reason:=null;
  if g is null then skipped:=skipped||jsonb_build_array(jsonb_build_object('id',pid,'reason','Prodotto non più presente'));continue;end if;
  next_product:=g;
  for field_key,field_value in select key,value#>>'{}' from jsonb_each(p_patch) loop
   raw_key:=case field_key when 'type' then 'TIPO' when 'size' then 'TAGLIA' when 'color' then 'COLORE' when 'client' then 'AZIENDA' when 'dept' then 'REPARTO' when 'name' then 'NOME E COGNOME' when 'estimatedBirthDate' then 'DATA PRESUNTA NASCITA INDUMENTO' else field_key end;
   if field_key in ('type','size','color','client','dept','name') then next_product:=jsonb_set(next_product,array[field_key],to_jsonb(field_value));end if;
   if field_key='estimatedBirthDate' and field_value<>'' then field_value:=to_char(field_value::date,'DD/MM/YYYY');end if;
   next_product:=jsonb_set(next_product,'{raw}',coalesce(next_product->'raw','{}')||jsonb_build_object(raw_key,field_value));
  end loop;
  if next_product=g then unchanged:=array_append(unchanged,pid);continue;end if;
  effective_client:=next_product->>'client';
  if effective_client is distinct from g->>'client' then
   if exists(select 1 from public.laundry_lots l cross join lateral jsonb_array_elements(l.data->'rows') r where r->>'code'=pid and r->>'state' not in ('Uscito','Dismesso')) then reason:='Cambio cliente bloccato: prodotto in un lotto aperto';
   elsif nullif(g->'rentalContract','null'::jsonb) is not null or nullif(g->>'airtableOrderId','') is not null or exists(select 1 from laundry_private.assets where product_id=pid) then reason:='Cambio cliente bloccato: noleggio, cespite o ordine collegato';end if;
  end if;
  if reason is null and (p_patch ? 'client' or p_patch ? 'dept') and coalesce(next_product->>'dept','')<>'' and not exists(select 1 from public.laundry_departments d join public.laundry_clients c on c.id=d.client_id where c.data->>'name'=effective_client and d.name=next_product->>'dept' and d.active) then reason:='Reparto non disponibile per il cliente: scegli un reparto compatibile oppure svuotalo';end if;
  if reason is not null then skipped:=skipped||jsonb_build_array(jsonb_build_object('id',pid,'reason',reason));continue;end if;
  update public.laundry_products set data=next_product where id=pid;
  insert into public.laundry_audit(actor_email,actor_id,action,details) values(who->>'email',auth.uid()::text,'product_bulk_edit',jsonb_build_object('id',pid,'patch',p_patch,'previous',g));
  updated:=array_append(updated,pid);
 end loop;
 if cardinality(updated)>0 then update public.laundry_meta set revision=revision+1 where id;end if;
 perform set_config('laundry.compact_snapshot','on',true);
 perform set_config('laundry.product_ids','[]',true);
 perform set_config('laundry.product_scope','',true);
 return laundry_private.laundry_authenticated('snapshot','{}')||jsonb_build_object('updated_ids',to_jsonb(updated),'unchanged_ids',to_jsonb(unchanged),'skipped',skipped);
end $$;
revoke all on function laundry_private.edit_selected_products(text[],jsonb,bigint) from public,anon;
grant execute on function laundry_private.edit_selected_products(text[],jsonb,bigint) to authenticated;
create or replace function public.laundry_edit_products(p_ids text[],p_patch jsonb,p_revision bigint)
returns jsonb language sql security invoker set search_path='' as $$select laundry_private.edit_selected_products(p_ids,p_patch,p_revision)$$;
revoke all on function public.laundry_edit_products(text[],jsonb,bigint) from public,anon;
grant execute on function public.laundry_edit_products(text[],jsonb,bigint) to authenticated;
