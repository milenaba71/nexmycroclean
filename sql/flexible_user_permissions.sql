-- Allow Super Admin-defined operational permissions for both operator profiles.
-- No account permissions are assigned by this migration; admin-only deletion is preserved.
do $migration$
declare d text;
begin
 d:=pg_get_functiondef('laundry_private.permission_set(text)'::regprocedure);
 if position('role_value=''admin'' or (role_value=''operator'' and key_name in (''lots_work'',''lots_create'',''production_execute'',''tickets_manage''))' in d)=0 then raise exception 'PERMISSION_DELEGATION_SOURCE_CHANGED: permission_set';end if;
 execute replace(d,'role_value=''admin'' or (role_value=''operator'' and key_name in (''lots_work'',''lots_create'',''production_execute'',''tickets_manage''))','role_value=''admin'' or (role_value=''operator'' and key_name<>''planning_delete'')');
 d:=pg_get_functiondef('laundry_private.permissions_control(text,jsonb)'::regprocedure);
 if position('role_value=''admin'' or (role_value=''operator'' and key_name in (''lots_work'',''lots_create'',''production_execute'',''tickets_manage''))' in d)=0 then raise exception 'PERMISSION_DELEGATION_SOURCE_CHANGED: permissions_control';end if;
 execute replace(d,'role_value=''admin'' or (role_value=''operator'' and key_name in (''lots_work'',''lots_create'',''production_execute'',''tickets_manage''))','role_value=''admin'' or (role_value=''operator'' and key_name<>''planning_delete'')');
 d:=pg_get_functiondef('laundry_private.airtable_map_client(text,text,text)'::regprocedure);
 if position('if (identity_result->''user''->>''role'') is distinct from ''admin'' then raise exception ''FORBIDDEN'';end if;' in d)=0 then raise exception 'PERMISSION_DELEGATION_SOURCE_CHANGED: airtable_map_client';end if;
 execute replace(d,'if (identity_result->''user''->>''role'') is distinct from ''admin'' then raise exception ''FORBIDDEN'';end if;','perform laundry_private.require_permission(''airtable_manage'');');
 d:=pg_get_functiondef('laundry_private.client_calendar(text,jsonb)'::regprocedure);
 if position('if who->>''role''<>''admin'' then raise exception ''FORBIDDEN'';end if;' in d)=0 then raise exception 'PERMISSION_DELEGATION_SOURCE_CHANGED: client_calendar';end if;
 execute replace(d,'if who->>''role''<>''admin'' then raise exception ''FORBIDDEN'';end if;','perform laundry_private.require_permission(''production_manage'');');
 d:=pg_get_functiondef('laundry_private.wash_batch_control(text,jsonb)'::regprocedure);
 if position('if p_action=''link'' and who->>''role''<>''admin'' then raise exception ''FORBIDDEN'';end if;' in d)=0 then raise exception 'PERMISSION_DELEGATION_SOURCE_CHANGED: wash_batch_control';end if;
 execute replace(d,'if p_action=''link'' and who->>''role''<>''admin'' then raise exception ''FORBIDDEN'';end if;','if p_action=''link'' then perform laundry_private.require_permission(''production_manage'');end if;');
 d:=pg_get_functiondef('laundry_private.manual_access(boolean)'::regprocedure);
 if position('(not write_access or who->>''role''=''admin'')' in d)=0 then raise exception 'PERMISSION_DELEGATION_SOURCE_CHANGED: manual_access';end if;
 execute replace(d,'(not write_access or who->>''role''=''admin'')','(not write_access or coalesce((who->''permissions''->>''documents_manage'')::boolean,false))');
 d:=pg_get_functiondef('laundry_private.production(text,jsonb)'::regprocedure);
 if position('if who->>''role''<>''admin'' then raise exception ''FORBIDDEN'';end if;' in d)=0 then raise exception 'PERMISSION_DELEGATION_SOURCE_CHANGED: production';end if;
 execute replace(d,'if who->>''role''<>''admin'' then raise exception ''FORBIDDEN'';end if;','perform laundry_private.require_permission(''production_manage'');');
 d:=pg_get_functiondef('laundry_private.production(text,jsonb)'::regprocedure);
 if position('if who->>''role''<>''admin'' or target->>''status'' not in' in d)=0 then raise exception 'PERMISSION_DELEGATION_SOURCE_CHANGED: production';end if;
 execute replace(d,'if who->>''role''<>''admin'' or target->>''status'' not in','if not coalesce((who->''permissions''->>''production_manage'')::boolean,false) or target->>''status'' not in');
 d:=pg_get_functiondef('laundry_private.laundry_core(jsonb,text,jsonb)'::regprocedure);
 if position('if p_action=''catalog_save'' then
  if m.role<>''admin'' then raise exception ''FORBIDDEN'';end if;' in d)=0 then raise exception 'PERMISSION_DELEGATION_SOURCE_CHANGED: laundry_core';end if;
 execute replace(d,'if p_action=''catalog_save'' then
  if m.role<>''admin'' then raise exception ''FORBIDDEN'';end if;','if p_action=''catalog_save'' then
  if not coalesce((laundry_private.permission_set(m.email)->''permissions''->>''masters_manage'')::boolean,false) then raise exception ''FORBIDDEN'';end if;');
 d:=pg_get_functiondef('laundry_private.laundry_core(jsonb,text,jsonb)'::regprocedure);
 if position('if p_action=''client_merge'' then
  if m.role<>''admin'' then raise exception ''FORBIDDEN'';end if;' in d)=0 then raise exception 'PERMISSION_DELEGATION_SOURCE_CHANGED: laundry_core';end if;
 execute replace(d,'if p_action=''client_merge'' then
  if m.role<>''admin'' then raise exception ''FORBIDDEN'';end if;','if p_action=''client_merge'' then
  if not coalesce((laundry_private.permission_set(m.email)->''permissions''->>''masters_manage'')::boolean,false) then raise exception ''FORBIDDEN'';end if;');
 d:=pg_get_functiondef('laundry_private.laundry_core(jsonb,text,jsonb)'::regprocedure);
 if position('m.role=''operator'' and k in (''clientRecords'',''processing'')' in d)=0 then raise exception 'PERMISSION_DELEGATION_SOURCE_CHANGED: laundry_core';end if;
 execute replace(d,'m.role=''operator'' and k in (''clientRecords'',''processing'')','not coalesce((laundry_private.permission_set(m.email)->''permissions''->>''masters_manage'')::boolean,false) and k in (''clientRecords'',''processing'')');
 d:=pg_get_functiondef('laundry_private.laundry_core(jsonb,text,jsonb)'::regprocedure);
 if position('m.role=''operator'' and k=''garments''' in d)=0 then raise exception 'PERMISSION_DELEGATION_SOURCE_CHANGED: laundry_core';end if;
 execute replace(d,'m.role=''operator'' and k=''garments''','not coalesce((laundry_private.permission_set(m.email)->''permissions''->>''products_manage'')::boolean,false) and k=''garments''');
 d:=pg_get_functiondef('laundry_private.laundry_core(jsonb,text,jsonb)'::regprocedure);
 if position('k=''garments'' and m.role=''admin''' in d)=0 then raise exception 'PERMISSION_DELEGATION_SOURCE_CHANGED: laundry_core';end if;
 execute replace(d,'k=''garments'' and m.role=''admin''','k=''garments'' and coalesce((laundry_private.permission_set(m.email)->''permissions''->>''products_manage'')::boolean,false)');
 d:=pg_get_functiondef('laundry_private.product_save_core(jsonb,jsonb)'::regprocedure);
 if position('if not found or m.role<>''admin'' then raise exception ''FORBIDDEN'';end if;' in d)=0 then raise exception 'PERMISSION_DELEGATION_SOURCE_CHANGED: product_save_core';end if;
 execute replace(d,'if not found or m.role<>''admin'' then raise exception ''FORBIDDEN'';end if;','if not found or not coalesce((laundry_private.permission_set(m.email)->''permissions''->>''products_manage'')::boolean,false) then raise exception ''FORBIDDEN'';end if;');
end $migration$;
