-- Individual operational powers; role ceilings and the unique Super Admin remain authoritative.
create table if not exists laundry_private.user_permissions(email text primary key references public.laundry_members(email) on delete cascade,profile text not null check(profile in ('admin','operator','basic','viewer')),permissions jsonb not null,revision bigint not null default 1,updated_at timestamptz not null default now());
alter table laundry_private.user_permissions enable row level security;
revoke all on laundry_private.user_permissions from public,anon,authenticated;
create or replace function laundry_private.permission_set(email_value text) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare role_value text; profile_value text; overrides jsonb; caps jsonb; key_name text; ceiling boolean;
begin
 select role into role_value from public.laundry_members where email=email_value;
 select profile,permissions into profile_value,overrides from laundry_private.user_permissions where email=email_value;
 profile_value:=coalesce(profile_value,role_value,'viewer');
 caps:='{}';
 foreach key_name in array array['lots_work','lots_create','products_manage','masters_manage','production_execute','production_manage','planning_delete','tickets_manage','airtable_manage','documents_manage'] loop
  ceiling:=role_value='admin' or (role_value='operator' and key_name in ('lots_work','lots_create','production_execute','tickets_manage'));
  caps:=caps||jsonb_build_object(key_name,coalesce(ceiling,false) and coalesce((overrides->>key_name)::boolean,case profile_value when 'admin' then true when 'operator' then key_name in ('lots_work','lots_create','production_execute','tickets_manage') when 'basic' then key_name in ('lots_work','production_execute') else false end));
 end loop;
 if exists(select 1 from laundry_private.laundry_super_admin where email=email_value) and role_value='admin' then
  select jsonb_object_agg(key,true) into caps from jsonb_each(caps);profile_value:='super';
 end if;
 return jsonb_build_object('profile',profile_value,'permissions',caps);
end $$;
revoke all on function laundry_private.permission_set(text) from public,anon,authenticated;
create or replace function laundry_private.require_permission(cap text) returns void
language plpgsql stable security definer set search_path='' as $$
declare email_value text;
begin
 select lower(email) into email_value from auth.users where id=auth.uid();
 if not exists(select 1 from public.laundry_members where email=email_value and active) then raise exception 'FORBIDDEN';end if;
 if cap='super' then
  if not exists(select 1 from laundry_private.laundry_super_admin s join public.laundry_members m on m.email=s.email where s.email=email_value and m.active and m.role='admin') then raise exception 'SUPER_ADMIN_ONLY';end if;
 elsif coalesce((laundry_private.permission_set(email_value)->'permissions'->>cap)::boolean,false) is not true then raise exception 'PERMISSION_DENIED: %',cap;
 end if;
end $$;
revoke all on function laundry_private.require_permission(text) from public,anon,authenticated;

