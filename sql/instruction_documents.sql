-- Private operating manuals, shared with active members; uploads/deletes restricted to admins.
create or replace function laundry_private.manual_access(write_access boolean default false)
returns boolean language plpgsql stable security definer set search_path='' as $$
declare who jsonb;
begin
 who:=laundry_private.laundry_authenticated('version','{}')->'user';
 return coalesce(who->>'role' in ('admin','operator','viewer') and (not write_access or who->>'role'='admin'),false);
exception when others then return false;
end;$$;
revoke all on function laundry_private.manual_access(boolean) from public,anon;
grant usage on schema laundry_private to authenticated;
grant execute on function laundry_private.manual_access(boolean) to authenticated;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('operating-manuals','operating-manuals',false,20971520,array['application/pdf'])
on conflict(id) do update set public=false,file_size_limit=20971520,allowed_mime_types=array['application/pdf'];
create policy manuals_read on storage.objects for select to authenticated
 using(bucket_id='operating-manuals' and laundry_private.manual_access(false));
create policy manuals_upload on storage.objects for insert to authenticated
 with check(bucket_id='operating-manuals' and lower(storage.extension(name))='pdf' and laundry_private.manual_access(true));
create policy manuals_delete on storage.objects for delete to authenticated
 using(bucket_id='operating-manuals' and laundry_private.manual_access(true));
