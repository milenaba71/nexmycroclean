-- The normal timer reconciliation advances the lot, product counts and planning atomically.
create or replace function public.laundry_end_machine_cycle(phase text, cycle_id uuid, cycle_start timestamptz)
returns void language plpgsql security definer set search_path='' as $$
declare
 who jsonb;
 b public.laundry_wash_batches;
 c public.laundry_dry_cycles;
 member public.laundry_wash_batches;
 production jsonb;
begin
 who:=laundry_private.laundry_authenticated('version','{}')->'user';
 perform laundry_private.require_permission('production_execute');
 if coalesce(who->>'role','') not in ('admin','operator') then raise exception 'FORBIDDEN';end if;
 perform 1 from public.laundry_meta where id for update;
 if phase='wash' then
  select * into strict b from public.laundry_wash_batches where id=cycle_id for update;
  if cycle_start is null or b.started_at is distinct from cycle_start then raise exception 'Ciclo cambiato. Aggiorna il carrello.';end if;
  for member in select * from public.laundry_wash_batches where id=b.id or load_group_id=b.load_group_id order by id for update loop
   perform laundry_private.require_water_batch_skill(member.id);
   if member.state='estimated' then continue;end if;
   if member.state<>'running' then raise exception 'Il ciclo non è in corso.';end if;
   update public.laundry_wash_batches set expected_end=least(expected_end,now()),
    events=events||jsonb_build_array(jsonb_build_object('action','operator_cycle_end','at',now(),'actor',who->>'email','plannedEnd',expected_end)) where id=member.id;
  end loop;
  perform laundry_private.wash_batch_tick();
  if exists(select 1 from public.laundry_wash_batches where (id=b.id or load_group_id=b.load_group_id) and state<>'estimated') then raise exception 'Verifica lo stato della macchina prima di terminare il ciclo.';end if;
  perform laundry_private.wash_sync_product_phases();
 elsif phase='dry' then
  select * into strict c from public.laundry_dry_cycles where id=cycle_id for update;
  if cycle_start is null or c.started_at is distinct from cycle_start then raise exception 'Ciclo cambiato. Aggiorna il carrello.';end if;
  select data into production from public.laundry_production where id;
  if who->>'role'<>'admin' and not exists(select 1 from jsonb_array_elements(production->'types') t,
    jsonb_array_elements(production->'operators') o,jsonb_array_elements(production->'stations') s
    where t->>'id'=c.program_id and s->>'id'=t->>'station' and coalesce(s->>'active','true')='true'
    and lower(o->>'email')=lower(who->>'email') and coalesce(o->>'active','true')='true' and (o->'skills') ? (t->>'station')) then raise exception 'STATION_SKILL_REQUIRED';end if;
  if c.state='estimated' then return;end if;
  if c.state<>'running' then raise exception 'Il ciclo non è in corso.';end if;
  update public.laundry_dry_cycles set expected_end=least(expected_end,now()),
   events=events||jsonb_build_array(jsonb_build_object('action','operator_cycle_end','at',now(),'actor',who->>'email','plannedEnd',expected_end)) where id=c.id;
 else raise exception 'Fase non valida';end if;
 perform laundry_private.dry_cycle_tick();
 if phase='dry' and not exists(select 1 from public.laundry_dry_cycles where id=c.id and state='estimated') then raise exception 'Verifica lo stato dell’essiccatoio prima di terminare il ciclo.';end if;
end $$;
revoke all on function public.laundry_end_machine_cycle(text,uuid,timestamptz) from public,anon;
grant execute on function public.laundry_end_machine_cycle(text,uuid,timestamptz) to authenticated;
