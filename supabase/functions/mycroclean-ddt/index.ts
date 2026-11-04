// Dedicated, authenticated automation endpoint. Never called with secrets by the browser.
Deno.serve(async(req:Request)=>{
 const reply=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{'Content-Type':'application/json','Cache-Control':'no-store'}});
 if(req.method!=='POST')return reply({error:'METHOD_NOT_ALLOWED'},405);
 const key=req.headers.get('X-Mycroclean-Sync')||'';
 if(!/^[a-f0-9]{64}$/.test(key))return reply({error:'UNAUTHORIZED'},401);
 try{
  const raw=await req.text();if(raw.length>3000000)return reply({error:'PAYLOAD_TOO_LARGE'},413);
  const {action,p={}}=JSON.parse(raw);if(!['begin','ack','finish'].includes(action))return reply({error:'INVALID_ACTION'},400);
  const service=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const response=await fetch(Deno.env.get('SUPABASE_URL')+'/rest/v1/rpc/laundry_ddt_sync',{method:'POST',headers:{'Content-Type':'application/json',apikey:service,Authorization:'Bearer '+service},body:JSON.stringify({p_key:key,p_action:action,p})});
  if(!response.ok)return reply({error:'SYNC_FAILED'},400);
  return reply(await response.json());
 }catch{return reply({error:'INVALID_REQUEST'},400)}
});
