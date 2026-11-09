-- The Super Admin manages production but is not an eligible production operator.
do $migration$
declare
  definition text;
  member_filter constant text := 'm.active and m.role in (''admin'',''operator'')))';
  excluded_filter constant text := 'm.active and m.role in (''admin'',''operator'') and not exists (select 1 from laundry_private.laundry_super_admin sa where sa.email=m.email)))';
begin
  definition := pg_get_functiondef('laundry_private.production(text,jsonb)'::regprocedure);
  if position(excluded_filter in definition) = 0 then
    if position(member_filter in definition) = 0 then
      raise exception 'PRODUCTION_MEMBER_LIST_CHANGED';
    end if;
    execute replace(definition, member_filter, excluded_filter);
  end if;
end $migration$;

create or replace function laundry_private.guard_super_admin_planning()
returns trigger
language plpgsql security definer set search_path='' as $$
begin
  if exists (
    select 1 from jsonb_array_elements(new.data->'operators') o
    join laundry_private.laundry_super_admin sa on sa.email=lower(o->>'email')
  ) then
    raise exception 'Il Super amministratore non può essere inserito tra gli operatori di produzione.';
  end if;
  if exists (
    select 1 from jsonb_array_elements(new.data->'tasks') t
    join laundry_private.laundry_super_admin sa on sa.email=lower(t->>'assignee')
    where t->>'status'='pending'
  ) or exists (
    select 1 from jsonb_array_elements(new.data#>'{plan,allocations}') a
    join jsonb_array_elements(new.data->'tasks') t on t->>'id'=a->>'taskId'
    join laundry_private.laundry_super_admin sa on sa.email=lower(a->>'email')
    where t->>'status'='pending'
  ) then
    raise exception 'Scegli un operatore diverso dal Super amministratore per la pianificazione.';
  end if;
  return new;
end $$;
revoke all on function laundry_private.guard_super_admin_planning() from public,anon,authenticated;

create or replace trigger guard_super_admin_planning
before insert or update of data on public.laundry_production
for each row execute function laundry_private.guard_super_admin_planning();

update public.laundry_production p
set data=jsonb_set(p.data,'{operators}',(
  select coalesce(jsonb_agg(o order by ord),'[]'::jsonb)
  from jsonb_array_elements(p.data->'operators') with ordinality as entries(o,ord)
  where not exists (select 1 from laundry_private.laundry_super_admin sa where sa.email=lower(o->>'email'))
)), revision=p.revision+1
where exists (
  select 1 from jsonb_array_elements(p.data->'operators') o
  join laundry_private.laundry_super_admin sa on sa.email=lower(o->>'email')
);
