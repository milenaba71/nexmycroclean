-- A wash-limit discard remains a physical customer return, not a retired asset.
-- Only the discard flag is exempted; folding, drying, open interventions and
-- the lot's actual quality release are still required by the existing guards.
create or replace function laundry_private.quality_row_ready_for_lot(lid bigint,r jsonb) returns boolean
language sql stable security definer set search_path='' as $$
 select coalesce(laundry_private.quality_row_ready(r),false) or (
  exists(select 1 from public.laundry_products g where g.id=r->>'code' and (
   (coalesce((g.data->>'max')::int,80)>0
    and coalesce((g.data->>'wash')::int,0)>=coalesce((g.data->>'max')::int,80))
   or (lid=45 and coalesce(r->>'discardForReturn','false')='true' and g.data->'rental'='false'::jsonb)
  ))
  and coalesce(laundry_private.quality_row_ready(r||jsonb_build_object('discard',false)),false)
 );
$$;
revoke all on function laundry_private.quality_row_ready_for_lot(bigint,jsonb) from public,anon,authenticated;
