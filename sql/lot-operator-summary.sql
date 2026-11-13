create or replace function laundry_private.lot_operator_summary(p_lot_id bigint)
returns jsonb language plpgsql security definer set search_path='' as $function$
declare who jsonb;
begin
 who:=laundry_private.laundry_authenticated('version','{}')->'user';
 if who->>'role'<>'admin' then raise exception 'FORBIDDEN';end if;
 if not exists(select 1 from public.laundry_lots where id=p_lot_id) then raise exception 'LOT_NOT_FOUND';end if;
 return jsonb_build_object(
 'creator',(select jsonb_build_object('name',coalesce(m.name,'Nome non disponibile'),'at',a.created_at) from public.laundry_audit a left join public.laundry_members m on m.email=a.actor_email where a.action='lot_create' and a.details->>'id'=p_lot_id::text order by a.id limit 1),
 'machines',(select coalesce(jsonb_agg(jsonb_build_object('id',b.id,'machine',b.machine_name,'program',b.program_name,'operator',coalesce(m.name,'Nome non disponibile'),'started_at',b.started_at)),'[]') from public.laundry_wash_batches b left join public.laundry_members m on m.email=b.started_by where b.lot_id=p_lot_id and b.started_at is not null),
 'dryers',(select coalesce(jsonb_agg(jsonb_build_object('id',d.id,'machine',d.machine_name,'program',d.program_name,'operator',coalesce(m.name,'Nome non disponibile'),'started_at',d.started_at)),'[]') from public.laundry_dry_cycles d join public.laundry_wash_batches b on b.id=d.wash_batch_id left join public.laundry_members m on m.email=d.started_by where b.lot_id=p_lot_id and d.started_at is not null)
 );
end $function$;
revoke all on function laundry_private.lot_operator_summary(bigint) from public,anon;
grant execute on function laundry_private.lot_operator_summary(bigint) to authenticated;
create or replace function public.laundry_lot_operator_summary(p_lot_id bigint)
returns jsonb language sql security invoker set search_path='' as $function$
 select laundry_private.lot_operator_summary(p_lot_id);
$function$;
revoke all on function public.laundry_lot_operator_summary(bigint) from public,anon;
grant execute on function public.laundry_lot_operator_summary(bigint) to authenticated;
