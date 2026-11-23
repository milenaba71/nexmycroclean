begin;
create temporary table verification_results(test text,details jsonb) on commit drop;
do $test$
declare claims jsonb; answer jsonb; expected jsonb; before_revision bigint; after_revision bigint; started timestamptz; ms numeric; super_email text; original_product jsonb;
begin
 select jsonb_build_object('sub',u.id,'session_id',s.id,'role','authenticated'),u.email into claims,super_email
 from auth.users u join auth.sessions s on s.user_id=u.id join laundry_private.laundry_super_admin a on a.email=lower(u.email)
 order by s.created_at desc limit 1;
 if claims is null then raise exception 'TEST_REQUIRES_ADMIN_SESSION';end if;
 perform set_config('request.jwt.claims',claims::text,true);
 started:=clock_timestamp();
 answer:=public.laundry_products_query('{"ids":["10791","10791","__absent_test__"],"limit":1000}');
 ms:=extract(epoch from clock_timestamp()-started)*1000;
 if (answer->>'total')::int<>1 or answer#>>'{rows,0,id}'<>'10791' then raise exception 'IDS_TEST_FAILED';end if;
 insert into verification_results values('selected product',jsonb_build_object('milliseconds',ms,'total',answer->'total'));
 answer:=public.laundry_products_query('{"ids":["10791"],"client":"__no_client__"}');
 if (answer->>'total')::int<>0 then raise exception 'IDS_FILTER_FAILED';end if;
 started:=clock_timestamp();
 answer:=public.laundry_products_query('{"prop":"rent","limit":1000}');
 ms:=extract(epoch from clock_timestamp()-started)*1000;
 if (answer->>'total')::int<>(select count(*) from public.laundry_products where data->>'rental'='true') then raise exception 'RENT_COUNT_FAILED';end if;
 if exists(select 1 from jsonb_array_elements(answer->'rows') r where r->>'rental' is distinct from 'true') then raise exception 'RENT_ROWS_FAILED';end if;
 insert into verification_results values('rental screen',jsonb_build_object('milliseconds',ms,'total',answer->'total'));
 answer:=public.laundry_products_query('{"client":"VISHAY","limit":10}');
 if (answer->>'total')::int<>(select count(*) from public.laundry_products where data->>'client'='VISHAY') then raise exception 'CLIENT_COUNT_FAILED';end if;
 answer:=public.laundry_products_query('{"client":"VISHAY","mode":"ids","limit":10}');
 select jsonb_agg(to_jsonb(id) order by created_at desc nulls last,id) into expected
 from(select id,coalesce(created_at,laundry_private.product_legacy_created(data)) created_at from public.laundry_products where data->>'client'='VISHAY' order by coalesce(created_at,laundry_private.product_legacy_created(data)) desc nulls last,id limit 10)t;
 if answer->'rows' is distinct from expected then raise exception 'ORDER_FAILED';end if;
 begin perform public.laundry_user_delete(super_email);raise exception 'ADMIN_NOT_PROTECTED';
 exception when others then if sqlerrm<>'SUPER_ADMIN_PROTECTED' then raise;end if;end;
 insert into public.laundry_members(email,name,role,active) values('delete-test@invalid.example','Rollback test','operator',true);
 answer:=public.laundry_user_delete('delete-test@invalid.example');
 if answer->>'ok'<>'true' or not exists(select 1 from public.laundry_members where email='delete-test@invalid.example' and not active and deleted_at is not null) then raise exception 'DELETE_FAILED';end if;
 if exists(select 1 from jsonb_array_elements(laundry_private.laundry_authenticated('users','{}')) u where u->>'email'='delete-test@invalid.example') then raise exception 'DELETED_USER_VISIBLE';end if;
 if exists(select 1 from jsonb_array_elements(public.laundry_user_permissions('read','{}')) u where u->>'email'='delete-test@invalid.example') then raise exception 'DELETED_PERMISSIONS_VISIBLE';end if;
 insert into verification_results values('user deletion', '{"protected_super_admin":true,"deleted_hidden":true,"historical_member_preserved":true,"all_changes_rolled_back":true}');
 select jsonb_build_object('sub',u.id,'session_id',s.id,'role','authenticated') into claims from auth.users u join auth.sessions s on s.user_id=u.id where lower(u.email)='reli@mycroclean.com' order by s.created_at desc limit 1;
 if claims is null then raise exception 'TEST_REQUIRES_RELI_SESSION';end if;
 perform set_config('request.jwt.claims',claims::text,true);
 answer:=public.laundry_label_layouts('read','{}');
 if answer->'payload' is null then raise exception 'RELI_LABELS_DENIED';end if;
 begin perform public.laundry_user_delete('delete-test@invalid.example');raise exception 'OPERATOR_ALLOWED_DELETE';
 exception when others then if sqlerrm<>'SUPER_ADMIN_ONLY' then raise;end if;end;
 perform set_config('laundry.compact_snapshot','on',true);
 perform set_config('laundry.product_ids','["10791"]',true);
 select data into original_product from public.laundry_products where id='10791';
 select revision into before_revision from public.laundry_meta where id;
 answer:=public.laundry_product_save(jsonb_build_object('revision',before_revision,'original_id','10791','mode','manual','product',original_product));
 if answer->>'saved_id'<>'10791' then raise exception 'RELI_SAVE_FAILED';end if;
 insert into verification_results values('Reli permissions','{"label_layout_read":true,"product_save":true,"user_delete_denied":true,"save_rolled_back":true}');
end $test$;
select * from verification_results;
rollback;
