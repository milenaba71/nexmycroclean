/* Dictation fills a field only. Saving/sending always remains an explicit action. */
(()=>{
 let current=null;
 window.attachDictation=function(input,{isActive=()=>true,onBusy=()=>{}}={}){
  const el=(tag,text)=>{const e=document.createElement(tag);if(text)e.textContent=text;return e};
  const box=el('div'),controls=el('div'),button=el('button','🎤 Detta'),language=el('select'),status=el('p'),hint=el('small');
  box.className='wide';box.dataset.dictation='';box.style.cssText='margin:8px 0 14px;max-width:100%';controls.style.cssText='display:flex;flex-wrap:wrap;align-items:center;gap:8px';
  button.type='button';button.className='btn secondary';button.setAttribute('aria-pressed','false');
  language.setAttribute('aria-label','Lingua della dettatura');language.style.cssText='max-width:100%;min-width:0';status.setAttribute('role','status');status.dir='auto';input.dir='auto';
  const languages=[['it-IT','Italiano'],['hy-AM','Հայերեն · Armeno'],['ro-RO','Română · Rumeno'],['uk-UA','Українська · Ucraino'],['ru-RU','Русский · Russo'],['en-GB','English · Inglese'],['fa-IR','فارسی · Farsi'],['ar-SA','العربية · Arabo'],['fr-FR','Français · Francese'],['es-ES','Español · Spagnolo'],['de-DE','Deutsch · Tedesco'],['pt-PT','Português · Portoghese'],['zh-CN','中文 · Cinese'],['hi-IN','हिन्दी · Hindi']];
  for(const [code,name] of languages){const option=el('option',name);option.value=code;language.append(option)}
  const browserLang=navigator.language||'it-IT';let preferred=browserLang;
  try{preferred=localStorage.getItem('mycroclean-dictation-language')||browserLang}catch{}
  language.value=languages.find(([code])=>code===preferred)?.[0]||languages.find(([code])=>code.split('-')[0]===preferred.split('-')[0])?.[0]||'it-IT';
  language.onchange=()=>{try{localStorage.setItem('mycroclean-dictation-language',language.value)}catch{}};
  const Recognition=window.SpeechRecognition||window.webkitSpeechRecognition;
  hint.textContent=Recognition?'Scegli la lingua, premi Detta e consenti il microfono. Ferma e controlla il testo prima di inviare o salvare. La dettatura usa il servizio del browser, che può elaborare l’audio online.':'Dettatura non disponibile in questo browser. Puoi usare il microfono della tastiera del telefono oppure scrivere.';
  button.disabled=!Recognition;language.disabled=!Recognition;
  controls.append(button,language);box.append(controls,status,hint);
  let session=null;
  const usable=()=>input.isConnected&&box.isConnected&&isActive()&&(!input.closest('dialog')||input.closest('dialog').open);
  function finish(message,abort=false){
   const s=session;if(!s)return;session=null;if(current===cancel)current=null;
   clearTimeout(s.limit);clearTimeout(s.fallback);s.observer.disconnect();
   document.removeEventListener('visibilitychange',s.hide);window.removeEventListener('pagehide',s.hide);s.dialog?.removeEventListener('close',s.hide);s.form?.removeEventListener('submit',s.submit,true);
   s.rec.onresult=s.rec.onerror=s.rec.onend=null;if(abort)try{s.rec.abort()}catch{}
   input.readOnly=s.readOnly;language.disabled=false;button.disabled=false;button.textContent='🎤 Detta';button.setAttribute('aria-pressed','false');onBusy(false);
   status.textContent=message||'Dettatura terminata. Controlla il testo prima di inviare o salvare.';
  }
  function cancel(){finish('Dettatura interrotta. Il testo già riconosciuto resta nel campo.',true)}
  function stop(){
   const s=session;if(!s||s.stopping)return;s.stopping=true;button.disabled=true;status.textContent='Completamento della dettatura…';
   s.fallback=setTimeout(()=>{if(session===s)finish('Dettatura terminata. Controlla il testo riconosciuto.',true)},3000);
   try{s.rec.stop()}catch{finish('Dettatura terminata. Controlla il testo riconosciuto.',true)}
  }
  button.onclick=()=>{
   if(session){stop();return}if(!Recognition||!usable()||input.disabled||input.readOnly)return;
   if(input.maxLength>=0&&input.value.length>=input.maxLength){status.textContent='Il campo ha raggiunto il numero massimo di caratteri.';return}
   current?.();
   let rec;try{rec=new Recognition()}catch{status.textContent='Microfono non disponibile. Usa la tastiera per continuare.';return}
   const s={rec,base:input.value,readOnly:input.readOnly,dialog:input.closest('dialog'),form:input.form,stopping:false,hasText:false};session=s;current=cancel;
   rec.lang=language.value;rec.continuous=true;rec.interimResults=true;rec.maxAlternatives=1;
   s.hide=()=>{if(session===s)cancel()};
   s.submit=e=>{if(session===s){e.preventDefault();e.stopImmediatePropagation();status.textContent='Prima premi Ferma, controlla il testo, poi salva.'}};
   s.observer=new MutationObserver(()=>{if(session===s&&!usable())cancel()});s.observer.observe(document.body,{childList:true,subtree:true});if(s.dialog)s.observer.observe(s.dialog,{attributes:true,attributeFilter:['open']});
   document.addEventListener('visibilitychange',s.hide);window.addEventListener('pagehide',s.hide);s.dialog?.addEventListener('close',s.hide);s.form?.addEventListener('submit',s.submit,true);
   input.readOnly=true;language.disabled=true;button.textContent='⏹ Ferma';button.setAttribute('aria-pressed','true');onBusy(true);status.textContent='Microfono attivo: parla…';
   rec.onresult=e=>{
    if(session!==s)return;if(!usable()){cancel();return}
    const final=[],interim=[];
    for(let i=0;i<e.results.length;i++){const r=e.results[i];(r.isFinal?final:interim).push(r[0].transcript)}
    const spoken=final.join(' ').trim();if(spoken){const combined=s.base+(s.base&&!/\s$/.test(s.base)?' ':'')+spoken;input.value=input.maxLength>=0?combined.slice(0,input.maxLength):combined;s.hasText=true;input.dispatchEvent(new Event('input',{bubbles:true}));
     if(input.maxLength>=0&&combined.length>=input.maxLength){stop();status.textContent='Limite di caratteri raggiunto. Controlla il testo.';return}}
    status.textContent=interim.length?'Sto ascoltando: '+interim.join(' '):'Testo aggiunto. Puoi continuare a parlare o premere Ferma.';
   };
   rec.onerror=e=>{if(session!==s)return;const messages={'not-allowed':'Consenti il microfono nelle impostazioni del browser e riprova. Puoi continuare a scrivere.','service-not-allowed':'Il browser non consente la dettatura. Usa il microfono della tastiera o scrivi.','audio-capture':'Microfono non disponibile: verifica che sia collegato e libero.','no-speech':'Non ho sentito parole. Premi Detta per riprovare.','network':'Connessione del servizio di dettatura non disponibile. Puoi continuare a scrivere.','language-not-supported':'Questa lingua non è supportata dal servizio di dettatura del browser. Usa la tastiera o seleziona un’altra lingua.'};finish(messages[e.error]||'Dettatura interrotta. Il testo già riconosciuto è conservato.',true)};
   rec.onend=()=>{if(session===s)finish(s.hasText?'Testo pronto: controllalo e poi invia o salva.':'Nessun testo riconosciuto. Premi Detta per riprovare.')};
   s.limit=setTimeout(stop,60000);
   try{rec.start()}catch{finish('Impossibile avviare il microfono. Controlla i permessi o continua a scrivere.',true)}
  };
  return {element:box,cancel,get busy(){return !!session}};
 };
})();
