const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const s=fs.readFileSync('operator-view.js','utf8'),ctx={};vm.createContext(ctx);
vm.runInContext(s.slice(s.indexOf('function entryCompletedCounts('),s.indexOf('F.entryTypeSummary=function')),ctx);
const lot={rows:[{code:'A',relabel:true,rewashPending:true,repairWork:[{kind:'relabel',quantity:2,minutesHundredths:300},{kind:'repair',minutesHundredths:1250}],rewashCycles:2},{code:'B',relabel:true,repair:true,rewash:true},{code:'C',repairWork:[{kind:'verify',minutesHundredths:900},{kind:'repair',minutesHundredths:275}]},{code:'D'}],events:[{code:'A',action:'Intervento completato · Etichettatura'},{code:'D',action:'Intervento completato · Etichettatura'},{code:'D',action:'Completata: Etichettatura'}]};
const original=JSON.stringify(lot);
assert.equal(JSON.stringify(ctx.entryCompletedCounts(lot)),JSON.stringify({labels:3,rewashes:2,repairMinutes:15.25}));
const h=ctx.entryCompletedSummary(lot);assert(h.includes('15,25'));assert(h.includes('Etichette fatte'));assert(h.includes('Rilavaggi eseguiti'));assert(h.includes('Minuti di riparazione'));assert.equal(JSON.stringify(lot),original);
assert.equal(JSON.stringify(ctx.entryCompletedCounts({rows:[]})),JSON.stringify({labels:0,rewashes:0,repairMinutes:0}));
console.log('PASS completed-only quantities, no duplicate legacy labels, repair-only minutes, empty lot and no mutation');
