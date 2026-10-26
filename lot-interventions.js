const lotTableBeforeInterventions=lotTable;
lotTable=function(){lotTableBeforeInterventions();let table=$('#lotTable table');if(!table)return;let head=table.querySelector('thead tr'),anchor=head.children[6];for(let label of ['Da riparare','Da etichettare','In verifica']){let th=document.createElement('th');th.textContent=label;head.insertBefore(th,anchor)}for(let tr of table.querySelectorAll('tbody tr')){let button=tr.querySelector('button[onclick^="openLot("]'),id=button?.getAttribute('onclick').match(/openLot\((\d+)\)/)?.[1],lot=db.lots.find(l=>l.id===Number(id));if(!lot){tr.querySelector('td')?.setAttribute('colspan','11');continue}let anchor=tr.children[6];for(let kind of ['repair','relabel','verify']){let td=document.createElement('td');td.textContent=lot.rows.filter(r=>!!r[kind]).length;tr.insertBefore(td,anchor)}let b=document.createElement('button');b.className='link';b.textContent='Riparazioni →';b.onclick=()=>openLotRepairs(lot.id);button.parentNode.appendChild(b)}};
function openLotRepairs(id){go('Riparazioni');repairDetail(id)}
const goBeforeInterventions=go;
go=function(p){repairLotId=null;goBeforeInterventions(p)};
const renderBeforeInterventions=render;
render=function(){let repairId=page==='Riparazioni'?repairLotId:null;renderBeforeInterventions();if(repairId!==null&&page==='Riparazioni'&&db.lots.some(l=>l.id===repairId))repairDetail(repairId)};
if(cloudUser)render();
