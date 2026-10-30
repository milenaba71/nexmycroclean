const fs=require('fs'),assert=require('assert');
(async()=>{
 const {handle}=await import('data:text/javascript;base64,'+Buffer.from(fs.readFileSync('supabase/functions/mycroclean-user-password/handler.js','utf8')).toString('base64'));
 const env=k=>({SUPABASE_URL:'https://test',SUPABASE_ANON_KEY:'anon',SUPABASE_SERVICE_ROLE_KEY:'secret'}[k]);
 const password='Example-00001234';
 async function run({superAdmin=true,existing=false,active=true,auth=true}={}){
  const calls=[];const send=async(u,o={})=>{calls.push([u,o]);let d={};let status=200;
   if(u.endsWith('/auth/v1/user')){status=auth?200:401;d={id:'actor'}}
   else if(u.endsWith('/rpc/laundry_app')){const b=JSON.parse(o.body);assert(!o.body.includes(password));d=b.p_action==='version'?{user:{role:'admin',isSuperAdmin:superAdmin}}:[{email:'person@example.com',active}]}
   else if(u.includes('/admin/users?'))d={users:existing?[{id:'target',email:'person@example.com'}]:[]};
   else {assert.equal(o.headers.Authorization,'Bearer secret');assert.equal(JSON.parse(o.body).password,password);d={id:'target'}}
   return new Response(JSON.stringify(d),{status});};
  const res=await handle(new Request('https://function',{method:'POST',headers:{Authorization:'Bearer caller'},body:JSON.stringify({email:'person@example.com',password})}),env,send);return {res,calls};
 }
 for(const opt of [{superAdmin:false},{auth:false},{active:false}]){const {res,calls}=await run(opt);assert(res.status>=400);assert(!calls.some(([u])=>u.includes('/admin/users')))}
 for(const existing of [false,true]){const {res,calls}=await run({existing});assert.equal(res.status,200);assert.equal(calls.at(-1)[1].method,existing?'PUT':'POST')}
 console.log('PASS manual passwords: authentication, Super Admin authorization, active-member restriction, create/update Auth, password excluded from app RPCs');
})().catch(e=>{console.error(e);process.exit(1)});
