CREATE OR REPLACE FUNCTION laundry_private.permission_set(email_value text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare role_value text; profile_value text; overrides jsonb; caps jsonb; key_name text; ceiling boolean;
begin
 select role into role_value from public.laundry_members where email=email_value;
 select profile,permissions into profile_value,overrides from laundry_private.user_permissions where email=email_value;
 profile_value:=coalesce(profile_value,role_value,'viewer');
 caps:='{}';
 foreach key_name in array array['lots_work','lots_create','products_manage','masters_manage','production_execute','production_manage','planning_delete','tickets_manage','airtable_manage','documents_manage','production_type_delete'] loop
  ceiling:=role_value='admin' or (role_value='operator' and key_name not in ('planning_delete','production_type_delete'));
  caps:=caps||jsonb_build_object(key_name,coalesce(ceiling,false) and coalesce((overrides->>key_name)::boolean,case profile_value when 'admin' then key_name<>'production_type_delete' when 'operator' then key_name in ('lots_work','lots_create','production_execute','tickets_manage') when 'basic' then key_name in ('lots_work','production_execute') else false end));
 end loop;
 if exists(select 1 from laundry_private.laundry_super_admin where email=email_value) and role_value='admin' then
  select jsonb_object_agg(key,true) into caps from jsonb_each(caps);profile_value:='super';
 end if;
 return jsonb_build_object('profile',profile_value,'permissions',caps);
end $function$;

CREATE OR REPLACE FUNCTION laundry_private.permissions_control(p_action text, p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare who jsonb; target text; profile_value text; role_value text; caps jsonb; old_row laundry_private.user_permissions; key_name text; ceiling boolean;
begin
 who:=laundry_private.laundry_authenticated('version','{}')->'user';
 perform laundry_private.require_permission('super');
 if p_action='save' then
  target:=lower(trim(p->>'email'));profile_value:=p->>'profile';caps:=p->'permissions';
  if exists(select 1 from laundry_private.laundry_super_admin where email=target) then raise exception 'SUPER_ADMIN_PROTECTED';end if;
  if profile_value not in ('admin','operator','basic','viewer') or profile_value is null or jsonb_typeof(caps) is distinct from 'object' then raise exception 'INVALID_PERMISSIONS';end if;
  role_value:=case profile_value when 'basic' then 'operator' else profile_value end;
  perform 1 from public.laundry_members where email=target for update;
  if not found then raise exception 'USER_NOT_FOUND';end if;
  select * into old_row from laundry_private.user_permissions where email=target for update;
  if coalesce(old_row.revision,0) is distinct from (p->>'revision')::bigint then raise exception 'REVISION_CONFLICT';end if;
  for key_name in select jsonb_object_keys(caps) loop
   if key_name not in ('lots_work','lots_create','products_manage','masters_manage','production_execute','production_manage','planning_delete','tickets_manage','airtable_manage','documents_manage','production_type_delete') or jsonb_typeof(caps->key_name)<>'boolean' then raise exception 'INVALID_PERMISSIONS';end if;
   ceiling:=role_value='admin' or (role_value='operator' and key_name not in ('planning_delete','production_type_delete'));
   if (caps->>key_name)::boolean and not ceiling then raise exception 'ROLE_PERMISSION_LIMIT';end if;
  end loop;
  if (select count(*) from jsonb_object_keys(caps-'production_type_delete'))<>10 then raise exception 'INVALID_PERMISSIONS';end if;
  if not (caps ? 'production_type_delete') then caps:=caps||jsonb_build_object('production_type_delete',role_value='admin' and coalesce((old_row.permissions->>'production_type_delete')::boolean,false));end if; update public.laundry_members set role=role_value where email=target;
  insert into laundry_private.user_permissions(email,profile,permissions) values(target,profile_value,caps) on conflict(email) do update set profile=excluded.profile,permissions=excluded.permissions,revision=user_permissions.revision+1,updated_at=now();
  update public.laundry_meta set revision=revision+1 where id;
  insert into public.laundry_audit(actor_email,actor_id,action,details) values(who->>'email',auth.uid()::text,'user_permissions_saved',jsonb_build_object('email',target,'profile',profile_value,'permissions',caps,'previous',to_jsonb(old_row)));
 elsif p_action<>'read' then raise exception 'INVALID_ACTION';end if;
 return (select coalesce(jsonb_agg(jsonb_build_object('email',m.email,'name',m.name,'active',m.active,'role',m.role,'revision',coalesce(u.revision,0))||laundry_private.permission_set(m.email) order by m.name),'[]') from public.laundry_members m left join laundry_private.user_permissions u on u.email=m.email);
end $function$;

