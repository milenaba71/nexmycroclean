/* Keep the production origin while working in its lot or repair module. */
let productionReturnContext=null,productionReturnScroll=null,productionReturning=false;
const productionActionBeforeReturn=pAction;
pAction=async function(action,id){
 if(page===productionPage&&['lot','repairLot'].includes(action)&&db.lots.some(l=>l.id===Number(id))){
  productionReturnContext={lotId:Number(id),tab:prodTab,date:prodDate,query:prodQuery,scroll:window.scrollY};
 }
 return productionActionBeforeReturn(action,id);
};
function decorateProductionReturn(){
 let ctx=productionReturnContext;
 if(!ctx||$('#productionReturnButton'))return;
 let matches=current?.id===ctx.lotId||page==='Riparazioni'&&repairLotId===ctx.lotId;
 if(!matches)return;
 let row=document.createElement('div');row.className='production-return-bar';
 let button=document.createElement('button');button.id='productionReturnButton';button.className='btn secondary';button.type='button';
 button.textContent=ctx.tab==='mine'?'← Torna alle mie attività':ctx.tab==='board'?'← Torna alla pianificazione':'← Torna a Produzione · '+(prodTabs[ctx.tab]||'Attività');
 button.onclick=returnToProductionActivities;row.append(button);$('#app').prepend(row);
}
async function returnToProductionActivities(){
 if(!productionReturnContext||productionReturning)return;
 if(lotBusy()||washBusy||prodBusy)return notify('Attendi che termini la registrazione in corso.');
 productionReturning=true;let button=$('#productionReturnButton');if(button)button.disabled=true;
 try{
  await cloudFlush();let ctx=productionReturnContext;productionReturnContext=null;
  prodTab=ctx.tab;prodDate=ctx.date;prodQuery=ctx.query;productionReturnScroll=ctx.scroll;
  $('#modal').close();go(productionPage);
 }catch(e){notify('Ritorno non completato: '+e.message);if(button)button.disabled=false}
 finally{productionReturning=false}
}
const detailBeforeProductionReturn=detail;detail=function(...args){let result=detailBeforeProductionReturn(...args);decorateProductionReturn();return result};
const repairDetailBeforeProductionReturn=repairDetail;repairDetail=function(...args){let result=repairDetailBeforeProductionReturn(...args);decorateProductionReturn();return result};
const repairProductBeforeProductionReturn=repairProductDetail;repairProductDetail=function(...args){let result=repairProductBeforeProductionReturn(...args);decorateProductionReturn();return result};
const goBeforeProductionReturn=go;go=function(destination){if(!['Lotti','Storico','Riparazioni'].includes(destination))productionReturnContext=null;return goBeforeProductionReturn(destination)};
const drawBeforeProductionReturn=pDraw;pDraw=function(...args){let result=drawBeforeProductionReturn(...args);if(page===productionPage&&!current&&productionReturnScroll!==null){let y=productionReturnScroll;productionReturnScroll=null;requestAnimationFrame(()=>window.scrollTo({top:y,behavior:'instant'}))}return result};
const productionReturnStyle=document.createElement('style');productionReturnStyle.textContent='.production-return-bar{margin:0 0 16px}.production-return-bar .btn{min-height:44px;white-space:normal;text-align:left}@media(max-width:700px){.production-return-bar .btn{width:100%}}';document.head.append(productionReturnStyle);
