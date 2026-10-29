# Vista reparto

La vista operatore usa gli stessi prodotti, lotti, carrelli, cicli e API Supabase del gestionale esistente. Non introduce copie dei dati né nuovi permessi. Il gestionale completo rimane disponibile per l'ufficio.

## Accesso

Gli operatori senza permesso di gestione della produzione arrivano alla home Reparto. Gli altri utenti possono aprire **Vista reparto** dal menu; per tornare usano **Gestionale ufficio**. I pulsanti **Il mio lavoro** e **Istruzioni** mantengono la vista reparto, con un pulsante Indietro. La postazione mostrata è quella abituale configurata in Operatori e turni; non si inventa una postazione quando manca.

## Sei regole

1. Entrata blu, lavaggio azzurro, asciugatura arancio, piegatura viola, uscita verde. Il testo accompagna sempre il colore.
2. Una fase e un lotto alla volta.
3. Pulsanti grandi, con verbo e oggetto.
4. Risposta visibile a ogni lettura: FATTO, METTI DA PARTE, FERMATI.
5. Il blocco rosso richiede un clic o un tocco su HO CAPITO. Il tasto Invio dello scanner non lo conferma.
6. Dati reali nelle operazioni; nomi inventati soltanto nei quattro esempi, marcati esplicitamente come tali.

## Funzioni

- Home: operatore, postazione abituale, cinque tasti con conteggi, problema, lavoro assegnato e istruzioni. Entrata conta i lotti aperti, lavaggio/asciugatura i carrelli in attesa, piegatura i capi lavati con asciugatura conclusa dove richiesta, uscita i capi pronti.
- Entrata: mantiene il campo di scansione originale e i suoi controlli. Mostra capi/capienza; il tasto di avvio appare per un carrello pronto (anche parziale dopo Termina controllo in entrata). Un ciclo bloccato ha il comando di riavvio.
- Macchine: LIBERO, minuti previsti, INTERROTTO, GUASTO o OCCUPATO per attività macchina ancora avviate. Un guasto bloccante non viene proposto. Il programma mantiene la scelta compatibile quando libera, altrimenti propone una macchina libera con capienza sufficiente. L'operatore conferma l'avvio reale, il database verifica nuovamente disponibilità e autorizzazione.
- Piegatura: i controlli cliente/lotto restano quelli originali. I capi già segnalati vengono indirizzati a un cesto senza registrare la piegatura. Il verde appare solo dopo il completamento della funzione di registrazione esistente. La lettura di un altro codice durante l'avviso è bloccata.
- Uscita: Caricati = capi usciti; In lavorazione = capi non pronti; Mancanti = capi non ancora usciti (include quelli in lavorazione). I dismessi sono esclusi. I mancanti sono elencati per utilizzatore, codice e stato. Non è una dichiarazione di smarrimento né un confronto con dotazioni teoriche.
- Problemi: chi ha il permesso ticket usa la scheda guasto esistente. Gli altri ricevono istruzioni per avvisare il responsabile: non viene simulato alcun invio.

## Reparto e ufficio

| Reparto | Ufficio |
|---|---|
| Scansioni e avanzamento capi | Anagrafiche, clienti e contratti |
| Carrelli, avvio e interruzione cicli | Programmi, capacità e tempi |
| Lavoro assegnato e segnalazioni | Ruoli, permessi, abilità e turni |
| Mancanti alla spedizione | Listini, ammortamenti e proposte di addebito |
| Guide operative | Configurazione e storico completo |

È una separazione dell'interfaccia, non una nuova regola di visibilità dei dati. Restano validi i permessi del database.

## Quattro passi per l'introduzione

1. Verificare account, permessi, postazioni abilitate e turni.
2. Preparare i cesti fisici con le etichette RIPARAZIONI, ETICHETTE, VERIFICHE, RILAVAGGIO, SCARTI DA VERIFICARE. Sono destinazioni operative indicate dall'interfaccia, non ubicazioni già censite nel database.
3. Eseguire un lotto pilota controllando entrata, lavaggio, eventuale asciugatura, piegatura e uscita.
4. Adottare la vista reparto; mantenere configurazioni e amministrazione nel gestionale ufficio.

## PDF conservati

Restano entrambe le guide in Istruzioni: **Produzione e pianificazione (2.0, 11 pagine)** e **Capi, scarto, sostituzione e riuso tag (1.0, 6 pagine)**. Il ridisegno non elimina nessuna delle due.

## Verifica

`tests/operator-view-ui.cjs` prova l'interfaccia con dati fittizi e risposte API simulate: home, contatore, avvio solo dopo carrello pronto, guasti e proposta essiccatoio, instradamento al cesto senza scritture, blocco rosso con conferma esplicita, piegatura riuscita, nomi in uscita, permessi, telefono e ritorno ufficio. I test non modificano i dati reali.

## Avvio asciugatura e continuità della vista

Avvia asciugatura apre una scelta esplicita del programma. I programmi senza durata restano visibili ma non selezionabili. Il pulsante finale si abilita soltanto dopo la scelta di un programma con minuti validi e di una macchina disponibile. La durata viene mostrata prima della conferma; gli errori restano nella finestra. Non vengono assegnate durate automaticamente.

