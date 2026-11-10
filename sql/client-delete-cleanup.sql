-- Internal helper: called only after authenticated catalog-delete permission and revision checks.
create or replace function laundry_private.prepare_client_deletion(p_id text,p_client jsonb,p_actor jsonb)
returns void language plpgsql security invoker set search_path='' as $$
declare departments_before jsonb; department_ids text[]; ref_id text;
begin
 if exists(select 1 from public.laundry_products where data->>'client'=p_client->>'name' or jsonb_path_exists(data,'$.** ? (@ == $ref)',jsonb_build_object('ref',p_id))) then raise exception 'DELETE_CLIENT_PRODUCTS';end if;
 if exists(select 1 from public.laundry_lots where data->>'client'=p_client->>'name' or jsonb_path_exists(data,'$.** ? (@ == $ref)',jsonb_build_object('ref',p_id))) then raise exception 'DELETE_CLIENT_LOTS';end if;
 if coalesce(jsonb_array_length(p_client->'serviceContracts'),0)>0 or coalesce(jsonb_array_length(p_client->'rentalContracts'),0)>0 then raise exception 'DELETE_CLIENT_CONTRACTS';end if;
 if exists(select 1 from public.laundry_airtable_client_map where client_id=p_id) then raise exception 'DELETE_CLIENT_AIRTABLE';end if;
 select coalesce(jsonb_agg(to_jsonb(d)),'[]'),coalesce(array_agg(d.id),'{}') into departments_before,department_ids from public.laundry_departments d where client_id=p_id;
 foreach ref_id in array array_prepend(p_id,department_ids) loop
  if exists(select 1 from public.laundry_production where jsonb_path_exists(data,'$.** ? (@ == $ref)',jsonb_build_object('ref',ref_id))) then raise exception 'DELETE_CLIENT_PLANNING';end if;
  if exists(select 1 from public.laundry_airtable_orders where jsonb_path_exists(data,'$.** ? (@ == $ref)',jsonb_build_object('ref',ref_id))) then raise exception 'DELETE_CLIENT_AIRTABLE';end if;
  if ref_id<>p_id and (exists(select 1 from public.laundry_products where jsonb_path_exists(data,'$.** ? (@ == $ref)',jsonb_build_object('ref',ref_id))) or exists(select 1 from public.laundry_lots where jsonb_path_exists(data,'$.** ? (@ == $ref)',jsonb_build_object('ref',ref_id)))) then raise exception 'DELETE_CLIENT_DEPARTMENT_IN_USE';end if;
 end loop;
 if jsonb_array_length(departments_before)>0 then
  insert into public.laundry_audit(actor_email,actor_id,action,details) values(p_actor->>'email',p_actor->>'id','client_departments_deleted',jsonb_build_object('client_id',p_id,'departments',departments_before));
  delete from public.laundry_departments where client_id=p_id;
 end if;
end $$;
revoke all on function laundry_private.prepare_client_deletion(text,jsonb,jsonb) from public,anon,authenticated;

-- Patch only the client guard; all other catalog and authentication logic is unchanged.
do $migration$
declare current_definition text; old_guard text:=$old$if catalog_kind='client' and (exists(select 1 from public.laundry_products where data->>'client'=catalog_name) or exists(select 1 from public.laundry_lots where data->>'client'=catalog_name) or exists(select 1 from public.laundry_departments where client_id=catalog_id)) then raise exception 'DELETE_IN_USE';end if;$old$;
begin
 select pg_get_functiondef('laundry_private.laundry_core(jsonb,text,jsonb)'::regprocedure) into current_definition;
 if strpos(current_definition,old_guard)=0 then raise exception 'CLIENT_DELETE_GUARD_CHANGED';end if;
 execute replace(current_definition,old_guard,$new$if catalog_kind='client' then perform laundry_private.prepare_client_deletion(catalog_id,before_data,p_actor);end if;$new$);
end $migration$;
