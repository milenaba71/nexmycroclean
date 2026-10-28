import { createClient } from 'npm:@supabase/supabase-js@2.57.4';
const url=Deno.env.get('SUPABASE_URL')!,serviceKey=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,anonKey=Deno.env.get('SUPABASE_ANON_KEY')!;
const options={auth:{persistSession:false,autoRefreshToken:false}};
const service=createClient(url,serviceKey,options);
const allowedOrigin='https://milenaba71.github.io';
Deno.serve(async(req:Request)=>{
 const origin=req.headers.get('origin');const headers={'Content-Type':'application/json','Cache-Control':'no-store','Access-Control-Allow-Origin':allowedOrigin,'Access-Control-Allow-Headers':'authorization, apikey, content-type, x-client-info','Access-Control-Allow-Methods':'POST, OPTIONS','Vary':'Origin'};
 const reply=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers});
 if(origin&&origin!==allowedOrigin)return reply({error:'FORBIDDEN'},403);
 if(req.method==='OPTIONS')return new Response(null,{status:204,headers});
 if(req.method!=='POST')return reply({error:'METHOD_NOT_ALLOWED'},405);
 async function rpc(action:string,p:Record<string,unknown>){const r=await service.rpc('laundry_accounts_service',{p_action:action,p});if(r.error)throw Error(r.error.message);return r.data;}
 try{
  const raw=await req.text();if(raw.length>16000)return reply({error:'PAYLOAD_TOO_LARGE'},413);const body=JSON.parse(raw);
  if(body.action==='login'){
   const login=String(body.login||'').trim().toLowerCase(),password=String(body.password||'');if(login.length>254||!login||password.length>256)return reply({error:'INVALID_CREDENTIALS'},401);
   const resolved=await rpc('login_lookup',{login});if(resolved.limited)return reply({error:'TOO_MANY_ATTEMPTS'},429);
   const client=createClient(url,anonKey,options);
   // Always perform a password check; do not expose whether a username exists.
   const r=await client.auth.signInWithPassword({email:resolved.email||'unknown-user@accounts.mycroclean.invalid',password});
   if(r.error||!resolved.email||!r.data.session)return reply({error:'INVALID_CREDENTIALS'},401);
   return reply({session:{access_token:r.data.session.access_token,refresh_token:r.data.session.refresh_token}});
  }
  const jwt=(req.headers.get('authorization')||'').replace(/^Bearer\s+/i,'');if(!jwt)return reply({error:'UNAUTHORIZED'},401);
  const userClient=createClient(url,anonKey,{...options,global:{headers:{Authorization:'Bearer '+jwt}}});
  const verified=await userClient.auth.getUser(jwt);if(verified.error||!verified.data.user)return reply({error:'UNAUTHORIZED'},401);
  const user=verified.data.user;
  const context=await userClient.rpc('laundry_password_context');if(context.error)return reply({error:context.error.message},403);
  if(body.action==='change_password'){
   const password=String(body.password||''),current=String(body.currentPassword||'');if(password.length<12||password.length>128)return reply({error:'PASSWORD_LENGTH'},400);if(password===current)return reply({error:'PASSWORD_MUST_DIFFER'},400);
   const check=createClient(url,anonKey,options);const r=await check.auth.signInWithPassword({email:user.email!,password:current});if(r.error||r.data.user?.id!==user.id)return reply({error:'CURRENT_PASSWORD_INVALID'},400);await check.auth.signOut({scope:'local'});
   const updated=await service.auth.admin.updateUserById(user.id,{password,app_metadata:{...user.app_metadata,must_change_password:false,password_reset_at:new Date().toISOString()}});if(updated.error)throw Error('PASSWORD_UPDATE_FAILED');
   return reply({ok:true,signInAgain:true});
  }
  if(context.data.mustChangePassword)return reply({error:'PASSWORD_CHANGE_REQUIRED'},403);
  if(context.data.role!=='admin')return reply({error:'FORBIDDEN'},403);
  const claims=JSON.parse(new TextDecoder().decode(Uint8Array.from(atob(jwt.split('.')[1].replace(/-/g,'+').replace(/_/g,'/')),c=>c.charCodeAt(0))));
  const actor={actor_email:user.email,actor_id:user.id,session_id:claims.session_id};
  if(body.action==='list')return reply({users:await rpc('list',actor)});
  if(!context.data.isSuperAdmin)return reply({error:'SUPER_ADMIN_ONLY'},403);
  if(body.action!=='save')return reply({error:'INVALID_ACTION'},400);
  const username=String(body.username||'').trim().toLowerCase(),contactEmail=String(body.contactEmail||'').trim().toLowerCase(),password=String(body.password||''),name=String(body.name||'').trim();
  if(!name||name.length>150||username&&!/^[a-z0-9][a-z0-9._-]{2,39}$/.test(username))return reply({error:'INVALID_USER'},400);
  if(contactEmail&&(!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(contactEmail)||contactEmail.length>254))return reply({error:'INVALID_EMAIL'},400);
  if(password&&(password.length<12||password.length>128))return reply({error:'PASSWORD_LENGTH'},400);
  const email=body.originalEmail?String(body.originalEmail).trim().toLowerCase():crypto.randomUUID()+'@accounts.mycroclean.invalid';
  const payload={...actor,email,username,contactEmail,name,role:body.role,active:body.active===true};
  const target=await rpc('target',payload);if(body.originalEmail&&!target.exists)return reply({error:'USER_CHANGED'},409);
  if(!target.id&&!password)return reply({error:'PASSWORD_REQUIRED'},400);
  let createdId:string|null=null;
  if(!target.id){const r=await service.auth.admin.createUser({email,password,email_confirm:true,app_metadata:{must_change_password:body.mustChangePassword!==false}});if(r.error||!r.data.user)throw Error('ACCOUNT_CREATE_FAILED');createdId=r.data.user.id;}
  try{await rpc('finalize',payload);}catch(e){if(createdId)await service.auth.admin.deleteUser(createdId);throw e;}
  if(password&&target.id){
   const prior=await service.auth.admin.getUserById(target.id);if(prior.error)throw Error('PROFILE_SAVED_PASSWORD_FAILED');
   const r=await service.auth.admin.updateUserById(target.id,{password,email_confirm:true,app_metadata:{...prior.data.user.app_metadata,must_change_password:body.mustChangePassword!==false,password_reset_at:new Date().toISOString()}});
   if(r.error)throw Error('PROFILE_SAVED_PASSWORD_FAILED');
  }
  if(password&&email!==user.email)await rpc('audit_password',{...payload,mustChangePassword:body.mustChangePassword!==false});
  return reply({ok:true,signInAgain:!!password&&email===user.email});
 }catch(e){const message=String((e as Error).message);const known=['SUPER_ADMIN_ONLY','USE_PERMISSION_EDITOR','USERNAME_TAKEN','USERNAME_REQUIRED','INVALID_USERNAME','INVALID_USER','FORBIDDEN_ADMIN_ROLE','SUPER_ADMIN_PROTECTED','CANNOT_DISABLE_SELF','SESSION_REVOKED','FORBIDDEN','PASSWORD_CHANGE_REQUIRED','ACCOUNT_CREATE_FAILED','PROFILE_SAVED_PASSWORD_FAILED','PASSWORD_UPDATE_FAILED'];return reply({error:known.find(x=>message.includes(x))||'OPERATION_FAILED'},400);}
});
