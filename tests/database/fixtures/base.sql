-- TEST ONLY: minimal contract of the legacy schema that is missing from git.
-- Not a schema dump, not evidence of the live database, never deploy this file.
create role anon;
create role authenticated;
create role service_role;
create schema auth;
create schema laundry_private;
create schema supabase_migrations;
create table supabase_migrations.schema_migrations(version text primary key,name text,statements text[]);
create table auth.users(id uuid primary key,email text,email_confirmed_at timestamptz,is_anonymous boolean default false,banned_until timestamptz);
create table auth.sessions(id uuid primary key,user_id uuid references auth.users);
create function auth.uid() returns uuid language sql stable as $$ select (nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'sub')::uuid $$;
create function auth.jwt() returns jsonb language sql stable as $$select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb$$;
grant usage on schema auth,laundry_private to authenticated;
grant execute on function auth.uid(),auth.jwt() to authenticated;
create table public.laundry_members(email text primary key,name text not null,role text not null check(role in ('admin','operator','viewer')),active boolean not null default true,site_user_id text,created_at timestamptz not null default now());
create table public.laundry_meta(id boolean primary key default true check(id),revision bigint not null default 1);
insert into public.laundry_meta values(true,1);
create table public.laundry_products(id text primary key,data jsonb not null);
create table public.laundry_clients(id text primary key,data jsonb not null);
create table public.laundry_processing(id text primary key,data jsonb not null);
create table public.laundry_lots(id bigint primary key,data jsonb not null);
create sequence public.laundry_lot_sequence;
-- Only its snapshot contract is known. Real repair projections/triggers must be
-- checked in a sanitized staging restore before production approval.
create table public.laundry_repairs(id bigint generated always as identity primary key,created_at timestamptz default now());
create table public.laundry_audit(id bigint generated always as identity primary key,actor_email text,actor_id text,action text,details jsonb,created_at timestamptz default now());
do $$declare t text;begin
 foreach t in array array['laundry_members','laundry_meta','laundry_products','laundry_clients','laundry_processing','laundry_lots','laundry_repairs','laundry_audit'] loop
 execute format('alter table public.%I enable row level security',t);
 execute format('revoke all on public.%I from public,anon,authenticated',t);
 end loop;
end;$$;
create function public.laundry_app(p_action text,p_payload jsonb default '{}') returns jsonb language plpgsql security invoker set search_path='' as $$begin return laundry_private.laundry_authenticated(p_action,p_payload);end;$$;
revoke all on function public.laundry_app(text,jsonb) from public,anon;
grant execute on function public.laundry_app(text,jsonb) to authenticated;
