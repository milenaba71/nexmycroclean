// Passwords go only to Supabase Auth; never to application tables or logs.
export async function handle(req, env, send = fetch) {
 const headers = {'Content-Type':'application/json','Cache-Control':'no-store','Access-Control-Allow-Origin':'https://milenaba71.github.io','Access-Control-Allow-Headers':'authorization, apikey, content-type, x-client-info','Access-Control-Allow-Methods':'POST, OPTIONS'};
 const reply=(body,status=200)=>new Response(JSON.stringify(body),{status,headers});
 if(req.method==='OPTIONS')return new Response(null,{status:204,headers});
 if(req.method!=='POST')return reply({error:'Metodo non consentito.'},405);
 const token=req.headers.get('Authorization')||'';
 if(!token.startsWith('Bearer '))return reply({error:'Accedi nuovamente.'},401);
 const url=env('SUPABASE_URL'),anon=env('SUPABASE_ANON_KEY'),secret=env('SUPABASE_SERVICE_ROLE_KEY');
 const caller={'apikey':anon,'Authorization':token,'Content-Type':'application/json'};
 try {
  const auth=await send(url+'/auth/v1/user',{headers:caller});
  if(!auth.ok)return reply({error:'Sessione scaduta.'},401);
  const rpc=async(action)=>send(url+'/rest/v1/rpc/laundry_app',{method:'POST',headers:caller,body:JSON.stringify({p_action:action,p_payload:{}})});
  const check=await rpc('version');
  if(!check.ok)return reply({error:'Accesso non autorizzato.'},403);
  const who=await check.json();
  if(who.user?.isSuperAdmin!==true||who.user?.role!=='admin')return reply({error:'Solo il Super amministratore può assegnare password.'},403);
  const raw=await req.text();if(raw.length>4096)return reply({error:'Richiesta troppo lunga.'},400);
  const p=JSON.parse(raw),email=String(p.email||'').trim().toLowerCase(),password=p.password;
  if(!email||typeof password!=='string'||password.length<12||password.length>128)return reply({error:'Inserisci una password da 12 a 128 caratteri.'},400);
  const members=await rpc('users');if(!members.ok)return reply({error:'Verifica utenti non riuscita.'},403);
  const target=(await members.json()).find(u=>u.email.toLowerCase()===email);
  if(!target||!target.active)return reply({error:'Salva e attiva prima questo utente nel gestionale.'},400);
  const admin={'apikey':secret,'Authorization':'Bearer '+secret,'Content-Type':'application/json'};
  let user=null;
  for(let page=1;;page++){
   const list=await send(url+'/auth/v1/admin/users?page='+page+'&per_page=100',{headers:admin});
   if(!list.ok)throw Error('AUTH_LOOKUP');
   const data=await list.json();if(!Array.isArray(data.users))throw Error('AUTH_LOOKUP');
   user=data.users.find(u=>u.email?.toLowerCase()===email);
   if(user||data.users.length<100)break;
   if(page>=1000)throw Error('AUTH_LOOKUP');
  }
  const result=await send(url+'/auth/v1/admin/users'+(user?'/'+encodeURIComponent(user.id):''),{method:user?'PUT':'POST',headers:admin,body:JSON.stringify(user?{password,email_confirm:true}:{email,password,email_confirm:true})});
  if(!result.ok)return reply({error:'Password non assegnata. Verifica i requisiti della password e riprova.'},400);
  return reply({ok:true});
 }catch{return reply({error:'Password non assegnata. Riprova; i dati utente già salvati restano disponibili.'},500)}
}