Il mio lavoro e Istruzioni restano nella vista reparto. Il mio lavoro mantiene le azioni, le dipendenze e i controlli delle attività originali, con meno dettagli sullo schermo. Gli interventi del lotto mantengono la cornice reparto. Il passaggio all'ufficio avviene con il pulsante dedicato. Entrambe le guide PDF restano disponibili.

La prova include conferma avvio, timer dopo aggiornamento, errore macchina occupata, interruzione, riavvio sullo stesso essiccatoio, annullamento e avvio dall'attività assegnata. Il test SQL verifica anche il rifiuto di una durata mancante.

## Riparazioni ed elenco capi nel reparto

La tab Riparazioni è sempre disponibile nella cornice reparto, anche durante le scansioni. La home ha un quinto accesso con il numero di capi da controllare. La coda comprende riparazioni, etichette, verifiche, sostituzioni, scarti da verificare e rilavaggi, raggruppati per lotto. Un capo con più segnalazioni conta una sola volta nel totale. Sono esclusi i capi usciti o dismessi e i lotti archiviati.

Dentro il lotto, aprire **Elenco capi del lotto**, cercare per codice, utilizzatore, tipo o reparto e premere **Segnalazioni e note**. Ogni spunta è salvata sul lotto attraverso il salvataggio condiviso esistente, con evento e operatore. I permessi restano `lots_work` per segnalazioni e riparazioni, `products_manage` per dismissione e sostituzione.

**Scarto da verificare** è un motivo di verifica: conserva `discardReview` nella riga e apre `verify`, già controllato dal flusso esistente. Non cambia lo stato del capo, non trasferisce tag e non genera addebiti. La richiesta è aperta finché è aperta la verifica; dopo la verifica il motivo resta nella riga e negli eventi. Gli scarti già imposti dalla scheda prodotto o dal limite lavaggi restano da valutare e non vengono rimossi con una spunta. La decisione definitiva usa il flusso esistente Scarto e sostituzione.

Il reparto registra riparazione, etichettatura o verifica con i pulsanti esistenti e i controlli sul lavaggio. Le sostituzioni e gli scarti hanno l'azione **Valuta scarto / sostituzione** solo per chi è abilitato. L'elenco del lotto resta consultabile anche quando un capo è uscito o dismesso, con le modifiche bloccate.

Test: ricerca capi, salvataggio dei sei tipi di segnalazione, completamento etichettatura, coda per lotto, permessi, esclusione usciti/dismessi e layout telefono. Nessuna prova modifica prodotti o lotti reali.

## Nuovo lotto dall'entrata

In **Entrata**, accanto alla scelta dei lotti esistenti, premere **Apri nuovo lotto**. Il modulo resta quello condiviso: cliente, colli e riconsegna, con eventuale reparto, appuntamento e ordine. Al termine il nuovo lotto si apre in Entrata nella Vista reparto, pronto per le scansioni. Il pulsante è disponibile anche dentro un lotto in Entrata. La creazione rispetta `lots_create`; se non autorizzata il pulsante nell'elenco è disabilitato. Il test copre errore senza creazione e creazione riuscita con apertura del nuovo lotto.

## Ordine della schermata Entrata

Prima **1. Scegli il percorso e il tipo di lavaggio**, con il programma e la macchina previsti (oppure una lavorazione senza macchina). Poi **2. Scansiona il codice del capo**. Il campo e il pulsante di registrazione restano disabilitati finché non è selezionato un percorso valido. Una scelta già salvata nel lotto viene mostrata e mantenuta. Contatore, elenco capi e carrelli rimangono nella stessa schermata.

## Capi per pagina

Nell'elenco capi del lotto, la tendina **Capi per pagina** permette di scegliere **10, 50, 100 o 1.000**. Precedente e Successiva cambiano pagina; il contatore indica la pagina corrente e il totale. La prima visualizzazione usa 10 capi. La scelta viene ricordata nello stesso browser, anche cambiando lotto. Una nuova ricerca riparte dalla prima pagina, mantenendo la quantità scelta.

La scelta 10 / 50 / 100 / 1.000 è disponibile anche nel gestionale ufficio: Prodotti, Lotti, Storico lotti, capi del lotto, Riparazioni, Clienti, Anagrafiche, Utenti, Ordini clienti, Mancati resi, Programmi fissi, Noleggi e Tipi di riparazione. Ogni elenco ricorda la propria quantità nello stesso browser. Nei Prodotti anche la selezione della pagina e dell'intervallo di pagine usa la quantità scelta; esportazione e selezione di tutti i risultati restano complete. Gli altri elenchi mantengono tutti i dati e mostrano soltanto le righe della pagina corrente; la stampa mostra tutte le righe.

## Colori dei lotti in Entrata

Le schede dei lotti sono rosse con **Aperto**, gialle con **In lavorazione**, verdi con **Finito**. Verde significa che tutti i capi sono usciti o sono stati dismessi tramite il flusso autorizzato; la sola fine del lavaggio o della piegatura non chiude il lotto. Un lotto vuoto resta rosso. I lotti finiti restano visibili nell'elenco Entrata fino all'archiviazione. Ogni scheda riporta anche il testo dello stato e il numero totale di capi.
