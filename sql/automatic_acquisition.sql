-- Retired: use the ordered supabase/migrations sequence.
-- See docs/database-migrations.md. Historical source is preserved in git.
do $retired$ begin
 raise exception 'LEGACY_SQL_RETIRED: use versioned migrations; do not overwrite current functions';
end;$retired$;
