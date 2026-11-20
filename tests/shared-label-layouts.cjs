const fs=require('fs'),vm=require('vm'),assert=require('node:assert/strict');
const clone=x=>JSON.parse(JSON.stringify(x));
const source=fs.readFileSync('label-layout-cloud.js','utf8');
let server={revision:0,payload:{presets:{},current:null}},fail=null;
function client(){
 const elements=new Map(),storage=new Map(),alerts=[],events={};let current={layout:{barcode:{x:1,y:2}},logo:'logo.png',freetexts:[],fields:{barcode:true},format:'roll'};
 const element=()=>({style:{},hidden:false,textContent:'',appendChild(){},closest(){return null;}});
 const context={JSON,Set,Map,Object,String,console,PRESETS_KEY:'presets',LS_KEY:'layout',FT_KEY:'texts',DEFAULT_LAYOUT:{},alert:s=>alerts.push(s),confirm:()=>true,refreshPresetSelect(){},currentPreset:()=>clone(current),applyPreset:p=>{current=clone(p);context.LabelCloud.dirty();},document:{getElementById:id=>{if(!elements.has(id))elements.set(id,element());return elements.get(id);},createElement:element,body:{appendChild(){}},addEventListener:(n,f)=>events[n]=f},localStorage:{getItem:k=>storage.get(k)||null,setItem(){throw Error('Local writes forbidden');},removeItem:k=>storage.delete(k)},addEventListener:(n,f)=>events[n]=f,parent:{async labelLayoutsRequest(action,p){if(fail)throw Error(fail);if(action==='read')return clone(server);assert.equal(action,'save');if(p.revision!==server.revision)throw Error('REVISION_CONFLICT');server={revision:server.revision+1,payload:clone(p.payload)};return clone(server);}}};
 context.window=context;vm.createContext(context);vm.runInContext(source,context);
 return {context,elements,storage,alerts,events,get current(){return current;}};
}
const settle=()=>new Promise(resolve=>setImmediate(resolve));
(async()=>{
 const a=client(),b=client();await settle();
 a.context.LabelCloud.dirty();assert.match(a.elements.get('labelCloudStatus').textContent,/non salvate/);assert.equal(server.revision,0);
 assert.equal(await a.context.LabelCloud.save({Rotolo:a.current}),true);assert.equal(server.revision,1);assert.equal(a.alerts.length,0);
 assert.equal(await b.context.LabelCloud.save({Stale:b.current}),false);assert.equal(server.revision,1);assert.match(b.alerts.at(-1),/collega/);assert(!server.payload.presets.Stale);
 await b.context.LabelCloud.load();assert.deepEqual(clone(b.context.LabelCloud.presets()),server.payload.presets);assert.deepEqual(b.current,a.current);
 fail='Network unavailable';b.storage.set('presets',JSON.stringify({Rotolo:{layout:{}}}));b.storage.set('layout','{}');await b.context.LabelCloud.importLegacy();assert(b.storage.has('presets'));assert.equal(server.revision,1);
 fail=null;await b.context.LabelCloud.importLegacy();assert.equal(b.storage.size,0);assert(server.payload.presets.Rotolo);assert(server.payload.presets['Rotolo (recuperato 1)']);assert(server.payload.presets['Layout locale recuperato']);
 const c=client();await settle();assert.deepEqual(clone(c.context.LabelCloud.presets()),server.payload.presets);
 const presets=c.context.LabelCloud.presets();delete presets.Rotolo;assert.equal(await c.context.LabelCloud.save(presets),true);await a.context.LabelCloud.load();assert(!a.context.LabelCloud.presets().Rotolo);
 fail='Non sei abilitato';const d=client();await settle();assert.match(d.elements.get('labelCloudStatus').textContent,/non riuscito/);assert.equal(await d.context.LabelCloud.save({}),false);
 assert(!/localStorage\.setItem/.test(fs.readFileSync('etichette.html','utf8')+source));
 console.log('PASS: cross-user shared state, saved acknowledgement, stale revision rejection, error recovery, legacy migration without overwrite or premature deletion, shared deletion, permission failure, no local layout writes');
})().catch(e=>{console.error(e);process.exitCode=1;});
