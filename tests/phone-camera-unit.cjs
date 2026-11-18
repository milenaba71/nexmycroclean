const vm=require('node:vm'),fs=require('node:fs'),assert=require('node:assert/strict');
const nodes=new Map();
function node(id){return {id,disabled:false,readOnly:false,value:'',textContent:'',open:false,remove(){nodes.delete(id)},blur(){},insertAdjacentHTML(where,html){for(const m of html.matchAll(/id="([^"]+)"/g))nodes.set(m[1],node(m[1]));const val=html.match(/id="phonePrintedCode"[^>]*value="([^"]*)"/);if(val)nodes.get('phonePrintedCode').value=val[1]},closest(){return this}}}
nodes.set('scan',node('scan'));nodes.set('modal',node('modal'));
const body=node('body'),head={appendChild(){}},sent=[],messages=[];
const context={console,setTimeout,clearTimeout,Map,Set,Date,Promise,Error,document:{body,head,createElement:()=>node('style'),addEventListener(){}},MutationObserver:class{observe(){}},navigator:{mediaDevices:{getUserMedia(){}},vibrate(){}},current:{id:1},stage:'Entrata',chosenProcessing:'P1',cloudBusy:false,cloudUser:null,db:{garments:[]},scanResults:[],detail(){},$:sel=>nodes.get(sel.slice(1)),lotWritable:()=>true,lotMutationAllowed:()=>true,selectedProcessing:()=>true,lotBusy:()=>false,notify:m=>messages.push(m),enqueueBarcode:code=>sent.push(code),resolveBarcode:code=>code,esc:s=>String(s),lotno:()=> 'L.TEST',addEventListener(){}};
context.window=context;vm.createContext(context);
for(const f of ['phone-scanner.js','phone-ocr.js'])vm.runInContext(fs.readFileSync(f,'utf8'),context);
const run=s=>vm.runInContext(s,context);
(async()=>{
run("phoneWaitResult=async()=>{}; phoneScanner={...phoneContext(),mode:'text',codes:new Set(),cancelled:false};");
nodes.set('phoneScanStatus',node('phoneScanStatus'));
run("acceptPrintedReading(phoneScanner,{text:'20264481AC',confidence:98});acceptPrintedReading(phoneScanner,{text:'20264481AC',confidence:98});");assert.equal(nodes.has('phonePrintedConfirm'),false);
run("acceptPrintedReading(phoneScanner,{text:'20264481AC',confidence:98})");assert.equal(nodes.has('phonePrintedConfirm'),true);assert.equal(sent.length,0);
nodes.get('phonePrintedCode').value='20264482AC';run('confirmPrintedCode()');assert.deepEqual(sent,['20264482AC']);assert.equal(nodes.has('phonePrintedConfirm'),false);
run("for(let i=0;i<3;i++)acceptPrintedReading(phoneScanner,{text:'20264483AC',confidence:98});retryPrintedCode()");assert.equal(sent.length,1);assert.equal(run('phoneScanner.pendingPrinted'),null);
run("for(let i=0;i<3;i++)acceptPrintedReading(phoneScanner,{text:'20264484AC',confidence:98});stage='Uscita';confirmPrintedCode()");assert.equal(sent.length,1);run("stage='Entrata';retryPrintedCode()");
run("for(let i=0;i<3;i++)acceptPrintedReading(phoneScanner,{text:'20264485AC',confidence:50})");assert.equal(nodes.has('phonePrintedConfirm'),false);
assert.throws(()=>run("submitPhoneCode('https://example.com',phoneScanner)"),/link/);
nodes.get('scan').disabled=true;assert.equal(run('phoneStartAllowed()'),false);nodes.get('scan').disabled=false;
context.cloudBusy=true;assert.equal(run('phoneStartAllowed()'),false);context.cloudBusy=false;
// Barcode callback: duplicate frames register only once, stale context never registers.
let callback,stops=0;context.ZXingBrowser={BrowserMultiFormatOneDReader:class{async decodeFromConstraints(opts,video,cb){assert.equal(opts.video.facingMode.ideal,'environment');callback=cb;return {stop(){stops++}}}}};
await run('startPhoneCamera()');assert.equal(nodes.get('scan').readOnly,true);
callback({getText:()=> '000123'},null,{stop(){}});callback({getText:()=> '000123'},null,{stop(){}});assert.deepEqual(sent,['20264482AC','000123']);
context.current={id:2};callback({getText:()=> '000456'},null,{stop(){}});assert.equal(sent.length,2);
run('stopPhoneCamera()');assert.equal(stops,1);assert.equal(nodes.get('scan').readOnly,false);assert.equal(nodes.has('phoneCameraPanel'),false);
// Close while camera permission/start is still pending: late controls must stop.
context.current={id:1};let finish;context.ZXingBrowser={BrowserMultiFormatOneDReader:class{decodeFromConstraints(){return new Promise(resolve=>finish=resolve)}}};const opening=run('startPhoneCamera()');await new Promise(r=>setImmediate(r));run('stopPhoneCamera()');finish({stop(){stops++}});await opening;assert.equal(stops,2);
console.log('PASS: barcode deduplication, OCR confirmation/edit/retry/confidence, context and busy guards, late camera cleanup');
})().catch(e=>{console.error(e);process.exitCode=1});
