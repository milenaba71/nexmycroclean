// Capture callback state before Supabase consumes the URL fragment.
const authCallback=new URLSearchParams(location.hash.slice(1));
let authRecovery=authCallback.get('type')==='recovery',authCallbackError=authCallback.has('error')||authCallback.has('error_code');
try{authRecovery=authRecovery||sessionStorage.getItem('mycroclean.passwordRecovery')==='1'}catch{}
function authRememberRecovery(value){authRecovery=value;try{if(value)sessionStorage.setItem('mycroclean.passwordRecovery','1');else sessionStorage.removeItem('mycroclean.passwordRecovery')}catch{}}
function authCleanCallback(){history.replaceState(null,'',location.pathname+location.search)}
const appSupabase=window.supabase.createClient(window.MYCRO_CONFIG.url,window.MYCRO_CONFIG.key,{auth:{persistSession:true,autoRefreshToken:true,detectSessionInUrl:true}});
let authMode='login',cloudPoll=null;
function standaloneLogin(message=''){cloudUser=null;current=null;$('#nav').innerHTML='';$('#cloudState')?.remove();$('aside footer').innerHTML='Mycroclean<br>Accesso riservato agli utenti abilitati';$('#app').innerHTML=`<div class="panel" style="max-width:560px;margin:45px auto;padding:30px"><h1>${authMode==='signup'?'Primo accesso':authMode==='reset'?'Recupero password':'Accedi al gestionale'}</h1><p>${authMode==='signup'?'Usa l’email abilitata dall’amministratore e scegli una password personale.':'Inserisci le tue credenziali Mycroclean.'}</p><form onsubmit="standaloneAuthenticate(event)" style="display:grid;gap:16px;margin-top:25px"><label>Email<input name="email" type="email" required autocomplete="email" style="width:100%"></label>${authMode!=='reset'?passwordField('loginPassword','Password',authMode==='signup'?'new-password':'current-password'):''}<button class="btn" id="loginButton">${authMode==='signup'?'Attiva account':authMode==='reset'?'Invia link di recupero':'Accedi'}</button><p id="authMessage" role="status" style="color:#a52359">${esc(message)}</p></form><div class="tools" style="padding:20px 0 0"><button class="link" onclick="authMode='login';standaloneLogin()">Accedi</button><button class="link" onclick="authMode='signup';standaloneLogin()">Primo accesso</button><button class="link" onclick="authMode='reset';standaloneLogin()">Password dimenticata</button></div><p style="font-size:11px;margin-top:18px">Non serve un account ChatGPT. Le autorizzazioni sono assegnate dall’amministratore.</p></div>`}
function authError(e){let m=String(e.message||'');if(/Invalid login credentials/.test(m))return'Email o password non corrette.';if(/Email not confirmed/.test(m))return'Conferma prima la tua email tramite il messaggio di attivazione.';if(/rate limit|security purposes/.test(m))return'Troppi tentativi. Attendi qualche minuto prima di riprovare.';return 'Operazione non completata: '+m}
async function standaloneAuthenticate(e){e.preventDefault();let b=e.submitter;b.disabled=true;let f=new FormData(e.target),email=f.get('email').trim(),password=f.get('password');try{if(authMode==='reset'){let r=await appSupabase.auth.resetPasswordForEmail(email,{redirectTo:new URL('./',location.href).href});if(r.error)throw r.error;$('#authMessage').textContent='Se l’account è presente, riceverai un messaggio per reimpostare la password.'}else if(authMode==='signup'){let r=await appSupabase.auth.signUp({email,password,options:{emailRedirectTo:new URL('./',location.href).href}});if(r.error)throw r.error;if(r.data.session){await cloudBoot()}else $('#authMessage').textContent='Controlla la tua email e conferma l’attivazione, poi torna qui e accedi. Se non arriva, chiedi all’amministratore di verificare l’abilitazione.'}else{let r=await appSupabase.auth.signInWithPassword({email,password});if(r.error)throw r.error;await cloudBoot()}}catch(err){$('#authMessage').textContent=authError(err)}finally{b.disabled=false}}
async function standaloneLogout(){await appSupabase.auth.signOut();cloudBase=null;cloudQueue=[];cloudStopped=false;standaloneLogin()}
function authRecoveryScreen(session,error){
 if(authCallbackError||(authRecovery&&(error||!session))){authCallbackError=false;authRememberRecovery(false);authCleanCallback();authMode='reset';standaloneLogin('Il link non è valido, è scaduto oppure è già stato usato. Richiedi una nuova email e apri soltanto il link più recente.');return true}
 if(!authRecovery)return false;
 authRememberRecovery(true);authCleanCallback();recoveryForm();return true;
}
function recoveryForm(){
 if(window.floor){floor.active=false;document.body.classList.remove('floor-mode')}
 standaloneLogin();
 $('#modal')?.close();
 $('#app').innerHTML=`<section class="panel" style="max-width:560px;margin:35px auto;padding:25px"><h1>Scegli la nuova password</h1><p>Inserisci almeno 12 caratteri e ripeti la password per confermarla.</p><form onsubmit="setRecoveredPassword(event)" style="display:grid;gap:18px;margin-top:20px">${passwordField('recoveryPassword','Nuova password','new-password')}<label>Ripeti la nuova password<input id="recoveryConfirm" name="confirmation" type="password" required minlength="12" autocomplete="new-password" style="width:100%"></label><button class="btn">Salva nuova password</button><p id="recoveryMessage" role="alert"></p></form><button class="link" onclick="cancelPasswordRecovery()">Annulla e torna all’accesso</button></section>`;
}
async function cancelPasswordRecovery(){authRememberRecovery(false);authCleanCallback();await appSupabase.auth.signOut({scope:'local'});authMode='login';standaloneLogin()}
async function setRecoveredPassword(e){
 e.preventDefault();const b=e.submitter,f=new FormData(e.target),message=$('#recoveryMessage');
 if(f.get('password')!==f.get('confirmation')){message.textContent='Le due password non coincidono. Ripetile uguali.';return}
 b.disabled=true;message.textContent='Salvataggio della nuova password…';
 try{const {error}=await appSupabase.auth.updateUser({password:f.get('password')});if(error)throw error;
 authRememberRecovery(false);authCleanCallback();await appSupabase.auth.signOut({scope:'local'});authMode='login';standaloneLogin('Password aggiornata. Ora accedi con la nuova password.');
 }catch(error){message.textContent=authError(error)}finally{b.disabled=false}
}
appSupabase.auth.onAuthStateChange((event)=>{
 if(event==='PASSWORD_RECOVERY'){authRememberRecovery(true);setTimeout(()=>void cloudBoot(),0)}
 if(event==='SIGNED_OUT')setTimeout(()=>{if(!authRecovery&&!$('#authMessage')?.textContent)standaloneLogin()},0);
});

function passwordField(id,label,autocomplete){return `<div><label for="${id}">${label}</label><div style="position:relative;margin-top:7px"><input id="${id}" name="password" type="password" minlength="12" required autocomplete="${autocomplete}" style="width:100%;padding-right:155px"><button type="button" aria-controls="${id}" aria-pressed="false" onclick="togglePasswordVisibility('${id}',this)" style="position:absolute;right:5px;top:5px;bottom:5px;border:0;background:#eef2fa;color:#294f91;padding:0 10px;border-radius:4px;font-size:12px;cursor:pointer">Mostra password</button></div></div>`}
function togglePasswordVisibility(id,button){const input=document.getElementById(id);if(!input)return;const visible=input.type==='password';input.type=visible?'text':'password';button.textContent=visible?'Nascondi password':'Mostra password';button.setAttribute('aria-pressed',String(visible));}
