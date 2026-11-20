-- Explicit opt-in for AI writes. No existing account receives a new grant.
do $patch$
declare d text;
begin
 d:=pg_get_functiondef('laundry_private.permission_set(text)'::regprocedure);
 if position('''assistant_edit''' in d)>0 then raise exception 'ALREADY_INSTALLED';end if;
 d:=replace(d,'''products_delete'',''production_type_delete''] loop','''products_delete'',''production_type_delete'',''assistant_edit''] loop');
 if position('''assistant_edit''] loop' in d)=0 then raise exception 'PERMISSION_SOURCE_CHANGED';end if;
 d:=replace(d,'case profile_value when','case when key_name=''assistant_edit'' then false else case profile_value when');
 d:=replace(d,'else false end));','else false end end));');
 execute d;
 d:=pg_get_functiondef('laundry_private.permissions_control(text,jsonb)'::regprocedure);
 d:=replace(d,'''products_delete'',''production_type_delete'') or jsonb_typeof','''products_delete'',''production_type_delete'',''assistant_edit'') or jsonb_typeof');
 d:=replace(d,'jsonb_object_keys(caps-''production_type_delete''-''products_delete'')','jsonb_object_keys(caps-''production_type_delete''-''products_delete''-''assistant_edit'')');
 -- Old clients may omit the new permission: preserve an explicit existing choice.
 d:=replace(d,'update public.laundry_members set role=role_value', 'if not (caps ? ''assistant_edit'') then caps:=caps||jsonb_build_object(''assistant_edit'',role_value in (''admin'',''operator'') and coalesce((old_row.permissions->>''assistant_edit'')::boolean,false));end if; update public.laundry_members set role=role_value');
 if position('''assistant_edit'') or jsonb_typeof' in d)=0 then raise exception 'PERMISSION_CONTROL_SOURCE_CHANGED';end if;
 execute d;
 d:=pg_get_functiondef('public.laundry_assistant_quota(boolean)'::regprocedure);
 -- Keep existing read access for administrators; allow explicitly enabled operators.
 d:=replace(d, 'coalesce(who->>''isSuperAdmin'',''false'') <> ''true'')', 'coalesce(who->>''isSuperAdmin'',''false'') <> ''true'' and coalesce(who#>>''{permissions,assistant_edit}'',''false'') <> ''true'')');
 d:=replace(d,'''remaining'',10-coalesce(quantity,0)', '''remaining'',10-coalesce(quantity,0),''canEdit'',coalesce((who#>>''{permissions,assistant_edit}'')::boolean,false)');
 execute d;
end $patch$;

-- All AI edits use the same existing business-rule save functions as ordinary forms.
-- One existing record and one explicitly supported field per confirmation.
create function laundry_private.assistant_edit(p_action text,p jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare who jsonb; kind text:=p->>'entity'; target text:=trim(p->>'target'); field_name text:=p->>'field';
 value jsonb:=p->'value'; before_data jsonb; after_data jsonb; old_value jsonb; raw_key text;
 rev bigint; result jsonb; record_id text; label text; matches integer; event_data jsonb;
begin
 who:=laundry_private.laundry_authenticated('version','{}')->'user';
 perform laundry_private.require_permission('assistant_edit');
 if p_action not in ('preview','commit') or p_action is null then raise exception 'INVALID_ACTION';end if;
 if kind not in ('product','lot') or kind is null or target is null or length(target) not between 1 and 200 or field_name is null or value is null then raise exception 'INVALID_EDIT';end if;
 perform laundry_private.require_permission(case when kind='product' then 'products_manage' else 'lots_work' end);
 if p_action='commit' then
  if p->'confirmed' is distinct from 'true'::jsonb then raise exception 'CONFIRMATION_REQUIRED';end if;
  select revision into rev from public.laundry_meta where id for update;
 end if;
 if kind='product' then
  if field_name not in ('name','size','color','notes') then raise exception 'UNSUPPORTED_FIELD';end if;
  select count(*) into matches from public.laundry_products where lower(id)=lower(target) or lower(data->>'barcode')=lower(target);
  if matches<>1 then raise exception 'TARGET_NOT_UNIQUE';end if;
  select id,data into record_id,before_data from public.laundry_products where lower(id)=lower(target) or lower(data->>'barcode')=lower(target);
  raw_key:=case field_name when 'name' then 'NOME E COGNOME' when 'size' then 'TAGLIA' when 'color' then 'COLORE' else 'NOTE' end;
  old_value:=case when field_name='notes' then before_data#>'{raw,NOTE}' else before_data->field_name end;
  label:='Prodotto '||coalesce(nullif(before_data->>'barcode',''),record_id)||' · '||coalesce(before_data->>'client','');
 else
  if field_name not in ('colli','date','due','notes') then raise exception 'UNSUPPORTED_FIELD';end if;
  if target!~'^[0-9]{1,15}$' then raise exception 'INVALID_LOT_ID';end if;
  select id::text,data into record_id,before_data from public.laundry_lots where id=target::bigint;
  if before_data is null then raise exception 'TARGET_NOT_UNIQUE';end if;
  if coalesce((before_data->>'archived')::boolean,false) then raise exception 'LOT_ARCHIVED';end if;
  if field_name='due' and nullif(before_data->>'airtableOrderId','') is not null then raise exception 'AIRTABLE_DELIVERY_MANAGED';end if;
  if field_name in ('due','date') and nullif(before_data->>'calendarId','') is not null then raise exception 'CALENDAR_DATE_MANAGED';end if;
  old_value:=before_data->field_name;
  label:='Lotto '||record_id||' · '||coalesce(before_data->>'client','');
 end if;
 if field_name='colli' then
  if jsonb_typeof(value)<>'number' or (value#>>'{}')!~'^[0-9]+$' or (value#>>'{}')::numeric not between 1 and 1000000 then raise exception 'INVALID_COLLI';end if;
 else
  if jsonb_typeof(value)<>'string' or length(value#>>'{}')>(case when field_name='notes' then 4000 else 200 end) then raise exception 'INVALID_VALUE';end if;
  if field_name in ('size','color') and length(trim(value#>>'{}'))=0 then raise exception 'INVALID_VALUE';end if;
  if field_name in ('date','due') then
   if (value#>>'{}')!~'^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then raise exception 'INVALID_DATE';end if;
   if to_char((value#>>'{}')::date,'YYYY-MM-DD')<>(value#>>'{}') then raise exception 'INVALID_DATE';end if;
  end if;
 end if;
 after_data:=before_data;
 if kind='product' then
  after_data:=jsonb_set(after_data,'{raw}',coalesce(after_data->'raw','{}')||jsonb_build_object(raw_key,value));
  if field_name<>'notes' then after_data:=jsonb_set(after_data,array[field_name],value);end if;
 else after_data:=jsonb_set(after_data,array[field_name],value);
 end if;
 if p_action='preview' then
  return jsonb_build_object('entity',kind,'target',record_id,'field',field_name,'value',value,'before',old_value,'label',label,'version',md5(before_data::text),'unchanged',after_data=before_data);
 end if;
 if p->>'version' is distinct from md5(before_data::text) then raise exception 'ASSISTANT_EDIT_CONFLICT';end if;
 if after_data=before_data then return jsonb_build_object('saved',false,'unchanged',true);end if;
 if kind='product' then
  -- The product save API expects the effective barcode in product.id.
  after_data:=jsonb_set(after_data,'{id}',to_jsonb(coalesce(nullif(before_data->>'barcode',''),record_id)));
  result:=laundry_private.product_save_authenticated(jsonb_build_object('revision',rev,'original_id',record_id,'mode','manual','product',after_data));
 else
  event_data:=jsonb_build_object('at',now(),'time',to_char(now() at time zone 'Europe/Rome','DD/MM/YYYY, HH24:MI:SS'),'action','Modifica confermata da assistente IA · '||field_name,'code','','actor',who->>'name','actorEmail',who->>'email');
  after_data:=jsonb_set(after_data,'{events}',coalesce(before_data->'events','[]')||jsonb_build_array(event_data));
  result:=laundry_private.laundry_authenticated('save',jsonb_build_object('revision',rev,'changes',jsonb_build_object('lots',jsonb_build_array(after_data))));
 end if;
 insert into public.laundry_audit(actor_email,actor_id,action,details) values(who->>'email',auth.uid()::text,'assistant_edit_confirmed',jsonb_build_object('entity',kind,'target',record_id,'field',field_name,'before',old_value,'after',value));
 return jsonb_build_object('saved',true,'label',label);
end $$;
revoke all on function laundry_private.assistant_edit(text,jsonb) from public,anon,authenticated;
grant execute on function laundry_private.assistant_edit(text,jsonb) to authenticated;
create function public.laundry_assistant_edit(p_action text,p jsonb default '{}') returns jsonb
language sql security invoker set search_path='' as $$select laundry_private.assistant_edit(p_action,p)$$;
revoke all on function public.laundry_assistant_edit(text,jsonb) from public,anon,authenticated;
grant execute on function public.laundry_assistant_edit(text,jsonb) to authenticated;