create or replace function laundry_private.permission_core_guard(action_value text,p jsonb) returns void
language plpgsql security definer set search_path='' as $$
declare item jsonb; old_item jsonb;
begin
 if action_value in ('snapshot','version','users') then return;end if;
 if action_value='user_save' then perform laundry_private.require_permission('super');return;end if;
 if action_value='lot_create' then perform laundry_private.require_permission('lots_create');return;end if;
 if action_value in ('lot_acquire','lot_set_type') then perform laundry_private.require_permission('lots_work');return;end if;
 if action_value in ('catalog_save','catalog_delete','client_merge') then perform laundry_private.require_permission('masters_manage');return;end if;
 if action_value='save' then
  if jsonb_array_length(coalesce(p#>'{changes,lots}','[]'))>0 then perform laundry_private.require_permission('lots_work');end if;
  if jsonb_array_length(coalesce(p#>'{changes,clientRecords}','[]'))>0 or jsonb_array_length(coalesce(p#>'{changes,processing}','[]'))>0 then perform laundry_private.require_permission('masters_manage');end if;
  for item in select value from jsonb_array_elements(coalesce(p#>'{changes,garments}','[]')) loop
   select data into old_item from public.laundry_products where id=item->>'id';
   -- Routine wash counters/history may accompany lot work. All product-card edits require the product power.
   if old_item is not null and item-'wash'-'history'-'raw'=old_item-'wash'-'history'-'raw' and coalesce(item->'raw','{}')-'SCARTO'=coalesce(old_item->'raw','{}')-'SCARTO' then
    perform laundry_private.require_permission('lots_work');
   else perform laundry_private.require_permission('products_manage');end if;
  end loop;
 end if;
end $$;
revoke all on function laundry_private.permission_core_guard(text,jsonb) from public,anon,authenticated;

create or replace function laundry_private.permissions_control(p_action text,p jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
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
   if key_name not in ('lots_work','lots_create','products_manage','masters_manage','production_execute','production_manage','planning_delete','tickets_manage','airtable_manage','documents_manage') or jsonb_typeof(caps->key_name)<>'boolean' then raise exception 'INVALID_PERMISSIONS';end if;
   ceiling:=role_value='admin' or (role_value='operator' and key_name in ('lots_work','lots_create','production_execute','tickets_manage'));
   if (caps->>key_name)::boolean and not ceiling then raise exception 'ROLE_PERMISSION_LIMIT';end if;
  end loop;
  if (select count(*) from jsonb_object_keys(caps))<>10 then raise exception 'INVALID_PERMISSIONS';end if;
  update public.laundry_members set role=role_value where email=target;
  insert into laundry_private.user_permissions(email,profile,permissions) values(target,profile_value,caps) on conflict(email) do update set profile=excluded.profile,permissions=excluded.permissions,revision=user_permissions.revision+1,updated_at=now();
  update public.laundry_meta set revision=revision+1 where id;
  insert into public.laundry_audit(actor_email,actor_id,action,details) values(who->>'email',auth.uid()::text,'user_permissions_saved',jsonb_build_object('email',target,'profile',profile_value,'permissions',caps,'previous',to_jsonb(old_row)));
 elsif p_action<>'read' then raise exception 'INVALID_ACTION';end if;
 return (select coalesce(jsonb_agg(jsonb_build_object('email',m.email,'name',m.name,'active',m.active,'role',m.role,'revision',coalesce(u.revision,0))||laundry_private.permission_set(m.email) order by m.name),'[]') from public.laundry_members m left join laundry_private.user_permissions u on u.email=m.email);
end $$;
revoke all on function laundry_private.permissions_control(text,jsonb) from public,anon;
grant execute on function laundry_private.permissions_control(text,jsonb) to authenticated;
create or replace function public.laundry_user_permissions(p_action text,p jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select laundry_private.permissions_control(p_action,p)$$;
revoke all on function public.laundry_user_permissions(text,jsonb) from public,anon;
grant execute on function public.laundry_user_permissions(text,jsonb) to authenticated;

-- Patch current live definitions, not historical copies of the core functions.
do $patch$
declare definition text; spec record; old_line text;
begin
 definition:=pg_get_functiondef('laundry_private.laundry_authenticated(text,jsonb)'::regprocedure);
 if position('permission_core_guard' in definition)=0 then
  old_line:='return laundry_private.laundry_core(jsonb_build_object(''id'',u.id::text,''email'',lower(u.email)),p_action,p_payload);';
  if position(old_line in definition)=0 then raise exception 'AUTH_FUNCTION_CHANGED_REVIEW_REQUIRED';end if;
  definition:=replace(definition,'declare u auth.users; sid text;','declare u auth.users; sid text; permission_result jsonb;');
  definition:=replace(definition,old_line,'perform laundry_private.permission_core_guard(p_action,p_payload); permission_result:=laundry_private.laundry_core(jsonb_build_object(''id'',u.id::text,''email'',lower(u.email)),p_action,p_payload); if jsonb_typeof(permission_result->''user'')=''object'' then permission_result:=jsonb_set(permission_result,''{user}'',permission_result->''user''||laundry_private.permission_set(lower(u.email)));end if;return permission_result;');
  execute definition;
 end if;
 for spec in select * from (values
 ('production(text,jsonb)','if p_action in (''save'',''plan'') then perform laundry_private.require_permission(''production_manage'');elsif p_action=''ticket'' then perform laundry_private.require_permission(''tickets_manage'');elsif p_action=''task'' then perform laundry_private.require_permission(case when p_payload->>''command'' in (''handoff'',''cancel'') then ''production_manage'' else ''production_execute'' end);end if;'),
 ('client_calendar(text,jsonb)','if p_action in (''lot_create'',''lot_create_unplanned'') then perform laundry_private.require_permission(''lots_create'');elsif p_action<>''read'' then perform laundry_private.require_permission(''production_manage'');end if;'),
 ('product_save_authenticated(jsonb)','perform laundry_private.require_permission(''products_manage'');'),
 ('airtable_lot_create(jsonb)','perform laundry_private.require_permission(''lots_create'');'),
 ('airtable_map_client(text,text,text)','perform laundry_private.require_permission(''airtable_manage'');'),
 ('manual_access(boolean)','if write_access then perform laundry_private.require_permission(''documents_manage'');end if;'),
 ('planning_delete_control(text,jsonb)','perform laundry_private.require_permission(''planning_delete'');'),
 ('production_bulk_delete(jsonb)','perform laundry_private.require_permission(''planning_delete'');'),
 ('wash_batch_control(text,jsonb)','if p_action=''link'' then perform laundry_private.require_permission(''production_manage'');elsif p_action in (''acquire'',''switch'',''finish'') then perform laundry_private.require_permission(''lots_work'');elsif p_action in (''start'',''interrupt'') then perform laundry_private.require_permission(''production_execute'');end if;')
 ) as guards(signature,guard_sql) loop
  definition:=pg_get_functiondef(('laundry_private.'||spec.signature)::regprocedure);
  if position('-- user_permission_guard' in definition)=0 then
   if position(E'begin\n' in definition)=0 then raise exception 'FUNCTION_LAYOUT_CHANGED';end if;
   definition:=regexp_replace(definition,E'begin\n',E'begin\n -- user_permission_guard\n '||spec.guard_sql||E'\n');
   execute definition;
  end if;
 end loop;
end $patch$;
