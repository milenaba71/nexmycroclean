/* Voice messages use the same private storage and recipients as attachments. */
(function(){
 const C=window.LotChat,el=id=>document.getElementById(id);
 const V=C.voice={session:null,urls:new Set(),player:null};
 const message=text=>{if(el('chatVoiceStatus'))el('chatVoiceStatus').textContent=text};
 const release=stream=>stream?.getTracks().forEach(track=>track.stop());
 const audioType=name=>/\.m4a$/i.test(name)?'audio/mp4':/\.ogg$/i.test(name)?'audio/ogg':/\.mp3$/i.test(name)?'audio/mpeg':/\.wav$/i.test(name)?'audio/wav':/\.webm$/i.test(name)?'audio/webm':'';
 V.url=blob=>{const url=URL.createObjectURL(blob);V.urls.add(url);return url};
 V.cancel=function(){const s=V.session;V.session=null;if(s){s.cancelled=true;clearInterval(s.timer);if(s.recorder?.state==='recording')s.recorder.stop();release(s.stream)}V.controls()};
 V.clear=function(){V.cancel();V.player?.pause();V.player=null;for(const url of V.urls)URL.revokeObjectURL(url);V.urls.clear()};
 V.controls=function(){const busy=!!V.session;if(el('chatVoiceStart'))el('chatVoiceStart').disabled=busy||!!C.compose?.sending;if(el('chatVoiceStop'))el('chatVoiceStop').hidden=!V.session?.recorder;if(el('chatVoiceDiscard'))el('chatVoiceDiscard').hidden=!busy;if(el('chatSend'))el('chatSend').disabled=busy||!!C.compose?.sending};
 V.mount=function(){if(!el('chatCompose')||el('chatVoice'))return;const box=document.createElement('section');box.id='chatVoice';box.className='chat-voice';box.innerHTML='<b>Messaggio vocale</b><div class="tools"><button type="button" class="btn secondary" id="chatVoiceStart">🎙 Registra vocale</button><button type="button" class="btn" id="chatVoiceStop" hidden>⏹ Termina</button><button type="button" class="btn secondary" id="chatVoiceDiscard" hidden>Scarta registrazione</button></div><p id="chatVoiceStatus" role="status" aria-live="polite">Registra, riascolta e poi premi Invia messaggio. Massimo 5 minuti.</p>';el('chatFileList').before(box);el('chatVoiceStart').onclick=V.start;el('chatVoiceStop').onclick=V.stop;el('chatVoiceDiscard').onclick=()=>{V.cancel();message('Registrazione scartata.')};el('modal').addEventListener('close',()=>{V.clear()},{once:true});V.controls()};
 V.start=async function(){const d=C.compose;if(!d||d.sending||V.session)return;if(d.files.length>=5){message('Rimuovi un allegato: puoi inviare al massimo 5 file o vocali.');return}if(!navigator.mediaDevices?.getUserMedia||!window.MediaRecorder){message('Registrazione non disponibile in questo browser. Puoi allegare un file audio con Allega file.');return}
  const s={draft:d,cancelled:false,chunks:[],bytes:0};V.session=s;V.controls();message('Consenti l’accesso al microfono per registrare.');
  try{const stream=await navigator.mediaDevices.getUserMedia({audio:true});if(V.session!==s||C.compose!==d||!el('modal')?.open||cloudUser?.email!==d.owner){release(stream);return}s.stream=stream;
   const mime=['audio/webm;codecs=opus','audio/mp4','audio/ogg;codecs=opus','audio/webm'].find(type=>MediaRecorder.isTypeSupported(type));s.recorder=mime?new MediaRecorder(stream,{mimeType:mime,audioBitsPerSecond:64000}):new MediaRecorder(stream);s.started=Date.now();
   s.recorder.ondataavailable=e=>{if(e.data.size){s.chunks.push(e.data);s.bytes+=e.data.size;if(s.bytes>9*1024*1024)V.stop()}};
   s.recorder.onerror=()=>{V.cancel();message('Registrazione interrotta. Controlla il microfono e riprova.')};
   s.recorder.onstop=()=>{release(stream);clearInterval(s.timer);if(s.cancelled||V.session!==s)return;V.session=null;V.controls();if(C.compose!==d||!el('chatCompose')||cloudUser?.email!==d.owner)return;
    const type=s.recorder.mimeType||s.chunks[0]?.type||'audio/webm',blob=new Blob(s.chunks,{type});if(!blob.size||blob.size>10*1024*1024){message('Vocale vuoto o troppo grande. Registra nuovamente.');return}
    const extension=type.includes('mp4')?'m4a':type.includes('ogg')?'ogg':'webm',name='Vocale-'+new Date().toISOString().replace(/[:.]/g,'-')+'.'+extension;
    C.addFiles([new File([blob],name,{type})]);message('Vocale pronto: riascoltalo qui sotto, poi premi Invia messaggio.');
   };
   s.recorder.start(1000);message('Registrazione in corso · 0:00');V.controls();s.timer=setInterval(()=>{const seconds=Math.floor((Date.now()-s.started)/1000);message('Registrazione in corso · '+Math.floor(seconds/60)+':'+String(seconds%60).padStart(2,'0'));if(seconds>=300)V.stop()},1000);
  }catch(e){if(V.session!==s)return;V.cancel();message(e.name==='NotAllowedError'?'Microfono non autorizzato. Consenti il microfono nelle impostazioni del sito e riprova.':e.name==='NotFoundError'?'Nessun microfono trovato. Collega un microfono e riprova.':'Microfono non disponibile. Chiudi le altre registrazioni e riprova.')}
 };
 V.stop=function(){const s=V.session;if(!s?.recorder||s.recorder.state!=='recording')return;clearInterval(s.timer);s.recorder.stop();release(s.stream);message('Preparazione del vocale…')};
 V.play=async function(button){const owner=cloudUser?.email,path=button.dataset.audioPath,type=audioType(button.dataset.audioName);if(!owner||!type)return;button.disabled=true;
  try{const {data,error}=await appSupabase.storage.from('chat-attachments').download(path);if(error)throw error;if(cloudUser?.email!==owner||!button.isConnected)return;const audio=document.createElement('audio');audio.controls=true;audio.preload='metadata';audio.setAttribute('aria-label','Messaggio vocale');audio.src=V.url(new Blob([data],{type}));audio.onplay=()=>{if(V.player!==audio)V.player?.pause();V.player=audio};audio.onerror=()=>notify('Audio non riproducibile in questo browser. Usa Scarica.');button.replaceWith(audio);await audio.play().catch(()=>{});
  }catch{if(button.isConnected){button.disabled=false;button.textContent='Riprova ascolto'}}
 };
 const attachmentHtml=C.attachmentHtml;C.attachmentHtml=function(m,i){return (m.attachments||[]).filter(f=>audioType(f.name)).map(f=>'<div class="chat-voice-playback"><button type="button" class="btn secondary" data-audio-path="'+esc(f.path)+'" data-audio-name="'+esc(f.name)+'" onclick="LotChat.voice.play(this)">▶ Ascolta vocale</button></div>').join('')+attachmentHtml(m,i)};
 const renderFiles=C.renderFiles;C.renderFiles=function(){renderFiles();if(!C.compose)return;el('chatFileList')?.querySelectorAll('.chat-file-item').forEach((row,i)=>{const f=C.compose.files[i];if(!audioType(f.name))return;const audio=document.createElement('audio');audio.controls=true;audio.preload='metadata';audio.setAttribute('aria-label','Riascolta vocale prima di inviarlo');if(!f.previewUrl)f.previewUrl=V.url(f.file);audio.src=f.previewUrl;row.append(audio)})};
 const removeFile=C.removeFile;C.removeFile=function(i){const f=C.compose?.files[i];if(C.compose?.sending)return;if(f?.previewUrl){URL.revokeObjectURL(f.previewUrl);V.urls.delete(f.previewUrl)}removeFile(i)};
 const newMessage=C.newMessage;C.newMessage=async function(...args){await newMessage(...args);V.mount()};
 const send=C.send;C.send=async function(event){if(V.session){event.preventDefault();message('Termina la registrazione prima di inviare.');return}if(C.compose?.files.some(f=>/^Vocale-/.test(f.name))&&!el('chatBody').value.trim())el('chatBody').value='🎙 Messaggio vocale';await send(event);if(!C.compose)V.clear();else V.controls()};
 const reset=C.reset;C.reset=function(){V.clear();return reset()};
 const poll=C.poll;C.poll=function(){if(V.player&&!V.player.paused&&C.owner===cloudUser?.email)return Promise.resolve();return poll()};
 // Also stop when navigation or an external close removes the composer.
 new MutationObserver(()=>{if(V.session&&(!el('chatCompose')||!el('modal')?.open))V.cancel()}).observe(document.body,{childList:true,subtree:true,attributes:true,attributeFilter:['open']});
})();
