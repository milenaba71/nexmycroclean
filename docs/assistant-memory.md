# Chat aziendale e memoria approvata

Aggiornamento: 26 novembre 2026.

Aprire il robot **🤖 → Chat aziendale · insegna all’IA**. È una conversazione libera sulle procedure e sui problemi aziendali, con consultazione delle regole approvate. Per conteggi attuali, fermi macchina o modifiche ai record restano disponibili i comandi specifici nella schermata principale dell’assistente.

## Insegnare una procedura

Solo il **Super amministratore** può approvare o cambiare la memoria condivisa:

1. Premere **Insegna all’IA**.
2. Scrivere titolo, istruzione verificata e fonte/documento di riferimento. Specificare quando si applica, cosa fare ed eventuali eccezioni. Una regola può contenere fino a 4.000 caratteri.
3. Premere **Approva e memorizza**. Da quel momento la regola è disponibile alle successive domande degli utenti abilitati all’assistente.

Sotto una risposta dell’IA, **Correggi / insegna la regola** apre una scheda in cui inserire la risposta corretta. Il testo prodotto dall’IA non viene approvato automaticamente. Non occorre attendere un riaddestramento del modello.

In **Memoria approvata** si possono cercare, modificare e disattivare regole superate. Ogni modifica ha una versione e uno storico nell’audit. Una modifica concorrente viene rifiutata conservando il testo nel modulo. La disattivazione impedisce l’uso nelle nuove risposte e non elimina lo storico.

## Cosa ricorda

La memoria approvata è permanente nel database del gestionale. La conversazione corrente resta solo nel pannello aperto ed è azzerata quando lo si chiude o si apre un’altra funzione. **Nuova conversazione** cancella il contesto della chat, non le regole approvate. Dire “ricorda” in chat, da solo, non salva una regola.

È memoria aziendale consultata durante la risposta, non un addestramento dei pesi del modello OpenAI. La ricerca testuale in italiano seleziona fino a cinque regole pertinenti; termini molto diversi o una domanda ambigua possono richiedere una riformulazione. Le fonti utilizzate sono indicate nella risposta con titolo e versione. Se manca una procedura approvata, l’IA deve dichiararlo; può offrire suggerimenti esplicitamente presentati come proposte da approvare.

Non vengono pre-caricate procedure non approvate. La chat non cambia prodotti, lotti, macchine, utenti o permessi. Le modifiche operative continuano a usare i percorsi dedicati con anteprima, autorizzazioni e conferma.

## Accesso e dati inviati

La chat usa gli accessi esistenti dell’assistente e la quota condivisa di 10 domande giornaliere per utente. Consultare o modificare la memoria non consuma domande. Domanda, ultimi messaggi della conversazione e regole pertinenti sono inviati a OpenAI per generare la risposta. Non vengono inviati automaticamente tutti i prodotti, lotti o dati degli utenti. La funzione usa `store:false`.

La tabella privata è protetta da RLS e non consente lettura/scrittura diretta agli utenti API. Gli RPC verificano sessione e permessi; solo il Super amministratore può salvare/disattivare regole. Le modifiche bloccano soltanto la regola interessata, senza bloccare la riga globale della produzione. La funzione Edge recupera le fonti dal database con il token del chiamante e rifiuta riferimenti inventati; non accetta documenti forniti dal browser come fonti approvate.

Verifiche automatiche: `assistant-memory-db.cjs`, `assistant-memory-edge.cjs`, `assistant-memory-ui.cjs`, più regressioni dell’assistente esistente. Non è stato eseguito un test manuale con l’account dell’operatore o un addestramento del modello.
