-- Match the existing Gestionale ufficio access rule. Automatic exit movements use a separate trigger.
do $migration$
declare
 definition text := pg_get_functiondef('public.laundry_bag_stock(text,jsonb)'::regprocedure);
 marker text := 'if action=''read'' then';
begin
 if strpos(definition,marker)=0 then raise exception 'Unexpected bag stock function'; end if;
 execute replace(definition,marker,$guard$if who->>'role' is distinct from 'admin' then
  perform laundry_private.require_permission('production_manage');
 end if;
 if action='read' then$guard$);
end $migration$;
