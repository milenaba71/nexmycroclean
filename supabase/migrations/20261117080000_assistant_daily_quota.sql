create table laundry_private.assistant_daily_usage (
  user_id uuid not null,
  usage_day date not null,
  used smallint not null check (used between 1 and 10),
  primary key (user_id, usage_day)
);
revoke all on laundry_private.assistant_daily_usage from public, anon, authenticated;

create function public.laundry_assistant_quota(p_consume boolean default false)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  who jsonb;
  caller uuid := auth.uid();
  today date := (statement_timestamp() at time zone 'Europe/Rome')::date;
  quantity integer;
begin
  who := laundry_private.laundry_authenticated('version','{}')->'user';
  if caller is null or (coalesce(who->>'role','') <> 'admin' and coalesce(who->>'isSuperAdmin','false') <> 'true') then
    raise exception 'FORBIDDEN' using errcode='42501';
  end if;
  if p_consume then
    insert into laundry_private.assistant_daily_usage as usage (user_id,usage_day,used)
    values(caller,today,1)
    on conflict (user_id,usage_day) do update set used=usage.used+1 where usage.used<10
    returning used into quantity;
    if quantity is null then return jsonb_build_object('allowed',false,'remaining',0); end if;
  else
    select used into quantity from laundry_private.assistant_daily_usage where user_id=caller and usage_day=today;
  end if;
  return jsonb_build_object('allowed',true,'remaining',10-coalesce(quantity,0));
end;
$$;
revoke all on function public.laundry_assistant_quota(boolean) from public,anon;
grant execute on function public.laundry_assistant_quota(boolean) to authenticated;
