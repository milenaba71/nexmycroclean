const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const source=fs.readFileSync('cloud.js','utf8');const code=source.slice(source.indexOf('async function userSaveDeadline'),source.indexOf('\nfunction resetDemo'));
let requests=0,invokes=0,closed=false,message='',fail=false;
const context={setTimeout,clearTimeout,cloudUser:{isSuperAdmin:true},FormData:class{constructor(f){return Object.entries(f.values)}},cloudRequest:async()=>{requests++},appSupabase:{functions:{invoke:async()=>{invokes++;if(fail)throw Error('Rete non disponibile');return{data:{ok:true}}}}},$:()=>({close(){closed=true}}),notify:m=>message=m,usersView:async()=>{}};vm.createContext(context);vm.runInContext(code,context);
function fixture(overrides={}){const error={textContent:''},button={disabled:false,textContent:'Salva utente'},form={dataset:{},values:{name:'Test',email:'test@example.com',role:'operator',active:'yes',manualPassword:'Test-password-123',confirmPassword:'Test-password-123',...overrides},elements:{manualPassword:{value:'x'},confirmPassword:{value:'x'}},querySelector:q=>q==='#userSaveError'?error:button};return{form,error,button,event:{preventDefault(){},target:form}}}
(async()=>{
let f=fixture();await context.saveUser(f.event);assert(closed);assert.equal(invokes,1);assert(message.includes('password assegnata'));assert.equal(f.form.elements.manualPassword.value,'');assert(!f.button.disabled);assert.equal(f.button.textContent,'Salva utente');
fail=true;closed=false;f=fixture();await context.saveUser(f.event);assert(!closed);assert(f.error.textContent.includes('Dati utente salvati.'));assert(!f.button.disabled);
let previous=requests;f=fixture({confirmPassword:'different'});await context.saveUser(f.event);assert.equal(requests,previous);assert(f.error.textContent.includes('non coincidono'));assert(!f.button.disabled);
f=fixture({manualPassword:'',confirmPassword:''});previous=invokes;await context.saveUser(f.event);assert.equal(invokes,previous);
f=fixture();f.form.dataset.saving='1';previous=requests;await context.saveUser(f.event);assert.equal(requests,previous);
context.setTimeout=(fn)=>setTimeout(fn,1);await assert.rejects(context.userSaveDeadline(()=>new Promise(()=>{})),/esito non è ancora confermato/);
console.log('PASS user save: success, partial failure, validation, optional password, duplicate guard, missing submitter, timeout, button recovery');
})().catch(e=>{console.error(e);process.exit(1)});
