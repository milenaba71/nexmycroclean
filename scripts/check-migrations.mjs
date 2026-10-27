import {readFileSync,readdirSync} from 'node:fs';
import {createHash} from 'node:crypto';
import assert from 'node:assert/strict';
const root=new URL('../',import.meta.url);
const read=p=>readFileSync(new URL(p,root));
const lock=JSON.parse(read('supabase/migrations.lock.json'));
const files=readdirSync(new URL('supabase/migrations/',root)).filter(x=>x.endsWith('.sql')).sort();
assert.deepEqual(files,Object.keys(lock),'Every migration needs a reviewed checksum in chronological order');
for(const [file,hash] of Object.entries(lock)){
 assert.match(file,/^\d{14}_[a-z0-9_]+\.sql$/);
 assert.equal(createHash('sha256').update(read('supabase/migrations/'+file)).digest('hex'),hash,`Migration changed: ${file}. Never edit applied migrations.`);
}
for(const file of readdirSync(new URL('sql/',root)).filter(x=>x.endsWith('.sql'))){
 const sql=read('sql/'+file).toString();
 assert.match(sql,/LEGACY_SQL_RETIRED/);
 assert.doesNotMatch(sql,/create\s+(or\s+replace\s+)?function/i);
}
const release=read('supabase/migrations/20261027090941_consolidate_laundry_core.sql').toString();
assert.doesNotMatch(release,/execute\s+replace\(/i,'No runtime textual patching');
assert.doesNotMatch(release,/order by created_at,email limit 1/i,'No implicit Super Admin');
assert.match(release,/CORE_RELEASE_ALREADY_INSTALLED/);
assert.match(release,/UNKNOWN_FUNCTION_REVIEW_REQUIRED/);
console.log(`PASS ${files.length} versioned migration checksums and retired SQL guards`);
