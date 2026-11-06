const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const source=fs.readFileSync('planning-delete.js','utf8');const c={db:{lots:[{id:123}]},lotno:l=>'L.'+String(l.id).padStart(6,'0')+'-2026'};vm.createContext(c);vm.runInContext(source.slice(source.indexOf('function planningLotConfirmation'),source.indexOf('async function planningDeleteDialog')),c);
for(const value of ['123',' 123 ','000123','L.000123-2026','l.000123-2026'])assert.equal(c.planningLotConfirmation(value,123),'123');
for(const value of ['','124','L.000124-2026','123-2026','123abc','1.23e2'])assert.equal(c.planningLotConfirmation(value,123),null);
assert.equal(c.planningLotConfirmation('999',999),null);
assert(source.includes('confirm:confirmation'));assert(source.includes("action==='clear_plan'?null"));console.log('PASS selected lot confirmation: numeric and displayed code accepted; wrong, malformed and absent lots rejected');
