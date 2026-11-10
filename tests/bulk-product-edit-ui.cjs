const fs=require('fs'),vm=require('vm'),assert=require('node:assert/strict');
const context={updateProductSelection(){},FormData:class{constructor(form){this.form=form}getAll(k){return this.form[k]||[]}get(k){return this.form[k]??null}},console};vm.createContext(context);vm.runInContext(fs.readFileSync('product-bulk-edit.js','utf8'),context);
let p=context.productEditPatch({apply:['size'],size:'U',client:'DO NOT CHANGE',NOTE:''});assert.equal(JSON.stringify(p),'{"size":"U"}');
p=context.productEditPatch({apply:['estimatedBirthDate','NOTE'],estimatedBirthDate:'2020-02-29',NOTE:''});assert.equal(p.estimatedBirthDate,'2020-02-29');assert.equal(p.NOTE,'');
assert.throws(()=>context.productEditPatch({apply:[]}),/Spunta/);assert.throws(()=>context.productEditPatch({apply:['size'],size:''}),/Seleziona/);
const source=fs.readFileSync('product-card.js','utf8');assert(source.includes("productInput('Data presunta nascita indumento (facoltativa)','estimatedBirthDate',toDateInput(r['DATA PRESUNTA NASCITA INDUMENTO']),'date')"));
const save=fs.readFileSync('product-barcodes.js','utf8');assert(save.includes("'DATA PRESUNTA NASCITA INDUMENTO':dateLabel(f.get('estimatedBirthDate'))"));
console.log('PASS only checked fields submitted, empty optional values supported, date control optional and persisted');
