# Dal carrello alla riconsegna

1. **Entrata:** scegli programma e macchina e scansiona i prodotti nel carrello. Restano Entrati fino all’avvio.
2. **Avvia macchinata:** i prodotti passano a **In lavaggio**. Un’interruzione mostra **Lavaggio interrotto** e blocca il passaggio successivo.
3. Alla fine del tempo previsto dal programma il lavaggio viene contato una sola volta. I capi passano a **Da lavorare · Piegatura**. Il timer è una stima: non riceve segnali dalla macchina. Dopo il lavaggio ad acqua passano prima a **Da asciugare**: vedi `asciugatura-dopo-lavaggio-acqua.md`.
4. Apri **02 Lavorazione**, piega il capo e scansiona il barcode. Il prodotto diventa **Pronto per l’uscita**; sono registrati data, ora e operatore. Non occorre premere Registra.
5. Riparazioni, etichettature, verifiche o rilavaggi aperti impediscono di segnare il capo pronto. Risolvi la segnalazione e ripeti la scansione.
6. In **03 Uscita**, scansiona i prodotti già pronti per registrare la riconsegna. Non aumenta il numero di lavaggi.

La piegatura non viene completata dal timer. Ripetere la scansione dello stesso capo già piegato non duplica la registrazione. I prodotti già usciti prima dell’aggiornamento mantengono il loro storico.

Installazione: `wash_product_phases.sql` dopo `flexible_user_permissions.sql`. La migrazione modifica le definizioni correnti delle funzioni e conserva i controlli dei permessi.
