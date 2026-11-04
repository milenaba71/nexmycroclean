# DDT fornitori · quantità manuali

Aprire **DDT fornitori · Airtable** dal menu ufficio. Selezionare il fornitore, poi il numero DDT. La vista iniziale mostra le righe aperte; **Evasi** e **Tutti** consentono di consultare quelle già rientrate.

Per ogni articolo sono mostrati inviati, già rientrati e residuo in laboratorio. Premere **Registra rientro**, indicare solo la quantità fisicamente contata in questa consegna, aggiungere eventuali note e confermare. Il permesso richiesto è quello per lavorare sui lotti. Data e operatore sono automatici.

Il rientro rimane **in attesa di sincronizzazione** fino all'aggiornamento Airtable, previsto ogni cinque minuti. Nel frattempo non è possibile inserire un altro rientro sulla stessa riga. Premere **Aggiorna elenco** per verificare l'esito. Non ripetere il conteggio già registrato. Il rientro viene sommato alla quantità precedente; quando il residuo della riga è zero, la riga è evasa.

**Storico rientri** distingue registrazioni applicate, in attesa e non applicate per conflitto. In caso di conflitto controllare le quantità in Airtable prima di registrare nuovamente. Le quantità pregresse sono incluse nei totali ma non nello storico delle nuove operazioni Mycroclean.

CSV ed Excel esportano tutte le righe corrispondenti ai filtri. Nessuna operazione di questo modulo crea prodotti, barcode o movimenti dei lotti di lavanderia.

## Attivazione amministrativa

L'automazione Airtable **Mycroclean · DDT fornitori e rientri manuali** è predisposta ma deve essere attivata dal proprietario della base. Fino alla prima sincronizzazione la sezione non contiene DDT. Se i dati non vengono aggiornati per più di 15 minuti, i nuovi rientri sono bloccati per evitare conteggi su residui obsoleti.

La sincronizzazione importa solo righe collegate a un unico DDT valido. Le righe con collegamenti ambigui devono essere corrette in Airtable. Per evitare modifiche concorrenti, registrare i nuovi rientri da Mycroclean durante l'utilizzo del modulo.
