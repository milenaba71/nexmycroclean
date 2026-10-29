-- Preserve the stock product's barcode history during substitution.
-- No permission, trigger, or historical record changes.
do $patch$
declare definition text; old_fragment text := 'perform laundry_private.tag_release(next_id);';
new_fragment text := 'perform laundry_private.tag_release(next_id);
      -- Reload aliases added by tag release before projecting the replacement.
      select data into replacement from public.laundry_products where id=next_id;';
begin
 select pg_get_functiondef('laundry_private.asset_control(text,jsonb)'::regprocedure) into definition;
 if position(new_fragment in definition)>0 then return;end if;
 if (length(definition)-length(replace(definition,old_fragment,'')))/length(old_fragment)<>1 then
  raise exception 'Unexpected asset_control definition; patch not applied';
 end if;
 execute replace(definition,old_fragment,new_fragment);
end $patch$;
