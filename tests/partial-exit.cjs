const fs=require('fs'),vm=require('vm'),assert=require('node:assert/strict');
const s=fs.readFileSync('operator-view.js','utf8');const c={openRows:l=>l.rows.filter(r=>!['Uscito','Dismesso'].includes(r.state)),lotReady:r=>r.completed,pendingFlags:r=>['repair','relabel','verify','rewashPending'].filter(k=>r[k])};vm.createContext(c);
vm.runInContext(s.slice(s.indexOf('function dispatchReadyRows'),s.indexOf('function labelsPending')),c);
const ready={code:'ok',state:'In lavorazione',completed:true},held={code:'label',state:'In lavorazione',completed:true,relabel:true};const lot={rows:[ready,held]};
assert.equal(c.readyForDispatch(lot),true);assert.equal(c.dispatchReadyRows(lot).length,1);assert.equal(held.relabel,true);
ready.state='Uscito';assert.equal(c.readyForDispatch(lot),false);assert.equal(held.state,'In lavorazione');
held.relabel=false;assert.equal(c.readyForDispatch(lot),true);assert.equal(c.dispatchReadyRows(lot)[0].code,'label');
held.repair=true;assert.equal(c.readyForDispatch(lot),false);held.repair=false;held.requiresDrying=true;held.dryState='running';assert.equal(c.readyForDispatch(lot),false);
console.log('PASS partial exit: ready garments proceed, held garments stay pending, repaired garment returns, drying and intervention guards preserved');
