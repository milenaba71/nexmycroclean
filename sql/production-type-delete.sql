-- A separate, opt-in permission for deleting standard production times.
do $migration$
declare
  definition text;
  signature regprocedure;
begin
  foreach signature in array array[
    'laundry_private.permission_set(text)'::regprocedure,
    'laundry_private.permissions_control(text,jsonb)'::regprocedure
  ] loop
    definition:=pg_get_functiondef(signature);
    if position('production_type_delete' in definition)>0 then continue; end if;
    if position('''documents_manage''' in definition)=0
      or position('key_name<>''planning_delete''' in definition)=0 then
      raise exception 'PERMISSION_FUNCTION_CHANGED';
    end if;
    definition:=replace(definition,'''documents_manage''','''documents_manage'',''production_type_delete''');
    definition:=replace(definition,'key_name<>''planning_delete''','key_name not in (''planning_delete'',''production_type_delete'')');
    if signature='laundry_private.permission_set(text)'::regprocedure then
      if position('when ''admin'' then true' in definition)=0 then raise exception 'PERMISSION_DEFAULT_CHANGED'; end if;
      definition:=replace(definition,'when ''admin'' then true','when ''admin'' then key_name<>''production_type_delete''');
    else
      if position('count(*) from jsonb_object_keys(caps))<>10' in definition)=0 then raise exception 'PERMISSION_COUNT_CHANGED'; end if;
      definition:=replace(definition,'count(*) from jsonb_object_keys(caps))<>10',
        'count(*) from jsonb_object_keys(caps-''production_type_delete''))<>10');
      definition:=replace(definition,'update public.laundry_members set role=role_value',
        'if not (caps ? ''production_type_delete'') then caps:=caps||jsonb_build_object(''production_type_delete'',role_value=''admin'' and coalesce((old_row.permissions->>''production_type_delete'')::boolean,false));end if; update public.laundry_members set role=role_value');
    end if;
    execute definition;
  end loop;
end $migration$;

create or replace function laundry_private.guard_production_type_delete()
returns trigger language plpgsql security definer set search_path='' as $$
declare
  removed jsonb;
  ids text[];
  actor jsonb;
begin
  select jsonb_agg(t),array_agg(t->>'id') into removed,ids
  from jsonb_array_elements(old.data->'types') t
  where not exists(select 1 from jsonb_array_elements(new.data->'types') n where n->>'id'=t->>'id');
  if ids is null then return new; end if;
  actor:=laundry_private.laundry_authenticated('version','{}')->'user';
  if actor->>'role' is distinct from 'admin' then raise exception 'FORBIDDEN'; end if;
  perform laundry_private.require_permission('production_type_delete');
  if ids && array['entry','fold','exit','repair-unknown'] then raise exception 'STANDARD_TYPE_REQUIRED'; end if;
  if exists(select 1 from jsonb_array_elements(old.data->'tasks') t where t->>'typeId'=any(ids))
    or exists(select 1 from public.laundry_wash_links where program_id=any(ids))
    or exists(select 1 from public.laundry_wash_batches where program_id=any(ids))
    or exists(select 1 from public.laundry_dry_cycles where program_id=any(ids)) then
    raise exception 'PRODUCTION_TYPE_IN_USE';
  end if;
  insert into public.laundry_audit(actor_email,actor_id,action,details)
    values(actor->>'email',auth.uid()::text,'production_types_deleted',jsonb_build_object('types',removed));
  return new;
end $$;
revoke all on function laundry_private.guard_production_type_delete() from public,anon,authenticated;
create or replace trigger guard_production_type_delete before update of data on public.laundry_production
for each row execute function laundry_private.guard_production_type_delete();

create or replace function public.laundry_production_type_delete(p_ids text[],p_revision bigint)
returns integer language plpgsql security definer set search_path='' as $$
declare
  current_data jsonb;
  current_revision bigint;
  item_count integer;
begin
  perform laundry_private.laundry_authenticated('version','{}');
  perform laundry_private.require_permission('production_type_delete');
  if coalesce(cardinality(p_ids),0)=0 then raise exception 'SELECTION_REQUIRED'; end if;
  perform 1 from public.laundry_meta where id for update;
  select data,revision into current_data,current_revision from public.laundry_production where id for update;
  if current_revision is distinct from p_revision then raise exception 'REVISION_CONFLICT'; end if;
  select count(*) into item_count from jsonb_array_elements(current_data->'types') t where t->>'id'=any(p_ids);
  if item_count<>cardinality(p_ids) then raise exception 'SELECTION_CHANGED'; end if;
  update public.laundry_production
  set data=jsonb_set(current_data,'{types}',(
    select coalesce(jsonb_agg(t order by n),'[]') from jsonb_array_elements(current_data->'types') with ordinality a(t,n)
    where not(t->>'id'=any(p_ids))
  )), revision=revision+1 where id;
  return item_count;
end $$;
revoke all on function public.laundry_production_type_delete(text[],bigint) from public,anon;
grant execute on function public.laundry_production_type_delete(text[],bigint) to authenticated;
