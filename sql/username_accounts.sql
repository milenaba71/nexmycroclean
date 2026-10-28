-- Credentials remain in Supabase Auth. No password is stored in application tables or audits.
create table laundry_private.user_logins(email text primary key references public.laundry_members(email),username text unique check(username ~ '^[a-z0-9][a-z0-9._-]{2,39}$'),contact_email text not null default '');
alter table laundry_private.user_logins enable row level security;
revoke all on laundry_private.user_logins from public,anon,authenticated;
create table laundry_private.login_attempts(key text primary key,started_at timestamptz not null,attempts integer not null);
alter table laundry_private.login_attempts enable row level security;
revoke all on laundry_private.login_attempts from public,anon,authenticated;
create or replace function laundry_private.password_context() returns jsonb language plpgsql security definer set search_path='' as $$
declare u auth.users; m public.laundry_members; started timestamptz;
begin
 select * into u from auth.users where id=auth.uid();
 if not found or u.email_confirmed_at is null or coalesce(u.is_anonymous,false) or u.banned_until>now() then raise exception 'UNAUTHORIZED';end if;
 select created_at into started from auth.sessions where id::text=auth.jwt()->>'session_id' and user_id=u.id;
 if started is null or started<coalesce((u.raw_app_meta_data->>'password_reset_at')::timestamptz,'-infinity') then raise exception 'SESSION_REVOKED';end if;
 select * into m from public.laundry_members where email=lower(u.email) and active;
 if not found then raise exception 'ACCESS_DENIED';end if;
 return jsonb_build_object('id',u.id,'email',m.email,'name',m.name,'role',m.role,'mustChangePassword',coalesce((u.raw_app_meta_data->>'must_change_password')::boolean,false),'isSuperAdmin',exists(select 1 from laundry_private.laundry_super_admin where email=m.email));
