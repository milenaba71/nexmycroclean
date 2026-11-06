begin;
alter table laundry_private.mask_movements drop constraint if exists mask_global_ship_250;
alter table laundry_private.mask_movements add constraint mask_global_ship_quantity check(line_id is not null or (kind='ship' and abs(quantity::bigint) between 1 and 1000000));
do $upgrade$
declare definition text;
begin
 definition:=pg_get_functiondef('laundry_private.mask_stock(text,jsonb)'::regprocedure);
 if position('if abs(qty)<>250 then raise exception ''SHIPMENT_MUST_BE_250'';end if;' in definition)=0 then
  raise exception 'MASK_FUNCTION_VERSION_MISMATCH';
 end if;
 definition:=replace(definition,'if abs(qty)<>250 then raise exception ''SHIPMENT_MUST_BE_250'';end if;','if abs(qty::bigint) not between 1 and 1000000 then raise exception ''INVALID_QUANTITY'';end if;');
 execute definition;
end $upgrade$;
commit;
