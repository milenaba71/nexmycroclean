# Rilavaggi nelle macchinate — modifica pronta, attivazione da approvare

## Comportamento
1. Terminato un ciclo, l’operatore controlla il capo. Se è ancora sporco, usa «Invia a rilavaggio» o il flag Rilavaggio nel lotto.
2. Sceglie programma e macchina e preme «Metti nel carrello». Il capo occupa un posto nel nuovo carrello; non viene duplicato nell’anagrafica o nelle entrate del lotto.
3. Il carrello è pronto per l’avvio, anche parziale. Se la macchina è occupata, attende in coda.
4. Alla fine prevista del ciclo viene aggiunto un lavaggio al prodotto e un rilavaggio eseguito alla riga del lotto, una sola volta.
5. Il flag Rilavaggio rimane per il conteggio anche dopo piegatura e uscita. Si chiude soltanto il blocco «Rilavaggio da eseguire».
6. Il capo torna da piegare: l’operatore può scansionarlo in Lavorazione, salvo riparazioni, etichettature o verifiche ancora aperte.

Il riepilogo distingue prodotti con rilavaggio e rilavaggi eseguiti. Due rilavaggi dello stesso capo valgono due cicli aggiuntivi, ma un solo prodotto. L’esportazione conserva il conteggio. Questo non genera una fattura automaticamente.

La fine ciclo resta calcolata dalla durata del programma; non è un segnale ricevuto dalla macchina fisica.

## Migrazione Supabase da approvare
File: `sql/wash_rewash.sql` — nome `wash_rewash_cycles`.

- Aggiunge archivio privato degli abbinamenti capo/macchinata completati, con RLS e accesso diretto revocato.
- Aggiunge operazione autenticata di inserimento nel carrello di rilavaggio, riservata al permesso esistente `lots_work` e ai ruoli operatore/amministratore.
- Aggiorna `wash_batch_tick` per chiudere il rilavaggio e contarlo a fine ciclo.
- Aggiorna il riepilogo restituito da `wash_batch_control` per conservare le quantità delle macchinate storiche.
- Aggiunge un trigger che conserva il flag quando ci sono rilavaggi eseguiti.
- Non elimina o azzera lotti, prodotti, lavaggi o utenti. Non modifica le password o le funzioni di autenticazione esistenti.

La revisione automatica ha rifiutato l’applicazione in produzione perché le modifiche coinvolgono funzioni condivise, trigger e permessi delle funzioni. Serve approvazione esplicita per applicare questa migrazione e pubblicare l’interfaccia collegata. La migrazione non è stata applicata.

## Verifiche eseguite
Database locale: due rilavaggi consecutivi, contatore incrementato una sola volta a ciclo, storico preservato, nessuna nuova riga lotto, richieste duplicate bloccate, controllo permessi, piegatura sbloccata, flag non cancellabile dopo un rilavaggio eseguito.
Interfaccia: desktop e smartphone, scelta programma/macchina, invio al carrello, conteggi visibili, flag persistente, azione di piegatura disponibile dopo il ciclo.
