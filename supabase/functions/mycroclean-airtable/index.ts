import { normalizePayload } from './normalize.js';
// Webhook only. No Airtable token or service key is exposed to the website.
Deno.serve(async (req: Request) => {
 const reply=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{'Content-Type':'application/json','Cache-Control':'no-store'}});
 if(req.method!=='POST')return reply({error:'METHOD_NOT_ALLOWED'},405);
 const key=req.headers.get('X-Mycroclean-Sync')||'';
 if(!/^[a-f0-9]{64}$/.test(key))return reply({error:'UNAUTHORIZED'},401);
 try {
  if(Number(req.headers.get('content-length')||0)>1500000)return reply({error:'PAYLOAD_TOO_LARGE'},413);
  const raw=await req.text();if(raw.length>1500000)return reply({error:'PAYLOAD_TOO_LARGE'},413);
  const payload=normalizePayload(JSON.parse(raw));
  const response=await fetch(Deno.env.get('SUPABASE_URL')+'/rest/v1/rpc/laundry_airtable_ingest',{method:'POST',headers:{'Content-Type':'application/json','apikey':Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,'Authorization':'Bearer '+Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!},body:JSON.stringify({p_key:key,p_payload:payload})});
  if(!response.ok){let error=await response.json();return reply({error:error.message==='UNAUTHORIZED_SYNC'?'UNAUTHORIZED':'IMPORT_FAILED'},error.message==='UNAUTHORIZED_SYNC'?401:400)}
  return reply(await response.json());
 }catch{return reply({error:'INVALID_PAYLOAD'},400)}
});
