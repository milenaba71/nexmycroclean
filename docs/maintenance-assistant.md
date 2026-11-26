# Fermi macchina e manutenzioni nell’assistente

Aggiornamento: 26 novembre 2026.

## Registrazione

Da **Guasti e manutenzioni** in Vista reparto, oppure **Produzione → Guasti e ticket**, aprire o aggiornare una segnalazione. Indicare macchina, stato, impatto e nota dell’evento. Nei **Dati per manutenzione e analisi IA** registrare, quando disponibili:

- Tipo: guasto reale, manutenzione programmata o prova/test.
- Componente e codice errore della macchina. Usare nomi coerenti per confrontare gli episodi.
- Causa verificata: lasciare vuota finché non confermata dal manutentore.
- Intervento effettuato e ricambi utilizzati.
- Data del prossimo controllo previsto. È un dato nello storico, non una notifica automatica.

Salvare il cambio tra **Macchina ferma** e **Macchina utilizzabile** al momento dell’evento. La chiusura definitiva richiede ancora il precedente stato **Risolto da verificare**. Ogni aggiornamento conserva una copia dei dati manutenzione nello storico; archiviare non cancella gli interventi.

## Analisi

Aprire **🤖 → Fermi macchina e manutenzioni**. Selezionare macchina e periodo: 30, 90, 365 giorni o tutto lo storico. **Aggiorna storico** rilegge i dati. I riepiloghi non consumano domande IA.

Il riepilogo mostra nuove segnalazioni di guasto, manutenzioni programmate, riaperture, ticket ancora aperti e ore di fermo documentate. Le ricorrenze numeriche raggruppano stessa macchina, componente e codice errore; non dimostrano da sole la stessa causa. Sono comprese le segnalazioni archiviate.

**Analizza ricorrenze con IA** propone verifiche sulla base dello storico, citando gli identificativi dei ticket. L’analisi usa una delle 10 domande giornaliere disponibili e invia a OpenAI i riepiloghi e le note di manutenzione pertinenti. Non modifica ticket, macchine o programmi. Le diagnosi devono essere verificate dal manutentore.

## Limiti dei dati

Le ore sono solari, non ore di produzione perse. I fermi contemporanei della stessa macchina sono contati una volta. I periodi privi di cambi di stato affidabili non sono stimati: il risultato viene indicato come parziale. Non è presente un collegamento ai sensori delle macchine.

I ticket classificati come prova/test sono esclusi. Per gli storici privi di classificazione, la presenza delle parole “test” o “prova” nelle note determina un’esclusione prudenziale, mostrata separatamente. Se era un guasto reale, classificarlo come **Guasto reale** nella scheda. Nessun ticket viene eliminato.

L’IA riceve al massimo 40 ticket (prima quelli ancora aperti, poi i più recenti), con gli ultimi 8 eventi per ticket e testi limitati a 500 caratteri. I conteggi del riepilogo considerano tutti i ticket pertinenti. Le analisi devono dichiarare una lettura parziale quando i limiti sono raggiunti.

## Implementazione e verifica

La lettura dedicata `laundry_maintenance_history` applica lo stesso controllo dell’assistente (sessione attiva e accesso esistente), non consuma quota e non blocca la riga produzione con `FOR UPDATE`. Restituisce solo macchine e ticket, senza elenchi di operatori, clienti, lotti o identità degli autori. Le scritture restano nell’RPC ticket esistente, con `tickets_manage`, controllo revisione e audit.

La funzione Edge rilegge i dati dal server con il token dell’utente: non accetta conteggi o storico dal browser. Chiavi segrete restano sul server. Controlla i riferimenti ai ticket dell’output IA; un riferimento assente provoca il rifiuto dell’analisi. Il modulo di analisi viene caricato solo su richiesta, senza nuovi polling nelle scansioni.

Test: `maintenance-core.cjs` (periodi, sovrapposizioni, riaperture, storico incompleto e prove); `maintenance-db.cjs` (campi, storico, compatibilità, permessi, revisioni e privacy); `maintenance-edge.cjs` (autorizzazione, quota, filtri, evidenze server e riferimenti IA); `maintenance-ui.cjs` (filtri, salvataggio modulo reale, risposte obsolete, doppio clic e rendering sicuro). Regressioni: analisi tempi, archivio ticket e modifiche tramite assistente.
