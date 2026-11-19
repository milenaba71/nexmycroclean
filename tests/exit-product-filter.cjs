const fs=require('fs'),vm=require('vm'),assert=require('node:assert/strict');
const source=fs.readFileSync('operator-view.js','utf8');
const context={F:{phase:'out'},lotReady:r=>r.completed&&!r.repair,lotRowStatus:r=>r.state};vm.createContext(context);
vm.runInContext(source.slice(source.indexOf('F.productRowStatus=function'),source.indexOf('F.productStatusControl=function')),context);
const rows=[...Array.from({length:18},(_,i)=>({code:'out'+i,state:'Uscito',completed:true})),{code:'missing1',state:'In lavorazione',completed:true,discardForReturn:true},{code:'missing2',state:'In lavorazione',completed:true,discardForReturn:true},{code:'retired',state:'Dismesso'}];
const select=status=>{context.F.productStatus=status;return rows.filter(context.F.matchesProductStatus).map(r=>r.code)};
assert.deepEqual(select('exit:missing'),['missing1','missing2']);assert.equal(select('exit:out').length,18);assert.deepEqual(select('exit:retired'),['retired']);assert.equal(select('exit:working').length,0);
assert.equal(context.F.productRowStatus(rows[18]),'Da uscire · Scarto da restituire al cliente');assert.equal(context.F.productRowStatus(rows[0]),'Uscito');
context.F.phase='fold';assert.deepEqual(select('state:In lavorazione'),['missing1','missing2']);
console.log('PASS: 18 exited, 2 missing customer returns; retired excluded; exit statuses and folding filters');

// A successful exit redraw must update counters without reopening missing details.
context.current={rows};
vm.runInContext(source.slice(source.indexOf('function exitSummary()'),source.indexOf('function exitSummary()')+source.slice(source.indexOf('function exitSummary()')).indexOf('\n')),context);
context.F.phase='out';
let summary=vm.runInContext('exitSummary()',context);
assert.match(summary,/<strong>18<\/strong><span>CARICATI/);
assert.ok(!summary.includes('<details'));
assert.ok(summary.includes('floor.showMissingProducts()'));
rows[18].state='Uscito';
summary=vm.runInContext('exitSummary()',context);
assert.match(summary,/<strong>19<\/strong><span>CARICATI/);
assert.match(summary,/Mostra i mancanti \(1\)/);
assert.ok(!summary.includes('<details'));
console.log('PASS continuous exit: counters advance; missing list only opens on request');
context.esc=s=>String(s??'');
vm.runInContext(source.slice(source.indexOf('function feedbackMarkup()'),source.indexOf('function asideFor(')),context);
context.F.feedback={tone:'done',title:'FATTO',message:'Uscita registrata.'};
let feedback=vm.runInContext('feedbackMarkup()',context);
assert.match(feedback,/FATTO/);assert.match(feedback,/19 \/ 20/);assert.match(feedback,/CARICATI/);
rows[19].state='Uscito';
feedback=vm.runInContext('feedbackMarkup()',context);assert.match(feedback,/20 \/ 20/);
// Re-reading the same saved garment must not increment the total again.
assert.match(vm.runInContext('feedbackMarkup()',context),/20 \/ 20/);
context.F.phase='fold';assert.ok(!vm.runInContext('feedbackMarkup()',context).includes('CARICATI'));
console.log('PASS exit feedback: live saved count next to FATTO, retired excluded, repeat scans do not inflate count');
