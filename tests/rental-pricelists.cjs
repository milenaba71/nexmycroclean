const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const contracts=[{id:'K1',number:'N1',status:'active',lines:[],feeMills:1200},{id:'K2',number:'N2',status:'active',lines:[]}];
let server={clientRecords:[{id:'C1',name:'Cliente',rentalContracts:contracts}],garments:[{id:'P',wash:10}]},revision=1,allowed=true,conflict=false,saves=0,closed=0;
const notices=[],formError={textContent:''},app={innerHTML:''},modal={style:{},close(){closed++}},clone=x=>JSON.parse(JSON.stringify(x));
const c={db:clone(server),cloudUser:{name:'Test',email:'test@example.invalid'},userCan:()=>allowed,clone,esc:s=>String(s??'').replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('"','&quot;'),assetArg:x=>JSON.stringify(x),catalogRows:()=>[{id:'T1',name:'Camice',active:true},{id:'T2',name:'Tuta',active:true}],euro3:n=>(n/1000).toFixed(3),assetMoney:n=>n==null?'Da completare':(n/100).toFixed(2),notify:x=>notices.push(x),show(){},$:q=>q==='#modal'?modal:app,document:{querySelector:()=>modal},FormData:class {constructor(form){this.values=form.values}get(k){return this.values[k]??null}},crypto:{randomUUID:()=> 'LIST1'},cloudFlush:async()=>{},cloudAccept:snap=>{c.db=clone(snap.db)},cloudRequest:async(action,payload)=>{if(action!=='save')return {db:clone(server),revision};assert(allowed);saves++;if(conflict){conflict=false;revision++;server.clientRecords[0].phone='Concurrent edit';throw Object.assign(Error('REVISION_CONFLICT'),{status:409})}assert.equal(payload.revision,revision);server.clientRecords[0]=clone(payload.changes.clientRecords[0]);revision++;return {revision}}};
vm.createContext(c);
const rental=fs.readFileSync('rentals.js','utf8');vm.runInContext(rental.slice(0,rental.indexOf('const renderBeforeRentals=')),c);
vm.runInContext("rentalClientId='C1';const rentalFinanceTabs=new Map();rentalClientView=function(){};",c);
vm.runInContext(fs.readFileSync('rental-pricelists.js','utf8'),c);
function draft(id='K1',mode='edit',sourceId=null){return {clientId:'C1',id,mode,sourceId,expected:JSON.stringify(server.clientRecords[0].rentalContracts.find(k=>k.id===id))}}
function setDraft(d){c.nextDraft=d;vm.runInContext('rentalPriceDraft=nextDraft',c)}
function form(values,rows=[]){const buttons=[{disabled:false},{disabled:false}];return {values,querySelectorAll:q=>q==='button'?buttons:rows.map(values=>({querySelector:q=>({value:values[q.match(/name="(.+)"/)[1]]||''})})),querySelector:()=>formError,buttons}}
(async()=>{
 const beforeGarments=JSON.stringify(server.garments),f=form({name:'Listino base',notes:'Condizioni'},[{typeId:'T1',price:'23.45',fee:'1.234',washMode:'extra',washPrice:'0.125'}]);
 const parsed=c.rentalPriceReadForm(f);assert.equal(parsed.rows[0].priceCents,2345);assert.equal(parsed.rows[0].feeMills,1234);assert.equal(parsed.rows[0].washPriceMills,125);
 for(const bad of [{...parsed,rows:[]},{...parsed,rows:[parsed.rows[0],parsed.rows[0]]},{...parsed,rows:[{...parsed.rows[0],priceCents:-1}]},{...parsed,rows:[{...parsed.rows[0],washPriceMills:null}]}])assert.throws(()=>c.rentalPriceValidate(bad));
 const price4=form({name:'Bad',notes:''},[{typeId:'T1',price:'1.234',fee:'',washMode:'unknown'}]);assert.throws(()=>c.rentalPriceReadForm(price4),/due decimali/);
 setDraft(draft());conflict=true;await c.rentalPriceSave({preventDefault(){},target:f,submitter:{value:'link'}});
 assert.equal(formError.textContent,'');assert.equal(closed,1);assert.equal(saves,2);assert.equal(server.clientRecords[0].phone,'Concurrent edit');
 const client=server.clientRecords[0],list=client.rentalPriceLists[0];assert.equal(client.rentalPriceLists.length,1);assert.equal(client.rentalContracts[0].priceListId,'LIST1');assert.equal(client.rentalContracts[0].feeMills,1200);assert.equal(JSON.stringify(server.garments),beforeGarments);
 // Reuse the saved list in another contract, then create a version for K1 only.
 const d2=draft('K2','link');setDraft(d2);await c.rentalPriceLinkSave({preventDefault(){},target:form({listId:'LIST1'})});assert.equal(server.clientRecords[0].rentalContracts[1].priceListId,'LIST1');
 const d1=draft('K1','edit','LIST1');await c.mutateRentalClient('C1',value=>c.rentalPriceApply(value,d1,{...parsed,rows:[{...parsed.rows[0],priceCents:3000}]},'LIST2',true));
 assert.equal(server.clientRecords[0].rentalPriceLists.length,2);assert.equal(server.clientRecords[0].rentalPriceLists[0].rows[0].priceCents,2345);assert.equal(server.clientRecords[0].rentalPriceLists[1].version,2);assert.equal(server.clientRecords[0].rentalContracts[0].priceListId,'LIST2');assert.equal(server.clientRecords[0].rentalContracts[1].priceListId,'LIST1');
 assert.throws(()=>c.rentalPriceLinkApply(clone(server.clientRecords[0]),draft('K1','link'),'OTHER_CLIENT_LIST'),/questo cliente/);
 assert.throws(()=>c.rentalPriceLinkApply(clone(server.clientRecords[0]),d1,'LIST1'),/cambiato/);
 const standalone=draft('K2');await c.mutateRentalClient('C1',value=>c.rentalPriceApply(value,standalone,parsed,'LIST3',false));assert.equal(server.clientRecords[0].rentalContracts[1].priceListId,'LIST1');
 const unlink=draft('K2','link');await c.mutateRentalClient('C1',value=>c.rentalPriceLinkApply(value,unlink,''));assert.equal(server.clientRecords[0].rentalContracts[1].priceListId,null);
 const readOnly=clone(server.clientRecords[0]);readOnly.rentalContracts[0].status='closed';const cd={...draft(),expected:JSON.stringify(readOnly.rentalContracts[0])};assert.throws(()=>c.rentalPriceApply(readOnly,cd,parsed,'NO',true),/chiuso/);
 let html=c.rentalPriceListsPanel(server.clientRecords[0],server.clientRecords[0].rentalContracts[0]);assert(html.includes('Crea listino'));assert(html.includes('Collega listino esistente'));assert(html.includes('30.00'));
 allowed=false;html=c.rentalPriceListsPanel(server.clientRecords[0],server.clientRecords[0].rentalContracts[0]);assert(!html.includes('onclick'));await assert.rejects(c.mutateRentalClient('C1',()=>{}),/riservata/);allowed=true;
 // Prices can be edited even if loading asset history fails; switching tabs renders immediately.
 c.assetData=null;c.rentalPanelBeforeFinance=()=>'';c.assetLoad=async()=>null;c.page='Noleggi e dotazioni';c.rentalFinanceProducts=()=>'';
 vm.runInContext(rental.slice(rental.indexOf('rentalContractPanel=function(c,k){'),rental.indexOf('function rentalFinanceProducts(')),c);
 await c.rentalFinanceSelect('K1','prices');html=c.rentalContractPanel(c.db.clientRecords[0],c.db.clientRecords[0].rentalContracts[0]);assert(html.includes('Crea listino'));assert(html.includes('Collega listino esistente'));
 assert.equal(JSON.stringify(server.garments),beforeGarments);console.log('PASS create/save/link, monetary precision, versions, reuse, unlink, concurrent retry, stale edit protection, read-only permissions and unavailable asset history');
})().catch(e=>{console.error(e);process.exitCode=1});
