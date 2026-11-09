do $$
declare d text; f regprocedure;
begin
 foreach f in array array['laundry_private.permission_set(text)'::regprocedure,'laundry_private.permissions_control(text,jsonb)'::regprocedure] loop
 d:=pg_get_functiondef(f);
 if position('products_delete' in d)>0 then raise exception 'PERMISSION_ALREADY_EXISTS';end if;
 d:=replace(d,'''documents_manage''','''documents_manage'',''products_delete''');
 d:=replace(d,'key_name not in (''planning_delete'',''production_type_delete'')','key_name not in (''planning_delete'',''production_type_delete'',''products_delete'')');
 d:=replace(d,'when ''admin'' then key_name<>''production_type_delete''','when ''admin'' then key_name not in (''production_type_delete'',''products_delete'')');
 d:=replace(d,'jsonb_object_keys(caps-''production_type_delete'')','jsonb_object_keys(caps-''production_type_delete''-''products_delete'')');
 if f='laundry_private.permissions_control(text,jsonb)'::regprocedure then
 d:=replace(d,'update public.laundry_members set role=role_value','if not (caps ? ''products_delete'') then caps:=caps||jsonb_build_object(''products_delete'',role_value=''admin'' and coalesce((old_row.permissions->>''products_delete'')::boolean,false));end if; update public.laundry_members set role=role_value');
 end if;
 execute d;
 end loop;
end $$;

create function laundry_private.delete_selected_products(p_ids text[],p_revision bigint)
returns jsonb language plpgsql security definer set search_path='' as $$
declare who jsonb; rev bigint; pid text; g jsonb; reason text; deleted text[]:='{}'; skipped jsonb:='[]'; tags_before jsonb; response jsonb;
begin
 who:=laundry_private.laundry_authenticated('version','{}')->'user';
 if who->>'role' is distinct from 'admin' then raise exception 'FORBIDDEN';end if;
 perform laundry_private.require_permission('products_delete');
 if coalesce(cardinality(p_ids),0) not between 1 and 500 then raise exception 'INVALID_SELECTION';end if;
 select revision into rev from public.laundry_meta where id for update;
 if p_revision is distinct from rev then raise exception 'REVISION_CONFLICT';end if;
 for pid in select distinct unnest(p_ids) loop
  select data into g from public.laundry_products where id=pid for update;
  reason:=null;
  if g is null then reason:='Prodotto non più presente';
  elsif coalesce((g->>'wash')::numeric,0)>0 or coalesce(jsonb_array_length(g->'history'),0)>0 then reason:='Sono presenti lavaggi o storico';
  elsif exists(select 1 from public.laundry_lots l cross join lateral jsonb_array_elements(l.data->'rows') r where r->>'code'=pid)
   or exists(select 1 from public.laundry_repairs where product_code=pid)
   or exists(select 1 from public.laundry_wash_items where code=pid)
   or exists(select 1 from public.laundry_production p cross join lateral jsonb_array_elements(p.data->'tasks') t cross join lateral jsonb_array_elements(t->'items') i where i->>'code'=pid)
   then reason:='Collegato a lotti, riparazioni o lavorazioni';
  elsif exists(select 1 from laundry_private.assets where product_id=pid or replaced_by=pid or replaces=pid)
   or exists(select 1 from laundry_private.asset_charges where product_id=pid)
   or nullif(g->'rentalContract','null'::jsonb) is not null or nullif(g->>'airtableOrderId','') is not null
   then reason:='Collegato a noleggio, sostituzioni o ordini';
  end if;
  if reason is not null then skipped:=skipped||jsonb_build_array(jsonb_build_object('id',pid,'reason',reason));continue;end if;
  select coalesce(jsonb_agg(to_jsonb(t)),'[]') into tags_before from laundry_private.tag_assignments t where product_id=pid;
  -- Retain the barcode in the registry, so deleted product codes are not reused.
  update laundry_private.tags set state='check',verified_at=null,verified_by=null
   where code in(select tag_code from laundry_private.tag_assignments where product_id=pid and released_at is null);
  delete from laundry_private.tag_assignments where product_id=pid;
  insert into public.laundry_audit(actor_email,actor_id,action,details)
   values(who->>'email',auth.uid()::text,'product_deleted',jsonb_build_object('product',g,'tagAssignments',tags_before,'createdAt',(select created_at from public.laundry_products where id=pid)));
  delete from public.laundry_products where id=pid;
  deleted:=array_append(deleted,pid);
 end loop;
 if cardinality(deleted)>0 then update public.laundry_meta set revision=revision+1 where id;end if;
 perform set_config('laundry.compact_snapshot','on',true);
 perform set_config('laundry.product_ids','[]',true);
 perform set_config('laundry.product_scope','',true);
 response:=laundry_private.laundry_authenticated('snapshot','{}');
 return response||jsonb_build_object('deleted_ids',to_jsonb(deleted),'skipped',skipped);
end $$;
revoke all on function laundry_private.delete_selected_products(text[],bigint) from public,anon,authenticated;
grant execute on function laundry_private.delete_selected_products(text[],bigint) to authenticated;
create function public.laundry_delete_products(p_ids text[],p_revision bigint)
returns jsonb language sql security invoker set search_path='' as $$select laundry_private.delete_selected_products(p_ids,p_revision)$$;
revoke all on function public.laundry_delete_products(text[],bigint) from public,anon,authenticated;
grant execute on function public.laundry_delete_products(text[],bigint) to authenticated;
update public.laundry_meta set revision=revision+1 where id;
