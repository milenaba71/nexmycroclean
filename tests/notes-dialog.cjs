const fs=require('fs'),vm=require('vm'),assert=require('node:assert/strict');
const row={code:`0001'"<&`,state:'Entrato',notes:'Nota esistente'};
let html='';
const c={current:{rows:[row]},db:{garments:[{id:row.code,rental:false}]},userCan:()=>true,show:s=>html=s,garmentLine:()=>'',flagLabels:{repair:'Riparazione',relabel:'Etichetta'},pendingFlags:()=>[],productIsDiscard:()=>false,button:(label,action,style,disabled='')=>`<button onclick="${action}" ${disabled}>${label}</button>`,esc:s=>String(s).replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('"','&quot;'),lotMutationAllowed:()=>true};
vm.createContext(c);
vm.runInContext(fs.readFileSync('garment-lifecycle.js','utf8').match(/^function assetArg\(x\).*$/m)[0],c);
const discard=fs.readFileSync('discard.js','utf8');vm.runInContext(discard.slice(discard.indexOf('const customerDiscardNote=')),c);
const op=fs.readFileSync('operator-view.js','utf8');vm.runInContext(`(function(){const F={},arg=v=>assetArg(v);${op.match(/^F.flags=function.*$/m)[0]}globalThis.floor=F;})();`,c);
assert.equal(c.arg,undefined); // Match the real script boundary, which previously broke all openings.
for(const rental of [false,true,undefined]){
 c.db.garments[0].rental=rental;c.floor.flags(row.code);
 assert(html.includes('Segnalazioni del capo'));assert(html.includes('Riparazione'));assert(html.includes('Note del capo'));
 let received;c.floor.flag=(...args)=>received=args;
 const handler=html.match(/onchange="([^"]+)"/)[1];vm.runInContext(`(function(){${handler}}).call({checked:true})`,c);
 assert.deepEqual(received,[row.code,'discardForReturn',true]);
}
vm.runInContext(fs.readFileSync('lot-workflow.js','utf8').match(/^function editLotRowNotes\(code\).*$/m)[0],c);
c.floor.flags(row.code);const notes=html.match(/onclick="([^"]+)"[^>]*>Note del capo/)[1];vm.runInContext(notes,c);assert(html.includes('Nota esistente'));assert(html.includes('Salva note'));
c.current.archived=true;c.floor.flags(row.code);assert(html.includes('disabled>Note del capo'));
console.log('PASS: shared dialog opens across ownership types; special codes, notes editor and read-only permissions preserved');
