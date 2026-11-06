-- Preserve the authenticated actor in the wash-cart deletion audit.
create or replace function laundry_private.wash_batch_guard_delete() returns trigger
language plpgsql security definer set search_path='' as $$
declare actor_email_value text;
begin
 if exists(select 1 from public.laundry_wash_batches where lot_id=old.id and started_at is not null) then raise exception 'LOT_HAS_WORK_HISTORY';end if;
 select lower(u.email) into actor_email_value from auth.users u where u.id=auth.uid();
 if nullif(actor_email_value,'') is null then raise exception 'UNAUTHORIZED';end if;
 insert into public.laundry_audit(actor_email,actor_id,action,details) values(actor_email_value,auth.uid()::text,'wash_carts_deleted_with_unworked_lot',jsonb_build_object('lotId',old.id,'batches',(select coalesce(jsonb_agg(to_jsonb(b)),'[]') from public.laundry_wash_batches b where b.lot_id=old.id)));
 return old;
end $$;
revoke all on function laundry_private.wash_batch_guard_delete() from public,anon,authenticated;
