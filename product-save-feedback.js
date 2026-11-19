/* Keep product validation and save failures inside the modal top layer. */
(function(){
 function feedback(form,message,error=true){
  let output=form.querySelector('[data-product-save-status]');
  if(!output){output=document.createElement('p');output.dataset.productSaveStatus='';output.className='wide';output.setAttribute('role','status');output.setAttribute('aria-live','polite');output.style.cssText='padding:12px;border:1px solid currentColor;border-radius:6px;white-space:pre-wrap';form.append(output)}
  output.textContent=message;output.style.color=error?'#a51543':'#245e50';output.scrollIntoView({block:'nearest'});
 }
 const previousNotify=notify;
 notify=function(message){const form=document.querySelector('#modal[open] #productForm');if(form)feedback(form,message);return previousNotify(message)};
 document.addEventListener('invalid',event=>{
  const field=event.target,form=field.form;
  if(form?.id!=='productForm')return;
  const label=field.getAttribute('aria-label')||field.closest('label')?.firstChild?.textContent?.trim()||field.name||'Campo obbligatorio';
  feedback(form,'Salvataggio non eseguito. '+label+': '+field.validationMessage);
 },true);
 const previousSave=saveProduct;
 saveProduct=async function(event,id){
  event.preventDefault();const form=event.target;
  if(form.dataset.productSaving==='true')return;
  form.dataset.productSaving='true';feedback(form,'Salvataggio in corso…',false);
  try{await previousSave(event,id)}catch(error){
   feedback(form,'Salvataggio non completato. '+(error?.message||'Riprova senza chiudere la scheda.'));
   form.querySelectorAll('button[type="submit"]').forEach(button=>button.disabled=!userCan('products_manage'));
  }finally{delete form.dataset.productSaving;}
 };
})();
