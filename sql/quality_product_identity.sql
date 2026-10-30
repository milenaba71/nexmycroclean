-- A release must also match the garment identity checked by the operator.
create or replace function laundry_private.quality_fingerprint(r jsonb) returns text
language sql stable set search_path='' as $$
 select md5(jsonb_build_object('row',r-'state','product',(
 select jsonb_build_object('barcode',p.data->'barcode','client',p.data->'client','name',p.data->'name','dept',p.data->'dept','type',p.data->'type','size',p.data->'size','color',p.data->'color')
 from public.laundry_products p where p.id=r->>'code'))::text)
$$;
revoke all on function laundry_private.quality_fingerprint(jsonb) from public,anon,authenticated;
