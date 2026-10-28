-- Run only in an authorized privileged maintenance session, after migration.
-- psql -X -v ON_ERROR_STOP=1 -v super_admin_user_id='AUTH-UUID' \
--   -v expected_previous_email='reviewed-existing-email-or-empty' \
--   -f sql/operations/designate_super_admin.sql
-- No default account; missing variables cause psql to fail. Never pass secrets here.
\set ON_ERROR_STOP on
begin;
select laundry_private.designate_super_admin(
 :'super_admin_user_id'::uuid,
 nullif(:'expected_previous_email','')
);
commit;
