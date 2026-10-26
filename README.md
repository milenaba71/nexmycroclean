# Mycroclean — lavanderia industriale

Gestionale statico per GitHub Pages con database e autenticazione Supabase. Il sito pubblico contiene solo codice; i dati operativi vengono caricati dopo l'accesso con email e password e la verifica dei permessi sul database.

## Funzioni

Prodotti, clienti in elenco, lavorazioni, lotti con numerazione server, scansione barcode da tastiera, riparazioni automatiche, riepilogo quantità per tipologia, ruoli amministratore/operatore/sola lettura, CSV/Excel, avvisi temporizzati ed editor etichette integrato con selezione multipla.

## Aggiornamento del 26 ottobre 2026

- Filtri combinabili per cliente, reparto, tipo, taglia, colore, proprietà e stato; filtri avanzati su tutte le colonne della scheda, anche quelle importate.
- Selezione di tutti i risultati, della pagina o di un intervallo di pagine da 50 prodotti. La selezione resta disponibile cambiando pagina e filtri; il contatore distingue il totale dai selezionati nei risultati correnti. Esportazione CSV/Excel anche dei soli selezionati.
- Cliente, utilizzatore e reparto in colonne e campi distinti. Reparti associati all’ID del cliente, anche dopo una rinomina.
- Anagrafiche amministratore: tipi, taglie, colori e reparti, con rinomina e disattivazione. I valori storici restano leggibili. I valori nuovi presenti negli import amministratore alimentano le anagrafiche.
- Clienti disattivabili e comando per riunire anagrafiche nel cliente principale, con reparto facoltativo. Nessuna fusione automatica dei nomi esistenti.
- Conteggi per riparazione, etichettatura e verifica nella lista lotti; accesso diretto agli interventi del lotto.

Le nuove tabelle Supabase hanno RLS e accesso diretto negato. Le operazioni passano dal gateway con controllo del ruolo, revisione e registro audit. Il file `sql/catalogs.sql` documenta l’estensione al database esistente; non è uno script per inizializzare un progetto vuoto.

Integrazione CO/Airtable e ordini di produzione: fase successiva, non implementata in questo aggiornamento.

## Scansione e operatività dei lotti

- Il lettore può terminare la scansione con Invio o Tab. È disponibile anche il riconoscimento automatico dopo 500 ms sul barcode completo conosciuto. I codici sono testo: zeri iniziali e maiuscole/minuscole vengono conservati.
- Le scansioni vengono salvate in coda, una per volta, con il lotto, la fase e la lavorazione scelti al momento della lettura. Gli errori restano visibili tra le scansioni da controllare. Durante gli avvisi temporizzati è possibile acquisire i prossimi codici nel campo della finestra.
- Le tre fasi sono Entrata, Lavorazione, Uscita. La lettura in Lavorazione registra il trattamento eseguito e il suo completamento; il lavaggio aumenta una sola volta quando previsto. Le scansioni duplicate non aggiungono lavaggi. L’uscita richiede lavorazione completata e assenza di interventi aperti.
- Aggiungi prodotti riporta all’Entrata e conserva tutte le righe e le uscite precedenti. È possibile aggiungere nuovi codici al lotto anche dopo una riconsegna completa. Un nuovo ingresso dello stesso codice già presente richiede un nuovo lotto, per conservare la tracciabilità.
- Note nel lotto, filtri per codice/utilizzatore/note, tipo, reparto, taglia, fase e segnalazione. Esportazione CSV dei risultati con note e flag.
- I flag Sostituzione e Rilavaggio alimentano il riepilogo per tipo. Sostituzione è una segnalazione del prodotto: il flag non assegna un nuovo barcode. Rilavaggio su un prodotto già completato richiede un nuovo ciclo prima dell’uscita; la nuova lettura in Lavorazione aggiunge un lavaggio e conserva il conteggio dei cicli. Togliere il flag prima del nuovo ciclo ripristina il completamento precedente.
- Le etichette totali nel riepilogo includono le richieste completate; le etichette ancora da fare sono indicate separatamente. I conteggi riguardano l’intero lotto anche quando la tabella è filtrata.
- Ogni apertura della scheda prodotto ricarica da Supabase le anagrafiche aggiornate prima di mostrare i menu. I file JavaScript hanno un identificativo di versione per evitare di usare menu precedenti rimasti in cache.

Il trigger documentato in `sql/lot_workflow.sql` controlla anche sul server le uscite, il cliente dei nuovi prodotti e la conservazione delle righe precedenti.

## Pubblicazione

In GitHub: Settings → Pages → Build and deployment → Source: Deploy from a branch → Branch: main → Folder: / (root) → Save.

In Supabase: Authentication → URL Configuration. Impostare Site URL e Redirect URLs sull'indirizzo HTTPS esatto restituito da GitHub Pages. Questo indirizzo serve per conferma email e recupero password.

Al primo accesso usare l'email abilitata dall'amministratore, scegliere una password e confermare la mail. L'account Supabase usato per gestire il progetto non crea automaticamente un account utente nell'applicazione.

Gli amministratori abilitano le email nella sezione Utenti; i colleghi usano Primo accesso. Un account non abilitato non può leggere o modificare dati anche se completa la registrazione.

## Sicurezza

`config.js` contiene solo l'URL del progetto e una chiave publishable, progettata per l'uso nel browser. Non contiene una chiave service_role, un token server o password. Il gateway SQL verifica utente confermato, sessione attiva, anagrafica utenti, stato e ruolo a ogni richiesta. L'accesso diretto alle tabelle è negato. I dati importati e le credenziali non sono nel repository.

## Etichette

Da Prodotti: selezionare uno o più capi e scegliere Etichette selezionate. Dalla scheda: Salva e prepara etichetta. La sezione Etichette integra l'editor con anteprima, campi, logo, barcode/QR, dimensioni, layout e stampa A4/rotolo.

## Librerie

Supabase JS 2.57.4 e SheetJS CE 0.20.3 sono caricate da CDN con versioni fissate. Il modello etichette usa inoltre JsBarcode, qrcode-generator, PDF.js e Tesseract tramite CDN con versioni dichiarate nel file.
