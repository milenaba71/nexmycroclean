const fs=require('fs'),assert=require('node:assert/strict');
const {JSDOM}=require(process.env.JSDOM_PATH||'jsdom');
(async()=>{
 const dom=new JSDOM('<div id="app"></div><dialog id="modal"></dialog>',{runScripts:'outside-only',pretendToBeVisual:true,url:'https://test.invalid'}),w=dom.window,d=w.document;
 let pollTimer,calls=0,tones=0,list={messages:[],unread:0,alerts:[]};
 w.setInterval=fn=>{pollTimer=fn};
 Object.assign(w,{cloudUser:{email:'user@test.invalid'},current:null,esc:String,cloudAccept:()=>{},standaloneLogin:()=>{w.cloudUser=null},notify:()=>{},appSupabase:{rpc:async()=>{calls++;return {data:list}}}});
 w.AudioContext=class{constructor(){this.state='running';this.currentTime=0;this.destination={}}createOscillator(){tones++;return{frequency:{},connect(){},start(){},stop(){},disconnect(){}}}createGain(){return{gain:{setValueAtTime(){},linearRampToValueAtTime(){},exponentialRampToValueAtTime(){}},connect(){},disconnect(){}}}};
 w.eval(fs.readFileSync('chat-sound.js','utf8'));w.eval(fs.readFileSync('lot-chat.js','utf8'));await new Promise(r=>setImmediate(r));await w.ChatSound.unlock();
 Object.defineProperty(d,'hidden',{configurable:true,value:true});
 list={messages:[],unread:1,alerts:[{id:'new-1',sender_name:'Collega',body:'Nuovo messaggio'}]};
 const before=calls;pollTimer();await new Promise(r=>setImmediate(r));assert.equal(calls,before+1);assert.equal(tones,2);assert.equal(w.LotChat.unread,1);
 pollTimer();await new Promise(r=>setImmediate(r));assert.equal(tones,2);
 list.alerts.push({id:'new-2',sender_name:'Collega',body:'Altro messaggio'});pollTimer();await new Promise(r=>setImmediate(r));assert.equal(tones,4); // Existing alert must not suppress a new sound.
 await w.ChatSound.toggle();list.alerts.push({id:'new-3'});pollTimer();await new Promise(r=>setImmediate(r));assert.equal(tones,4);
 w.standaloneLogin();const loggedOut=calls;pollTimer();await new Promise(r=>setImmediate(r));assert.equal(calls,loggedOut);
 dom.window.close();console.log('PASS: hidden-page polling, notification audio, deduplication, mute and logout');
})().catch(e=>{console.error(e);process.exitCode=1});
