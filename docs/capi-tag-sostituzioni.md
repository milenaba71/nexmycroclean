# Capi, tag e sostituzioni

Il database e le operazioni atomiche rimangono su Supabase. L'interfaccia usa il repository e il sito già esistenti.

## Avvio

Aprire **Capi e tag** nel menu (su telefono: **Altro**). I capi preesistenti mantengono ID, barcode e storico; date di servizio, prezzi e ammortamenti non vengono dedotti né inventati.

1. In **Fasce di ammortamento**, creare una tabella e scegliere mesi o lavaggi. Compilare ogni percentuale; non ci sono valori preimpostati. Le fasce partono da zero, sono consecutive e l'ultima non ha limite finale. Il limite iniziale è incluso, quello finale escluso.
2. Nei **Dati del capo**, impostare il listino, lo stato e la data documentata di messa in servizio. Le condizioni vengono congelate quando il capo entra in servizio. Una nuova versione delle fasce non modifica quelle già congelate.
3. Nei lotti o nelle schede prodotto usare **Scarta / Sostituisci**. Scegliere un motivo, quindi solo dismissione oppure sostituzione con un capo nuovo o uno compatibile in scorta. Per i capi in carrelli di produzione non ancora completati, completare prima lavaggio e asciugatura.
4. Il vecchio capo non viene cancellato. Le sue righe nei lotti diventano **Dismesso**, senza registrare una consegna o una riparazione inesistente. Il nuovo capo mantiene utilizzatore, reparto, tipo, taglia, colore e contratto. Se proviene dalla scorta, mantiene i lavaggi già effettuati.
5. Per riusare lo stesso tag confermare recupero, controllo e idoneità del tag **termosaldato e cucito**. Per smarrimento o mancato reso non si può riutilizzare immediatamente il tag del capo non recuperato. I tag staccati passano a **Da verificare**; dopo controllo possono diventare **Liberi** oppure **Distrutti**.
6. **Addebiti da approvare** contiene solo proposte. Usura, limite lavaggi, rottura e macchia permanente non generano proposte secondo le regole concordate. Danno improprio, smarrimento e mancato reso possono generarle; prezzi, date o fasce mancanti producono **Da completare**, non un importo inventato. Il riscatto concordato a contratto chiuso genera una proposta del valore residuo. Solo le proposte approvate entrano nel CSV dedicato; non viene emessa alcuna fattura.

## Fine contratto

Chiudere il contratto nella sezione esistente. Registrare poi **Reso fine contratto** o **Riscatto** sul capo. Il reso entra in **Da ricondizionare**; dopo controllo torna in scorta usato senza assegnazione personale e senza azzerare i lavaggi. Il capo riscattato esce dalle dotazioni attive; il tag rimane associato al capo acquistato e non torna disponibile per il riuso.

## Tracciabilità e calcolo

- Una sola associazione attiva per tag e per capo, garantita dal database.
- La scansione identifica il capo attuale; i lotti già registrati mantengono il vecchio ID interno.
- Date delle assegnazioni legacy non documentate sono dichiarate sconosciute.
- Mesi interi calcolati sull'anniversario della messa in servizio, con fine mese adattata al mese di destinazione. Per i lavaggi si sottrae il contatore documentato alla messa in servizio.
- Valori monetari in centesimi, arrotondamento al centesimo; il prezzo usato è quello congelato sul capo.
- La gestione richiede il permesso esistente **Gestione prodotti**. Le operazioni verificano la revisione e hanno una chiave anti-duplicazione.
- Attività pendenti condivise conservano gli altri capi; le assegnazioni interessate richiedono ripianificazione. Le riparazioni aperte dei capi dismessi sono annullate, non completate.

## Installazione e verifica

Applicare in un'unica migrazione `sql/garment_lifecycle.sql` seguito da `sql/garment_lifecycle_integration.sql`, poi pubblicare i file dell'interfaccia. I controlli del secondo script interrompono la migrazione se le funzioni di partenza sono cambiate.

Test SQL e integrazione: `node tests/garment-lifecycle.cjs` con `@electric-sql/pglite` 0.3.14 (oppure variabile `PGLITE_PATH`). Test browser: `node tests/garment-lifecycle-ui.cjs` e `node tests/garment-lifecycle-app-ui.cjs`, con Playwright e Chromium installati (variabili opzionali `PLAYWRIGHT_PATH` e `CHROMIUM_PATH`). Il browser di test usa risposte simulate e non modifica dati reali.
