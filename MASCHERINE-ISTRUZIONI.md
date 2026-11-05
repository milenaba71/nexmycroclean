# Mascherine: confezionamento e scarico

Aggiornamento 5 novembre 2026.

- Ufficio: aprire **Mascherine · Confezionamento**. Reparto: premere la scheda **Mascherine**, disponibile anche nella navigazione in alto.
- Cercare fornitore, DDT o articolo. Il numero DDT apre **Carica imbustati**: inserire solo i pezzi confezionati adesso. Il carico non ha un vincolo di 250 pezzi e conserva il collegamento al DDT.
- I pezzi caricati non possono superare i rientri DDT sincronizzati. Per nuovi rientri usare DDT fornitori e attendere la sincronizzazione Airtable (circa 5 minuti).
- La giacenza in alto è **globale**, non cambia ambito con i filtri. Include tutti i carichi meno tutti gli scarichi e i relativi storni.
- Per una consegna usare **Scarica 250 mascherine imbustate** e confermare. Non scegliere un DDT. Per 500 pezzi registrare due scarichi da 250. Se la giacenza è inferiore a 250 lo scarico viene bloccato anche dal database.
- Esempio: 150 pezzi caricati dal DDT A e 100 dal DDT B permettono uno scarico unico di 250 pezzi. Giacenza finale: zero.
- Correggere i carichi con **Modifica / Annulla** nella riga DDT. Inserire la nuova quantità del singolo movimento e il motivo, oppure annullare il movimento.
- Per gli scarichi usare **Scarichi · Storico / Correzioni**. Le note sono modificabili; la quantità dei nuovi scarichi è fissa a 250. Un annullamento ripristina la giacenza. Le correzioni richiedono il permesso `planning_delete` e conservano autore, data, motivo e originale.
- I vecchi scarichi collegati a un DDT e con altre quantità restano nello storico e nel totale: nessun movimento preesistente viene rimosso o convertito. Sono ancora correggibili.
- La riduzione di un carico non può rendere negativa la giacenza globale né contraddire i vecchi scarichi di quel DDT. Correggere prima gli eventuali scarichi sbagliati.
- I movimenti del magazzino mascherine **non modificano Airtable**. Solo i rientri e storni in DDT fornitori vengono sincronizzati.
- CSV ed Excel esportano i carichi dei DDT filtrati. I totali globali rimangono visibili nella schermata; lo storico scarichi è separato.