end;$$;
revoke all on function laundry_private.password_context() from public,anon;
grant execute on function laundry_private.password_context() to authenticated;
create or replace function public.laundry_password_context() returns jsonb language sql security invoker set search_path='' as $$select laundry_private.password_context()$$;
revoke all on function public.laundry_password_context() from public,anon;
grant execute on function public.laundry_password_context() to authenticated;
-- Preserve the existing core and enforce password changes before any business operation.
CREATE OR REPLACE FUNCTION laundry_private.laundry_authenticated(p_action text, p_payload jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare u auth.users; sid text; permission_result jsonb;
begin
 perform laundry_private.password_context();
 if auth.uid() is null then raise exception 'UNAUTHORIZED';end if;
 select * into u from auth.users where id=auth.uid();
 if not found or u.email_confirmed_at is null or coalesce(u.is_anonymous,false) or (u.banned_until is not null and u.banned_until>now()) then raise exception 'UNAUTHORIZED';end if;
 if coalesce((u.raw_app_meta_data->>'must_change_password')::boolean,false) then raise exception 'PASSWORD_CHANGE_REQUIRED';end if;
 sid:=auth.jwt()->>'session_id';
 if sid is null or not exists(select 1 from auth.sessions where id::text=sid and user_id=u.id) then raise exception 'SESSION_REVOKED';end if;
 if p_action not in ('snapshot','version','users','user_save','save','lot_create','catalog_save','client_merge','lot_acquire','lot_set_type','catalog_delete') then raise exception 'INVALID_ACTION';end if;
 perform laundry_private.permission_core_guard(p_action,p_payload); permission_result:=laundry_private.laundry_core(jsonb_build_object('id',u.id::text,'email',lower(u.email)),p_action,p_payload); if jsonb_typeof(permission_result->'user')='object' then permission_result:=jsonb_set(permission_result,'{user}',permission_result->'user'||laundry_private.permission_set(lower(u.email)));end if;return permission_result;
end;$function$
;
-- Service-only RPC. The Edge Function verifies the caller JWT/session before administrator actions.
create or replace function laundry_private.accounts_service(p_action text,p jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare actor public.laundry_members; target public.laundry_members; identity_email text; username_value text; uid uuid; super boolean; count_attempts int; out_data jsonb; key_value text;
begin
 if p_action='login_lookup' then
  key_value:=md5(lower(trim(p->>'login')));
  delete from laundry_private.login_attempts where started_at<now()-interval '1 day';
  insert into laundry_private.login_attempts values(key_value,now(),1) on conflict(key) do update set attempts=case when login_attempts.started_at<now()-interval '15 minutes' then 1 else login_attempts.attempts+1 end,started_at=case when login_attempts.started_at<now()-interval '15 minutes' then now() else login_attempts.started_at end returning attempts into count_attempts;
  if count_attempts>10 then return jsonb_build_object('limited',true);end if;
  insert into laundry_private.login_attempts values('global',now(),1) on conflict(key) do update set attempts=case when login_attempts.started_at<now()-interval '15 minutes' then 1 else login_attempts.attempts+1 end,started_at=case when login_attempts.started_at<now()-interval '15 minutes' then now() else login_attempts.started_at end returning attempts into count_attempts;
  if count_attempts>300 then return jsonb_build_object('limited',true);end if;
  select m.email into identity_email from public.laundry_members m left join laundry_private.user_logins l on l.email=m.email where m.active and (l.username=lower(trim(p->>'login')) or m.email=lower(trim(p->>'login'))) limit 1;
  return jsonb_build_object('email',identity_email);
 end if;
 select * into actor from public.laundry_members where email=lower(p->>'actor_email') and active and role='admin';
 if not found then raise exception 'FORBIDDEN';end if;
 if not exists(select 1 from auth.users u join auth.sessions s on s.user_id=u.id where u.id=(p->>'actor_id')::uuid and lower(u.email)=actor.email and s.id::text=p->>'session_id' and u.email_confirmed_at is not null and not coalesce(u.is_anonymous,false) and (u.banned_until is null or u.banned_until<=now()) and not coalesce((u.raw_app_meta_data->>'must_change_password')::boolean,false) and s.created_at>=coalesce((u.raw_app_meta_data->>'password_reset_at')::timestamptz,'-infinity')) then raise exception 'SESSION_REVOKED';end if;
 super:=exists(select 1 from laundry_private.laundry_super_admin where email=actor.email);
 if p_action='list' then
  select coalesce(jsonb_agg(jsonb_build_object('email',m.email,'name',m.name,'role',m.role,'active',m.active,'username',l.username,'contactEmail',coalesce(l.contact_email,case when m.email like '%@accounts.mycroclean.invalid' then '' else m.email end),'registered',u.id is not null,'mustChangePassword',coalesce((u.raw_app_meta_data->>'must_change_password')::boolean,false),'isSuperAdmin',exists(select 1 from laundry_private.laundry_super_admin where email=m.email)) order by m.name),'[]') into out_data from public.laundry_members m left join laundry_private.user_logins l on l.email=m.email left join auth.users u on lower(u.email)=m.email;return out_data;
 end if;
 if not super then raise exception 'SUPER_ADMIN_ONLY';end if;
 identity_email:=lower(p->>'email');username_value:=nullif(lower(trim(p->>'username')),'');
 select * into target from public.laundry_members where email=identity_email;
 if not super and (target.role='admin' or p->>'role'='admin') then raise exception 'FORBIDDEN_ADMIN_ROLE';end if;
 if p_action in ('target','finalize') then
  if username_value is not null and username_value!~'^[a-z0-9][a-z0-9._-]{2,39}$' then raise exception 'INVALID_USERNAME';end if;
  if exists(select 1 from laundry_private.user_logins where username=username_value and email<>identity_email) then raise exception 'USERNAME_TAKEN';end if;
  if target.email is null and username_value is null then raise exception 'USERNAME_REQUIRED';end if;
  if p->>'role' not in ('admin','operator','viewer') or length(trim(coalesce(p->>'name','')))=0 then raise exception 'INVALID_USER';end if;
  if exists(select 1 from laundry_private.laundry_super_admin where email=identity_email) and (p->>'role'<>'admin' or not (p->>'active')::boolean) then raise exception 'SUPER_ADMIN_PROTECTED';end if;
  if identity_email=actor.email and (p->>'role'<>'admin' or not (p->>'active')::boolean) then raise exception 'CANNOT_DISABLE_SELF';end if;
  if target.email is not null and target.role is distinct from p->>'role' then raise exception 'USE_PERMISSION_EDITOR';end if;
  if p_action='finalize' then
   perform laundry_private.laundry_core(jsonb_build_object('email',actor.email,'id',p->>'actor_id'),'user_save',jsonb_build_object('email',identity_email,'name',p->>'name','role',p->>'role','active',(p->>'active')::boolean));
   insert into laundry_private.user_logins(email,username,contact_email) values(identity_email,username_value,coalesce(p->>'contactEmail','')) on conflict(email) do update set username=excluded.username,contact_email=excluded.contact_email;
   return jsonb_build_object('ok',true);
  end if;
  select id into uid from auth.users where lower(email)=identity_email;
  return jsonb_build_object('id',uid,'email',identity_email,'exists',target.email is not null);
 end if;
 if p_action='audit_password' then
  insert into public.laundry_audit(actor_email,actor_id,action,details) values(actor.email,p->>'actor_id','account_password_set',jsonb_build_object('target_email',identity_email,'must_change_password',p->'mustChangePassword'));
  return jsonb_build_object('ok',true);
 end if;
 raise exception 'INVALID_ACTION';
end;$$;
revoke all on function laundry_private.accounts_service(text,jsonb) from public,anon,authenticated;
grant usage on schema laundry_private to service_role;
grant execute on function laundry_private.accounts_service(text,jsonb) to service_role;
create or replace function public.laundry_accounts_service(p_action text,p jsonb) returns jsonb language sql security invoker set search_path='' as $$select laundry_private.accounts_service(p_action,p)$$;
revoke all on function public.laundry_accounts_service(text,jsonb) from public,anon,authenticated;
grant execute on function public.laundry_accounts_service(text,jsonb) to service_role;
