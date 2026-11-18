create or replace function laundry_private.entry_product_ownership(product jsonb, rental jsonb)
returns jsonb language plpgsql immutable set search_path='' as $$
begin
 if jsonb_typeof(rental) is distinct from 'boolean' then raise exception 'Scegli Proprietà cliente oppure Noleggio'; end if;
 if product->'rental' is not null and product->'rental'<>'null'::jsonb and product->'rental' is distinct from rental then
  raise exception 'Proprietà già definita: modificarla dalla scheda prodotto';
 end if;
 return jsonb_set(product,'{rental}',rental)||jsonb_build_object('raw',coalesce(nullif(product->'raw','null'::jsonb),'{}'::jsonb)||jsonb_build_object('GESTIONE',case when rental='true'::jsonb then 'Mycroclean · Noleggio' else 'Proprietà cliente' end));
end $$;
do $migration$
declare source text; needle text := $needle$    event_data:=jsonb_build_object('action','Tipo prodotto assegnato · '$needle$;
begin
 select pg_get_functiondef(p.oid) into source from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='laundry_private' and p.proname='laundry_core';
 if position(needle in source)=0 then raise exception 'Ownership patch location not found';end if;
 source:=replace(source,needle,$patch$    if p_payload ? 'rental' then
     product:=laundry_private.entry_product_ownership(product,p_payload->'rental');
    end if;
$patch$||needle);
 execute source;
end $migration$;
