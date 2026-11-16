const headers = {'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, apikey, x-client-info, content-type','Cache-Control':'no-store'};
const reply = (body: unknown, status = 200) => Response.json(body, {status, headers});
Deno.serve(async req => {
  if (req.method === 'OPTIONS') return new Response(null, {headers});
  if (req.method !== 'POST') return reply({},405);
  const token = req.headers.get('authorization');
  if (!token) return reply({},401);
  try {
    const auth = await fetch(Deno.env.get('SUPABASE_URL')+'/rest/v1/rpc/laundry_app',{
      method:'POST',headers:{Authorization:token,apikey:Deno.env.get('SUPABASE_ANON_KEY')!,'Content-Type':'application/json'},
      body:JSON.stringify({p_action:'snapshot',p_payload:{}})
    });
    if (!auth.ok) return reply({},403);
    const {user} = await auth.json();
    if (!(user?.isSuperAdmin || user?.role === 'admin')) return reply({},403);
    const key = Deno.env.get('PRODUCT_PHOTO_OPENAI_KEY');
    if (!key) return reply({error:'Servizio domande da configurare.'},503);
    const {question}=await req.json();
    if(typeof question!=='string'||!question.trim()||question.length>450)return reply({},400);
    const response=await fetch('https://api.openai.com/v1/chat/completions',{method:'POST',
      headers:{Authorization:'Bearer '+key,'Content-Type':'application/json'},
      body:JSON.stringify({model:'gpt-4.1-mini',store:false,max_completion_tokens:200,response_format:{type:'json_object'},
        messages:[{role:'system',content:'Traduci la domanda in un filtro JSON: metric (all, repair, relabel, verify, out oppure unsupported), lot (numero senza anno o stringa vuota), client e department (sottostringhe letterali o vuote). Disponibili solo conteggi di indumenti dei lotti non archiviati, totali o per intervento. Per filtri temporali, tipi di capo, stato del lotto, archivi, interrogazioni diverse o ambigue usa unsupported. Non inventare filtri.'},{role:'user',content:question}]})});
    if(!response.ok)return reply({},502);
    const plan=JSON.parse((await response.json()).choices[0].message.content);
    const result:Record<string,string>={metric:['all','repair','relabel','verify','out'].includes(plan.metric)?plan.metric:'unsupported'};
    for(const field of ['lot','client','department'])result[field]=String(plan[field]??'').slice(0,120);
    return reply(result);
  }catch{return reply({},502)}
});
